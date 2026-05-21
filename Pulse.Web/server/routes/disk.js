import { Router } from "express";
import { runScript } from "../powershell.js";

const router = Router();

/**
 * GET /api/disk
 *
 * Returns volume information, physical disk details, recent disk errors,
 * and notable path sizes from Get-DiskHealth.ps1.
 */
router.get("/", async (_req, res) => {
  try {
    const data = await runScript("Get-DiskHealth.ps1");

    res.json({
      volumes: data.volumes ?? [],
      physicalDisks: data.physicalDisks ?? [],
      recentErrors: data.recentErrors ?? [],
      pathSizes: data.pathSizes ?? data.paths ?? {},
    });
  } catch (err) {
    console.error("Disk error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;
