"""Peer-to-peer LAN sharing for Pulse.

Lets one Pulse push its diagnostic snapshot to another Pulse on the same
local network. The receiving side opts in with an "enable receive" toggle,
which is the ONLY time we bind to 0.0.0.0 — keeping the main app loopback-only
(and avoiding the Windows Defender Firewall prompt) for everyone who doesn't
use this feature. See main.py's entry point for that loopback rationale.

Design:
  * Receiver starts a second, minimal uvicorn server bound to 0.0.0.0 on a
    dedicated LAN port (default = UI port + 1). It exposes exactly two routes:
    POST /api/peer/receive  and  GET /api/peer/ping.
  * Receiver shows a pairing code that encodes its LAN IP + port + a random
    nonce. The sender pastes the code; the nonce is sent back in the
    X-Pulse-Pair header and must match the active session, so a random box on
    the LAN can't inject a report.
  * Received reports are written to received_reports/ for the inbox UI.

No third-party deps — stdlib urllib for the outbound push, same as the
self-updater (main.py:_resolve_latest_release).
"""

import os
import re
import json
import socket
import struct
import secrets
import asyncio
import datetime
import urllib.request
import urllib.error
from typing import Optional

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

# received_reports/ lives next to pulse-settings.json (the web root).
_web_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_RECEIVED_DIR = os.path.join(_web_root, "received_reports")

# Reports are usually well under a megabyte, but event logs can be chunky.
# Cap inbound bodies so a hostile/buggy peer can't fill the disk.
MAX_REPORT_BYTES = 32 * 1024 * 1024

# Pairing code: 5 simple words encode the receiver's IP (32 bits) + a 23-bit
# pairing number (~8.4M combos), using an 11-bit-per-word list (2048 words).
# The LAN port is NOT in the code — it assumes the default below; a non-default
# port is reached via the address-override field on the Send form.
DEFAULT_LAN_PORT = 8766
_PAIR_WORDS = 5
_NONCE_BITS = 23
_NONCE_MASK = (1 << _NONCE_BITS) - 1
_WORDLIST_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wordlist.txt")

_ID_RE = re.compile(r"^[0-9A-Za-z_\-T]+$")  # guards inbox ids against path traversal


def _load_wordlist():
    """The BIP39 English wordlist — 2048 short, unambiguous, read-aloud-friendly
    words, purpose-built for transcribable codes like this."""
    with open(_WORDLIST_PATH, encoding="utf-8") as f:
        words = [w.strip().lower() for w in f if w.strip()]
    if len(words) < 2048:
        raise RuntimeError(f"wordlist needs 2048 words, found {len(words)}")
    return words[:2048]


_WORDS = _load_wordlist()
_WORD_INDEX = {w: i for i, w in enumerate(_WORDS)}


# ─── LAN address discovery ────────────────────────────────────

def get_lan_ip() -> str:
    """Best-effort primary non-loopback IPv4. The UDP-connect trick reads the
    OS's chosen outbound interface without sending a packet, so it works on an
    air-gapped LAN. Falls back to hostname resolution, then loopback."""
    s = None
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))  # no packet sent for UDP connect
        ip = s.getsockname()[0]
        if ip and not ip.startswith("127."):
            return ip
    except Exception:
        pass
    finally:
        if s is not None:
            try:
                s.close()
            except Exception:
                pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip and not ip.startswith("127."):
                return ip
    except Exception:
        pass
    return "127.0.0.1"


def _is_ipv4(ip: str) -> bool:
    try:
        socket.inet_aton(ip)
        return ip.count(".") == 3
    except OSError:
        return False


def list_lan_ips() -> list:
    """All usable non-loopback IPv4 addresses on this host, default-route first.
    A multi-NIC box (VPUs have uplink + camera ports; this dev Mac has two LANs)
    needs the tech to pick which one the peer can actually reach, so we surface
    every candidate. Stdlib enumeration is unreliable cross-platform, so we also
    parse ipconfig/ifconfig — no extra dependency."""
    ips, seen = [], set()

    def add(ip):
        if ip and ip not in seen and not ip.startswith("127.") and not ip.startswith("169.254."):
            seen.add(ip)
            ips.append(ip)

    add(get_lan_ip())  # default-route interface goes first (best default)
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            add(info[4][0])
    except Exception:
        pass
    try:
        import subprocess
        cmd = ["ipconfig"] if os.name == "nt" else ["ifconfig"]
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=5).stdout
        for m in re.findall(r"(?:IPv4[^\n:]*:\s*|inet )(\d+\.\d+\.\d+\.\d+)", out):
            add(m)
    except Exception:
        pass
    return ips


# ─── Pairing code ─────────────────────────────────────────────

def gen_nonce() -> int:
    return secrets.randbits(_NONCE_BITS)


def encode_pair(ip: str, nonce: int) -> str:
    """Encode the receiver's IP + pairing number as 5 space-separated words,
    e.g. 'tiger maple river copper dust'."""
    ip_int = struct.unpack(">I", socket.inet_aton(ip))[0]
    val = (ip_int << _NONCE_BITS) | (nonce & _NONCE_MASK)  # 55-bit value
    return " ".join(_WORDS[(val >> (11 * i)) & 0x7FF] for i in range(_PAIR_WORDS - 1, -1, -1))


