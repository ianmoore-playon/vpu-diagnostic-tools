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

# ── Server log file ──────────────────────────────────────────
# Attach a file handler to the root logger so ANY library that logs
# (uvicorn, asyncio, fastapi, our app, third-party deps) flows into
# pulse-server.log. The Server Log tab in the UI tails this file.
#
# Mode "w" truncates on each process start so the file never grows
# unbounded across restarts. The file is also small enough (a few KB
# per session) that we don't need rotation.
import logging as _logging
_server_log_handler = _logging.FileHandler(SERVER_LOG_PATH, mode="w", encoding="utf-8")
_server_log_handler.setLevel(_logging.INFO)
_server_log_handler.setFormatter(
    _logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s",
                       datefmt="%Y-%m-%d %H:%M:%S")
)
_root_logger = _logging.getLogger()
_root_logger.setLevel(_logging.INFO)
_root_logger.addHandler(_server_log_handler)
_server_log = _logging.getLogger("pulse")
_server_log.info(f"pulse-server.log opened — Pulse Web bootstrap")

app = FastAPI(title="Pulse Web | VPU Diagnostics")
app.mount("/static", StaticFiles(directory=_static_dir), name="static")

PIXELLOT_OUIS = ["00:0E:53", "00:30:53", "70:B3:D5", "00:D0:89"]

# ── US timezone allowlist ────────────────────────────────────
# VPUs must run in a US timezone for log timestamps / scheduling to line up
# with field operations. Anything off-continent (Jerusalem, UTC, Tokyo, etc.)
# breaks correlation with cloud-side event timing.
#
# Matches Windows TimeZoneInfo.StandardName values. Covers the 50 states +
# DC + Indiana/Arizona quirks. Excludes Mexico/Canada zones that share names
# with US zones, and explicitly excludes Atlantic Standard Time which is
# ambiguous (Puerto Rico is US, but Canada also uses it).
_US_TIMEZONE_IDS = {
    "Hawaiian Standard Time",          # HST (UTC-10)
    "Aleutian Standard Time",          # HAST/HADT (UTC-10/-9, Alaska Aleutians)
    "Alaskan Standard Time",           # AKST/AKDT (UTC-9/-8)
    "Pacific Standard Time",           # PST/PDT (UTC-8/-7)
    "US Mountain Standard Time",       # MST (UTC-7, Arizona — no DST)
    "Mountain Standard Time",          # MST/MDT (UTC-7/-6)
    "Central Standard Time",           # CST/CDT (UTC-6/-5)
    "US Eastern Standard Time",        # EST (UTC-5, Indiana East — no DST)
    "Eastern Standard Time",           # EST/EDT (UTC-5/-4)
}

# Fallback substrings for matching Caption strings when StandardName missing.
# Order matters — more specific first (so "Arizona" wins over "Mountain").
_US_CAPTION_HINTS = (
    "(US & Canada)",  # canonical Windows caption for the 4 main US zones
    "Hawaii",
    "Aleutian",
    "Alaska",
    "Arizona",
    "Indiana",
)


def _is_us_timezone(tz_id: str, tz_caption: str = "") -> bool:
    """True if the system is in a US timezone (50 states + DC).

    Prefers the stable StandardName (`tz_id`). Falls back to fuzzy substring
    matching on the user-visible caption for hosts that only supply that.
    Returns False for anything off-continent — Jerusalem, UTC, GMT, Mexico,
    Canada-only zones, etc.
    """
    if tz_id and tz_id in _US_TIMEZONE_IDS:
        return True
    if tz_caption:
        cap = tz_caption
        for hint in _US_CAPTION_HINTS:
            if hint in cap:
                return True
    return False


@app.on_event("startup")
async def _on_startup():
    """Log startup info to both the Script Log buffer (UI) and the
    Server Log file (pulse-server.log)."""
    msg_version = f"Pulse Web {APP_VERSION} starting"
    msg_python  = f"Python {_sys.version.split()[0]} | port {_os.environ.get('PORT', 8765)}"
    msg_mode    = f"Demo mode = {DEMO_MODE} | platform = {_sys.platform}"
    msg_paths   = f"Scripts dir = {_os.path.join(_app_dir, 'scripts')} | Settings = {SETTINGS_PATH}"
    for msg in (msg_version, msg_python, msg_mode, msg_paths):
        ps_log("server", 0, "ok", msg)
        _server_log.info(msg)


def load_settings() -> dict:
    try:
        with open(SETTINGS_PATH, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"scoreConnectUrl": "http://localhost:5000", "pollIntervalMs": 3000}


def save_settings(data: dict) -> None:
    with open(SETTINGS_PATH, "w") as f:
        json.dump(data, f, indent=2)


# ── CGI probe for Dynacolor cameras (OCR + main heads) ──────────────
# Mirrors the WPF's OcrProbeService: HTTP GET to the camera's admin CGI
# returns the camera MAC, positively identifying it. OCR and main cameras
# share the same Dynacolor firmware and respond on the same endpoint.
#
# Results are cached by IP with a 30-second TTL so the 3-second live poll
# doesn't hammer the cameras. The probe runs via asyncio.to_thread to
# avoid blocking the event loop (no httpx dependency required).

import base64
import time
import urllib.request
import urllib.error
from typing import Optional

_CGI_PROBE_CACHE = {}  # ip -> {mac, ts, is_ocr}
_CGI_PROBE_TTL = 30  # seconds

# Known default OCR IPs (from WPF's DefaultOcrIps + Pixellot convention)
_DEFAULT_OCR_IPS = {"169.254.16.52", "169.254.16.53", "169.254.16.60"}
# Known default main camera IPs
_DEFAULT_MAIN_IPS = {"169.254.16.50", "169.254.16.51"}

# Camera model → (role, expected link speed in Mbps)
# Used for positive hardware-based identification from CGI Brand.ProdNbr.
_CAMERA_MODELS = {
    "Z4SF-F": ("Main Camera", 1000),
    "R2SD-G": ("OCR / Scoreboard", 100),
    "S5SD-G": ("OCR / Scoreboard", 100),
    "E8NC-G": ("OCR / Scoreboard", 1000),
}


def _lookup_camera_model(model_number: Optional[str]) -> tuple:
    """Return (role, expected_speed_mbps) for a known model, or (None, None)."""
    if not model_number:
        return None, None
    # Try exact match first, then prefix match (ProdNbr may have suffixes)
    if model_number in _CAMERA_MODELS:
        return _CAMERA_MODELS[model_number]
    for prefix, info in _CAMERA_MODELS.items():
        if model_number.startswith(prefix):
            return info
    return None, None


def _cgi_fetch_group(ip, group, headers, timeout=2.0):
    """Fetch a param.cgi group and return a flat dict of key=value pairs."""
    url = f"http://{ip}/cgi-bin/admin/param.cgi?action=list&group={group}"
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            result = {}
            for line in body.splitlines():
                if "=" in line:
                    key, val = line.split("=", 1)
                    key = key.strip()
                    if key.startswith("root."):
                        key = key[5:]
                    result[key] = val.strip()
            return result
    except Exception:
        return {}


