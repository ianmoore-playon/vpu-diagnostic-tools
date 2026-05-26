"""Pulse Web — FastAPI backend for VPU diagnostics."""

import os as _os
import sys as _sys

_app_dir = _os.path.dirname(_os.path.abspath(__file__))
if _app_dir not in _sys.path:
    _sys.path.insert(0, _app_dir)

import asyncio
import json

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query, Request
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles

from powershell import (
    run_ps, LOG_BUFFER, DEMO_MODE, _log as ps_log,
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

SERVER_LOG_PATH = _os.path.join(_web_root, "pulse-server.log")

app = FastAPI(title="Pulse Web | VPU Diagnostics")
app.mount("/static", StaticFiles(directory=_static_dir), name="static")

PIXELLOT_OUIS = ["00:0E:53", "00:30:53", "70:B3:D5"]


@app.on_event("startup")
async def _on_startup():
    """Log startup info so the Script Log shows server activity."""
    ps_log("server", 0, "ok", f"Pulse Web {APP_VERSION} starting")
    ps_log("server", 0, "ok", f"Python {_sys.version.split()[0]} | port {_os.environ.get('PORT', 8765)}")


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
        critical_svcs = {"agent"}  # vpu not running is normal (idle state)
        for svc in services.get("services", []):
            name_lower = svc["name"].lower()
            display = svc.get("displayName") or svc["name"]
            if svc["status"] == "Stopped" and name_lower in critical_svcs:
                findings.append(
                    {
                        "severity": "critical",
                        "category": "Services",
                        "title": f"{display} Stopped",
                        "recommendation": f"Restart {display} from the Services page.",
                    }
                )
            elif svc["status"] == "NotFound" and name_lower in critical_svcs:
                findings.append(
                    {
                        "severity": "warning",
                        "category": "Services",
                        "title": f"{display} Not Running",
                        "recommendation": f"{display} service was not found running.",
                    }
                )

    if nics and not nics.get("error"):
        for port in nics.get("ports", []):
            if port.get("status") != "Up":
                # Only flag NICs that have Pixellot cameras in their ARP table.
                # Ports with no camera MACs are unused hardware — not a finding.
                arp = port.get("arpEntries") or []
                has_cameras = any(
                    _is_pixellot_mac(a.get("mac", "")) for a in arp
                )
                if not has_cameras:
                    continue
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


def _compute_camera_findings(ports: list) -> list:
    findings = []
    for port in ports:
        name = port.get("name", "Port")
        is_up = port.get("isUp")
        cams = port.get("camerasDetected") or []

        if not is_up and cams:
            findings.append(
                {
                    "severity": "critical",
                    "title": f"{name} down — {len(cams)} camera(s) last detected",
                    "body": "Port is down but Pixellot cameras were recently in the ARP table. Check the cable or use Fault Isolator.",
                }
            )

        if is_up and port.get("isDegraded"):
            speed = port.get("linkSpeedMbps")
            findings.append(
                {
                    "severity": "warning",
                    "title": f"{name} running at {speed} Mbps — expected 1 Gbps",
                    "body": "Degraded link speed usually means a bad cable, faulty connector, or wrong duplex negotiation.",
                }
            )

        if is_up and port.get("fullDuplex") is False:
            findings.append(
                {
                    "severity": "warning",
                    "title": f"{name} in half-duplex mode",
                    "body": "Half-duplex causes collisions and packet loss at camera scale. Check cable quality.",
                }
            )

        rx_errs = (port.get("rxPacketErrors") or 0) + (port.get("rxDiscards") or 0)
        tx_errs = (port.get("txPacketErrors") or 0) + (port.get("txDiscards") or 0)
        total_errs = rx_errs + tx_errs
        if is_up and total_errs > 0:
            findings.append(
                {
                    "severity": "warning",
                    "title": f"{name} — {total_errs} packet error(s)",
                    "body": f"RX {rx_errs}, TX {tx_errs}. May indicate a bad cable or NIC driver issue.",
                }
            )

    return findings


# ─── Data-building helpers (shared by per-page and preload) ──


def _build_dashboard(identity, performance, services, nics, network_config=None):
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
            "vpuName": identity.get("pixellot", {}).get("vpuName"),
            "isNonVpuHost": identity.get("isNonVpuHost", False),
        }

    # Basic network config for the dashboard network card
    net_cfg = {}
    if network_config and not network_config.get("error"):
        net_cfg = {
            "ipConfig": network_config.get("ipConfigurations", []),
            "uplinkAdapter": network_config.get("uplinkAdapter"),
            "internetReachable": network_config.get("internet", {}).get("reachable", False),
            "testedHost": network_config.get("internet", {}).get("testedHost"),
            "ntpSource": network_config.get("ntpSource"),
        }

    return {
        "identity": flat_identity,
        "performance": performance if not performance.get("error", False) else {},
        "services": services if not services.get("error", False) else {"services": []},
        "findings": _compute_findings(identity, performance, services, nics),
        "networkConfig": net_cfg,
    }