def decode_pair(code: str):
    """Inverse of encode_pair. Tolerant of case, spacing, and punctuation.
    Returns (ip, port, nonce) — port is the assumed default, nonce is the
    pairing number as a string. Raises ValueError on a bad code."""
    tokens = re.findall(r"[a-z]+", (code or "").lower())
    if len(tokens) != _PAIR_WORDS:
        raise ValueError(f"pairing code should be {_PAIR_WORDS} words")
    val = 0
    for t in tokens:
        idx = _WORD_INDEX.get(t)
        if idx is None:
            raise ValueError(f"unknown word: {t}")
        val = (val << 11) | idx
    nonce = val & _NONCE_MASK
    ip = socket.inet_ntoa(struct.pack(">I", (val >> _NONCE_BITS) & 0xFFFFFFFF))
    return ip, DEFAULT_LAN_PORT, str(nonce)


def parse_address(addr: str, default_port: int):
    """Parse 'host', 'host:port', or a 'http://host:port/' URL. Returns
    (host, port) or None."""
    addr = (addr or "").strip()
    if not addr:
        return None
    for scheme in ("http://", "https://"):
        if addr.startswith(scheme):
            addr = addr[len(scheme):]
    addr = addr.strip("/")
    if ":" in addr:
        host, _, p = addr.rpartition(":")
        try:
            return host, int(p)
        except ValueError:
            return None
    return addr, default_port


# ─── Inbox file IO ────────────────────────────────────────────

def _safe_path(rec_id: str) -> Optional[str]:
    if not rec_id or not _ID_RE.match(rec_id):
        return None
    return os.path.join(_RECEIVED_DIR, rec_id + ".json")


def save_received(report, sender_ip: str) -> str:
    """Persist an incoming report and return its inbox id. The id is generated
    here — never derived from anything the sender supplied."""
    os.makedirs(_RECEIVED_DIR, exist_ok=True)
    ts = datetime.datetime.now(datetime.timezone.utc)
    rec_id = ts.strftime("%Y%m%dT%H%M%S") + "-" + secrets.token_hex(3)
    if not isinstance(report, dict):
        report = {"report": report}
    report = dict(report)
    report["_received"] = {"id": rec_id, "receivedAt": ts.isoformat(), "senderIp": sender_ip}
    with open(os.path.join(_RECEIVED_DIR, rec_id + ".json"), "w", encoding="utf-8") as f:
        json.dump(report, f)
    return rec_id


def _summarize(path: str, report: dict) -> dict:
    rec = report.get("_received", {}) if isinstance(report, dict) else {}
    meta = report.get("_meta", {}) if isinstance(report, dict) else {}
    findings = report.get("findings") if isinstance(report, dict) else None
    sections = [k for k in report if not k.startswith("_") and k != "findings"] if isinstance(report, dict) else []
    ident = report.get("identity") if isinstance(report, dict) else None
    pix = ident.get("pixellot") if isinstance(ident, dict) else None
    vpu_name = pix.get("vpuName") if isinstance(pix, dict) else None
    return {
        "id": rec.get("id") or os.path.basename(path)[:-5],
        "receivedAt": rec.get("receivedAt"),
        "senderIp": rec.get("senderIp"),
        "vpuName": vpu_name,
        "hostname": meta.get("hostname"),
        "generatedAt": meta.get("generatedAt"),
        "pulseVersion": meta.get("pulseVersion"),
        "channel": meta.get("channel"),
        "findingCount": len(findings) if isinstance(findings, list) else 0,
        "sectionCount": len(sections),
        "sourceErrorCount": len(meta.get("sourceErrors") or {}),
        "sizeBytes": os.path.getsize(path),
    }


def list_received() -> list:
    if not os.path.isdir(_RECEIVED_DIR):
        return []
    out = []
    for name in os.listdir(_RECEIVED_DIR):
        if not name.endswith(".json"):
            continue
        path = os.path.join(_RECEIVED_DIR, name)
        try:
            with open(path, encoding="utf-8") as f:
                out.append(_summarize(path, json.load(f)))
        except Exception:
            continue
    out.sort(key=lambda r: r.get("receivedAt") or "", reverse=True)
    return out


def get_received(rec_id: str):
    path = _safe_path(rec_id)
    if not path or not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def delete_received(rec_id: str) -> bool:
    path = _safe_path(rec_id)
    if not path or not os.path.isfile(path):
        return False
    os.remove(path)
    return True


# ─── Outbound push (sender side) ──────────────────────────────