def _cgi_probe_sync(ip: str, timeout: float = 2.0) -> Optional[dict]:
    """Probe a Dynacolor camera CGI endpoint for full diagnostic data.
    Pulls: MAC, brand/model, serial, firmware, network config, stream
    settings, and image sensor parameters. All queries except MAC are
    best-effort — missing data just means those fields are None.
    Runs in a thread — safe to call via asyncio.to_thread.

    Auth is the Pixellot/Dynacolor factory default (Admin / 1234). If a
    site has rotated camera credentials, probes will silently return None
    and identification falls back to ARP/cameras.cfg only.
    """
    headers = {"Authorization": "Basic " + base64.b64encode(b"Admin:1234").decode()}

    # Request 1: MAC address (critical — determines if camera responds)
    mac_data = _cgi_fetch_group(ip, "Network.eth0.MACAddress", headers, timeout)
    mac = mac_data.get("Network.eth0.MACAddress")
    if not mac:
        return None

    # Request 2: Brand / model / product type
    brand = _cgi_fetch_group(ip, "Brand", headers, timeout)

    # Request 3: Firmware version + serial number
    props = _cgi_fetch_group(ip, "Properties", headers, timeout)

    # Request 4: Camera network config (IP, subnet, gateway, DHCP)
    net = _cgi_fetch_group(ip, "Network.eth0", headers, timeout)

    # Request 5: Stream encoding settings (S0 = primary H264, S1 = MJPEG)
    streams = _cgi_fetch_group(ip, "Image.I0.Appearance", headers, timeout)

    # Request 6: Image sensor / exposure settings
    sensor = _cgi_fetch_group(ip, "ImageSource.I0.Sensor", headers, timeout)

    def _v(d, k):
        """Get a value, return None if empty."""
        val = d.get(k, "")
        return val if val else None

    return {
        "mac": mac,
        # Device identity
        "brand": _v(brand, "Brand.Brand"),
        "model": _v(brand, "Brand.ProdFullName") or _v(brand, "Brand.ProdNbr"),
        "modelNumber": _v(brand, "Brand.ProdNbr"),
        "productType": _v(brand, "Brand.ProdType"),
        "serialNumber": _v(props, "Properties.System.SerialNumber"),
        "firmwareVersion": _v(props, "Properties.Firmware.Version"),
        # Network
        "network": {
            "ip": _v(net, "Network.eth0.IPAddress"),
            "subnet": _v(net, "Network.eth0.SubnetMask"),
            "gateway": _v(net, "Network.eth0.DefaultRouter"),
            "dhcp": _v(net, "Network.eth0.DHCP.Enabled"),
        },
        # Stream 0 (primary — typically H264 for recording)
        "stream0": {
            "codec": _v(streams, "Image.I0.Appearance.Stream.S0.EncodeType"),
            "resolution": _v(streams, "Image.I0.Appearance.Stream.S0.Resolution"),
            "framerate": _v(streams, "Image.I0.Appearance.Stream.S0.Framerate"),
        },
        # Stream 1 (secondary — typically MJPEG for live preview)
        "stream1": {
            "enabled": _v(streams, "Image.I0.Appearance.Stream.S1.Enabled"),
            "codec": _v(streams, "Image.I0.Appearance.Stream.S1.EncodeType"),
            "resolution": _v(streams, "Image.I0.Appearance.Stream.S1.Resolution"),
            "framerate": _v(streams, "Image.I0.Appearance.Stream.S1.Framerate"),
        },
        # Image sensor tuning
        "sensor": {
            "exposure": _v(sensor, "ImageSource.I0.Sensor.Exposure"),
            "brightness": _v(sensor, "ImageSource.I0.Sensor.Brightness"),
            "contrast": _v(sensor, "ImageSource.I0.Sensor.Contrast"),
            "colorLevel": _v(sensor, "ImageSource.I0.Sensor.ColorLevel"),
            "maxShutterGain": _v(sensor, "ImageSource.I0.Sensor.Exposure.MaxShutterGain"),
            "minShutterSpeed": _v(sensor, "ImageSource.I0.Sensor.Exposure.MinShutterSpeed"),
        },
    }


async def _probe_camera_ip(ip, is_ocr_ip):
    """Probe a single camera IP, returning cached result if fresh."""
    now = time.monotonic()
    cached = _CGI_PROBE_CACHE.get(ip)
    if cached and (now - cached["ts"]) < _CGI_PROBE_TTL:
        return cached

    info = await asyncio.to_thread(_cgi_probe_sync, ip)
    if info and info.get("mac"):
        result = {
            **info,
            "mac": info["mac"].upper().replace("-", ":"),
            "ts": now,
            "is_ocr": is_ocr_ip,
            "ip": ip,
        }
        _CGI_PROBE_CACHE[ip] = result
        return result
    return None


def _collect_camera_ips(ports, ocr_ips):
    """Collect all IPs worth probing: defaults + any Pixellot ARP entries."""
    all_camera_ips = set(ocr_ips)
    all_camera_ips.update(_DEFAULT_OCR_IPS)
    all_camera_ips.update(_DEFAULT_MAIN_IPS)
    for port in ports:
        for arp in port.get("arpEntries", []):
            if _is_pixellot_mac(arp.get("mac", "")):
                ip = arp.get("ip", "").strip()
                if ip:
                    all_camera_ips.add(ip)
    return all_camera_ips


def _cached_probes_by_mac() -> dict:
    """Return all currently-fresh probe cache entries keyed by MAC."""
    now = time.monotonic()
    by_mac = {}
    for entry in list(_CGI_PROBE_CACHE.values()):
        if (now - entry["ts"]) < _CGI_PROBE_TTL and entry.get("mac"):
            by_mac[entry["mac"]] = entry
    return by_mac


async def _probe_all_cameras(ports, ocr_ips, block: bool = True):
    """Probe all camera IPs found in ARP entries across all ports.

    block=True  — wait for probes (used for dashboard/WS preload).
    block=False — return cached data immediately; start a fire-and-forget
                  background probe for any cold IPs. Used by /api/cameras
                  so the first paint isn't gated on slow CGI calls. The
                  next live-refresh tick picks up the new data.

    Returns a dict keyed by normalized MAC -> probe result.
    """
    all_camera_ips = _collect_camera_ips(ports, ocr_ips)

    if not block:
        now = time.monotonic()
        cold_ips = [
            ip for ip in all_camera_ips
            if (_CGI_PROBE_CACHE.get(ip) is None
                or (now - _CGI_PROBE_CACHE[ip]["ts"]) >= _CGI_PROBE_TTL)
        ]
        if cold_ips:
            async def _warm_cache():
                tasks = [
                    _probe_camera_ip(
                        ip, ip in ocr_ips or ip in _DEFAULT_OCR_IPS
                    )
                    for ip in cold_ips
                ]
                await asyncio.gather(*tasks, return_exceptions=True)
            asyncio.create_task(_warm_cache())
        return _cached_probes_by_mac()

    tasks = []
    for ip in all_camera_ips:
        is_ocr = ip in ocr_ips or ip in _DEFAULT_OCR_IPS
        tasks.append(_probe_camera_ip(ip, is_ocr))

    results = await asyncio.gather(*tasks, return_exceptions=True)
    by_mac = {}
    for r in results:
        if isinstance(r, dict) and r.get("mac"):
            by_mac[r["mac"]] = r
    return by_mac


def _is_pixellot_mac(mac: str) -> bool:
    if not mac:
        return False
    normalized = mac.upper().replace("-", ":").replace(".", ":")
    parts = normalized.split(":")
    if len(parts) >= 3:
        prefix = ":".join(parts[:3])
        return prefix in PIXELLOT_OUIS
    return False


PIXELLOT_MIN_RAM_GB = 32

# ── Approved NTP sources ─────────────────────────────────────
# Per Pixellot Troubleshooting Tips PDF #9: VPU clocks must sync from the
# US NTP pool. A school IT department occasionally points VPUs at an
# internal NTP server which drifts, breaking signed-URL streaming.
PIXELLOT_APPROVED_NTP_SOURCES = (
    "0.us.pool.ntp.org",
    "1.us.pool.ntp.org",
    "2.us.pool.ntp.org",
    "3.us.pool.ntp.org",
)


def _is_approved_ntp_source(source: Optional[str]) -> bool:
    """True if `source` matches one of the approved Pixellot NTP servers.

    Match is case-insensitive and tolerates trailing whitespace. We also
    accept any `*.us.pool.ntp.org` host since the four canonical names
    are aliases for the same NTP pool.
    """
    if not source:
        return False
    host = source.strip().lower()
    if host in PIXELLOT_APPROVED_NTP_SOURCES:
        return True
    return host.endswith(".us.pool.ntp.org")


# ── Windows LTSC lifecycle map (PDF #4) ─────────────────────
# Pixellot VPUs ship on Win 10 IoT LTSC. Two builds in the field:
#   1809 (LTSC 2019) → build 17763 → all VPUs except Z2
#   21H2 (LTSC 2021) → build 19044 → Z2 VPUs
# Date format: ISO yyyy-mm-dd, used to compute days-until-EOS.
_LTSC_LIFECYCLE = {
    "17763": {
        "ltscRelease": "Windows 10 IoT Enterprise LTSC 2019 (1809)",
        "eosDate": "2029-01-09",  # IoT extended support / end-of-servicing
    },
    "19044": {
        "ltscRelease": "Windows 10 IoT Enterprise LTSC 2021 (21H2)",
        "eosDate": "2027-01-12",  # end-of-support per PDF #4
        "endOfServicingDate": "2032-01-13",  # IoT extended servicing
    },
}


def _os_lifecycle(build_number) -> Optional[dict]:
    """Return {ltscRelease, eosDate, daysToEos[, endOfServicingDate]} for
    a known Pixellot OS build, or None if build is unknown."""
    if not build_number:
        return None
    key = str(build_number).strip()
    info = _LTSC_LIFECYCLE.get(key)
    if not info:
        return None
    from datetime import date as _date
    try:
        y, m, d = [int(x) for x in info["eosDate"].split("-")]
        days = (_date(y, m, d) - _date.today()).days
    except (ValueError, KeyError):
        days = None
    return {
        **info,
        "daysToEos": days,
    }


