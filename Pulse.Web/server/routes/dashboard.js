import { Router } from "express";
import { runScript } from "../powershell.js";

const router = Router();

/**
 * GET /api/dashboard
 *
 * Aggregates data from multiple PowerShell scripts into a single
 * DashboardSnapshot that the frontend can render in one fetch.
 */
router.get("/", async (_req, res) => {
  try {
    const [identity, performance, nics, services, diskHealth] =
      await Promise.all([
        runScript("Get-SystemIdentity.ps1"),
        runScript("Get-Performance.ps1"),
        runScript("Get-NicAdapters.ps1"),
        runScript("Get-Services.ps1"),
        runScript("Get-DiskHealth.ps1"),
      ]);

    const findings = generateFindings(performance, nics, services, diskHealth);

    const cs = identity.computerSystem ?? {};
    const bios = identity.bios ?? {};
    const nicPorts = (nics.ports ?? []).map((p) => ({
      ...p,
      isUp: p.status === "Up",
      isDegraded: p.linkSpeedMbps != null && p.linkSpeedMbps < 1000 && p.linkSpeedMbps !== 100,
      isFlapping: false,
      isOcr: p.linkSpeedMbps === 100,
    }));

    const snapshot = {
      identity: {
        hostname: cs.name ?? identity.hostname ?? null,
        manufacturer: cs.manufacturer ?? identity.manufacturer ?? null,
        model: cs.model ?? identity.model ?? null,
        serialNumber: bios.serialNumber ?? identity.serialNumber ?? null,
        isNonVpuHost: identity.isNonVpuHost ?? false,
        uptime: identity.uptime?.formatted ?? identity.uptime ?? null,
        pixellotVersion: identity.pixellot?.version ?? null,
        imageVersion: identity.pixellot?.imageVersion ?? null,
      },
      gauges: {
        cpu: performance.cpuPercent ?? performance.cpu ?? null,
        memory: performance.memoryPercent ?? performance.memory ?? null,
        disk: performance.diskPercent ?? performance.disk ?? null,
        temperature: performance.temperature ?? null,
      },
      nicPorts,
      services: services.services ?? (Array.isArray(services) ? services : []),
      volumes: diskHealth.volumes ?? (Array.isArray(diskHealth) ? diskHealth : []),
      findings,
    };

    res.json(snapshot);
  } catch (err) {
    console.error("Dashboard error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── Findings generator ──────────────────────────────────────────────

function finding(severity, category, title, recommendation) {
  return { severity, category, title, recommendation };
}

function generateFindings(perf, nics, services, diskHealth) {
  const results = [];

  const cpu = perf.cpuPercent ?? perf.cpu;
  if (typeof cpu === "number" && cpu > 85) {
    results.push(finding("Critical", "CPU", `CPU usage at ${cpu.toFixed(1)}%`, "Close unused applications or check for runaway processes"));
  }

  const mem = perf.memoryPercent ?? perf.memory;
  if (typeof mem === "number" && mem > 85) {
    results.push(finding("Critical", "Memory", `Memory usage at ${mem.toFixed(1)}%`, "Close unused applications or add more RAM"));
  }

  const disk = perf.diskPercent ?? perf.disk;
  if (typeof disk === "number" && disk > 85) {
    results.push(finding("Critical", "Disk", `Disk usage at ${disk.toFixed(1)}%`, "Free up disk space or expand storage"));
  }

  const temp = perf.temperature;
  if (typeof temp === "number") {
    if (temp > 80) {
      results.push(finding("Critical", "Temperature", `CPU temperature ${temp}°C`, "Check ventilation and cooling system"));
    } else if (temp > 70) {
      results.push(finding("Warning", "Temperature", `CPU temperature ${temp}°C`, "Monitor closely — ensure adequate airflow"));
    }
  }

  const svcList = Array.isArray(services.services) ? services.services : Array.isArray(services) ? services : [];
  for (const svc of svcList) {
    const status = svc.status ?? svc.Status;
    const name = svc.displayName ?? svc.name ?? svc.Name;
    if (status && status !== "Running" && status !== "NotFound") {
      const sev = status === "Stopped" ? "Critical" : "Warning";
      results.push(finding(sev, "Service", `${name} is ${status}`, "Navigate to Services to restart"));
    }
  }

  const nicList = Array.isArray(nics.ports) ? nics.ports : Array.isArray(nics.adapters) ? nics.adapters : [];
  for (const nic of nicList) {
    const errors = (nic.rxErrors ?? 0) + (nic.txErrors ?? 0);
    if (errors > 0) {
      results.push(finding("Warning", "Network", `${nic.name ?? "NIC"} has ${errors} errors`, "Check cable connections and NIC driver"));
    }
  }

  if (perf.internetReachable === false) {
    results.push(finding("Critical", "Network", "Internet is not reachable", "Check uplink cable and router connectivity"));
  }

  const order = { Critical: 0, Warning: 1, Info: 2 };
  results.sort((a, b) => (order[a.severity] ?? 9) - (order[b.severity] ?? 9));
  return results.slice(0, 5);
}

export default router;
