import { Router } from "express";
import { readFile, writeFile } from "fs/promises";
import { existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SETTINGS_PATH = join(__dirname, "..", "pulse-settings.json");

const router = Router();

const DEFAULT_SETTINGS = {
  scoreConnectUrl: "http://localhost:5000",
  pollingIntervalMs: 2000,
};

/** Ensure settings file exists with defaults. */
async function ensureSettings() {
  if (!existsSync(SETTINGS_PATH)) {
    await writeFile(SETTINGS_PATH, JSON.stringify(DEFAULT_SETTINGS, null, 2), "utf-8");
  }
}

/** GET /api/settings */
router.get("/", async (_req, res) => {
  try {
    await ensureSettings();
    const raw = await readFile(SETTINGS_PATH, "utf-8");
    res.json(JSON.parse(raw));
  } catch (err) {
    console.error("Settings read error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/** POST /api/settings */
router.post("/", async (req, res) => {
  try {
    await ensureSettings();

    const existing = JSON.parse(await readFile(SETTINGS_PATH, "utf-8"));
    const updated = { ...existing };

    // Only allow known keys to be written
    if (typeof req.body.scoreConnectUrl === "string") {
      updated.scoreConnectUrl = req.body.scoreConnectUrl;
    }
    if (typeof req.body.pollingIntervalMs === "number" && req.body.pollingIntervalMs > 0) {
      updated.pollingIntervalMs = req.body.pollingIntervalMs;
    }

    await writeFile(SETTINGS_PATH, JSON.stringify(updated, null, 2), "utf-8");
    res.json(updated);
  } catch (err) {
    console.error("Settings write error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;