# ── Unsupported security software ────────────────────────────
# Per Pixellot Troubleshooting Tips PDF #11: any EDR / non-Defender
# antivirus blocks agent.exe and forces an RMA. Only Windows Defender is
# approved. Each entry is matched as a case-insensitive substring against
# the installed-software displayName.
# ── Pixellot version × hardware compatibility (field guidance) ──
# Per Logan T (2026-05-28):
#   Win 8 hosts                          → max 2.66.17
#   Maxwell GPU (5.x cap, GTX 9xx, M-)   → max 2.66.17 (these are all Win 8 hosts)
#   Win 10 + Pascal GPU (10xx, 6.x cap)  → max 5.2.x
#   Win 10 + Turing or newer (≥7.5 cap)  → any version
#   Volta GPU (7.0/7.2 — V100, Titan V)  → ANOMALY: never deployed; if detected,
#                                          flag as a hardware configuration error
#
# Pixellot version strings are dotted-numeric (e.g. "5.13.6"). Caps can
# be exact ("2.66.17") or wildcarded ("5.2.x") — the latter allows any
# patch under that major.minor.

# arch → max Pixellot version (None means unlimited, "__ANOMALY__" means
# not a known-deployed configuration)
_ARCH_VERSION_CAPS = {
    "Maxwell":    "2.66.17",
    "Pascal":     "5.2.x",
    "Volta":      "__ANOMALY__",
    "Turing":     None,
    "Ampere/Ada": None,
    "Hopper":     None,
    "Blackwell":  None,
    # Unknown/None handled separately
}


def _parse_version(v: str):
    """Return tuple of ints from a dotted version, ignoring suffixes.
    "5.13.6" → (5, 13, 6). "2.66.17" → (2, 66, 17). Empty/bad → ()."""
    if not v:
        return ()
    parts = []
    for piece in str(v).split("."):
        piece = piece.strip()
        # Strip non-numeric tail (e.g. "5.13.6-beta" → "5.13.6")
        num = ""
        for ch in piece:
            if ch.isdigit():
                num += ch
            else:
                break
        if num == "":
            break
        parts.append(int(num))
    return tuple(parts)


def _version_exceeds_cap(installed: str, cap: str) -> bool:
    """True if `installed` is strictly newer than `cap`.

    Cap formats:
      "2.66.17"   exact maximum (5.13.6 exceeds, 2.66.17 OK, 2.66.16 OK)
      "5.2.x"     wildcard patch — anything in 5.2.* allowed; 5.3.0+ exceeds
    """
    if not installed or not cap:
        return False
    iv = _parse_version(installed)
    if not iv:
        return False

    # Wildcard form: "5.2.x" → require major.minor match, patch unbounded
    if cap.lower().endswith(".x"):
        prefix = cap[:-2]  # "5.2"
        cv = _parse_version(prefix)
        if not cv:
            return False
        # Out of range if installed major > cap major, or same major + minor > cap minor
        if iv[0] != cv[0]:
            return iv[0] > cv[0]
        if len(iv) < 2 or len(cv) < 2:
            return False
        return iv[1] > cv[1]

    # Exact form: pad to same length and compare
    cv = _parse_version(cap)
    if not cv:
        return False
    max_len = max(len(iv), len(cv))
    iv_padded = iv + (0,) * (max_len - len(iv))
    cv_padded = cv + (0,) * (max_len - len(cv))
    return iv_padded > cv_padded


def _check_pixellot_compatibility(identity, gpu_info) -> dict:
    """Return a status dict describing Pixellot version compatibility
    with the detected Windows + GPU combination.

    Returns:
      {
        status: "ok" | "over" | "no-gpu" | "skip",
        installedVersion: str | None,
        maxVersion: str | None,          # None = unlimited
        capReason: str,                  # which rule applied
        architecture: str,
        windowsBuild: str | None,
      }
    """
    out = {
        "status": "skip",
        "installedVersion": None,
        "maxVersion": None,
        "capReason": "",
        "architecture": "Unknown",
        "windowsBuild": None,
    }
    if not identity or identity.get("error"):
        return out

    installed = (identity.get("pixellot") or {}).get("version")
    out["installedVersion"] = installed
    if not installed:
        out["status"] = "skip"
        out["capReason"] = "Pixellot version not detected — VPU software may not be installed"
        return out

    os_caption = (identity.get("operatingSystem") or {}).get("caption") or ""
    os_build = (identity.get("operatingSystem") or {}).get("buildNumber") or ""
    out["windowsBuild"] = os_build

    # Win 8 / 8.1 binding constraint regardless of GPU
    is_win8 = "Windows 8" in os_caption
    if is_win8:
        out["maxVersion"] = "2.66.17"
        out["capReason"] = "Windows 8 hosts are capped at Pixellot 2.66.17"
        out["status"] = "over" if _version_exceeds_cap(installed, "2.66.17") else "ok"
        return out

    arch = (gpu_info or {}).get("primaryArchitecture") or "Unknown"
    out["architecture"] = arch

    if arch in ("None", None):
        out["status"] = "no-gpu"
        out["capReason"] = "No NVIDIA GPU detected — Pixellot requires NVIDIA hardware for encoding"
        return out

    cap = _ARCH_VERSION_CAPS.get(arch)

    # Anomaly: architecture not deployed in the Pixellot field — flag as
    # a hardware configuration error so support can investigate.
    if cap == "__ANOMALY__":
        out["status"] = "anomaly"
        out["maxVersion"] = None
        out["capReason"] = (
            f"{arch} GPUs are not a deployed Pixellot configuration. "
            f"Verify this host's hardware roster — Volta cards were never "
            f"shipped in production VPUs."
        )
        return out

    if cap is None:
        # Either an architecture that's unlimited (Turing+) or one we
        # don't have data for. For Unknown, default to compliant — we
        # don't want a false-positive critical finding on a strange host.
        out["maxVersion"] = None
        if arch in ("Turing", "Ampere/Ada", "Hopper", "Blackwell"):
            out["capReason"] = f"{arch} architecture — no Pixellot version cap"
            out["status"] = "ok"
        else:
            out["capReason"] = f"Architecture '{arch}' — no cap data, assuming compatible"
            out["status"] = "ok"
        return out

    out["maxVersion"] = cap
    out["capReason"] = f"{arch} GPU caps Pixellot at {cap}"
    out["status"] = "over" if _version_exceeds_cap(installed, cap) else "ok"
    return out


# ── Concerning software categories ───────────────────────────
# Each category lists case-insensitive substring patterns that match
# software displayName. The first matching category wins per row.
# The frontend uses the per-entry `concern` field to badge the
# Software Inventory table; _compute_findings emits dashboard findings
# from these as well.
_CONCERNING_SOFTWARE = {
    "security": {
        "severity": "critical",
        "label": "Unsupported security software",
        "shortLabel": "AV/EDR",
        "reason": (
            "Pixellot VPUs only support Windows Defender. Third-party AV/EDR "
            "products block agent.exe and force an RMA (PDF #11)."
        ),
        "patterns": [
            "CrowdStrike", "SentinelOne", "Sophos", "Carbon Black", "Bitdefender",
            "McAfee", "Norton", "Symantec", "Trend Micro", "Kaspersky", "ESET",
            "Webroot", "Cylance", "Cortex XDR",
        ],
    },
    "crypto_miner": {
        "severity": "critical",
        "label": "Cryptocurrency miner",
        "shortLabel": "Miner",
        "reason": (
            "Mining software consumes GPU/CPU resources required for video "
            "encoding and is never legitimate on a VPU."
        ),
        # Be specific — "Claymore" alone risks false positives on common surnames,
        # but full strings like "Claymore's Miner" / NiceHash are unambiguous.
        "patterns": [
            "xmrig", "ethminer", "phoenixminer", "NiceHash", "MinerGate",
            "Claymore's Miner", "T-Rex Miner", "lolMiner", "Gminer", "TeamRedMiner",
        ],
    },
    "torrent": {
        "severity": "critical",
        "label": "Torrent client",
        "shortLabel": "Torrent",
        "reason": (
            "Torrent clients saturate upload bandwidth used for cloud streaming "
            "and are a common malware vector. Not appropriate on a VPU."
        ),
        "patterns": [
            "BitTorrent", "µTorrent", "uTorrent", "qBittorrent",
            "Transmission-Qt", "Deluge", "Vuze", "Tixati", "Frostwire",
        ],
    },
    "system_cleaner": {
        "severity": "critical",
        "label": "System cleaner / optimizer",
        "shortLabel": "Cleaner",
        "reason": (
            "Registry/system cleaners and driver-updater junkware are known to "
            "break Pixellot installs by deleting required files or registry keys. "
            "Uninstall and reimage if a cleaner was recently run."
        ),
        "patterns": [
            "CCleaner", "Advanced SystemCare", "IObit", "MyCleanPC", "PC Cleaner",
            "Glary Utilities", "Wise Care", "Auslogics BoostSpeed",
            "Driver Booster", "Driver Easy", "Driver Genius", "Driver Updater",
        ],
    },
    "alt_remote": {
        "severity": "warning",
        "label": "Non-standard remote-access tool",
        "shortLabel": "Alt Remote",
        "reason": (
            "LogMeIn is the approved Pixellot remote-access tool. Alternative "
            "products run their own background telemetry and may compete with "
            "LogMeIn for ports / system tray. Confirm with field operations "
            "before relying on these."
        ),
        # VNC variants (TightVNC, RealVNC) are often standard on VPUs — left out
        # to avoid false positives.
        "patterns": [
            "TeamViewer", "AnyDesk", "Splashtop", "GoToMyPC",
            "ConnectWise Control", "ScreenConnect", "Chrome Remote Desktop",
        ],
    },
    "game_platform": {
        "severity": "warning",
        "label": "Gaming platform",
        "shortLabel": "Games",
        "reason": (
            "Game launchers run background updates and game-streaming services "
            "that compete with Pixellot for CPU/GPU and upload bandwidth."
        ),
        "patterns": [
            "Steam", "Epic Games", "Battle.net", "Riot Client", "Riot Games",
            "GOG Galaxy", "Origin", "Ubisoft Connect", "EA app", "EA Desktop",
        ],
    },
    "consumer_sync": {
        "severity": "warning",
        "label": "Consumer cloud-sync client",
        "shortLabel": "Sync",
        "reason": (
            "Consumer-grade file sync can saturate upload bandwidth needed for "
            "video streams. Disable or pause sync during events."
        ),
        # Exclude OneDrive — common on Win 10 IoT and harder to remove cleanly.
        "patterns": ["Dropbox", "Google Drive", "iCloud", "Box Drive", "MEGAsync"],
    },
}


