import { Router } from "express";
import { runScript } from "../powershell.js";

const router = Router();

// ── Singleton session state ─────────────────────────────────────────
let session = null;

function freshSession(suspectedPortMac, testPortMac, baselineNics) {
  return {
    suspectedPortMac,
    testPortMac,
    baselineNics,
    phases: [],
    currentPhase: 0,
    verdict: null,
    startedAt: Date.now(),
  };
}

/** Helper — find a NIC entry by MAC. */
function findPort(nics, mac) {
  const list = Array.isArray(nics.adapters)
    ? nics.adapters
    : Array.isArray(nics.ports)
      ? nics.ports
      : Array.isArray(nics)
        ? nics
        : [];
  return list.find(
    (p) =>
      (p.macAddress ?? p.mac ?? "").toLowerCase() === mac.toLowerCase()
  );
}

// ── Routes ──────────────────────────────────────────────────────────

/** GET /api/fault-isolator/ports — available NIC ports */
router.get("/ports", async (_req, res) => {
  try {
    const nics = await runScript("Get-NicAdapters.ps1");
    const ports = nics.adapters ?? nics.ports ?? nics ?? [];
    res.json({ ports: Array.isArray(ports) ? ports : [] });
  } catch (err) {
    console.error("Fault isolator ports error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/** POST /api/fault-isolator/start — begin a fault-isolation session */
router.post("/start", async (req, res) => {
  const { suspectedPortMac, testPortMac } = req.body ?? {};

  if (!suspectedPortMac || !testPortMac) {
    return res.status(400).json({ error: "suspectedPortMac and testPortMac are required" });
  }

  try {
    // Snapshot current NIC state as baseline
    const baseline = await runScript("Get-NicAdapters.ps1");
    session = freshSession(suspectedPortMac, testPortMac, baseline);
    res.json({ started: true, session });
  } catch (err) {
    console.error("Fault isolator start error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/** GET /api/fault-isolator/status */
router.get("/status", (_req, res) => {
  if (!session) {
    return res.json({ active: false });
  }
  res.json({ active: true, ...session });
});

/** POST /api/fault-isolator/advance — move to the next phase */
router.post("/advance", async (_req, res) => {
  if (!session) {
    return res.status(400).json({ error: "No active fault-isolation session" });
  }

  try {
    // Re-read live NIC state
    const currentNics = await runScript("Get-NicAdapters.ps1");

    const suspected = findPort(currentNics, session.suspectedPortMac);
    const testPort = findPort(currentNics, session.testPortMac);
    const baseSuspected = findPort(session.baselineNics, session.suspectedPortMac);
    const baseTest = findPort(session.baselineNics, session.testPortMac);

    const phase = {
      index: session.currentPhase,
      ts: Date.now(),
      suspected: {
        status: suspected?.status ?? suspected?.mediaConnectionState ?? "Unknown",
        linkSpeed: suspected?.linkSpeedMbps ?? suspected?.speed ?? null,
        errors: (suspected?.inErrors ?? 0) + (suspected?.outErrors ?? 0),
      },
      testPort: {
        status: testPort?.status ?? testPort?.mediaConnectionState ?? "Unknown",
        linkSpeed: testPort?.linkSpeedMbps ?? testPort?.speed ?? null,
        errors: (testPort?.inErrors ?? 0) + (testPort?.outErrors ?? 0),
      },
      baselineDelta: {
        suspectedChanged:
          (suspected?.status ?? "") !== (baseSuspected?.status ?? ""),
        testChanged:
          (testPort?.status ?? "") !== (baseTest?.status ?? ""),
      },
    };

    session.phases.push(phase);
    session.currentPhase++;

    res.json({ phase, session });
  } catch (err) {
    console.error("Fault isolator advance error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/fault-isolator/conclude
 *
 * Generate a verdict from the collected phase data.
 * Possible verdicts: NicPort, Cable, Camera, NicHardware, LikelyCamera
 */
router.post("/conclude", (_req, res) => {
  if (!session) {
    return res.status(400).json({ error: "No active fault-isolation session" });
  }

  if (session.phases.length === 0) {
    return res.status(400).json({ error: "No phases have been run yet" });
  }

  const verdict = deriveVerdict(session);
  session.verdict = verdict;

  res.json({ verdict, session });
});

/** POST /api/fault-isolator/reset */
router.post("/reset", (_req, res) => {
  session = null;
  res.json({ reset: true });
});

// ── Verdict logic ───────────────────────────────────────────────────

function deriveVerdict(s) {
  const latest = s.phases[s.phases.length - 1];
  if (!latest) return { type: "Unknown", confidence: "Low", detail: "No phase data" };

  const suspectedUp = latest.suspected.status === "Up" || latest.suspected.status === "Connected";
  const testUp = latest.testPort.status === "Up" || latest.testPort.status === "Connected";
  const suspectedErrors = latest.suspected.errors > 0;
  const testErrors = latest.testPort.errors > 0;
  const suspectedChanged = latest.baselineDelta.suspectedChanged;
  const testChanged = latest.baselineDelta.testChanged;

  // If the suspected port came back up after cable swap -> Cable issue
  if (suspectedChanged && suspectedUp && !suspectedErrors) {
    return {
      type: "Cable",
      confidence: "High",
      detail: "Suspected port recovered after cable change — cable was faulty.",
    };
  }

  // If the test port also fails -> NIC hardware issue
  if (!suspectedUp && !testUp) {
    return {
      type: "NicHardware",
      confidence: "Medium",
      detail: "Both ports are down — likely NIC hardware failure.",
    };
  }

  // If suspected port is down but test port works -> NicPort issue
  if (!suspectedUp && testUp && !testErrors) {
    return {
      type: "NicPort",
      confidence: "High",
      detail: "Suspected port is down while test port works — NIC port failure.",
    };
  }

  // If suspected port has errors and test port is clean with same cable
  if (suspectedUp && suspectedErrors && testUp && !testErrors) {
    return {
      type: "NicPort",
      confidence: "Medium",
      detail: "Suspected port has errors that test port does not — NIC port degraded.",
    };
  }

  // If test port also shows issues with the camera cable -> likely camera
  if (testUp && testErrors && suspectedErrors) {
    return {
      type: "LikelyCamera",
      confidence: "Medium",
      detail: "Both ports show errors with camera cable — camera may be faulty.",
    };
  }

  // Default: camera is most likely culprit
  return {
    type: "Camera",
    confidence: "Low",
    detail: "No definitive NIC or cable fault found — suspect camera.",
  };
}

export default router;
