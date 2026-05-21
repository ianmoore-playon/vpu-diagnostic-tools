import { Router } from "express";
import { runScript } from "../powershell.js";

const router = Router();

/**
 * Services that can be restarted through the API.
 * Restrict to known Pixellot / VPU services to avoid
 * accidentally restarting critical OS services.
 */
const ALLOWED_SERVICES = new Set([
  "PixellotAgent",
  "PixellotService",
  "PixellotUpdater",
  "PixellotWatchdog",
  "ScoreConnect",
  "ScoreConnectService",
  "NVDisplay.ContainerLocalSystem",
  "WinRM",
  "W32Time",
]);

/** GET /api/services */
router.get("/", async (_req, res) => {
  try {
    const data = await runScript("Get-Services.ps1");
    res.json(data);
  } catch (err) {
    console.error("Services error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/services/:name/restart
 *
 * Restarts a service by name. The name must be in the allow-list.
 */
router.post("/:name/restart", async (req, res) => {
  const { name } = req.params;

  if (!ALLOWED_SERVICES.has(name)) {
    return res.status(403).json({
      success: false,
      message: `Service "${name}" is not in the allowed restart list`,
    });
  }

  try {
    const result = await runScript("Restart-Service.ps1", { ServiceName: name });
    res.json({ success: true, message: `Service ${name} restarted`, detail: result });
  } catch (err) {
    console.error(`Service restart error (${name}):`, err.message);
    res.status(500).json({ success: false, message: err.message });
  }
});

export default router;