def _detect_concerning_software(installed_sw) -> dict:
    """Categorize installed software into concerning buckets.
    Returns {category_key: [{name, version, matched}, ...]}.
    Each software entry is matched against the first category whose
    patterns hit; subsequent categories are skipped for that entry."""
    out = {k: [] for k in _CONCERNING_SOFTWARE}
    if not installed_sw or installed_sw.get("error"):
        return out
    seen_names = set()  # dedupe — installers often appear under multiple keys
    for sw in installed_sw.get("software") or []:
        name = (sw.get("displayName") or "").strip()
        if not name:
            continue
        name_lc = name.lower()
        if name_lc in seen_names:
            continue
        for cat_key, cat in _CONCERNING_SOFTWARE.items():
            for pattern in cat["patterns"]:
                if pattern.lower() in name_lc:
                    seen_names.add(name_lc)
                    out[cat_key].append({
                        "name": name,
                        "version": (sw.get("displayVersion") or "").strip() or None,
                        "matched": pattern,
                    })
                    break
            if name_lc in seen_names:
                break
    return out


def _enrich_software_with_concerns(installed_sw):
    """Tag each software entry with a `concern` field if it matches a
    concerning-software pattern. Returns the same dict for chaining."""
    if not installed_sw or installed_sw.get("error"):
        return installed_sw
    for sw in installed_sw.get("software") or []:
        name_lc = (sw.get("displayName") or "").strip().lower()
        if not name_lc:
            continue
        for cat_key, cat in _CONCERNING_SOFTWARE.items():
            for pattern in cat["patterns"]:
                if pattern.lower() in name_lc:
                    sw["concern"] = {
                        "category": cat_key,
                        "severity": cat["severity"],
                        "label": cat["label"],
                        "shortLabel": cat["shortLabel"],
                        "reason": cat["reason"],
                        "matched": pattern,
                    }
                    break
            if "concern" in sw:
                break
    return installed_sw


# Backwards-compat shim — _compute_findings still uses this for the
# critical AV finding with its specific RMA copy.
def _detect_banned_security(installed_sw) -> list:
    return _detect_concerning_software(installed_sw).get("security", [])


def _total_ram_gb(hardware, performance) -> float:
    """Return total installed RAM in GB. Prefers DIMM sum (exact) over the
    OS-visible total (reduced by reserved memory). Returns 0 if neither
    source is usable."""
    if hardware and not hardware.get("error"):
        dimms = hardware.get("memory") or []
        total = sum((d.get("capacityGB") or 0) for d in dimms)
        if total > 0:
            return float(total)
    if performance and not performance.get("error"):
        mem = performance.get("memory") or {}
        # Real script emits totalMB; demo emits totalGB. Try both.
        total_mb = mem.get("totalMB")
        if total_mb:
            return round(total_mb / 1024, 2)
        total_gb = mem.get("totalGB")
        if total_gb:
            return float(total_gb)
    return 0.0


