"""Pulse Web — FastAPI backend for VPU diagnostics."""

import os as _os
import sys as _sys

_app_dir = _os.path.dirname(_os.path.abspath(__file__))
if _app_dir not in _sys.path:
    _sys.path.insert(0, _app_dir)

import asyncio
import json

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query, Request
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from powershell import (
    run_ps, LOG_BUFFER, DEMO_MODE,
    get_running_tasks, cancel_task, cancel_all_tasks,
)

_web_root = _os.path.dirname(_app_dir)
SETTINGS_PATH = _os.path.join(_web_root, "pulse-settings.json")

def _read_version() -> str:
    import subprocess
    repo_root = _os.path.dirname(_web_root)
    try:
        result = subprocess.run(
            ["git", "for-each-ref", "--sort=-creatordate", "--count=1",
             "--format=%(refname:short)",
             "refs/tags/web-v*", "refs/tags/web-beta-v*", "refs/tags/web-dev-v*"],
            capture_output=True, text=True, cwd=repo_root, timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception:
        pass
    try:
        result = subprocess.run(
            ["git", "describe", "--tags", "--always"],
            capture_output=True, text=True, cwd=repo_root, timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception:
        pass
    try:
        with open(_os.path.join(_web_root, "VERSION")) as f:
            return f.read().strip()
    except FileNotFoundError:
        return "unknown"

APP_VERSION = _read_version()
_static_dir = _os.path.join(_app_dir, "static")

app = FastAPI(title="Pulse Web | VPU Diagnostics")
app.mount("/static", StaticFiles(directory=_static_dir), name="static")

PIXELLOT_OUIS = ["00:0E:53", "00:30:53", "70:B3:D5"]


def load_settings() -> dict:
    try:
        with open(SETTINGS_PATH, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"scoreConnectUrl": "http://localhost:5000", "pollIntervalMs": 3000}


def save_settings(data: dict) -> None:
    with open(SETTINGS_PATH, "w") as f:
        json.dump(data, f, indent=2)


def _is_pixellot_mac(mac: str) -> bool:
    if not mac:
        return False
    normalized = mac.upper().replace("-", ":").replace(".", ":")
    parts = normalized.split(":")
    if len(parts) >= 3:
        prefix = ":".join(parts[:3])
        return prefix in PIXELLOT_OUIS
    return False


def _compute_findings(identity, performance, services, nics) -> list:
    findings = []

    if identity and not identity.get("error"):
        uptime_secs = identity.get("uptime", {}).get("totalSeconds", 0)
        if uptime_secs and uptime_secs > 30 * 86400:
            findings.append(
                {
                    "severity": "warning",
                    "category": "System",
                    "title": "High Uptime",
                    "recommendation": f"System running {uptime_secs // 86400} days. Consider a reboot.",
                }
            )

    if performance and not performance.get("error"):
        cpu = performance.get("cpu", {}).get("usagePercent", 0)
        if cpu and cpu > 90:
            findings.append(
                {
                    "severity": "critical",
                    "category": "Performance",
                    "title": "CPU Usage Critical",
                    "recommendation": f"CPU at {cpu}%. Check for runaway processes.",
                }
            )
        elif cpu and cpu > 75:
            findings.append(
                {
                    "severity": "warning",
                    "category": "Performance",
                    "title": "CPU Usage Elevated",
                    "recommendation": f"CPU at {cpu}%. Monitor for sustained high usage.",
                }
            )

        mem = performance.get("memory", {}).get("usedPercent", 0)
        if mem and mem > 90:
            findings.append(
                {
                    "severity": "critical",
                    "category": "Performance",
                    "title": "Memory Usage Critical",
                    "recommendation": f"Memory at {mem}%. Close apps or add RAM.",
                }
            )

        disk = performance.get("disk", {}).get("usedPercent", 0)
        if disk and disk > 90:
            findings.append(
                {
                    "severity": "critical",
                    "category": "Storage",
                    "title": "Disk Space Critical",
                    "recommendation": f"Disk at {disk}%. Free space immediately.",
                }
            )
        elif disk and disk > 80:
            findings.append(
                {
                    "severity": "warning",
                    "category": "Storage",
                    "title": "Disk Space Low",
                    "recommendation": f"Disk at {disk}%. Plan cleanup soon.",
                }
            )

        temp = performance.get("temperature", {}).get("celsius")
        if temp and temp > 85:
            findings.append(
                {
                    "severity": "critical",
                    "category": "Hardware",
                    "title": "Temperature Critical",
                    "recommendation": f"Temperature at {temp}°C. Check cooling.",
                }
            )

    if services and not services.get("error"):
        for svc in services.get("services", []):
            if svc["status"] == "Stopped" and svc["name"] in (
                "PixellotAgent",
                "PixellotVPU",
            ):
                findings.append(
                    {
                        "severity": "critical",
                        "category": "Services",
                        "title": f"{svc['name']} Stopped",
                        "recommendation": f"Restart {svc['name']} from the Services page.",
                    }
                )
            elif svc["status"] == "NotFound" and svc["name"] in (
                "PixellotAgent",
                "PixellotVPU",
            ):
                findings.append(
                    {
                        "severity": "warning",
                        "category": "Services",
                        "title": f"{svc['name']} Not Installed",
                        "recommendation": f"{svc['name']} was not found on this system.",
                    }
                )

    if nics and not nics.get("error"):
        for port in nics.get("ports", []):
            if port.get("status") != "Up":
                findings.append(
                    {
                        "severity": "warning",
                        "category": "Network",
                        "title": f"NIC {port['name']} Down",
                        "recommendation": f"{port['name']} is {port.get('status', 'unknown')}. Check cable.",
                    }
                )
            speed = port.get("linkSpeedMbps")
            if (
                port.get("status") == "Up"
                and speed
                and speed < 1000
                and speed != 100
            ):
                findings.append(
                    {
                        "severity": "warning",
                        "category": "Network",
                        "title": f"NIC {port['name']} Degraded",
                        "recommendation": f"Running at {speed} Mbps, expected 1 Gbps.",
                    }
                )

    return findings


def _enrich_ports(nics: dict) -> list:
    ports = []
    if nics and not nics.get("error"):
        for port in nics.get("ports", []):
            speed = port.get("linkSpeedMbps")
            is_up = port.get("status") == "Up"
            is_ocr = speed == 100
            cameras = [
                arp
                for arp in port.get("arpEntries", [])
                if _is_pixellot_mac(arp.get("mac", ""))
            ]
            ports.append(
                {
                    **port,
                    "isUp": is_up,
                    "isOcr": is_ocr,
                    "isDegraded": is_up
                    and speed is not None
                    and speed < 1000
                    and not is_ocr,
                    "camerasDetected": cameras,
                }
            )
    return ports


# ─── Data-building helpers (shared by per-page and preload) ──


def _build_dashboard(identity, performance, services, nics):
    flat_identity = {}
    if identity and not identity.get("error"):
        flat_identity = {
            "hostname": identity.get("computerSystem", {}).get("name"),
            "manufacturer": identity.get("computerSystem", {}).get("manufacturer"),
            "model": identity.get("computerSystem", {}).get("model"),
            "serialNumber": identity.get("bios", {}).get("serialNumber"),
            "uptime": identity.get("uptime", {}).get("formatted"),
            "uptimeSeconds": identity.get("uptime", {}).get("totalSeconds"),
            "os": identity.get("operatingSystem", {}).get("caption"),
            "osVersion": identity.get("operatingSystem", {}).get("version"),
            "pixellotVersion": identity.get("pixellot", {}).get("version"),
            "imageVersion": identity.get("pixellot", {}).get("imageVersion"),
            "isNonVpuHost": identity.get("isNonVpuHost", False),
        }

    return {
        "identity": flat_identity,
        "performance": performance if not performance.get("error", False) else {},
        "services": services if not services.get("error", False) else {"services": []},
        "findings": _compute_findings(identity, performance, services, nics),
    }


def _build_network(config, domains, ports, ntp):
    net = {}
    if config and not config.get("error"):
        net = {
            "adapters": config.get("adapters", []),
            "ipConfig": config.get("ipConfigurations", []),
            "uplinkAdapter": config.get("uplinkAdapter"),
            "internetReachable": config.get("internet", {}).get("reachable", False),
            "testedHost": config.get("internet", {}).get("testedHost"),
            "ntpSource": config.get("ntpSource"),
        }

    return {"config": net, "domains": domains, "ports": ports, "ntp": ntp}


# ─── Routes ───────────────────────────────────────────────────


@app.get("/")
async def serve_index():
    return FileResponse(_os.path.join(_static_dir, "index.html"))


@app.get("/api/preload")
async def api_preload():
    """Run ALL diagnostic scripts once in parallel and return per-page data."""
    (
        identity,
        hardware,
        performance,
        network_config,
        nics,
        services,
        disk_health,
        event_logs,
        scoreconnect,
        pixellot_config,
        installed_sw,
        domains,
        ports,
        ntp,
    ) = await asyncio.gather(
        run_ps("Get-SystemIdentity.ps1"),
        run_ps("Get-Hardware.ps1"),
        run_ps("Get-Performance.ps1"),
        run_ps("Get-NetworkConfig.ps1"),
        run_ps("Get-NicAdapters.ps1"),
        run_ps("Get-Services.ps1"),
        run_ps("Get-DiskHealth.ps1"),
        run_ps("Get-EventLogs.ps1"),
        run_ps("Get-ScoreConnectStatus.ps1"),
        run_ps("Get-PixellotConfig.ps1"),
        run_ps("Get-InstalledSoftware.ps1"),
        run_ps("Test-NetworkDomains.ps1"),
        run_ps("Test-NetworkPorts.ps1"),
        run_ps("Test-NtpDrift.ps1"),
    )

    return {
        "dashboard": _build_dashboard(identity, performance, services, nics),
        "system": {
            "identity": identity,
            "hardware": hardware,
            "software": installed_sw,
        },
        "network": _build_network(network_config, domains, ports, ntp),
        "cameras": {
            "ports": _enrich_ports(nics),
            "pixellotConfig": pixellot_config,
        },
        "services": services,
        "disk-health": disk_health,
        "events": event_logs,
        "scoreconnect": scoreconnect,
        "settings": load_settings(),
        "_version": APP_VERSION,
        "_logs": list(LOG_BUFFER),
    }


@app.get("/api/version")
async def api_version():
    return {"version": APP_VERSION}


@app.get("/api/logs")
async def api_logs(since: int = Query(default=0)):
    """Return recent script execution logs. `since` is an index offset."""
    logs = list(LOG_BUFFER)
    return {"demoMode": DEMO_MODE, "logs": logs[since:], "total": len(logs)}


@app.get("/api/scripts/running")
async def api_scripts_running():
    return {"tasks": get_running_tasks()}


@app.post("/api/scripts/cancel")
async def api_scripts_cancel(request: Request):
    body = await request.json()
    task_id = body.get("taskId", "")
    return {"ok": cancel_task(task_id)}


@app.post("/api/scripts/cancel-all")
async def api_scripts_cancel_all():
    count = cancel_all_tasks()
    return {"ok": True, "cancelled": count}


@app.get("/api/dashboard")
async def api_dashboard():
    identity, performance, services, nics = await asyncio.gather(
        run_ps("Get-SystemIdentity.ps1"),
        run_ps("Get-Performance.ps1"),
        run_ps("Get-Services.ps1"),
        run_ps("Get-NicAdapters.ps1"),
    )
    return _build_dashboard(identity, performance, services, nics)


@app.get("/api/system")
async def api_system():
    identity, hardware, software = await asyncio.gather(
        run_ps("Get-SystemIdentity.ps1"),
        run_ps("Get-Hardware.ps1"),
        run_ps("Get-InstalledSoftware.ps1"),
    )
    return {"identity": identity, "hardware": hardware, "software": software}


@app.get("/api/network")
async def api_network():
    config, domains, ports, ntp = await asyncio.gather(
        run_ps("Get-NetworkConfig.ps1"),
        run_ps("Test-NetworkDomains.ps1"),
        run_ps("Test-NetworkPorts.ps1"),
        run_ps("Test-NtpDrift.ps1"),
    )
    return _build_network(config, domains, ports, ntp)


@app.get("/api/cameras")
async def api_cameras():
    nics, pix_config = await asyncio.gather(
        run_ps("Get-NicAdapters.ps1"),
        run_ps("Get-PixellotConfig.ps1"),
    )
    return {"ports": _enrich_ports(nics), "pixellotConfig": pix_config}


@app.get("/api/services")
async def api_services():
    return await run_ps("Get-Services.ps1")


@app.post("/api/services/restart")
async def api_restart_service(request: Request):
    body = await request.json()
    name = body.get("serviceName", "")
    return await run_ps("Restart-Service.ps1", {"ServiceName": name}, timeout=60)


@app.get("/api/disk-health")
async def api_disk_health():
    return await run_ps("Get-DiskHealth.ps1")


@app.get("/api/events")
async def api_events(
    hours: int = Query(default=48), level: str = Query(default="all")
):
    return await run_ps("Get-EventLogs.ps1", {"HoursBack": hours, "Level": level})


@app.get("/api/scoreconnect")
async def api_scoreconnect():
    settings = load_settings()
    url = settings.get("scoreConnectUrl", "http://localhost:5000")
    return await run_ps("Get-ScoreConnectStatus.ps1", {"BaseUrl": url})


@app.get("/api/settings")
async def api_get_settings():
    return load_settings()


@app.post("/api/settings")
async def api_save_settings(request: Request):
    body = await request.json()
    save_settings(body)
    return {"ok": True}


@app.get("/api/reports/export")
async def api_export():
    keys = [
        "identity",
        "hardware",
        "performance",
        "networkConfig",
        "nicAdapters",
        "services",
        "diskHealth",
        "eventLogs",
        "scoreConnect",
        "pixellotConfig",
        "installedSoftware",
        "networkDomains",
        "networkPorts",
        "ntpDrift",
    ]
    results = await asyncio.gather(
        run_ps("Get-SystemIdentity.ps1"),
        run_ps("Get-Hardware.ps1"),
        run_ps("Get-Performance.ps1"),
        run_ps("Get-NetworkConfig.ps1"),
        run_ps("Get-NicAdapters.ps1"),
        run_ps("Get-Services.ps1"),
        run_ps("Get-DiskHealth.ps1"),
        run_ps("Get-EventLogs.ps1"),
        run_ps("Get-ScoreConnectStatus.ps1"),
        run_ps("Get-PixellotConfig.ps1"),
        run_ps("Get-InstalledSoftware.ps1"),
        run_ps("Test-NetworkDomains.ps1"),
        run_ps("Test-NetworkPorts.ps1"),
        run_ps("Test-NtpDrift.ps1"),
    )
    return dict(zip(keys, results))


# ─── WebSocket — live metrics ─────────────────────────────────


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    try:
        settings = load_settings()
        interval = max(settings.get("pollIntervalMs", 3000), 1000) / 1000
        last_log_idx = len(LOG_BUFFER)

        while True:
            perf, nics = await asyncio.gather(
                run_ps("Get-Performance.ps1", timeout=10),
                run_ps("Get-NicAdapters.ps1", timeout=10),
            )
            all_logs = list(LOG_BUFFER)
            new_logs = all_logs[last_log_idx:]
            last_log_idx = len(all_logs)

            await ws.send_json(
                {
                    "type": "metrics",
                    "performance": perf,
                    "ports": _enrich_ports(nics),
                    "logs": new_logs,
                }
            )
            await asyncio.sleep(interval)
    except WebSocketDisconnect:
        pass
    except Exception:
        pass


# ─── Entry point ──────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn

    port = int(_os.environ.get("PORT", 8765))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
