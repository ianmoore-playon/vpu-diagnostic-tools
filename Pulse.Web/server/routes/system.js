import { Router } from "express";
import { runScript } from "../powershell.js";

const router = Router();

/**
 * GET /api/system
 *
 * Returns system identity, hardware breakdown, installed software, and OS
 * information shaped into 6 summary cards for the frontend.
 */
router.get("/", async (_req, res) => {
  try {
    const [identity, hardware, software] = await Promise.all([
      runScript("Get-SystemIdentity.ps1"),
      runScript("Get-Hardware.ps1"),
      runScript("Get-InstalledSoftware.ps1"),
    ]);

    const cs = identity.computerSystem ?? {};
    const os = identity.operatingSystem ?? {};
    const bios = identity.bios ?? {};

    const cpuInfo = hardware.cpu ?? hardware.processor ?? {};
    const memInfo = hardware.memory ?? {};
    const gpuInfo = hardware.gpu ?? hardware.videoController ?? {};
    const diskInfo = hardware.disks ?? hardware.physicalDisks ?? [];
    const monitorInfo = hardware.monitors ?? [];

    // Shape into 6 summary cards
    const cards = {
      vpuIdentity: {
        model: cs.model ?? null,
        hostname: cs.name ?? null,
        serial: bios.serialNumber ?? null,
        manufacturer: cs.manufacturer ?? null,
        assetTag: identity.assetTag ?? null,
        pixellotVersion: identity.pixellot?.version ?? null,
        imageVersion: identity.pixellot?.imageVersion ?? null,
      },
      operatingSystem: {
        caption: os.caption ?? null,
        version: os.version ?? null,
        build: os.buildNumber ?? null,
        arch: os.osArchitecture ?? null,
        installDate: os.installDate ?? null,
      },
      cpu: {
        name: cpuInfo.name ?? cpuInfo.Name ?? null,
        cores: cpuInfo.cores ?? cpuInfo.numberOfCores ?? null,
        threads: cpuInfo.threads ?? cpuInfo.numberOfLogicalProcessors ?? null,
        clock: cpuInfo.maxClockSpeed ?? cpuInfo.clock ?? null,
      },
      memory: {
        totalGB: memInfo.totalGB ?? memInfo.total ?? null,
        type: memInfo.type ?? memInfo.memoryType ?? null,
        speed: memInfo.speed ?? memInfo.configuredClockSpeed ?? null,
        stickCount: memInfo.stickCount ?? memInfo.count ?? null,
      },
      gpu: {
        name: gpuInfo.name ?? gpuInfo.Name ?? null,
        vram: gpuInfo.vram ?? gpuInfo.adapterRAM ?? null,
        driver: gpuInfo.driverVersion ?? gpuInfo.driver ?? null,
      },
      storage: {
        diskCount: Array.isArray(diskInfo) ? diskInfo.length : diskInfo.count ?? null,
        totalCapacityGB: Array.isArray(diskInfo)
          ? diskInfo.reduce((sum, d) => sum + (d.sizeGB ?? d.size ?? 0), 0)
          : diskInfo.totalCapacityGB ?? null,
      },
    };

    const flatIdentity = {
      hostname: cs.name ?? null,
      manufacturer: cs.manufacturer ?? null,
      model: cs.model ?? null,
      serialNumber: bios.serialNumber ?? null,
      biosVersion: bios.smbiosVersion ?? null,
      assetTag: identity.assetTag ?? null,
      pixellotVersion: identity.pixellot?.version ?? null,
      imageVersion: identity.pixellot?.imageVersion ?? null,
    };

    const flatOs = {
      caption: os.caption ?? null,
      version: os.version ?? null,
      buildNumber: os.buildNumber ?? null,
      architecture: os.osArchitecture ?? null,
      installDate: os.installDate ?? null,
      lastBootUpTime: os.lastBootUpTime ?? null,
      timeZone: identity.timezone ?? null,
      lastKb: hardware.lastKb ?? null,
    };

    const flatCpu = {
      name: cpuInfo.name ?? cpuInfo.Name ?? null,
      cores: cpuInfo.cores ?? cpuInfo.numberOfCores ?? null,
      logicalProcessors: cpuInfo.threads ?? cpuInfo.numberOfLogicalProcessors ?? null,
      maxClockSpeed: cpuInfo.maxClockSpeed ?? cpuInfo.clock ?? null,
      socket: cpuInfo.socket ?? cpuInfo.socketDesignation ?? null,
      l2CacheSize: cpuInfo.l2CacheSize ?? cpuInfo.l2Cache ?? null,
      l3CacheSize: cpuInfo.l3CacheSize ?? cpuInfo.l3Cache ?? null,
    };

    const flatMemory = {
      totalBytes: memInfo.totalBytes ?? (memInfo.totalGB ? memInfo.totalGB * 1073741824 : null),
      sticks: memInfo.sticks ?? memInfo.modules ?? [],
    };

    const flatGpu = {
      name: gpuInfo.name ?? gpuInfo.Name ?? null,
      adapterRam: gpuInfo.adapterRAM ?? gpuInfo.vram ?? null,
      driverVersion: gpuInfo.driverVersion ?? gpuInfo.driver ?? null,
      driverDate: gpuInfo.driverDate ?? null,
    };

    res.json({
      identity: flatIdentity,
      hardware: {
        cpu: flatCpu,
        memory: flatMemory,
        gpu: flatGpu,
        monitorCount: Array.isArray(monitorInfo) ? monitorInfo.length : monitorInfo.count ?? 0,
        disks: Array.isArray(diskInfo) ? diskInfo : [],
      },
      installedSoftware: software.software ?? (Array.isArray(software) ? software : []),
      os: flatOs,
    });
  } catch (err) {
    console.error("System error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;
