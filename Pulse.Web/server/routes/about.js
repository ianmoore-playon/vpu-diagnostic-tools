import { Router } from "express";
import { hostname, platform } from "os";

const router = Router();

/** GET /api/about */
router.get("/", (_req, res) => {
  res.json({
    version: "0.9.0-web",
    hostname: hostname(),
    platform: platform(),
  });
});

export default router;
