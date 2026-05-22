"""Run PowerShell scripts and capture JSON output."""

from __future__ import annotations

import asyncio
import json
import os
import sys
import time
from collections import deque
from datetime import datetime
from typing import Optional

SCRIPTS_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts")
)

DEMO_MODE = sys.platform != "win32"

LOG_BUFFER: deque[dict] = deque(maxlen=500)


def _log(script: str, duration_ms: float, status: str, detail: str = "", size: int = 0):
    entry = {
        "ts": datetime.now().isoformat(timespec="milliseconds"),
        "script": script,
        "durationMs": round(duration_ms, 1),
        "status": status,
        "detail": detail,
        "bytes": size,
    }
    LOG_BUFFER.append(entry)
    return entry


async def run_ps(
    script_name: str, args: Optional[dict] = None, timeout: int = 30
) -> dict:
    t0 = time.monotonic()

    if DEMO_MODE:
        from demo_data import get_demo

        await asyncio.sleep(0.05 + 0.15 * __import__("random").random())
        result = get_demo(script_name, args)
        ms = (time.monotonic() - t0) * 1000
        if result is not None:
            raw = json.dumps(result)
            _log(script_name, ms, "ok", "demo mode", len(raw))
            return result
        _log(script_name, ms, "error", "no demo data for this script")
        return {"error": True, "message": f"No demo data for {script_name}"}

    script_path = os.path.join(SCRIPTS_DIR, script_name)
    if not os.path.isfile(script_path):
        _log(script_name, (time.monotonic() - t0) * 1000, "error", "script not found")
        return {"error": True, "message": f"Script not found: {script_name}"}

    cmd = [
        "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", script_path,
    ]
    if args:
        for key, value in args.items():
            cmd.extend([f"-{key}", str(value)])

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        ms = (time.monotonic() - t0) * 1000
        output = stdout.decode("utf-8", errors="replace").strip()
        stderr_text = stderr.decode("utf-8", errors="replace").strip()

        if not output:
            _log(script_name, ms, "error", "no output", 0)
            return {"error": True, "message": f"No output from {script_name}"}

        result = json.loads(output)
        detail = stderr_text[:200] if stderr_text else "ok"
        _log(script_name, ms, "ok", detail, len(output))
        return result

    except asyncio.TimeoutError:
        ms = (time.monotonic() - t0) * 1000
        try:
            proc.kill()
        except ProcessLookupError:
            pass
        _log(script_name, ms, "timeout", f"after {timeout}s")
        return {"error": True, "message": f"Timeout after {timeout}s: {script_name}"}

    except json.JSONDecodeError as e:
        ms = (time.monotonic() - t0) * 1000
        _log(script_name, ms, "error", f"invalid JSON: {e}")
        return {"error": True, "message": f"Invalid JSON from {script_name}: {e}"}

    except FileNotFoundError:
        ms = (time.monotonic() - t0) * 1000
        _log(script_name, ms, "error", "powershell.exe not found")
        return {"error": True, "message": "powershell.exe not found — this tool requires Windows"}

    except Exception as e:
        ms = (time.monotonic() - t0) * 1000
        _log(script_name, ms, "error", str(e))
        return {"error": True, "message": str(e)}
