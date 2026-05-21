"""Run PowerShell scripts and capture JSON output."""

from __future__ import annotations

import asyncio
import json
import os
from typing import Optional

SCRIPTS_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts")
)


async def run_ps(
    script_name: str, args: Optional[dict] = None, timeout: int = 30
) -> dict:
    script_path = os.path.join(SCRIPTS_DIR, script_name)
    if not os.path.isfile(script_path):
        return {"error": True, "message": f"Script not found: {script_name}"}

    cmd = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        script_path,
    ]
    if args:
        for key, value in args.items():
            cmd.extend([f"-{key}", str(value)])

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        output = stdout.decode("utf-8", errors="replace").strip()
        if not output:
            return {"error": True, "message": f"No output from {script_name}"}
        return json.loads(output)
    except asyncio.TimeoutError:
        try:
            proc.kill()
        except ProcessLookupError:
            pass
        return {"error": True, "message": f"Timeout after {timeout}s: {script_name}"}
    except json.JSONDecodeError as e:
        return {"error": True, "message": f"Invalid JSON from {script_name}: {e}"}
    except FileNotFoundError:
        return {
            "error": True,
            "message": "powershell.exe not found — this tool requires Windows",
        }
    except Exception as e:
        return {"error": True, "message": str(e)}
