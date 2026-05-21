import { Router } from "express";
import { runScript } from "../powershell.js";

const router = Router();

/** Known Pixellot camera MAC OUIs (first 3 octets) */
const PIXELLOT_OUIS = ["00:0E:53", "00:30:53", "70:B3:D5"];

/**
 * GET /api/cameras
 *
 * Enriches NIC adapter data with Pixellot camera config.
 * A port is flagged as a "camera port" when:
 *   - link speed is 100 Mbps, AND
 *   - the connected device's MAC matches a known Pixellot OUI.
 */
router.get("/", async (_req, res) => {
  try {
    const [nics, pixConfig] = await Promise.all([
      runScript("Get-NicAdapters.ps1"),
      runScript("Get-PixellotConfig.ps1").catch(() => null),
    ]);

    const rawPorts = Array.isArray(nics.ports) ? nics.ports : Array.isArray(nics.adapters) ? nics.adapters : [];

    const cameras = [];
    const configuredCameras = pixConfig?.cameras ?? [];

    const ports = rawPorts.map((p) => {
      const isUp = p.status === "Up";
      const isOcr = isUp && p.linkSpeedMbps === 100;

      const arpMacs = (p.arpEntries || []).map((a) => (a.mac || "").toUpperCase().replace(/-/g, ":"));
      const hasPixellotDevice = arpMacs.some((m) =>
        PIXELLOT_OUIS.some((oui) => m.startsWith(oui)),
      );

      if (isOcr || hasPixellotDevice) {
        for (const arp of p.arpEntries || []) {
          cameras.push({ ip: arp.ip, mac: arp.mac, role: isOcr ? "OCR" : "Camera" });
        }
      }

      return {
        ...p,
        isUp,
        isOcr,
        isDegraded: isUp && p.linkSpeedMbps != null && p.linkSpeedMbps < 1000 && !isOcr,
        isFlapping: false,
      };
    });

    for (const cam of configuredCameras) {
      if (!cameras.find((c) => c.ip === cam.ip)) {
        cameras.push(cam);
      }
    }

    res.json({ ports, cameras });
  } catch (err) {
    console.error("Cameras error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;