def _compute_findings(identity, performance, services, nics, hardware=None, installed_sw=None, network_config=None, install_state=None, port_tests=None, gpu_info=None) -> list:
    findings = []

    # ── NTP allowlist (PDF #9) ───────────────────────────────
    # School networks sometimes force VPUs onto an internal NTP server. If
    # that source drifts, signed-URL streaming breaks. The four canonical
    # `*.us.pool.ntp.org` hosts are the only Pixellot-approved sources.
    if network_config and not network_config.get("error"):
        ntp_src = (network_config.get("ntpSource") or "").strip()
        if ntp_src and not _is_approved_ntp_source(ntp_src):
            approved_list = ", ".join(PIXELLOT_APPROVED_NTP_SOURCES)
            findings.append(
                {
                    "severity": "warning",
                    "category": "Network",
                    "title": "NTP source not in approved Pixellot list",
                    "recommendation": (
                        f"Current source: {ntp_src}. Pixellot requires one of: {approved_list}. "
                        f"Run `w32tm /config /manualpeerlist:\"0.us.pool.ntp.org 1.us.pool.ntp.org "
                        f"2.us.pool.ntp.org 3.us.pool.ntp.org\" /syncfromflags:manual /update` and "
                        f"restart the Windows Time service."
                    ),
                }
            )

    # ── Concerning software (PDF #11 + general VPU hygiene) ──
    # Walks the installed-software list through the _CONCERNING_SOFTWARE
    # categories and emits one finding per category that matched anything.
    # AV/EDR stays critical with PDF #11 copy; miners/torrents/cleaners are
    # critical with their own reasons; alt-remote / games / cloud-sync are
    # warnings.
    concerns = _detect_concerning_software(installed_sw)
    if concerns.get("security"):
        names_str = ", ".join(
            f"{b['name']}" + (f" {b['version']}" if b.get('version') else "")
            for b in concerns["security"]
        )
        findings.append({
            "severity": "critical",
            "category": "Hardware",
            "title": "Unsupported security software detected",
            "recommendation": (
                f"Found: {names_str}. Pixellot VPUs only support Windows Defender — "
                f"third-party AV/EDR products block agent.exe and force an RMA. "
                f"Uninstall the listed software immediately."
            ),
        })
    for cat_key in ("crypto_miner", "torrent", "system_cleaner"):
        hits = concerns.get(cat_key) or []
        if not hits:
            continue
        cat = _CONCERNING_SOFTWARE[cat_key]
        names_str = ", ".join(
            f"{h['name']}" + (f" {h['version']}" if h.get('version') else "")
            for h in hits
        )
        findings.append({
            "severity": "critical",
            "category": "Software",
            "title": f"{cat['label']} installed",
            "recommendation": f"Found: {names_str}. {cat['reason']} Uninstall this software.",
        })
    for cat_key in ("alt_remote", "game_platform", "consumer_sync"):
        hits = concerns.get(cat_key) or []
        if not hits:
            continue
        cat = _CONCERNING_SOFTWARE[cat_key]
        names_str = ", ".join(h["name"] for h in hits)
        findings.append({
            "severity": "warning",
            "category": "Software",
            "title": f"{cat['label']} installed",
            "recommendation": f"Found: {names_str}. {cat['reason']}",
        })

    # ── Installed RAM ────────────────────────────────────────
    # Pixellot VPUs ship with 32GB of RAM. Anything less suggests an
    # undersized host or a failed DIMM — encoder workloads will degrade.
    total_ram = _total_ram_gb(hardware, performance)
    if total_ram > 0 and total_ram < PIXELLOT_MIN_RAM_GB - 1:  # -1 GB tolerance for OS overhead when falling back to performance.memory
        findings.append(
            {
                "severity": "warning",
                "category": "Hardware",
                "title": "Insufficient RAM",
                "recommendation": f"System has {total_ram:g} GB RAM; Pixellot VPUs require {PIXELLOT_MIN_RAM_GB} GB. Encoder workloads may stall or drop frames. Add memory or escalate for replacement.",
            }
        )

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

        # Timezone must be a US zone — cloud-side timestamps are recorded in
        # US local time, so a VPU set to Jerusalem (or any non-US zone) will
        # produce logs that don't line up with field events.
        tz_id = identity.get("timezoneId") or ""
        tz_caption = identity.get("timezone") or ""
        if (tz_id or tz_caption) and not _is_us_timezone(tz_id, tz_caption):
            shown = tz_caption or tz_id
            findings.append(
                {
                    "severity": "critical",
                    "category": "System",
                    "title": "Non-US Timezone",
                    "recommendation": f"System timezone is '{shown}'. VPU must be set to a US timezone (Pacific/Mountain/Central/Eastern, or Alaska/Hawaii). Open Date & Time settings and choose a US zone.",
                }
            )

        # ── OS lifecycle (PDF #4) ───────────────────────────────
        # Warn 12 months before LTSC EOS, critical at 3 months. Skip
        # silently if the build isn't in our LTSC map (covers non-VPU dev
        # boxes running 22H2 / Server / etc).
        build = identity.get("operatingSystem", {}).get("buildNumber")
        lifecycle = _os_lifecycle(build)
        if lifecycle and lifecycle.get("daysToEos") is not None:
            days = lifecycle["daysToEos"]
            release = lifecycle["ltscRelease"]
            eos = lifecycle["eosDate"]
            if days < 0:
                findings.append({
                    "severity": "critical",
                    "category": "System",
                    "title": "OS end-of-support reached",
                    "recommendation": f"{release} reached end-of-support on {eos} ({abs(days)} days ago). This host no longer receives security updates and should be re-imaged to a supported LTSC release.",
                })
            elif days < 90:
                findings.append({
                    "severity": "critical",
                    "category": "System",
                    "title": "OS end-of-support imminent",
                    "recommendation": f"{release} end-of-support is {eos} — {days} days away. Plan re-imaging to a supported LTSC release before that date.",
                })
            elif days < 365:
                months = days // 30
                findings.append({
                    "severity": "warning",
                    "category": "System",
                    "title": "OS end-of-support approaching",
                    "recommendation": f"{release} end-of-support is {eos} (~{months} months away). Begin planning a re-image to a supported LTSC release.",
                })

        # ── Pixellot version × hardware compatibility ───────────
        # Logan T 2026-05-28: Win 8 caps at 2.66.17, Win 10 + Pascal at
        # 5.2.x, Win 10 + Turing+ unlimited. Critical if installed > cap.
        compat = _check_pixellot_compatibility(identity, gpu_info)
        if compat["status"] == "over":
            arch_str = compat["architecture"] if compat["architecture"] != "Unknown" else "this hardware"
            findings.append({
                "severity": "critical",
                "category": "Pixellot",
                "title": "Pixellot version exceeds hardware compatibility cap",
                "recommendation": (
                    f"Installed Pixellot {compat['installedVersion']} is newer than the maximum "
                    f"supported version for {arch_str} ({compat['maxVersion']}). "
                    f"{compat['capReason']}. Downgrade Pixellot to {compat['maxVersion']} or earlier "
                    f"on this VPU — newer builds will not run correctly on this GPU/OS combination."
                ),
            })
        elif compat["status"] == "no-gpu":
            findings.append({
                "severity": "critical",
                "category": "Hardware",
                "title": "No NVIDIA GPU detected",
                "recommendation": (
                    "Pixellot requires an NVIDIA GPU for video encoding. No NVIDIA hardware was "
                    "found via nvidia-smi or WMI. If a GPU is physically installed, check driver "
                    "status; otherwise this VPU cannot run the encoder."
                ),
            })
        elif compat["status"] == "anomaly":
            # Volta hardware shouldn't exist in the Pixellot field — escalate.
            findings.append({
                "severity": "critical",
                "category": "Hardware",
                "title": "Unexpected GPU architecture",
                "recommendation": (
                    f"{compat['architecture']} GPU detected, which is not a known Pixellot "
                    f"deployment configuration. Escalate to support — this host may be "
                    f"mis-imaged or the hardware roster needs review. "
                    f"Installed Pixellot: {compat['installedVersion']}."
                ),
            })

    if performance and not performance.get("error"):
        # Use `is not None` instead of truthy checks so a legitimate 0 value
        # doesn't get short-circuited (would mask metric-collection bugs).
        cpu = performance.get("cpu", {}).get("usagePercent")
        if cpu is not None and cpu > 90:
            findings.append(
                {
                    "severity": "critical",
                    "category": "Performance",
                    "title": "CPU Usage Critical",
                    "recommendation": f"CPU at {cpu}%. Check for runaway processes.",
                }
            )
        elif cpu is not None and cpu > 75:
            findings.append(
                {
                    "severity": "warning",
                    "category": "Performance",
                    "title": "CPU Usage Elevated",
                    "recommendation": f"CPU at {cpu}%. Monitor for sustained high usage.",
                }
            )

        mem = performance.get("memory", {}).get("usedPercent")
        if mem is not None and mem > 90:
            findings.append(
                {
                    "severity": "critical",
                    "category": "Performance",
                    "title": "Memory Usage Critical",
                    "recommendation": f"Memory at {mem}%. Close apps or add RAM.",
                }
            )
        elif mem is not None and mem > 80:
            findings.append(
                {
                    "severity": "warning",
                    "category": "Performance",
                    "title": "Memory Usage Elevated",
                    "recommendation": f"Memory at {mem}%. Monitor for pressure.",
                }
            )

        disk = performance.get("disk", {}).get("usedPercent")
        if disk is not None and disk > 90:
            findings.append(
                {
                    "severity": "critical",
                    "category": "Storage",
                    "title": "Disk Space Critical",
                    "recommendation": f"Disk at {disk}%. Free space immediately.",
                }
            )
        elif disk is not None and disk > 80:
            findings.append(
                {
                    "severity": "warning",
                    "category": "Storage",
                    "title": "Disk Space Low",
                    "recommendation": f"Disk at {disk}%. Plan cleanup soon.",
                }
            )

        temp = performance.get("temperature", {}).get("celsius")
        if temp is not None and temp > 85:
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
            # Flag any port running below gigabit. The only legitimate
            # sub-gigabit case is an OCR/scoreboard camera (R2SD-G, S5SD-G),
            # which negotiates to 100 Mbps because that's its native rate.
            # We detect OCR ports by checking whether *every* Pixellot ARP
            # entry on the port uses the Dynacolor OUI (00:D0:89) — main
            # camera heads use the 00:0E:53 / 00:30:53 / 70:B3:D5 OUIs.
            #
            # Category is "Camera" when the port has Pixellot cameras —
            # a degraded link on a camera port is fundamentally a camera
            # problem (the cameras drop frames), not a generic network
            # one. Routes the finding to the Camera Connectivity tab.
            if port.get("status") == "Up" and speed and speed < 1000:
                arp = port.get("arpEntries") or []
                pixellot_arps = [a for a in arp if _is_pixellot_mac(a.get("mac", ""))]
                only_ocr_at_100 = (
                    speed == 100
                    and pixellot_arps
                    and all(
                        (a.get("mac", "").upper().startswith("00:D0:89"))
                        for a in pixellot_arps
                    )
                )
                if not only_ocr_at_100:
                    has_cameras = bool(pixellot_arps)
                    category = "Camera" if has_cameras else "Network"
                    findings.append(
                        {
                            "severity": "warning",
                            "category": category,
                            "title": f"NIC {port['name']} at {speed} Mbps (expected 1 Gbps)",
                            "recommendation": (
                                f"{port['name']} negotiated to {speed} Mbps instead of 1 Gbps. "
                                f"Camera streams on this port will drop frames at reduced bandwidth. "
                                f"Check cable quality (Cat5e+ required), reseat the connector, and "
                                f"confirm the switch port is set to auto-negotiate."
                            ),
                        }
                    )

    # ── Half-finished install (PDF #3) ───────────────────────
    # If part_1/2/3 files exist in c:\pixellot\downloadedversion and the
    # most-recent installer log doesn't end with "Rebooting...", the last
    # install run was interrupted and needs to be resumed.
    if install_state and not install_state.get("error") and install_state.get("incomplete"):
        part_count = install_state.get("partCount", 0)
        log = install_state.get("log") or {}
        last_line = (log.get("lastLine") or "").strip()
        log_name = log.get("name") or "(no log)"
        last_excerpt = last_line[:160] + ("…" if len(last_line) > 160 else "")
        findings.append(
            {
                "severity": "warning",
                "category": "Pixellot",
                "title": "Half-finished Pixellot install detected",
                "recommendation": (
                    f"{part_count} part file(s) present in C:\\pixellot\\downloadedversion "
                    f"and {log_name} does not end with 'Rebooting...'. Last log line was: "
                    f'"{last_excerpt}". Resume the install by re-running the installer in '
                    f"that directory."
                ),
            }
        )

    # ── Required port blocked ────────────────────────────────
    # Test-NetworkPorts hits the cloud endpoints Pixellot needs to stream.
    # A "required" (non-optional) port that fails is almost always a venue
    # firewall blocking it — surfaces on the Dashboard so the tech sees it
    # without drilling into the Network tab. Optional ports (RTMP, etc.)
    # are intentionally skipped — they vary by venue configuration.
    if port_tests and not port_tests.get("error"):
        for r in port_tests.get("results", []):
            if r.get("status") != "fail":
                continue
            if r.get("optional"):
                continue
            host = r.get("host", "?")
            port = r.get("port", "?")
            proto = (r.get("protocol") or "").upper()
            purpose = r.get("purpose") or "service"
            err = r.get("errorMessage") or "No response"
            findings.append(
                {
                    "severity": "warning",
                    "category": "Network",
                    "title": f"{purpose} port blocked ({proto} {port})",
                    "recommendation": (
                        f"{proto} port {port} to {host} is unreachable ({err}). "
                        f"This is a required Pixellot endpoint — ask the venue's "
                        f"IT team to open it in the firewall."
                    ),
                }
            )

    # Deduplicate by (category, title) — separate checks shouldn't produce
    # the same finding twice on the dashboard.
    seen = set()
    deduped = []
    for f in findings:
        key = (f.get("category", ""), f.get("title", ""))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(f)
    return deduped