def push_report_sync(report_bytes: bytes, ip: str, port: int, nonce: str, timeout: int = 30) -> dict:
    """POST a serialized report to a peer's receive endpoint. Blocking — call
    via asyncio.to_thread so it doesn't stall the event loop."""
    req = urllib.request.Request(
        f"http://{ip}:{port}/api/peer/receive",
        data=report_bytes, method="POST",
        headers={"Content-Type": "application/json", "X-Pulse-Pair": nonce,
                 "User-Agent": "Pulse-Peer"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def ping_peer_sync(ip: str, port: int, timeout: int = 5) -> dict:
    """Confirm a peer is reachable and is actually a Pulse receiver. Blocking."""
    req = urllib.request.Request(f"http://{ip}:{port}/api/peer/ping",
                                 headers={"User-Agent": "Pulse-Peer"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


# ─── Receive listener (receiver side, opt-in) ─────────────────

# Active pairing session: {code, nonce, ip, port, startedAt} or None.
_session: Optional[dict] = None
_server = None            # uvicorn.Server while receiving
_task = None              # asyncio.Task running server.serve()
_app_version = "unknown"  # set by start_listener, reported via /api/peer/ping

peer_app = FastAPI(title="Pulse Peer Receiver")


class _NoSignalServer(uvicorn.Server):
    """The primary uvicorn server owns the process signal handlers (the
    idle-shutdown path SIGINTs itself). A second server must not clobber them."""

    def install_signal_handlers(self):
        pass


@peer_app.get("/api/peer/ping")
async def _peer_ping():
    return {"pulse": True, "hostname": socket.gethostname(), "version": _app_version}


@peer_app.post("/api/peer/receive")
async def _peer_receive(request: Request):
    sess = _session
    if not sess:
        return JSONResponse({"ok": False, "error": "not accepting reports"}, status_code=503)
    nonce = request.headers.get("x-pulse-pair", "")
    if not nonce or nonce.strip() != sess["nonce"]:
        return JSONResponse({"ok": False, "error": "wrong or missing pairing code"}, status_code=403)
    raw = await request.body()
    if len(raw) > MAX_REPORT_BYTES:
        return JSONResponse({"ok": False, "error": "report too large"}, status_code=413)
    try:
        report = json.loads(raw.decode("utf-8"))
    except Exception:
        return JSONResponse({"ok": False, "error": "invalid JSON"}, status_code=400)
    sender_ip = request.client.host if request.client else "?"
    rec_id = save_received(report, sender_ip)
    return {"ok": True, "id": rec_id, "hostname": socket.gethostname()}


def is_receiving() -> bool:
    return _session is not None and _task is not None and not _task.done()


def listener_status() -> dict:
    if not is_receiving():
        return {"on": False, "code": None, "address": None, "lanPort": None,
                "candidates": list_lan_ips()}
    s = _session
    return {
        "on": True,
        "code": s["code"],
        "ip": s["ip"],
        "lanPort": s["port"],
        "address": f"{s['ip']}:{s['port']}",
        "candidates": s.get("candidates") or list_lan_ips(),
        "startedAt": s["startedAt"],
    }


def set_advertise_ip(ip: str) -> dict:
    """Re-point the pairing code at a different local IP without rebinding the
    listener (it already listens on 0.0.0.0). Lets the tech pick the interface
    the peer can actually reach. Keeps the same pairing number."""
    if not is_receiving():
        return listener_status()
    if not _is_ipv4(ip):
        raise ValueError("not a valid IPv4 address")
    _session["ip"] = ip
    _session["code"] = encode_pair(ip, int(_session["nonce"]))
    return listener_status()


async def start_listener(lan_port: int, app_version: str = "unknown",
                         advertise_ip: Optional[str] = None) -> dict:
    """Bind the receive listener to 0.0.0.0:lan_port and open a pairing
    session. If already running, just re-points the advertised IP (if given).
    Raises RuntimeError if the port can't be opened."""
    global _session, _server, _task, _app_version
    if is_receiving():
        if advertise_ip:
            return set_advertise_ip(advertise_ip)
        return listener_status()
    _app_version = app_version
    ip = advertise_ip if (advertise_ip and _is_ipv4(advertise_ip)) else get_lan_ip()
    nonce = gen_nonce()
    _session = {
        "code": encode_pair(ip, nonce),
        "nonce": str(nonce),
        "ip": ip,
        "port": lan_port,
        "candidates": list_lan_ips(),
        "startedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    config = uvicorn.Config(peer_app, host="0.0.0.0", port=lan_port,
                            log_level="warning", access_log=False, lifespan="off")
    _server = _NoSignalServer(config)
    _task = asyncio.create_task(_server.serve())

    # Wait briefly for the socket to bind so we surface "port in use" as an
    # error here rather than silently failing inside the background task.
    for _ in range(60):
        if getattr(_server, "started", False):
            return listener_status()
        if _task.done():
            exc = _task.exception()
            _session = _server = _task = None
            raise RuntimeError(f"could not open port {lan_port}: {exc or 'already in use?'}")
        await asyncio.sleep(0.05)
    return listener_status()


async def stop_listener() -> dict:
    global _session, _server, _task
    if _server is not None:
        _server.should_exit = True
    if _task is not None:
        try:
            await asyncio.wait_for(asyncio.shield(_task), timeout=5)
        except Exception:
            pass
    _session = _server = _task = None
    return {"on": False}