def _build_network(config, domains, ports, ntp, local=None):
    net = {}
    if config and not config.get("error"):
        net = {
            "adapters": config.get("adapters", []),
            "ipConfig": config.get("ipConfigurations", []),
            "uplinkAdapter": config.get("uplinkAdapter"),
            "uplinkStats": config.get("uplinkStats"),
            "internetReachable": config.get("internet", {}).get("reachable", False),
            "testedHost": config.get("internet", {}).get("testedHost"),
            "ntpSource": config.get("ntpSource"),
        }

    # Pass local data through even on error — let frontend display the issue
    return {"config": net, "domains": domains, "ports": ports, "ntp": ntp,
            "local": local}


# ─── Routes ───────────────────────────────────────────────────


_BOOT_TS = str(int(__import__("time").time()))  # changes every server restart


@app.get("/")
async def serve_index():
    with open(_os.path.join(_static_dir, "index.html")) as f:
        html = f.read()
    # Cache-bust with version + boot timestamp so Chrome always gets fresh assets
    bust = f"{APP_VERSION}.{_BOOT_TS}"
    html = html.replace("/static/style.css", f"/static/style.css?v={bust}")
    html = html.replace("/static/app.js", f"/static/app.js?v={bust}")
    return HTMLResponse(html)


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
        local,
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
        run_ps("Test-LocalNetwork.ps1"),
    )

    return {
        "dashboard": _build_dashboard(identity, performance, services, nics, network_config),
        "system": {
            "identity": identity,
            "hardware": hardware,
            "software": installed_sw,
        },
        "network": _build_network(network_config, domains, ports, ntp, local),
        "cameras": {
            "ports": _enrich_ports(nics),
            "pixellotConfig": pixellot_config,
        },
        "services": services,
        "disk-health": disk_health,
        "events": event_logs,
        "scoreconnect": scoreconnect,
        "settings": {
            **load_settings(),
            "_paths": {
                "settingsFile": SETTINGS_PATH,
                "serverLog": SERVER_LOG_PATH,
            },
        },
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


@app.get("/api/server-log")
async def api_server_log(tail: int = Query(default=200)):
    """Return the last N lines of the server bootstrap/startup log file."""
    try:
        with open(SERVER_LOG_PATH, "r", errors="replace") as f:
            lines = f.readlines()
        return {"lines": [l.rstrip() for l in lines[-tail:]], "total": len(lines)}
    except FileNotFoundError:
        return {"lines": [], "total": 0}


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
    identity, performance, services, nics, net_config = await asyncio.gather(
        run_ps("Get-SystemIdentity.ps1"),
        run_ps("Get-Performance.ps1"),
        run_ps("Get-Services.ps1"),
        run_ps("Get-NicAdapters.ps1"),
        run_ps("Get-NetworkConfig.ps1", timeout=15),
    )
    return _build_dashboard(identity, performance, services, nics, net_config)


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
    config, domains, ports, ntp, local = await asyncio.gather(
        run_ps("Get-NetworkConfig.ps1", timeout=15),
        run_ps("Test-NetworkDomains.ps1", timeout=20),
        run_ps("Test-NetworkPorts.ps1", timeout=45),
        run_ps("Test-NtpDrift.ps1", timeout=15),
        run_ps("Test-LocalNetwork.ps1", timeout=20),
    )
    return _build_network(config, domains, ports, ntp, local)


@app.get("/api/network/local-ping")
async def api_local_ping(count: int = 4):
    count = max(1, min(count, 100))  # clamp 1-100
    timeout = max(20, count * 3)  # ~3s per ping round
    result = await run_ps("Test-LocalNetwork.ps1", timeout=timeout,
                          args={"Count": count})
    return result


@app.get("/api/network/health")
async def api_network_health():
    return await run_ps("Get-NetworkHealth.ps1", timeout=10)


@app.get("/api/network/capture")
async def api_network_capture(duration: int = 30):
    duration = max(10, min(duration, 60))
    timeout = duration + 30  # extra headroom for pktmon stop + analysis
    result = await run_ps("Start-NetworkCapture.ps1", timeout=timeout,
                          args={"DurationSec": duration})
    return result


@app.get("/api/network/traceroute")
async def api_traceroute(target: str = "pixellot.tv", max_hops: int = 20):
    max_hops = max(5, min(max_hops, 30))
    timeout = max(30, max_hops * 3)  # generous — most finish well under this
    result = await run_ps("Test-Traceroute.ps1", timeout=timeout,
                          args={"Target": target, "MaxHops": max_hops})
    return result


@app.get("/api/network/speedtest")
async def api_speedtest(result_id: str = ""):
    """Fetch a Speedtest.net result by ID or URL and parse the speeds."""
    import re
    import urllib.request
    import urllib.error

    # Extract numeric ID from URL or bare ID
    result_id = result_id.strip()
    m = re.search(r"(\d{9,14})", result_id)
    if not m:
        return {"error": True, "message": "Invalid result ID. Paste the Speedtest result URL or numeric ID."}
    rid = m.group(1)
    url = f"https://www.speedtest.net/result/{rid}"

    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120",
            "Accept": "text/html",
        })
        resp = urllib.request.urlopen(req, timeout=10)
        html = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return {"error": True, "message": f"Speedtest returned HTTP {e.code}. Check the result ID."}
    except Exception as e:
        return {"error": True, "message": f"Failed to fetch result: {e}"}

    # Strategy 1: Parse OG description — "Download: XX.XX Mbps Upload: XX.XX Mbps Ping: XX ms"
    download = upload = ping = jitter = isp = server = None

    og_desc = re.search(r'<meta\s+[^>]*property=["\']og:description["\'][^>]*content=["\']([^"\']+)', html, re.I)
    if og_desc:
        desc = og_desc.group(1)
        dl_m = re.search(r"Download[:\s]+(\d+(?:\.\d+)?)\s*(Mbps|Kbps|Gbps)", desc, re.I)
        ul_m = re.search(r"Upload[:\s]+(\d+(?:\.\d+)?)\s*(Mbps|Kbps|Gbps)", desc, re.I)
        pg_m = re.search(r"Ping[:\s]+(\d+(?:\.\d+)?)\s*ms", desc, re.I)
        if dl_m:
            download = float(dl_m.group(1))
            if dl_m.group(2).lower() == "kbps": download /= 1000
            elif dl_m.group(2).lower() == "gbps": download *= 1000
        if ul_m:
            upload = float(ul_m.group(1))
            if ul_m.group(2).lower() == "kbps": upload /= 1000
            elif ul_m.group(2).lower() == "gbps": upload *= 1000
        if pg_m:
            ping = float(pg_m.group(1))

    # Strategy 2: Look for JSON data in script tags
    if download is None:
        json_m = re.search(r'"download"[:\s]+(\d+(?:\.\d+)?)', html)
        if json_m:
            val = float(json_m.group(1))
            download = val / 1000 if val > 10000 else val  # might be kbps
    if upload is None:
        json_m = re.search(r'"upload"[:\s]+(\d+(?:\.\d+)?)', html)
        if json_m:
            val = float(json_m.group(1))
            upload = val / 1000 if val > 10000 else val
    if ping is None:
        json_m = re.search(r'"ping"[:\s]+(\d+(?:\.\d+)?)', html)
        if json_m:
            ping = float(json_m.group(1))

    # ISP and server
    isp_m = re.search(r'"isp_name"[:\s]*"([^"]+)"', html) or re.search(r'"isp"[:\s]*"([^"]+)"', html)
    if isp_m: isp = isp_m.group(1)
    srv_m = re.search(r'"server_name"[:\s]*"([^"]+)"', html) or re.search(r'"name"[:\s]*"([^"]+)"', html)
    if srv_m: server = srv_m.group(1)
    jitter_m = re.search(r'"jitter"[:\s]+(\d+(?:\.\d+)?)', html)
    if jitter_m: jitter = float(jitter_m.group(1))

    if download is None and upload is None:
        return {"error": True, "message": "Could not parse speeds from the result page. The result may be private or the page format changed."}

    return {
        "resultId": rid,
        "url": url,
        "download": round(download, 2) if download else None,
        "upload": round(upload, 2) if upload else None,
        "ping": round(ping, 1) if ping else None,
        "jitter": round(jitter, 1) if jitter else None,
        "isp": isp,
        "server": server,
    }


