import { Router } from "express";
import { runScript } from "../powershell.js";

const router = Router();

/** GET /api/network/config */
router.get("/config", async (_req, res) => {
  try {
    const data = await runScript("Get-NetworkConfig.ps1");
    const ipConfigs = data.ipConfigurations ?? data.ipConfig ?? [];
    const ipConfig = ipConfigs.map((ipc) => ({
      interfaceAlias: ipc.interfaceAlias,
      ipv4Address: Array.isArray(ipc.ipv4Address) ? ipc.ipv4Address.join(", ") : ipc.ipv4Address,
      gateway: Array.isArray(ipc.ipv4DefaultGateway) ? ipc.ipv4DefaultGateway[0] : ipc.ipv4DefaultGateway,
      dnsServers: Array.isArray(ipc.dnsServers) ? ipc.dnsServers.flat() : [],
    }));
    res.json({
      adapters: data.adapters ?? [],
      ipConfig,
      internetReachable: data.internet?.reachable ?? data.internetReachable ?? null,
      ntpSource: data.ntpSource ?? null,
      uplinkAdapter: data.uplinkAdapter?.interfaceAlias ?? data.uplinkAdapter ?? null,
    });
  } catch (err) {
    console.error("Network config error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/** GET /api/network/ports — may take a while, allow 30 s */
router.get("/ports", async (_req, res) => {
  try {
    const data = await runScript("Test-NetworkPorts.ps1", {}, { timeout: 30_000 });
    res.json(data);
  } catch (err) {
    console.error("Network ports error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/** GET /api/network/domains */
router.get("/domains", async (_req, res) => {
  try {
    const data = await runScript("Test-NetworkDomains.ps1");
    res.json(data);
  } catch (err) {
    console.error("Network domains error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/** GET /api/network/ntp */
router.get("/ntp", async (_req, res) => {
  try {
    const data = await runScript("Test-NtpDrift.ps1");
    res.json(data);
  } catch (err) {
    console.error("NTP error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/** GET /api/network/all — runs every network check in parallel */
router.get("/all", async (_req, res) => {
  try {
    const [config, ports, domains, ntp] = await Promise.all([
      runScript("Get-NetworkConfig.ps1"),
      runScript("Test-NetworkPorts.ps1", {}, { timeout: 30_000 }),
      runScript("Test-NetworkDomains.ps1"),
      runScript("Test-NtpDrift.ps1"),
    ]);
    res.json({ config, ports, domains, ntp });
  } catch (err) {
    console.error("Network all error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;
