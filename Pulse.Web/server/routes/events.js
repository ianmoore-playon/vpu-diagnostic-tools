import { Router } from "express";
import { runScript } from "../powershell.js";

const router = Router();

/**
 * GET /api/events
 *
 * Query params:
 *   hours  – how far back to look (default 48)
 *   level  – "all", "Error", "Warning", etc. (default "all")
 */
router.get("/", async (req, res) => {
  const hours = parseInt(req.query.hours, 10) || 48;
  const level = req.query.level || "all";

  try {
    const data = await runScript("Get-EventLogs.ps1", {
      HoursBack: hours,
      Level: level,
    });

    res.json({
      entries: data.entries ?? data.events ?? [],
      totalCount: data.totalCount ?? data.count ?? 0,
    });
  } catch (err) {
    console.error("Events error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;
