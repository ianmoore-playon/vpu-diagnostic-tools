"""Run PowerShell scripts and capture JSON output."""

from __future__ import annotations

import asyncio
import json
import os
import sys
import time
import uuid
from collections import deque
from datetime import datetime
from typing import Optional

SCRIPTS_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts")
)

DEMO_MODE = sys.platform != "win32"

LOG_BUFFER: deque[dict] = deque(maxlen=500)
RUNNING_TASKS: dict[str, dict] = {}


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


def get_running_tasks() -> list[dict]:
    now = time.monotonic()
    return [
        {"id": tid, "script": t["script"], "runningSec": round(now - t["started"], 1)}
        for tid, t in RUNNING_TASKS.items()
    ]


def cancel_task(task_id: str) -> bool:
    task = RUNNING_TASKS.get(task_id)
    if not task:
        return False
    handle = task.get("handle")
    if handle:
        try:
            handle.kill()
        except ProcessLookupError:
            pass
    cancel_evt = task.get("cancel")
    if cancel_evt:
        cancel_evt.set()
    return True


def cancel_all_tasks() -> int:
    count = 0
    for tid in list(RUNNING_TASKS):
        if cancel_task(tid):
            count += 1
    return count


async def run_ps(
    script_name: str, args: Optional[dict] = None, timeout: int = 30
) -> dict:
    task_id = uuid.uuid4().hex[:8]
    t0 = time.monotonic()
    cancel_evt = asyncio.Event()
    RUNNING_TASKS[task_id] = {
        "script": script_name,
        "started": t0,
        "handle": None,
        "cancel": cancel_evt,
    }

    try:
        return await _run_ps_inner(script_name, args, timeout, task_id, cancel_evt)
    finally:
        RUNNING_TASKS.pop(task_id, None)


async def _run_ps_inner(script_name, args, timeout, task_id, cancel_evt):
    t0 = RUNNING_TASKS[task_id]["started"]

    if DEMO_MODE:
        from demo_data import get_demo

        try:
            await asyncio.wait_for(
                cancel_evt.wait(),
                timeout=0.05 + 0.15 * __import__("random").random(),
            )
            ms = (time.monotonic() - t0) * 1000
            _log(script_name, ms, "cancelled", "user cancelled")
            return {"error": True, "message": f"Cancelled: {script_name}"}
        except asyncio.TimeoutError:
            pass

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
        RUNNING_TASKS[task_id]["handle"] = proc

        async def wait_cancel():
            await cancel_evt.wait()
            try:
                proc.kill()
            except ProcessLookupError:
                pass

        cancel_task_coro = asyncio.create_task(wait_cancel())
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        finally:
            cancel_task_coro.cancel()

        if cancel_evt.is_set():
            ms = (time.monotonic() - t0) * 1000
            _log(script_name, ms, "cancelled", "user cancelled")
            return {"error": True, "message": f"Cancelled: {script_name}"}

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