def _build_camera_sets(pixellot_config=None):
    """Return cameras.cfg-derived sets for OCR and Main camera identification.

    Returns dict with keys:
      ocr_ips, ocr_macs  — OCR cameras (role contains "OCR")
      main_ips, main_macs — Main/Panoramic/Tactical cameras (other roles)
    Always includes the hardcoded default OCR IPs.
    """
    ocr_ips = set(_DEFAULT_OCR_IPS)
    ocr_macs = set()
    main_ips = set()
    main_macs = set()
    cfg_cameras = []
    if pixellot_config and not pixellot_config.get("error"):
        cfg_cameras = pixellot_config.get("cameras", [])
    for cam in cfg_cameras:
        role = (cam.get("role") or cam.get("section") or "").strip()
        ip = cam.get("ip", "").strip()
        mac = cam.get("mac", "").strip().upper().replace("-", ":")
        if role.upper() == "OCR":
            if ip:
                ocr_ips.add(ip)
            if mac:
                ocr_macs.add(mac)
        elif role:
            # Main, Panoramic, Tactical, etc — non-OCR Pixellot camera roles.
            if ip:
                main_ips.add(ip)
            if mac:
                main_macs.add(mac)
    return {
        "ocr_ips": ocr_ips,
        "ocr_macs": ocr_macs,
        "main_ips": main_ips,
        "main_macs": main_macs,
    }


def _build_ocr_sets(pixellot_config=None):
    """Backwards-compatible wrapper — returns (ocr_ips, ocr_macs)."""
    s = _build_camera_sets(pixellot_config)
    return s["ocr_ips"], s["ocr_macs"]


def _enrich_ports(
    nics: dict,
    pixellot_config: dict = None,
    probe_results=None,
) -> list:
    """Enrich raw NIC port data with status flags and camera detection.

    OCR / degraded determination uses a layered approach:
      1. Camera model number from CGI probe (hardware identity — highest
         priority).  Known models map to role + expected link speed.
      2. CGI probe IP match against known OCR/main IPs
      3. cameras.cfg role mapping (IP/MAC cross-reference)
      4. Default IP convention
    Degraded = actual speed < expected speed for the camera model. When
    model is unknown, any sub-1 Gbps non-OCR port is treated as degraded.

    probe_results: dict keyed by normalized MAC -> {mac, ip, is_ocr, ...}
    from _probe_all_cameras(). Optional — when absent, falls back to
    cfg-only identification.
    """
    cam_sets = _build_camera_sets(pixellot_config)
    ocr_ips = cam_sets["ocr_ips"]
    ocr_macs = cam_sets["ocr_macs"]
    main_ips = cam_sets["main_ips"]
    main_macs = cam_sets["main_macs"]
    probe_results = probe_results or {}

    ports = []
    if nics and not nics.get("error"):
        for port_idx, port in enumerate(nics.get("ports", [])):
            speed = port.get("linkSpeedMbps")
            is_up = port.get("status") == "Up"

            # Build enriched camera list from ARP entries
            cameras = []
            is_ocr = False
            expected_speed = None  # from camera model lookup
            for arp in port.get("arpEntries", []):
                arp_mac_raw = arp.get("mac", "")
                if not _is_pixellot_mac(arp_mac_raw):
                    continue
                arp_ip = (arp.get("ip") or "").strip()
                arp_mac = arp_mac_raw.strip().upper().replace("-", ":")

                # Determine camera identity — layered approach
                probe = probe_results.get(arp_mac)
                cam_entry = {**arp}

                # Layer 1: CGI probe data (copy all fields)
                if probe:
                    cam_entry["cgiConfirmed"] = True
                    cam_entry["cgiMac"] = probe["mac"]
                    for pkey in ("model", "modelNumber", "brand",
                                 "productType", "serialNumber",
                                 "firmwareVersion", "network",
                                 "stream0", "stream1", "sensor"):
                        if probe.get(pkey) is not None:
                            cam_entry[pkey] = probe[pkey]

                # Layer 1a: Model number → role + expected speed (highest priority)
                model_role, model_speed = _lookup_camera_model(
                    cam_entry.get("modelNumber")
                )
                if model_role:
                    cam_entry["role"] = model_role
                    cam_entry["identitySource"] = "Camera model"
                    cam_entry["expectedSpeedMbps"] = model_speed
                    expected_speed = model_speed
                    if "OCR" in model_role:
                        is_ocr = True
                # Layer 2: CGI probe IP-based OCR flag (only flags OCR; we
                # don't assume "Main Camera" without model or cfg confirmation)
                elif probe and probe.get("is_ocr"):
                    cam_entry["role"] = "OCR / Scoreboard"
                    cam_entry["identitySource"] = "CGI probe + OCR IP"
                    is_ocr = True
                # Layer 3: cameras.cfg
                elif arp_ip in ocr_ips or arp_mac in ocr_macs:
                    cam_entry["role"] = "OCR / Scoreboard"
                    cam_entry["identitySource"] = "Matched cameras.cfg"
                    is_ocr = True
                elif arp_ip in main_ips or arp_mac in main_macs:
                    cam_entry["role"] = "Main Camera"
                    cam_entry["identitySource"] = "Matched cameras.cfg"
                # Layer 4: Default IP convention
                elif arp_ip in _DEFAULT_MAIN_IPS:
                    cam_entry["role"] = "Main Camera"
                    cam_entry["identitySource"] = "Default IP"
                # Layer 5: CGI probe confirmed a Pixellot camera but no role match
                elif probe:
                    cam_entry["role"] = "Pixellot Camera"
                    cam_entry["identitySource"] = "CGI probe"
                else:
                    cam_entry["role"] = None
                    cam_entry["identitySource"] = "OUI vendor match"

                cameras.append(cam_entry)

            # Degraded: compare actual speed against expected speed from
            # camera model. If model is unknown, fall back to < 1 Gbps
            # for non-OCR ports.
            if expected_speed is not None:
                is_degraded = (
                    is_up and speed is not None and speed < expected_speed
                )
            else:
                is_degraded = (
                    is_up
                    and speed is not None
                    and speed < 1000
                    and not is_ocr
                )

            # Populate expectedSpeedMbps so downstream consumers (findings,
            # fault isolator) have a consistent value. When model lookup
            # didn't fire, default to 100 for OCR (most common) or 1000
            # for everything else. This is a safe heuristic — the 1 Gbps
            # OCR variant (E8NC-G) only gets correctly classified when
            # CGI probe succeeds and the model match runs.
            if expected_speed is None and cameras:
                expected_speed = 100 if is_ocr else 1000

            ports.append(
                {
                    **port,
                    "portIndex": port_idx,
                    "portLabel": f"Port {port_idx + 1}",
                    "isUp": is_up,
                    "isOcr": is_ocr,
                    "isDegraded": is_degraded,
                    "expectedSpeedMbps": expected_speed,
                    "camerasDetected": cameras,
                }
            )

    # Second pass: number main cameras and OCR cameras by camera IP so
    # numbering is stable (Main Camera 1 = .50, Main Camera 2 = .51, etc).
    # Collect per-role, sort, then assign numeric suffixes.
    main_ports = []
    ocr_ports = []
    for p in ports:
        cams = p.get("camerasDetected") or []
        if not cams:
            p["cameraLabel"] = None
            continue
        role = cams[0].get("role") or ""
        if "OCR" in role:
            ocr_ports.append(p)
        elif role == "Main Camera":
            main_ports.append(p)
        elif role == "Pixellot Camera":
            p["cameraLabel"] = "Pixellot Camera"
        else:
            p["cameraLabel"] = "Camera"

    def _ip_sort_key(p):
        # Numeric per-octet sort so .50 < .100 (string sort would invert)
        ip = p["camerasDetected"][0].get("ip", "")
        try:
            return tuple(int(o) for o in ip.split("."))
        except (ValueError, AttributeError):
            return (999, 999, 999, 999)

    main_ports.sort(key=_ip_sort_key)
    for i, p in enumerate(main_ports, 1):
        p["cameraLabel"] = f"Main Camera {i}"

    ocr_ports.sort(key=_ip_sort_key)
    if len(ocr_ports) == 1:
        ocr_ports[0]["cameraLabel"] = "OCR"
    else:
        for i, p in enumerate(ocr_ports, 1):
            p["cameraLabel"] = f"OCR {i}"

    return ports


