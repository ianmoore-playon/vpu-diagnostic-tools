# HANDOFF — Proactive Monitoring pilot (PULSEDEV-50)

Pulse as an **unattended Windows service** that recomputes the Stream Readiness
verdict on a cadence and **Slack-alerts when a VPU develops a new problem** —
caught days before a game, not at kickoff. This is the minimal, pilotable slice
of the OneUptime detection-layer story; it proves the whole detection →
notification chain on 2–3 beta boxes without OneUptime or fleet deployment.

Status: **51–54 built on branch `proactive-monitoring`** (off `dev`). **55 is
operational** — needs a real VPU + LMI session.

```
VPU service loop ──(snapshot every ~20 min / on change)──▶ Google Sheet (ledger)
                                                                │
                                              Apps Script: new blocker? ──▶ Slack 🔔
                                                                │
                                                      (later) ──▶ OneUptime → incidents/MTTR
```

## What was built

| Story | What | Where |
| --- | --- | --- |
| **52** | Finding-state diff + severity gate (pure, unit-tested) | `app/monitor.py` |
| **51** | Service loop, recording-aware backoff, NSSM packaging | `app/main.py`, `scripts/Get-RecordingState.ps1`, `runners/install_pulse_service.ps1` |
| **53** | Periodic + state-change beacon; locked payload shape | `app/main.py` `_send_checkin` |
| **54** | Sheet → Slack relay (Apps Script reference) | `integrations/checkin_relay.gs` |
| tests | 20 unit tests for the engine | `tests/test_monitor.py` |

### The loop (`monitor.run_monitor`)

- **Cheap heartbeat (~5 min, `PULSE_MONITOR_HEARTBEAT_SECONDS`)** — a service
  tripwire only: runs `Get-Services` and, if `agent`/`coordinator` isn't
  `Running`, forces an immediate full recompute. No network, no cameras — safe
  mid-game.
- **Full recompute (~20 min, `PULSE_MONITOR_FULL_SECONDS`)** — the authoritative
  pass: `_collect_dashboard` → readiness verdict → diff → persist → beacon.
- **Incident tightening (~60 s, `PULSE_MONITOR_INCIDENT_SECONDS`)** — while any
  finding is open, the full recompute cadence tightens.
- **Recording-aware backoff** — `Get-RecordingState.ps1` reads NVENC encoder
  activity (`nvidia-smi`). While encoding, the full recompute **skips only the
  intrusive `Test-NetworkPorts` probe**; everything else is a pure read and runs.
  The skipped probe's codes (`monitor.INTRUSIVE_PORT_CODES`) are **carried
  forward**, so a skipped check never false-resolves a streaming blocker, and the
  verdict stays honest (`status_from_open`) — no FAIL↔WARN flap at boundaries.

### State diff + severity gate (`monitor.compute_delta`)

- Open finding codes persist to `C:\Pulse\pulse-monitor-state.json` (survives
  restart; a reinstall re-downloads `C:\Pulse`, clearing it).
- Each run diffs current vs persisted → **opened** / **resolved** / **persisting**.
  We beacon on transitions, never while a finding merely persists.
- Routing by readiness class: **blocker → alert now**, **risk → digest/quiet**,
  **info → log only** (info findings are chronic — alerting on them kills signal).
- `serial:code` fingerprints every event for fleet dedup at the relay.

### Locked beacon payload (the relay contract)

`_send_checkin(dashboard, delta, reason)` posts to the existing Apps Script
endpoint. Fires three ways: `reason` = `startup` | `periodic` | `state-change`.
Keep additions **additive** so the relay's parsing never breaks.

```jsonc
{
  "secret": "...", "hostname": "...", "serialNumber": "...", "venueId": "...",
  "vpuName": "...", "model": "...", "pulseVersion": "...", "channel": "...",
  "reason": "state-change",
  "readiness": { "status": "FAIL", "policyVersion": "v1",
                 "blockers": ["agent-down"], "risks": ["nic-slow"] },
  "delta": {                              // omitted on startup beacons
    "opened":   [{ "code": "agent-down", "fingerprint": "SN:agent-down",
                   "class": "blocker", "route": "alert", "title": "...",
                   "category": "Services", "recommendation": "...", "since": "..." }],
    "resolved": [],
    "persisting": ["nic-slow"],
    "status": "FAIL", "prevStatus": "WARN", "statusChanged": true, "alert": true
  }
}
```

