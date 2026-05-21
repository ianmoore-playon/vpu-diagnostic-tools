import { Router } from "express";
import { readdir, readFile, stat } from "fs/promises";
import { join, basename, resolve } from "path";
import { existsSync } from "fs";

const router = Router();

const IS_WINDOWS = process.platform === "win32";

/** Resolve the reports directory. On Windows use the real path; otherwise mock. */
function getReportsDir() {
  if (IS_WINDOWS) {
    const localAppData = process.env.LOCALAPPDATA || join(process.env.USERPROFILE || "", "AppData", "Local");
    return join(localAppData, "Pulse.WPF", "Reports");
  }
  // Dev fallback — use a local reports folder next to the server
  return join(process.cwd(), "server", "reports");
}

/**
 * Sanitize a filename to prevent path-traversal attacks.
 * Only allow alphanumeric, hyphens, underscores, dots, and spaces.
 */
function sanitizeFilename(name) {
  const base = basename(name); // strip any directory components
  if (/[^a-zA-Z0-9._\- ]/.test(base)) return null;
  if (base.includes("..")) return null;
  return base;
}

/** GET /api/reports — list report files */
router.get("/", async (_req, res) => {
  try {
    const dir = getReportsDir();

    if (!existsSync(dir)) {
      return res.json({ reports: [] });
    }

    const files = await readdir(dir);
    const txtFiles = files
      .filter((f) => f.endsWith(".txt"))
      .map((f) => ({
        filename: f,
        path: join(dir, f),
      }));

    // Attach file stats (size, mtime) for each report
    const reports = await Promise.all(
      txtFiles.map(async ({ filename, path: filePath }) => {
        try {
          const stats = await stat(filePath);
          return {
            filename,
            sizeBytes: stats.size,
            modified: stats.mtime.toISOString(),
          };
        } catch {
          return { filename, sizeBytes: null, modified: null };
        }
      })
    );

    res.json({ reports });
  } catch (err) {
    console.error("Reports list error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/** GET /api/reports/:filename — read a specific report */
router.get("/:filename", async (req, res) => {
  try {
    const safe = sanitizeFilename(req.params.filename);
    if (!safe) {
      return res.status(400).json({ error: "Invalid filename" });
    }

    const dir = getReportsDir();
    const filePath = resolve(dir, safe);

    // Double-check the resolved path is still inside the reports dir
    if (!filePath.startsWith(resolve(dir))) {
      return res.status(403).json({ error: "Access denied" });
    }

    const content = await readFile(filePath, "utf-8");
    res.json({ filename: safe, content });
  } catch (err) {
    if (err.code === "ENOENT") {
      return res.status(404).json({ error: "Report not found" });
    }
    console.error("Report read error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;
