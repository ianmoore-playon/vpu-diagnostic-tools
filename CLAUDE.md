# CLAUDE.md

## Project

Pulse — diagnostic tools for Pixellot VPU field support.

- **Pulse.Web** (`Pulse.Web/`) — Python + vanilla-JS web app (FastAPI + Uvicorn). **This is the product** — the only thing built, shipped, and supported.
- **Pulse.WPF** (`Pulse.WPF/`) — the **deprecated** gen-2 C#/WPF desktop app. Not built or shipped; source kept for reference/provenance only. Ignore it unless explicitly reviving the line. (WPF = Windows Presentation Foundation, a Windows desktop-UI framework — unrelated to Pixellot cameras or the stream pipeline.)

## Key Directories

- `runners/` — `.bat` launchers for all channels.
- `Pulse.Web/app/` — FastAPI backend (`main.py`, `powershell.py`) + SPA frontend (`static/`).
- `Pulse.Web/scripts/` — PowerShell data-collection + action scripts (WMI/CIM), ~45 `.ps1`.
- `Pulse.WPF/` — deprecated gen-2 desktop app, reference only (not built/shipped).

## Architecture Map (reuse before you reimplement)

Pointer map — `name · purpose · file:line`. Read the line for ground truth; don't trust this for exact return shapes. Keep it lean; every line loads every session.

`Pulse.Web/` is the product: FastAPI backend (`app/main.py`) + vanilla-JS SPA (`app/static/`); PowerShell collectors in `Pulse.Web/scripts/` invoked through `app/powershell.py`. **Probe-first**: confirm an existing helper/collector already does the work before writing a new one.

### Backend helpers — do not reimplement (`main.py`)

- `_cgi_probe_sync(ip, timeout=2.0) -> Optional[dict]` — :310. Camera CGI probe.
- `_probe_camera_ip(ip, is_ocr_ip)` *(async)* — :396. Async wrapper over the CGI probe.
- `_CGI_PROBE_CACHE` — :225. `ip → probe`, ~10s TTL; stops re-hammering cameras. New camera-touching endpoints share this cache (nearly free).
- `_check_pixellot_compatibility(identity, gpu_info) -> dict` — :749. GPU/OS vs Pixellot-version cap → compat banner.
- `_compute_findings(...)` — :1181. Dashboard findings engine; emits `critical`/`warning`. Optional kwargs are the data sources a finding can draw on: `(identity, performance, services, nics, hardware, installed_sw, network_config, install_state, port_tests, gpu_info, wifi, pixellot_config, expectations)`.

### `powershell.py`