def _compute_camera_findings(ports: list) -> list:
    findings = []
    for port in ports:
        label = port.get("portLabel", port.get("name", "Port"))
        adapter = port.get("name", "")
        is_up = port.get("isUp")
        cams = port.get("camerasDetected") or []

        if not is_up and cams:
            findings.append(
                {
                    "severity": "critical",
                    "title": f"{label} down — camera last detected",
                    "body": f"{adapter}. Port is down but a Pixellot camera was recently in the ARP table. Check the cable or use Fault Isolator.",
                }
            )

        if is_up and port.get("isDegraded"):
            speed = port.get("linkSpeedMbps")
            exp = port.get("expectedSpeedMbps") or 1000
            exp_label = f"{exp} Mbps" if exp < 1000 else f"{exp // 1000} Gbps"
            findings.append(
                {
                    "severity": "warning",
                    "title": f"{label} running at {speed} Mbps — expected {exp_label}",
                    "body": f"{adapter}. Degraded link speed usually means a bad cable, faulty connector, or wrong duplex negotiation.",
                }
            )

        if is_up and port.get("fullDuplex") is False:
            findings.append(
                {
                    "severity": "warning",
                    "title": f"{label} in half-duplex mode",
                    "body": f"{adapter}. Half-duplex causes collisions and packet loss at camera scale. Check cable quality.",
                }
            )

        rx_errs = (port.get("rxPacketErrors") or 0) + (port.get("rxDiscards") or 0)
        tx_errs = (port.get("txPacketErrors") or 0) + (port.get("txDiscards") or 0)
        total_errs = rx_errs + tx_errs
        if is_up and total_errs > 0:
            findings.append(
                {
                    "severity": "warning",
                    "title": f"{label} — {total_errs} packet error(s)",
                    "body": f"{adapter}. RX {rx_errs}, TX {tx_errs}. May indicate a bad cable or NIC driver issue.",
                }
            )

    return findings


# ─── Data-building helpers (shared by per-page and preload) ──


def _build_dashboard(identity, performance, services, nics, network_config=None, hardware=None, installed_sw=None, install_state=None, port_tests=None, gpu_info=None):
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
        "findings": _compute_findings(identity, performance, services, nics, hardware, installed_sw, network_config, install_state, port_tests, gpu_info),
        "networkConfig": net_cfg,
    }


def _build_network(config, domains, ports, ntp, local=None, ntp_peers=None, dns_resolution=None):
    net = {}
    if config and not config.get("error"):
        ntp_src = config.get("ntpSource")
        net = {
            "adapters": config.get("adapters", []),
            "ipConfig": config.get("ipConfigurations", []),
            "uplinkAdapter": config.get("uplinkAdapter"),
            "uplinkStats": config.get("uplinkStats"),
            "internetReachable": config.get("internet", {}).get("reachable", False),
            "testedHost": config.get("internet", {}).get("testedHost"),
            "ntpSource": ntp_src,
            "ntpSourceApproved": _is_approved_ntp_source(ntp_src),
            "ntpSourceApprovedList": list(PIXELLOT_APPROVED_NTP_SOURCES),
        }

    # Pass local, ntpPeers, dnsResolution through even on error — let the
    # frontend surface whichever subsection failed.
    return {"config": net, "domains": domains, "ports": ports, "ntp": ntp,
            "local": local, "ntpPeers": ntp_peers,
            "dnsResolution": dns_resolution}


# ─── Routes ───────────────────────────────────────────────────


_BOOT_TS = str(int(__import__("time").time()))  # changes every server restart


@app.get("/")
async def serve_index():
    with open(_os.path.join(_static_dir, "index.html")) as f:
        html = f.read()
    # Cache-bust with version + boot timestamp so Chrome always gets fresh
    # assets. Regex-based replacement is robust to attribute reordering or
    # additional tag attributes — string replace would silently break.
    import re
    bust = f"{APP_VERSION}.{_BOOT_TS}"
    html = re.sub(
        r'(/static/[a-z0-9_\-]+\.(?:css|js))(\?[^"\']*)?',
        lambda m: f"{m.group(1)}?v={bust}",
        html,
    )
    return HTMLResponse(html)


