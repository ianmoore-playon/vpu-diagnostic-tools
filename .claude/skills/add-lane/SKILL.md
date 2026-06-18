---
name: add-lane
description: Add or extend a Pulse.Web diagnostic lane end-to-end — collector script, demo payload, API endpoint, and frontend render + nav wiring. Use when adding a new tab/page to Pulse, building a new diagnostic, surfacing a collector in the UI, or asked to "add a lane", "add a tab", "new page", "wire up a diagnostic", or "surface X in Pulse".
---

# Add a Pulse diagnostic lane

End-to-end recipe for adding or extending a lane (tab) in Pulse.Web:
**collector → demo payload → endpoint → frontend render + nav → test.**
Follow the order; each step has a reuse check so you don't duplicate machinery.

Before starting: isolate a worktree and claim the lane (see CLAUDE.md → Multi-Session Etiquette).

## 0. Probe-first — do not skip

`ls Pulse.Web/scripts/` and grep `@app.` in `app/main.py`. If a collector or endpoint
already produces what you need, reuse it — most camera/system/network data already
exists. For camera identity/config, reuse `_probe_camera_ip` / `_CGI_PROBE_CACHE`
(`main.py` :396 / :225); do **not** write a new CGI probe.

## 1. Collector (`Pulse.Web/scripts/`)

- Pick the class and copy an existing script of that class for output shape/conventions:
  **LOCAL** (WMI/CIM/registry/fs) · **NETWORK** (live ping/DNS/HTTP/port/ARP) ·
  **ACTION** (mutates state).
- Emit a single JSON object on stdout.
- **NETWORK collectors: scope to the active-default-route NIC** (IPv4 gateway / lowest
  route metric) — never first-across-all-interfaces (field-truth guardrail; this was the
  `Test-NetworkPorts` DNS false-positive root cause).
- It's invoked via `run_ps(script_name, ...)` (`powershell.py` :167), which already caches
  results 25s and dedupes in-flight calls — don't add your own caching.

## 2. Demo payload (`Pulse.Web/app/demo_data.py`) — REQUIRED, not optional

On non-Windows, `DEMO_MODE` (`powershell.py` :26) returns `demo_data.py` instead of
running PowerShell. Add a synthetic payload keyed to your script name, **matching the real
output shape**, or the lane renders **blank on every Mac dev/preview**. `demo_data.py` is a
multi-session hazard file — commit by path.

## 3. Endpoint (`app/main.py`)

- Add `GET /api/<lane>` on the one-endpoint-per-lane pattern; call your collector via
  `run_ps`. Actions get `POST /api/<lane>/<verb>`.
- If the lane drives a dashboard finding, thread its data into `_compute_findings(...)`
  (`main.py` :1181) via the matching kwarg. **Guardrail:** never emit a `critical` that a
  passing check on the same panel contradicts.

## 4. Frontend (`app/static/app.js`) — read the live maps, don't hardcode ids

The nav was restructured by PR #86 (page-ids retired via `RETIRED_PAGE_ALIASES`,
`_findingPageFor` / `_subsystemHealth` remapped). **Read the current maps before editing —
never assume an id from memory.** Anchors (@ `e695eb4`): `NAV_SECTIONS` :62,
`pageRenderers` :796, `PAGE_API` :114, `RETIRED_PAGE_ALIASES` :104, `_findingPageFor` :1111,
`_subsystemHealth` :1048.

- Register the render fn in `pageRenderers` (:796).
- Add the page to `NAV_SECTIONS` (:62) under the right group (TRIAGE / TROUBLESHOOTING /
  PIXELLOT CONFIGURATION / SYSTEM INFORMATION / DATA LOGS / PULSE).
- **Endpoint wiring — `PAGE_API` is NOT 1:1 with `pageRenderers`.** Either give the lane its
  own `/api/<lane>` and add a `PAGE_API` (:114) entry, **or** (for a tab split off an existing
  consolidated payload) skip `PAGE_API` and reuse `cached("system")` /
  `cached("pixellot-config")` directly, the way the post-#86 split tabs do. Pick the pattern
  that matches your data source.
- Don't reuse a retired id (`system`, `pixellot-config`) for a new page — they still resolve
  via `RETIRED_PAGE_ALIASES`. If a finding should deep-link here, update `_findingPageFor`.
- Use the house formatters — `formatTime` (primary), `_pcFmtDate`, `formatBytes`, `esc` —
  don't roll your own. (Verify their line numbers; they drift.)
- Reuse component/badge/table classes from a sibling lane's render fn. **Do not hand-edit
  `tailwind-min.css`** (prebuilt subset); if you introduce a new utility class, regenerate
  the subset. `style.css` is the hand-edited one (and a hazard file).

## 5. Test / verify

- Run locally in demo mode: `python3 app/main.py`.
- **A static edit only appears after a server restart**, not a reload (serve-time `?v=`
  cache-bust). Restart, then hard-check the lane.
- Confirm: the lane renders with demo data; any finding appears/clears correctly; no
  false-positive `critical` fires against a passing sibling check.

## Commit (multi-session)

Commit only your files by path; `git show --stat HEAD` must list only yours. Hazard files
(`app.js`, `main.py`, `demo_data.py`, `style.css`) — one session at a time. Add a one-line
`CHANGELOG.md` `[Unreleased]` bullet written for a field tech.