- `run_ps(script_name, args=None, timeout=30, use_cache=True, cache_ttl=None) -> dict` — :167. Async PS runner; **25s result cache + in-flight dedup** (don't hammer cameras/net during preload).
- `DEMO_MODE = sys.platform != "win32"` — :26. **Non-Windows returns `demo_data.py` payloads and never runs `powershell.exe`.** All Mac dev/preview is synthetic.

### Routes (`main.py`)

Pattern: one `GET /api/<lane>` feeds one lane render fn; actions are `POST /api/<lane>/<verb>`; live stream is `WEBSOCKET /ws`. ~40 routes total — grep `@app.` in `main.py` for the current list rather than relying on memory.

### Collectors (`Pulse.Web/scripts/`, ~45 `.ps1`)

Classify by **how it gets data** — this is the convention for a new one:

- **LOCAL** — WMI/CIM/registry/filesystem (e.g. `Get-PixellotConfig`, `Get-Services`, `Get-SystemIdentity`, `Get-GpuInfo`).
- **NETWORK** — live probes: ping/DNS/HTTP/port/ARP (e.g. `Test-NetworkPorts`, `Test-DnsResolution`, `Test-NetworkDomains`, `Get-NetworkHealth`, `Test-CameraVideo`).
- **ACTION** — mutates state (e.g. `Restart-PixellotAgent`, `Restart-Service`, `Install-*`, `Invoke-RepairTool`).

Before writing a collector, `ls Pulse.Web/scripts/` — most of what you need already exists.

### Frontend (`app/static/app.js`, vanilla JS) — post-PR-#86 (@ `e695eb4`)

- **Read these maps live before wiring; don't hardcode ids:** `NAV_SECTIONS` :62 (nav groups/order), `pageRenderers` :796 (id → render fn, ~22 entries), `PAGE_API` :114 (page-id → `/api/<same>`), `RETIRED_PAGE_ALIASES` :104 (resolved at :131 via `id = RETIRED_PAGE_ALIASES[id] || id`), `_subsystemHealth` :1048, `_findingPageFor` :1111.
- **6 nav groups** (`:62`): TRIAGE · TROUBLESHOOTING · PIXELLOT CONFIGURATION · SYSTEM INFORMATION · DATA LOGS · PULSE. See :62 for tab membership.
- **Retired ids:** #86 split the old consolidated tabs — `system → hardware`, `pixellot-config → pixellot-software`. Old ids still resolve via `RETIRED_PAGE_ALIASES`; don't reuse them for anything new.
- **⚠ `PAGE_API` is NOT 1:1 with `pageRenderers`.** It still keys only the *old* ids (`system`, `pixellot-config`, `audio`). The split/new tabs (`hardware`, `applications`, `environment`, `pixellot-software`, `camera-hardware`, `calibrations`, …) have **no `PAGE_API` entry** — they reuse `cached("system")` / `cached("pixellot-config")` payloads directly. A new lane either gets its own `/api/<lane>` + `PAGE_API` entry, or reuses a cached consolidated payload.
- **⚠ `audio` is hidden but live:** commented out of `NAV_SECTIONS`, yet still in `pageRenderers` + `PAGE_API` + `/api/audio`. Reachable by hash route, not shown in nav.
- **Use the house formatters, don't roll your own:** `formatTime` (primary, ISO→locale), `_pcFmtDate` (date + relative age), `formatBytes`, `esc` (HTML-escape). *(Line numbers last confirmed pre-#86 and may have drifted; the names are stable — verify the line.)*
- **`tailwind-min.css` (~12KB) is PREBUILT** — a vendored Tailwind-utility subset, not live Tailwind. New utility classes won't exist at runtime; regenerate the subset if you add any. **`style.css` (~128KB) is the hand-edited one** (theme vars, layout, components) — and a multi-session hazard file.

## Field-truth guardrails (diagnostics must not cry wolf)

A diagnostic that false-positives trains techs to ignore it — the most expensive bug class here.

- **Scope network probes to the active-default-route interface** (the NIC with an IPv4 gateway / lowest route metric) — never first-across-all-interfaces, never a name/index like "Ethernet 16". A stale resolver on a dead/secondary/VPN adapter must not win. (Root cause of the `Test-NetworkPorts` DNS false positive.)
- **A critical that contradicts a passing check on the same panel suppresses itself** — e.g. `_compute_findings` must not emit "can't resolve any hostname" while Domain Reachability is all-green.

## Gotchas (fresh-session traps)

1. **Demo mode:** on non-Windows, `DEMO_MODE` serves `demo_data.py`, not real PowerShell. A new tab needs a matching demo payload or it renders blank on Mac.
2. **Cache-bust is on serve, not reload:** `serve_index` appends `?v=<version>` to CSS/JS links; the browser caches the versioned URL, so a local static edit only appears after a **server restart** (the token changes on restart/version bump), not a plain reload.
3. **Preview needs repo-root cwd:** `preview_start` requires the server cwd *inside* the project root. A worktree outside the root can't be previewed — spin a throwaway worktree under `.claude/worktrees/<name>` at your commit and point the launch config there.
4. **Repo must stay PUBLIC:** launchers + in-app auto-update read anonymously (raw URLs + release assets). `playon/pulse` keeps reverting to internal (suspected enterprise policy) — if a launcher 404s, check repo visibility first.

## Build

```bash
# Pulse.Web — no build step. On a VPU, just run the launcher:
cd Pulse.Web && run.bat
# On macOS/Linux it auto-runs in demo mode: python3 app/main.py  (see DEMO_MODE)
```

## Multi-Session Etiquette

Several Claude sessions often share **one** checkout of this repo — the same `.git`, working tree, staging index, and HEAD on `dev`. Every session's changes are interleaved with yours at all times. Left unmanaged this causes: staged files swept into another session's commit, a commit message landing on unrelated files, uncommitted edits wiped by another session's `checkout`/`restore`, and the shared `dev` HEAD detached or rebased mid-edit.

### Best fix — one worktree per session

Before working, isolate yourself:

```bash
git worktree add ../pulse-<task> -b <task> origin/dev
```

Work there, commit, `git push origin <task>`, open a PR. Separate tree + index + HEAD = zero collisions. Prefer this for anything beyond a quick one-file edit.

### If you share the checkout

1. **Never stage broadly.** No `git add -A`, `git add .`, or `git commit -am` — they grab every session's WIP.
2. **Commit only your files, by path, in one command:** `git commit <path1> <path2> -m "msg"`. A pathspec commit ignores the shared index, so a parallel `git commit` can't race in between (it *will* if you `git add` then commit as separate steps). Caveat: if another session edited the *same* file, you still co-commit their lines — so claim your lane.
3. **One file = one session at a time.** Hazard files everyone reaches for: `Pulse.Web/app/static/app.js`, `Pulse.Web/app/main.py`, `Pulse.Web/app/demo_data.py`, `Pulse.Web/app/static/style.css`. Don't edit one another session is in.
4. **Commit small and often.** Uncommitted work gets clobbered by another session's checkout/restore; committed work is safe.
5. **Verify before *and* after committing:** `git show --stat HEAD` (or `git diff --cached --stat`) must list only *your* files. If others' appear, you swept them.

### Never run tree-wide or history commands on the shared checkout

`git checkout -- .` · `git restore .` · `git reset --hard` · `git stash` (without a pathspec) · `git rebase` · `git pull --rebase` · `git checkout <branch>`. They discard or rewrite other sessions' work and move HEAD under everyone. (`git pull --rebase` also replays other sessions' unpushed commits and drops you into *their* conflicts — which is why it's no longer the recommended pre-push step here.) And never rewrite pushed `dev` history — no `commit --amend`, `rebase`, or force-push on `dev`.

### Pushing through someone else's conflict

If a push is rejected over a conflict in another session's commit, **do not resolve their conflict.** Cherry-pick *your* commit onto `origin/dev` in a throwaway worktree and push that:

```bash
git worktree add --detach /tmp/wt origin/dev
git -C /tmp/wt cherry-pick <your-sha>
git -C /tmp/wt push origin HEAD:dev && git worktree remove --force /tmp/wt
```

**Lanes:** Camera Connectivity · ScoreConnect · Network · System · Setup · Audio · Pixellot Cloud. Edit your area's render function and scripts; treat the others' as read-only.

## Session Hygiene

Durable context lives in **files**, not in the conversation. A chat thread is disposable; `CLAUDE.md`, `Pulse.Web/CHANGELOG.md`, and `.claude/HANDOFF.md` are not. Do **not** keep a session alive to "preserve context" — that is what degrades it. Every old file read, resolved bug, and exploratory tangent stays resident, slowing every turn and spreading attention thin across stale tokens. Resuming a long-running session is the anti-pattern here, not the safe choice.

**One task = one session.** Not "the Network lane session" that lives for weeks — "fix the DNS false positive," done, session ends. Refactor, bug hunt, or feature: each gets a session with a clear start and end.

### At a task boundary (do this proactively)

When the current task is finished, or the user switches to unrelated work:

1. Write a 3–5 line handoff to `.claude/HANDOFF.md`: what changed, what's left, files that matter, what was ruled out. **Overwrite it** — it's a baton, not a log.
2. Promote anything durable the *next* task will need (a newly-confirmed lane pattern, a gotcha) into this file or the changelog so it stops being rediscovered.
3. Tell the user the work is at a clean boundary and recommend a fresh session (`/clear`, then a new `claude`). Don't silently roll into unrelated work in the same thread.

### Mid-task

- **Edits stay on the main thread** (it holds the plan, commits, and verifies). Delegate to a subagent only for **read-only** work — multi-file reads, greps, log dumps — so the noise stays out of the main context. Exception: a batch of independent edits across disjoint files, run with `isolation: worktree`.
- If context feels heavy, or a compaction just fired, re-read this file's cardinal rules and `.claude/HANDOFF.md` before continuing. Don't trust an auto-summary for load-bearing facts (interface scoping, the probe cache, prebuilt CSS).
- Watch the saturation signals: asking for something already provided, contradicting an earlier decision, losing the file map. Those mean start fresh, not push harder.

### Safety net (for when the user forgets)

`.claude/settings.json` hooks back this up: `SessionStart` re-injects the cardinal rules + the latest `HANDOFF.md` on every start / resume / clear / compact, and `PreCompact` snapshots the transcript before a lossy auto-compaction. These lower the cost of forgetting — they don't replace the task-boundary ritual.

## Releases

Versioning, the `dev → beta → main` promotion workflow, tagging, changelog, and CI all live in the **`promote-pulse` skill** (`.claude/skills/promote-pulse/`). It loads on demand when you promote or cut a release, or invoke it with `/promote-pulse`. Version source of truth: `Pulse.Web/VERSION`.

## MCP Tools

Claude in Chrome is **not enabled** for this org. Do not attempt to use browser automation MCP tools (`mcp__Claude_in_Chrome__*`). Use `mcp__Claude_Preview__*` for UI previewing instead. Preferably ask the user whether they're running a local dev server first, then start one only if they aren't already.
