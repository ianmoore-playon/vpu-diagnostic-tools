import { Router } from "express";
import { writeFile, mkdir } from "fs/promises";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { existsSync } from "fs";
import { runScript } from "../powershell.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const router = Router();

const IS_WINDOWS = process.platform === "win32";

// ── Singleton state ─────────────────────────────────────────────────
let baselineState = {
  running: false,
  phase: null,
  progress: 0,
  findings: [],
};

const PHASES = [
  { name: "dashboard", label: "Dashboard" },
  { name: "system", label: "System Info" },
  { name: "network", label: "Network" },
  { name: "disk", label: "Disk Health" },
  { name: "services", label: "Services" },
  { name: "events", label: "Event Logs" },
  { name: "cameras", label: "Cameras" },
];

function finding(severity, category, message) {
  return { severity, category, message };
}

/** Get the directory where reports are stored. */
function getReportsDir() {
  if (IS_WINDOWS) {
    const localAppData = process.env.LOCALAPPDATA || join(process.env.USERPROFILE || "", "AppData", "Local");
    return join(localAppData, "Pulse.WPF", "Reports");
  }
  return join(__dirname, "..", "reports");
}

/** Run all phases sequentially, collecting findings. */
async function runBaseline() {
  baselineState = { running: true, phase: null, progress: 0, findings: [] };
  const results = {};

  for (let i = 0; i < PHASES.length; i++) {
    const phase = PHASES[i];
    baselineState.phase = phase.name;
    baselineState.progress = Math.round(((i) / PHASES.length) * 100);

    try {
      switch (phase.name) {
        case "dashboard": {
          const [perf, nics] = await Promise.all([
            runScript("Get-Performance.ps1"),
            runScript("Get-NicAdapters.ps1"),
          ]);
          results.dashboard = { perf, nics };
          const cpu = perf.cpuPercent ?? perf.cpu;
          if (typeof cpu === "number" && cpu > 85)
            baselineState.findings.push(finding("Critical", "CPU", `CPU at ${cpu.toFixed(1)}%`));
          const mem = perf.memoryPercent ?? perf.memory;
          if (typeof mem === "number" && mem > 85)
            baselineState.findings.push(finding("Critical", "Memory", `Memory at ${mem.toFixed(1)}%`));
          break;
        }
        case "system": {
          results.system = await runScript("Get-SystemIdentity.ps1");
          break;
        }
        case "network": {
          const [config, ports, domains, ntp] = await Promise.all([
            runScript("Get-NetworkConfig.ps1"),
            runScript("Test-NetworkPorts.ps1", {}, { timeout: 30_000 }),
            runScript("Test-NetworkDomains.ps1"),
            runScript("Test-NtpDrift.ps1"),
          ]);
          results.network = { config, ports, domains, ntp };
          break;
        }
        case "disk": {
          results.disk = await runScript("Get-DiskHealth.ps1");
          break;
        }
        case "services": {
          results.services = await runScript("Get-Services.ps1");
          const svcList = results.services.services ?? results.services ?? [];
          if (Array.isArray(svcList)) {
            for (const svc of svcList) {
              if ((svc.status ?? svc.Status) !== "Running") {
                baselineState.findings.push(
                  finding("Warning", "Service", `${svc.displayName ?? svc.name} is ${svc.status ?? svc.Status}`)
                );
              }
            }
          }
          break;
        }
        case "events": {
          results.events = await runScript("Get-EventLogs.ps1", { HoursBack: 48, Level: "all" });
          break;
        }
        case "cameras": {
          results.cameras = await runScript("Get-NicAdapters.ps1");
          break;
        }
      }
    } catch (err) {
      baselineState.findings.push(
        finding("Warning", phase.label, `Phase failed: ${err.message}`)
      );
    }
  }

  baselineState.progress = 100;
  baselineState.phase = "complete";

  // Generate report file
  try {
    await generateReport(results);
  } catch (err) {
    console.error("Failed to write baseline report:", err.message);
  }

  baselineState.running = false;
}

/** Write a text report to the reports directory. */
async function generateReport(results) {
  const dir = getReportsDir();
  if (!existsSync(dir)) {
    await mkdir(dir, { recursive: true });
  }

  const ts = new Date().toISOString().replace(/[:.]/g, "-");
  const filename = `Baseline_${ts}.txt`;
  const filePath = join(dir, filename);

  const lines = [
    "=== Pulse Baseline Report ===",
    `Generated: ${new Date().toISOString()}`,
    "",
    `Findings (${baselineState.findings.length}):`,
  ];

  for (const f of baselineState.findings) {
    lines.push(`  [${f.severity}] ${f.category}: ${f.message}`);
  }

  if (baselineState.findings.length === 0) {
    lines.push("  No issues found.");
  }

  lines.push("", "--- Raw Data ---", JSON.stringify(results, null, 2));

  await writeFile(filePath, lines.join("\n"), "utf-8");
}

// ── Routes ──────────────────────────────────────────────────────────

/** POST /api/baseline/run — kick off a baseline */
router.post("/run", (_req, res) => {
  if (baselineState.running) {
    return res.status(409).json({ error: "Baseline already running" });
  }

  // Fire and forget — the client polls /status
  runBaseline().catch((err) => {
    console.error("Baseline run error:", err.message);
    baselineState.running = false;
    baselineState.phase = "error";
  });

  res.json({ started: true });
});

/** GET /api/baseline/status */
router.get("/status", (_req, res) => {
  res.json(baselineState);
});

export default router;
