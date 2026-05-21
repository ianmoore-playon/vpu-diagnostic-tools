import { Router } from "express";
import { runScript } from "../powershell.js";
import { readFile } from "fs/promises";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SETTINGS_PATH = join(__dirname, "..", "pulse-settings.json");

const router = Router();

/** Read the configured ScoreConnect base URL (fallback to localhost:5000). */
async function getScoreConnectUrl() {
  try {
    const raw = await readFile(SETTINGS_PATH, "utf-8");
    const settings = JSON.parse(raw);
    return settings.scoreConnectUrl || "http://localhost:5000";
  } catch {
    return "http://localhost:5000";
  }
}

/** Proxy helper — fetch with a 5-second timeout. */
async function proxyGet(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5000);
  try {
    const resp = await fetch(url, { signal: controller.signal });
    const data = await resp.json();
    return { data, error: null };
  } catch (err) {
    return { data: null, error: err.message };
  } finally {
    clearTimeout(timer);
  }
}

async function proxyPost(url, body) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5000);
  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const data = await resp.json();
    return { data, error: null };
  } catch (err) {
    return { data: null, error: err.message };
  } finally {
    clearTimeout(timer);
  }
}

/** GET /api/scoreconnect/status */
router.get("/status", async (_req, res) => {
  try {
    const data = await runScript("Get-ScoreConnectStatus.ps1");
    res.json(data);
  } catch (err) {
    console.error("ScoreConnect status error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/** GET /api/scoreconnect/config — proxy to ScoreConnect API */
router.get("/config", async (_req, res) => {
  try {
    const base = await getScoreConnectUrl();
    const result = await proxyGet(`${base}/api/config`);
    res.json(result);
  } catch (err) {
    res.status(500).json({ data: null, error: err.message });
  }
});

/** GET /api/scoreconnect/vendors */
router.get("/vendors", async (_req, res) => {
  try {
    const base = await getScoreConnectUrl();
    const result = await proxyGet(`${base}/api/vendors`);
    res.json(result);
  } catch (err) {
    res.status(500).json({ data: null, error: err.message });
  }
});

/** GET /api/scoreconnect/vendors/:id/sports */
router.get("/vendors/:id/sports", async (req, res) => {
  try {
    const base = await getScoreConnectUrl();
    const result = await proxyGet(`${base}/api/vendors/${req.params.id}/sports`);
    res.json(result);
  } catch (err) {
    res.status(500).json({ data: null, error: err.message });
  }
});

/** POST /api/scoreconnect/configure */
router.post("/configure", async (req, res) => {
  try {
    const base = await getScoreConnectUrl();
    const result = await proxyPost(`${base}/api/configure`, req.body);
    res.json(result);
  } catch (err) {
    res.status(500).json({ data: null, error: err.message });
  }
});

export default router;
