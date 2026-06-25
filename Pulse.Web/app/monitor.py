"""Proactive monitoring — unattended readiness loop + finding-state diff.

This is the engine behind the proactive-monitoring pilot (PULSEDEV-50). It turns
the existing on-demand readiness verdict into a background watch:

  * **State diff (PULSEDEV-52).** Persist the set of *open* finding codes across
    runs and diff each new verdict against it, so we emit an event only when a
    finding *opens* or *resolves* — never on every poll while it persists.
  * **Severity gate (PULSEDEV-52).** Route each transition by its readiness
    class: blocker → alert now, risk → low-urgency/digest, info → log only
    (info findings are chronic and fleet-wide; alerting on them destroys signal).
  * **Collection loop (PULSEDEV-51).** A cheap heartbeat tripwire (core-service
    liveness) interleaved with a periodic full recompute, tightened to an
    incident cadence while a finding is open, with recording-aware backoff so we
    never run the intrusive network probe while the VPU is encoding a game.

Everything that makes a *decision* (`codes_from_verdict`, `compute_delta`,
`route_for`, `should_alert_now`) is a pure function with no I/O, so it is unit-
testable in demo mode on any platform. The file-backed state and the async loop
are thin wrappers around those pure functions. `main.py` injects its collectors
and the beacon via `MonitorDeps`, so this module never imports `main` (no import
cycle) and carries no FastAPI/PowerShell dependency of its own.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
from datetime import datetime, timezone
from typing import Awaitable, Callable, Optional

_log = logging.getLogger("pulse.monitor")

# ── State schema version ─────────────────────────────────────────────────────
# Bumped only if the on-disk shape changes incompatibly; load tolerates a
# mismatch by starting from an empty open-set (first run after an upgrade just
# re-opens whatever is currently failing — no false "resolved" storm).
STATE_VERSION = 1

# Readiness class → alert routing. Mirrors the policy in main.py's
# `_READINESS_POLICY` (blocker/risk/info) but expressed as a *transport* routing
# decision so the relay (PULSEDEV-54) and the beacon (PULSEDEV-53) agree.
_ROUTE = {
    "blocker": "alert",    # page us now — won't stream tonight
    "risk":    "digest",   # low-urgency — a human should eyeball before game time
    "info":    "log",      # chronic/context — never alert
}

# Finding codes that come *only* from the intrusive network-port probe
# (Test-NetworkPorts). When recording-aware backoff skips that probe, these
# codes are "not evaluated this run" — they must be carried forward, never
# resolved, or we'd emit a phantom "all-clear" for a streaming blocker mid-game.
INTRUSIVE_PORT_CODES = frozenset({
    "stream-2088-blocked",
    "stream-443-blocked",
    "port-dns-blocked",
    "port-required-blocked",
})


# ── Cadence (seconds), env-overridable so the pilot can be tuned per box ──────
def _env_int(name: str, default: int) -> int:
    try:
        v = int(str(os.environ.get(name, "")).strip())
        return v if v > 0 else default
    except (TypeError, ValueError):
        return default


HEARTBEAT_SECONDS = _env_int("PULSE_MONITOR_HEARTBEAT_SECONDS", 300)    # ~5 min cheap tripwire
FULL_SECONDS      = _env_int("PULSE_MONITOR_FULL_SECONDS", 1200)        # ~20 min authoritative recompute
INCIDENT_SECONDS  = _env_int("PULSE_MONITOR_INCIDENT_SECONDS", 60)      # ~60 s while a finding is open
STARTUP_DELAY_SECONDS = _env_int("PULSE_MONITOR_STARTUP_DELAY_SECONDS", 20)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# ── Pure decision functions (no I/O — unit-tested directly) ───────────────────

def codes_from_verdict(verdict: Optional[dict]) -> dict:
    """Flatten a readiness verdict into ``{code: {class,title,category,recommendation}}``.

    The verdict already classifies every code by which bucket it lands in
    (blockers/risks/info), so the readiness *class* is implied by position — no
    second lookup against the policy table needed. This is also why we diff on
    the verdict rather than the raw findings list: the verdict includes the
    readiness-only computed codes (disk-c-critical, cpu-sustained, …) that the
    dashboard findings don't carry.
    """
    out: dict = {}
    for cls, key in (("blocker", "blockers"), ("risk", "risks"), ("info", "info")):
        for f in (verdict or {}).get(key) or []:
            code = (f or {}).get("code")
            if not code:
                continue
            out[code] = {
                "class": cls,
                "title": f.get("title", ""),
                "category": f.get("category", ""),
                "recommendation": f.get("recommendation", ""),
            }
    return out


def route_for(cls: str) -> str:
    """Alert routing for a readiness class (alert / digest / log)."""
    return _ROUTE.get(cls or "", "log")


def _fingerprint(serial: Optional[str], code: str) -> str:
    """Cross-fleet identity for one open finding: ``serial:code``.

    Locally we key state by ``code`` alone (state is per-box), but every emitted
    event carries the fingerprint so the Sheet/relay can dedup across the fleet.
    """
    return f"{serial}:{code}" if serial else code


def compute_delta(prev_open: dict, current: dict, prev_status: Optional[str],
                  status: Optional[str], serial: Optional[str],
                  out_of_scope: frozenset = frozenset(), now: Optional[str] = None):
    """Diff the prior open-set against the current verdict.

    Returns ``(new_open, delta)`` where:

      * ``new_open`` is the open-set to persist — current findings plus any
        ``out_of_scope`` codes carried forward unevaluated.
      * ``delta`` is the structured transition record the beacon sends:
        ``opened`` / ``resolved`` lists (each entry tagged with its class +
        fingerprint + routing), ``persisting`` codes, the status flip, and an
        ``alert`` flag set when any *blocker* opened or resolved.

    ``out_of_scope`` codes (e.g. the port probe was skipped while recording) are
    never resolved — a check we didn't run can't have "cleared". They carry
    forward from ``prev_open`` so the next full run reconciles them.
    """
    now = now or _now_iso()
    opened, resolved, persisting = [], [], []
    new_open: dict = {}

    for code, info in current.items():
        if code in prev_open:
            persisting.append(code)
            # Preserve the original open time so "open for N hours" stays true.
            since = prev_open[code].get("since") or now
            new_open[code] = {**info, "since": since}
        else:
            new_open[code] = {**info, "since": now}
            opened.append(_event(code, info, serial, since=now))

    for code, info in prev_open.items():
        if code in current:
            continue
        if code in out_of_scope:
            # Not evaluated this run — carry forward, do NOT resolve.
            new_open[code] = info
            continue
        resolved.append(_event(code, info, serial, since=info.get("since")))

    alert = any(e["class"] == "blocker" for e in opened) or \
            any(e["class"] == "blocker" for e in resolved)

    delta = {
        "opened": opened,
        "resolved": resolved,
        "persisting": sorted(persisting),
        "status": status,
        "prevStatus": prev_status,
        "statusChanged": status != prev_status,
        "alert": alert,
    }
    return new_open, delta


def _event(code: str, info: dict, serial: Optional[str], since: Optional[str]) -> dict:
    cls = info.get("class", "info")
    return {
        "code": code,
        "fingerprint": _fingerprint(serial, code),
        "class": cls,
        "route": route_for(cls),
        "title": info.get("title", ""),
        "category": info.get("category", ""),
        "recommendation": info.get("recommendation", ""),
        "since": since,
    }


def should_alert_now(delta: dict) -> bool:
    """Whether a delta warrants an *immediate*, off-cadence beacon.

    Fires for any blocker/risk transition or an overall status flip. Info-only
    changes ride the next periodic beacon instead — they're reported, but they
    never trigger an off-cycle alert (severity gate: info → log only).
    """
    transitions = (delta.get("opened") or []) + (delta.get("resolved") or [])
    if any(e.get("class") in ("blocker", "risk") for e in transitions):
        return True
    return bool(delta.get("statusChanged"))


def summarize_delta(delta: dict) -> str:
    """One-line human summary for the server log."""
    o, r = delta.get("opened") or [], delta.get("resolved") or []
    parts = [f"status={delta.get('status')}"]
    if o:
        parts.append("opened=" + ",".join(e["code"] for e in o))
    if r:
        parts.append("resolved=" + ",".join(e["code"] for e in r))
    if not o and not r:
        parts.append(f"steady ({len(delta.get('persisting') or [])} open)")
    return " ".join(parts)


# ── File-backed state (survives restart, resets on reinstall) ─────────────────
# Lives alongside pulse-settings.json in the install tree, so a reinstall (which
# re-downloads C:\Pulse) clears it — a fresh box re-opens whatever is currently
# failing rather than inheriting a stale ledger.

def load_state(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict) or data.get("version") != STATE_VERSION:
            return _empty_state()
        data.setdefault("open", {})
        data.setdefault("status", None)
        return data
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return _empty_state()


def save_state(path: str, open_map: dict, status: Optional[str],
               serial: Optional[str]) -> None:
    payload = {
        "version": STATE_VERSION,
        "serial": serial,
        "status": status,
        "open": open_map,
        "updatedAt": _now_iso(),
    }
    try:
        tmp = f"{path}.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
        os.replace(tmp, path)  # atomic — a torn write can't corrupt the ledger
    except OSError as e:
        _log.warning("Monitor state save failed (%s) — continuing in memory", e)


def _empty_state() -> dict:
    return {"version": STATE_VERSION, "serial": None, "status": None, "open": {}}


# ── Dependency injection for the async loop ───────────────────────────────────
# main.py supplies the collectors + beacon; this keeps monitor.py free of any
# import of main (no cycle) and trivially mockable in tests.

class MonitorDeps:
    def __init__(
        self,
        collect_dashboard: Callable[[bool], Awaitable[dict]],   # (skip_intrusive) -> dashboard
        send_checkin: Callable[..., Awaitable[None]],           # (dashboard, delta, reason)
        is_recording: Callable[[], Awaitable[bool]],
        service_tripwire: Callable[[], Awaitable[bool]],        # True if a core service is down
        get_serial: Callable[[dict], Optional[str]],            # dashboard -> serial
        clear_cache: Callable[[], object],
    ):
        self.collect_dashboard = collect_dashboard
        self.send_checkin = send_checkin
        self.is_recording = is_recording
        self.service_tripwire = service_tripwire
        self.get_serial = get_serial
        self.clear_cache = clear_cache


async def run_full_recompute(deps: MonitorDeps, state_path: str,
                             recording: bool) -> dict:
    """One authoritative pass: collect → diff → persist → beacon.

    When ``recording`` we skip the intrusive port probe and carry its codes
    forward (``INTRUSIVE_PORT_CODES``) so the diff can't false-resolve a
    streaming blocker mid-game. Returns the delta (for logging/tests)."""
    if not recording:
        # Force genuinely fresh data; the 25 s result cache is far shorter than
        # our cadence, but clearing makes the "this is the authoritative read"
        # intent explicit and avoids reusing a stale heartbeat-era entry.
        deps.clear_cache()

    dashboard = await deps.collect_dashboard(recording)
    verdict = (dashboard or {}).get("readiness") or {}
    serial = deps.get_serial(dashboard or {})
    out_of_scope = INTRUSIVE_PORT_CODES if recording else frozenset()

    state = load_state(state_path)
    current = codes_from_verdict(verdict)
    new_open, delta = compute_delta(
        state.get("open", {}), current, state.get("status"),
        verdict.get("status"), serial, out_of_scope=out_of_scope,
    )
    save_state(state_path, new_open, verdict.get("status"), serial)

    reason = "state-change" if should_alert_now(delta) else "periodic"
    _log.info("Monitor recompute: %s (reason=%s, recording=%s)",
              summarize_delta(delta), reason, recording)
    try:
        await deps.send_checkin(dashboard=dashboard, delta=delta, reason=reason)
    except Exception as e:  # fail-open: a beacon error must never stall the loop
        _log.warning("Monitor beacon failed (%s)", e)
    return delta


def _state_has_open(state_path: str) -> bool:
    return bool(load_state(state_path).get("open"))


async def run_monitor(deps: MonitorDeps, state_path: str,
                      stop_event: asyncio.Event) -> None:
    """The background loop. Interleaves a cheap heartbeat tripwire with a
    periodic full recompute, tightening to the incident cadence while any
    finding is open. Gated entirely by the caller (never started in demo/dev).

    The loop owns no wall-clock assumptions beyond ``loop.time()`` and is fully
    stoppable: every sleep races ``stop_event`` so shutdown is immediate.
    """
    _log.info(
        "Proactive monitor starting (heartbeat=%ss full=%ss incident=%ss)",
        HEARTBEAT_SECONDS, FULL_SECONDS, INCIDENT_SECONDS,
    )
    loop = asyncio.get_event_loop()

    # Let the app finish binding + the startup beacon fire before we pile on.
    try:
        await asyncio.wait_for(stop_event.wait(), timeout=STARTUP_DELAY_SECONDS)
        return  # stopped during the settle delay
    except asyncio.TimeoutError:
        pass

    next_full = 0.0                          # 0 ⇒ run a full recompute immediately
    next_hb = loop.time() + HEARTBEAT_SECONDS

    while not stop_event.is_set():
        try:
            recording = await deps.is_recording()
            now = loop.time()

            if now >= next_full:
                await run_full_recompute(deps, state_path, recording)
                interval = INCIDENT_SECONDS if _state_has_open(state_path) else FULL_SECONDS
                next_full = loop.time() + interval
                next_hb = loop.time() + HEARTBEAT_SECONDS
            elif now >= next_hb:
                tripped = await deps.service_tripwire()
                next_hb = loop.time() + HEARTBEAT_SECONDS
                if tripped:
                    _log.info("Heartbeat tripwire: core service down — forcing full recompute")
                    next_full = 0.0          # escalate now (full recompute does the diff/beacon)
        except Exception as e:
            _log.warning("Monitor loop iteration failed (%s)", e)

        # Sleep until the sooner deadline, racing the stop event for instant shutdown.
        deadline = min(next_full if next_full > 0 else loop.time() + FULL_SECONDS, next_hb)
        delay = max(1.0, deadline - loop.time())
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=delay)
        except asyncio.TimeoutError:
            pass

    _log.info("Proactive monitor stopped")