## Deploy

### A. Slack relay (PULSEDEV-54) — do this first, it's where the secret lives

1. Create a **Slack incoming webhook** for the alert channel.
2. Open the Sheet's bound Apps Script (Extensions → Apps Script).
3. **Reconcile** `integrations/checkin_relay.gs` with the live script:
   match `LEDGER_HEADERS` to the real ledger columns, then merge the relay half
   (`routeDelta_` / `notifySlack_` / incident store) into the existing `doPost`.
   Do **not** blind-overwrite the deployed script.
4. Set Script Properties: `CHECKIN_SECRET` (matches `main.py`), `SLACK_WEBHOOK_URL`,
   `ALERT_MENTION` (e.g. `<!here>`). Run `setup()`, then `testSlack()`.
5. Redeploy the web app as a new version.

### B. Service on a pilot box (PULSEDEV-51 → -55)

1. **⚠️ Confirm the LMI shell is elevated** — see open questions. `nssm install`
   needs admin; `install_pulse_service.ps1` hard-fails fast if not elevated.
2. Ensure Pulse is installed (`C:\Pulse`) and has run once (bootstraps embedded
   Python). The `_CHECKIN_SECRET` in `main.py` must be the real secret (not the
   placeholder) or the beacon stays inert by design.
3. From the elevated LMI shell:
   ```powershell
   powershell -ExecutionPolicy Bypass -File C:\Pulse\runners\install_pulse_service.ps1 -DownloadNssm
   ```
   Installs the `Pulse` service with `PULSE_MONITOR=1` + `PORT=8765`, auto-start,
   restart-on-crash, logging to `C:\Pulse\pulse-service.log`.
4. The service **owns port 8765** — don't also run the interactive launcher on a
   pilot box (`run.bat` frees the port on start and would kill the service).

### Validate (PULSEDEV-55 acceptance)

- [ ] Service survives a **reboot** (auto-start) — check `pulse-service.log` for
      `Proactive monitor starting`.
- [ ] Heartbeat + full recompute fire and rows land in the Sheet (`reason` cycles
      `startup` → `periodic`).
- [ ] Induce a real FAIL (unplug a camera / stop the agent) → **Slack alert**
      within an incident cadence; clearing it → **resolved** note.
- [ ] No measurable impact on live recording/encoding during a game window.

## Open questions (resolve during the pilot)

1. **Is the LMI shell elevated?** Gates the whole service install (PULSEDEV-55).
   The installer fails fast with a clear message if not — confirm on the first
   box before committing the cohort.
2. **NVENC idle-vs-recording reading.** `Get-RecordingState.ps1` keys "recording"
   on encoder *utilization* > 0 (falling back to session count). Validate against
   a genuinely idle VPU vs one mid-game during soak; tune `-UtilizationThreshold`
   if an idle box holds a non-zero session. Fail-open = `recording:false` (we run
   the normal, still non-intrusive, recompute), so a misread degrades gracefully.
3. **Cadence tuning.** Defaults (5/20/1 min) are env-overridable per box —
   adjust from the soak.

## Tuning knobs (env, set on the service)

`PULSE_MONITOR=1` (enable) · `PORT` · `PULSE_MONITOR_HEARTBEAT_SECONDS` ·
`PULSE_MONITOR_FULL_SECONDS` · `PULSE_MONITOR_INCIDENT_SECONDS` ·
`PULSE_MONITOR_STARTUP_DELAY_SECONDS` · `PULSE_CHECKIN_URL` / `PULSE_CHECKIN_SECRET`.

## Graduation to OneUptime

The beacon payload is transport-agnostic. To graduate: point the same body at
OneUptime's Incoming Request Monitor (swap `notifySlack_` for an OneUptime POST,
or have the VPU post both). Routing/dedup logic is unchanged — see the
oneuptime-integration notes.
