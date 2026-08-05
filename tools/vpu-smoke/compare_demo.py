#!/usr/bin/env python3
"""Compare real VPU collector payloads (from a sweep.py run) against demo_data.py.

For each collector that produced parseable JSON, diff the *structure* (key
paths + value types, never values) against what demo mode serves. Surfaces:
  - key paths the demo has but the real VPU never emitted (UI may render
    fields that don't exist in the field), and
  - key paths the real VPU emits that demo lacks (UI never exercised them).

Output is key names only, so it is safe to display without redaction.

Usage:
    python3 tools/vpu-smoke/compare_demo.py --sweep-dir /path/to/results
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "Pulse.Web" / "app"))

from sweep import MANIFEST, extract_json  # noqa: E402
import demo_data  # noqa: E402


def key_paths(obj, prefix: str = "") -> set[str]:
    """All key paths with a type tag. Lists merge every element's structure."""
    paths: set[str] = set()
    if isinstance(obj, dict):
        for key, value in obj.items():
            path = f"{prefix}.{key}" if prefix else key
            paths.add(f"{path}:{type(value).__name__}")
            paths |= key_paths(value, path)
    elif isinstance(obj, list):
        for item in obj:
            paths |= key_paths(item, f"{prefix}[]")
    return paths


def strip_types(paths: set[str]) -> set[str]:
    return {p.rsplit(":", 1)[0] for p in paths}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sweep-dir", required=True)
    args = ap.parse_args()
    sweep_dir = pathlib.Path(args.sweep_dir)

    for script, script_args, _timeout in MANIFEST:
        stem = script.replace(".ps1", "")
        stdout_file = sweep_dir / f"{stem}.stdout.txt"
        meta_file = sweep_dir / f"{stem}.meta.json"
        if not stdout_file.exists():
            continue
        meta = json.loads(meta_file.read_text()) if meta_file.exists() else {}
        real = extract_json(stdout_file.read_text(encoding="utf-8", errors="replace"))
        demo = demo_data.get_demo(script, script_args)

        if demo is None:
            print(f"\n== {script}: NO DEMO PAYLOAD (real status: {meta.get('status')})")
            continue
        if real is None:
            print(f"\n== {script}: no parseable real payload ({meta.get('status')})")
            continue

        demo_paths, real_paths = key_paths(demo), key_paths(real)
        demo_keys, real_keys = strip_types(demo_paths), strip_types(real_paths)
        only_demo = sorted(demo_keys - real_keys)
        only_real = sorted(real_keys - demo_keys)
        # Same key present in both but with a different type.
        type_diff = sorted(
            k for k in (demo_keys & real_keys)
            if {p for p in demo_paths if p.rsplit(":", 1)[0] == k}
            != {p for p in real_paths if p.rsplit(":", 1)[0] == k}
        )

        if not (only_demo or only_real or type_diff):
            print(f"== {script}: structures match ({len(real_keys)} key paths)")
            continue
        print(f"\n== {script}: {len(only_demo)} demo-only, {len(only_real)} real-only, "
              f"{len(type_diff)} type-mismatch")
        for key in only_demo[:25]:
            print(f"   demo-only : {key}")
        if len(only_demo) > 25:
            print(f"   demo-only : ... {len(only_demo) - 25} more")
        for key in only_real[:25]:
            print(f"   real-only : {key}")
        if len(only_real) > 25:
            print(f"   real-only : ... {len(only_real) - 25} more")
        for key in type_diff[:15]:
            print(f"   type-diff : {key}")
    return 0


if __name__ == "__main__":
    main()