@app.get("/api/cameras")
async def api_cameras():
    nics, pix_config = await asyncio.gather(
        run_ps("Get-NicAdapters.ps1"),
        run_ps("Get-PixellotConfig.ps1"),
    )
    ports = _enrich_ports(nics)
    return {
        "ports": ports,
        "pixellotConfig": pix_config,
        "findings": _compute_camera_findings(ports),
    }


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
    return {
        **load_settings(),
        "_paths": {
            "settingsFile": SETTINGS_PATH,
            "serverLog": SERVER_LOG_PATH,
        },
    }


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


# ─── WebSocket — live metrics + auto-shutdown ────────────────

_ws_clients: set = set()
_shutdown_task = None  # Optional[asyncio.Task]
_ever_had_client: bool = False
IDLE_SHUTDOWN_SECS = 60  # shut down 60s after last client disconnects


async def _idle_shutdown():
    """Shut down the server after all WebSocket clients disconnect."""
    await asyncio.sleep(IDLE_SHUTDOWN_SECS)
    if not _ws_clients and _ever_had_client:
        _log("auto-shutdown", 0, "ok", f"no clients for {IDLE_SHUTDOWN_SECS}s")
        _os._exit(0)


def _on_ws_connect(ws: WebSocket):
    global _shutdown_task, _ever_had_client
    _ws_clients.add(id(ws))
    _ever_had_client = True
    if _shutdown_task and not _shutdown_task.done():
        _shutdown_task.cancel()
        _shutdown_task = None


def _on_ws_disconnect(ws: WebSocket):
    global _shutdown_task
    _ws_clients.discard(id(ws))
    if not _ws_clients and _ever_had_client:
        _shutdown_task = asyncio.create_task(_idle_shutdown())


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    _on_ws_connect(ws)
    try:
        settings = load_settings()
        interval = max(settings.get("pollIntervalMs", 3000), 1000) / 1000
        last_log_idx = len(LOG_BUFFER)

        while True:
            perf, nics, net_health = await asyncio.gather(
                run_ps("Get-Performance.ps1", timeout=10),
                run_ps("Get-NicAdapters.ps1", timeout=10),
                run_ps("Get-NetworkHealth.ps1", timeout=10),
            )
            all_logs = list(LOG_BUFFER)
            new_logs = all_logs[last_log_idx:]
            last_log_idx = len(all_logs)

            await ws.send_json(
                {
                    "type": "metrics",
                    "performance": perf,
                    "ports": _enrich_ports(nics),
                    "networkHealth": net_health,
                    "logs": new_logs,
                }
            )
            await asyncio.sleep(interval)
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        _on_ws_disconnect(ws)


# ─── Entry point ──────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn

    port = int(_os.environ.get("PORT", 8765))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