@app.get("/api/preload")
async def api_preload():
    """Run ALL diagnostic scripts once in parallel and return per-page data."""
    sc_url = load_settings().get("scoreConnectUrl", "http://localhost:5000")
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
        ntp_peers,
        dns_resolution,
        install_state,
        gpu_info,
    ) = await asyncio.gather(
        run_ps("Get-SystemIdentity.ps1"),
        run_ps("Get-Hardware.ps1"),
        run_ps("Get-Performance.ps1"),
        run_ps("Get-NetworkConfig.ps1"),
        run_ps("Get-NicAdapters.ps1"),
        run_ps("Get-Services.ps1"),
        run_ps("Get-DiskHealth.ps1"),
        run_ps("Get-EventLogs.ps1"),
        run_ps("Get-ScoreConnectStatus.ps1", {"BaseUrl": sc_url}),
        run_ps("Get-PixellotConfig.ps1"),
        run_ps("Get-InstalledSoftware.ps1"),
        run_ps("Test-NetworkDomains.ps1"),
        run_ps("Test-NetworkPorts.ps1"),
        run_ps("Test-NtpDrift.ps1"),
        run_ps("Test-LocalNetwork.ps1"),
        run_ps("Get-NtpPeers.ps1"),
        run_ps("Test-DnsResolution.ps1"),
        run_ps("Test-PixellotInstallState.ps1", timeout=15),
        run_ps("Get-GpuInfo.ps1", timeout=15),
    )
    # Audio is deferred — lazy-fetched on tab visit to keep preload lean.

    # Run CGI probes for camera identification (cached 30s)
    ocr_ips_pre, _ = _build_ocr_sets(pixellot_config)
    raw_ports_pre = nics.get("ports", []) if nics and not nics.get("error") else []
    probe_results_pre = await _probe_all_cameras(raw_ports_pre, ocr_ips_pre)

    return {
        "dashboard": _build_dashboard(identity, performance, services, nics, network_config, hardware, installed_sw, install_state, None, gpu_info),
        "system": {
            "identity": _enrich_identity_pixellot_compat(_enrich_identity_lifecycle(identity), gpu_info),
            "hardware": hardware,
            "software": _enrich_software_with_concerns(installed_sw),
        },
        "network": _build_network(network_config, domains, ports, ntp, local, ntp_peers, dns_resolution),
        "cameras": {
            "ports": _enrich_ports(nics, pixellot_config, probe_results_pre),
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
    identity, performance, services, nics, net_config, hardware, installed_sw, install_state, port_tests, gpu_info = await asyncio.gather(
        run_ps("Get-SystemIdentity.ps1"),
        run_ps("Get-Performance.ps1"),
        run_ps("Get-Services.ps1"),
        run_ps("Get-NicAdapters.ps1"),
        run_ps("Get-NetworkConfig.ps1", timeout=15),
        run_ps("Get-Hardware.ps1"),
        run_ps("Get-InstalledSoftware.ps1"),
        run_ps("Test-PixellotInstallState.ps1", timeout=15),
        # 20s timeout (down from 45) for dashboard use — keeps the
        # Run-All cold start under ~25s while still giving real port
        # checks time to complete on a healthy connection.
        run_ps("Test-NetworkPorts.ps1", timeout=20),
        run_ps("Get-GpuInfo.ps1", timeout=15),
    )
    return _build_dashboard(identity, performance, services, nics, net_config, hardware, installed_sw, install_state, port_tests, gpu_info)


def _enrich_identity_lifecycle(identity):
    """Attach OS lifecycle info (PDF #4) to identity.operatingSystem so the
    System Overview can display it next to the OS version. No-op if the
    build number isn't in our LTSC map."""
    if not identity or identity.get("error"):
        return identity
    os_block = identity.get("operatingSystem") or {}
    lifecycle = _os_lifecycle(os_block.get("buildNumber"))
    if lifecycle:
        os_block["lifecycle"] = lifecycle
        identity["operatingSystem"] = os_block
    return identity


def _enrich_identity_pixellot_compat(identity, gpu_info):
    """Attach pixellotCompat = {status, installedVersion, maxVersion, ...}
    to identity so System Overview can render the GPU/OS-vs-Pixellot banner."""
    if not identity or identity.get("error"):
        return identity
    compat = _check_pixellot_compatibility(identity, gpu_info)
    pix_block = identity.get("pixellot") or {}
    pix_block["compat"] = compat
    identity["pixellot"] = pix_block
    return identity


@app.get("/api/system")
async def api_system():
    identity, hardware, software, gpu_info = await asyncio.gather(
        run_ps("Get-SystemIdentity.ps1"),
        run_ps("Get-Hardware.ps1"),
        run_ps("Get-InstalledSoftware.ps1"),
        run_ps("Get-GpuInfo.ps1", timeout=15),
    )
    identity = _enrich_identity_lifecycle(identity)
    identity = _enrich_identity_pixellot_compat(identity, gpu_info)
    return {
        "identity": identity,
        "hardware": hardware,
        "software": _enrich_software_with_concerns(software),
    }


@app.get("/api/network")
async def api_network():
    config, domains, ports, ntp, local, ntp_peers, dns_resolution = await asyncio.gather(
        run_ps("Get-NetworkConfig.ps1", timeout=15),
        run_ps("Test-NetworkDomains.ps1", timeout=20),
        run_ps("Test-NetworkPorts.ps1", timeout=45),
        run_ps("Test-NtpDrift.ps1", timeout=15),
        run_ps("Test-LocalNetwork.ps1", timeout=20),
        run_ps("Get-NtpPeers.ps1", timeout=15),
        run_ps("Test-DnsResolution.ps1", timeout=30),
    )
    return _build_network(config, domains, ports, ntp, local, ntp_peers, dns_resolution)


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
    ocr_ips, _ = _build_ocr_sets(pix_config)
    # First paint: use cached probes only; warm the cache in the background
    # so the next live-refresh tick picks up fresh camera identification.
    raw_ports = nics.get("ports", []) if nics and not nics.get("error") else []
    probe_results = await _probe_all_cameras(raw_ports, ocr_ips, block=False)
    ports = _enrich_ports(nics, pix_config, probe_results)
    return {
        "ports": ports,
        "pixellotConfig": pix_config,
        "findings": _compute_camera_findings(ports),
        # Frontend uses this to skip swap-verification in the fault isolator,
        # since static demo data can't simulate the ARP change after a swap.
        "demoMode": DEMO_MODE,
    }


@app.get("/api/services")
async def api_services():
    return await run_ps("Get-Services.ps1")


@app.post("/api/services/restart")
async def api_restart_service(request: Request):
    body = await request.json()
    name = body.get("serviceName", "")
    return await run_ps("Restart-Service.ps1", {"ServiceName": name}, timeout=60)


@app.post("/api/services/restart-agent")
async def api_restart_agent():
    """Runs c:\\pixellot\\bin\\keepagentup.exe per PDF #13 — the documented
    fast remedy for hung agent/coordinator before escalating to RMA."""
    return await run_ps("Restart-PixellotAgent.ps1", timeout=120)


@app.post("/api/services/reinstall-deps")
async def api_reinstall_deps():
    """Downloads and runs Pixellot-Installer-Dependencies-5.0.0.exe per
    PDF #2 — the documented remedy for CUDNN/TensorFlow errors in the
    VPU logs. Download can take a few minutes; installer up to ~10 min."""
    # 20 min cap covers a slow download plus the installer itself.
    return await run_ps("Install-PixellotDependencies.ps1", timeout=1200)


@app.get("/api/services/install-state")
async def api_install_state():
    """PDF #3: detect a half-finished install in c:\\pixellot\\downloadedversion.
    Returns the part files present and the last line of the most-recent
    installer log."""
    return await run_ps("Test-PixellotInstallState.ps1", timeout=15)


@app.get("/api/disk-health")
async def api_disk_health():
    return await run_ps("Get-DiskHealth.ps1")


# PDF #1: Image / file repair commands. RestoreHealth and sfc /scannow
# can run 10–30 minutes, so each action gets its own generous timeout.
_REPAIR_TIMEOUTS = {
    "CheckHealth":    240,    # ~30s typical, give it 4 min
    "RestoreHealth":  1900,   # up to 30 min + buffer
    "SfcScan":        1900,
    "ChkdskSchedule": 60,     # just queues, returns fast
}


@app.post("/api/disk-health/repair")
async def api_disk_repair(request: Request):
    body = await request.json()
    action = body.get("action", "")
    if action not in _REPAIR_TIMEOUTS:
        return {"error": True, "message": f"Unknown action: {action!r}. Expected one of {list(_REPAIR_TIMEOUTS)}"}
    return await run_ps(
        "Invoke-RepairTool.ps1",
        {"Action": action},
        timeout=_REPAIR_TIMEOUTS[action],
    )


@app.get("/api/events")
async def api_events(
    hours: int = Query(default=48), level: str = Query(default="all")
):
    return await run_ps("Get-EventLogs.ps1", {"HoursBack": hours, "Level": level})


@app.get("/api/pixellot-logs")
async def api_pixellot_logs(hours: int = Query(default=24)):
    """Scan C:\\Pixellot\\Data\\Log for errors, fatals, and process
    restarts in the last `hours` (PDF #5). Returns up to 500 matches with
    a `depsErrorDetected` flag that the UI uses to surface the PDF #2
    dependency-reinstall remedy."""
    return await run_ps("Search-PixellotLogs.ps1", {"HoursBack": hours}, timeout=30)


@app.get("/api/audio")
async def api_audio():
    return await run_ps("Get-AudioDevices.ps1")


@app.post("/api/audio/volume")
async def api_audio_volume(request: Request):
    body = await request.json()
    device_id = body.get("deviceId", "")
    volume = body.get("volume")

    # Validate — reject bad input before it reaches PowerShell.
    if not isinstance(device_id, str) or not device_id.strip():
        return {"error": True, "message": "deviceId must be a non-empty string"}
    try:
        volume = int(volume)
    except (TypeError, ValueError):
        return {"error": True, "message": "volume must be an integer"}
    if volume < 0 or volume > 100:
        return {"error": True, "message": "volume must be 0-100"}

    return await run_ps("Set-AudioVolume.ps1", {"DeviceId": device_id, "Volume": volume})


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
    sc_url = load_settings().get("scoreConnectUrl", "http://localhost:5000")
    results = await asyncio.gather(
        run_ps("Get-SystemIdentity.ps1"),
        run_ps("Get-Hardware.ps1"),
        run_ps("Get-Performance.ps1"),
        run_ps("Get-NetworkConfig.ps1"),
        run_ps("Get-NicAdapters.ps1"),
        run_ps("Get-Services.ps1"),
        run_ps("Get-DiskHealth.ps1"),
        run_ps("Get-EventLogs.ps1"),
        run_ps("Get-ScoreConnectStatus.ps1", {"BaseUrl": sc_url}),
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
        # Send SIGINT to ourselves so uvicorn's lifespan handlers run cleanly.
        # _os._exit would bypass cleanup and abruptly tear down the process.
        import signal
        try:
            _os.kill(_os.getpid(), signal.SIGINT)
        except Exception:
            _os._exit(0)  # fall back to hard exit if signal raise fails


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
        # Cache pixellot config but refresh periodically so config changes
        # made during a long session pick up without forcing a reconnect.
        pix_cfg = await run_ps("Get-PixellotConfig.ps1", timeout=10)
        ws_ocr_ips, _ = _build_ocr_sets(pix_cfg)
        pix_cfg_ttl_secs = 120  # refresh every ~2 minutes
        last_pix_refresh = time.time()

        while True:
            # Periodically refresh pixellot config (cheap — runs in parallel below).
            if time.time() - last_pix_refresh > pix_cfg_ttl_secs:
                try:
                    pix_cfg = await run_ps("Get-PixellotConfig.ps1", timeout=10)
                    ws_ocr_ips, _ = _build_ocr_sets(pix_cfg)
                    last_pix_refresh = time.time()
                except Exception as e:
                    ps_log("ws-refresh", 0, "warn", f"pix_cfg refresh failed: {e}")
                    _server_log.warning(f"pix_cfg refresh failed: {e}")

            perf, nics, net_health = await asyncio.gather(
                run_ps("Get-Performance.ps1", timeout=10),
                run_ps("Get-NicAdapters.ps1", timeout=10),
                run_ps("Get-NetworkHealth.ps1", timeout=10),
            )
            # CGI probes use 30s cache — no extra network cost on each tick
            ws_raw = nics.get("ports", []) if nics and not nics.get("error") else []
            ws_probes = await _probe_all_cameras(ws_raw, ws_ocr_ips)
            all_logs = list(LOG_BUFFER)
            new_logs = all_logs[last_log_idx:]
            last_log_idx = len(all_logs)

            await ws.send_json(
                {
                    "type": "metrics",
                    "performance": perf,
                    "ports": _enrich_ports(nics, pix_cfg, ws_probes),
                    "networkHealth": net_health,
                    "logs": new_logs,
                }
            )
            await asyncio.sleep(interval)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        # Log unexpected errors so they're surfaced in BOTH the Script Log
        # buffer (for live WS clients) and the Server Log file (for
        # post-hoc inspection) instead of silently killing live metric updates.
        msg = f"WebSocket loop crashed: {type(e).__name__}: {e}"
        ps_log("ws-loop", 0, "error", msg)
        _server_log.exception(msg)
    finally:
        _on_ws_disconnect(ws)


# ─── Entry point ──────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn

    port = int(_os.environ.get("PORT", 8765))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
