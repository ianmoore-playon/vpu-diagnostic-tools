# CLAUDE.md

## Project

Pulse — diagnostic tools for Pixellot VPU field support. Two variants:

- **Pulse.WPF** (`Pulse.WPF/`) — C# / WPF / .NET Framework 4.8 desktop app
- **Pulse.Web** (`Pulse.Web/`) — Python + vanilla JS web app (FastAPI + Uvicorn)

## Multi-Session Etiquette

Multiple Claude Code sessions often work this repo at once on the same checkout (`dev`). Uncommitted changes are visible to every session, so a careless commit can sweep up another session's in-progress work. Follow these:

1. **Stage explicitly — never broadly.** Use `git add <specific files you personally edited>`. Never `git add -A`, `git add .`, or `git commit -am` — they grab everything in the tree, including other sessions' WIP.
2. **Review the staged diff before every commit.** Run `git diff --cached --stat` first. If it lists files you didn't touch — or the line count is bigger than your change — stop; another session's work is mixed in. Unstage with `git restore --staged <file>`.
3. **Commit small and often.** Land your own work the moment a change is coherent. WIP left sitting in a shared file is what gets swept up. The less you leave floating, the safer everyone is.
4. **The big shared files are the hazard:** `Pulse.Web/app/static/app.js`, `Pulse.Web/app/main.py`, `Pulse.Web/app/static/style.css`. Several areas edit them. Edits rarely *conflict* (different functions), but `git add app.js` grabs everyone's uncommitted lines. If you must commit one while another session has WIP in it, coordinate first or expect to co-commit their lines — and name it honestly in the message.
5. **Pull before you push:** `git pull --rebase origin dev`.
6. **Never rewrite pushed `dev` history** — no `commit --amend`, `rebase`, or force-push on `dev`; other sessions are actively pulling it.

**Lanes:** Camera Connectivity · ScoreConnect · Network · System · Setup · Audio · Pixellot Cloud. Edit your area's render function and scripts; treat the others' as read-only.

The single most important habit is **#2 — check `git diff --cached --stat` before committing.**

## Build

```bash
# WPF (requires .NET 8 SDK, targets net48)
dotnet build Pulse.WPF/Pulse.WPF/Pulse.WPF.csproj -c Release

# Web — no build step, just run
cd Pulse.Web && run.bat
```

## Branches & Releases

Code flows `dev` → `beta` → `main`. Each branch has CI builds; tags create releases mirrored to `ianmoore-playon/pulse-releases`.

| App | Dev tag | Beta tag | Production tag |
|-----|---------|----------|----------------|
| Pulse.WPF | `dev-v*` | `beta-v*` | `wpf-pilot-v*` |
| Pulse.Web | `web-dev-v*` | `web-beta-v*` | `web-v*` |

Dev and beta tags create pre-releases. Production tags create full releases.

Launchers in `runners/` are per-channel (`run_pulse.bat`, `run_pulse_beta.bat`, `run_pulse_dev.bat`, and web equivalents). Each installs to its own `%LOCALAPPDATA%` directory so channels coexist on a VPU.

### Versioning

Both apps use semver (`MAJOR.MINOR.PATCH`) with a three-channel pipeline. Dev stays roughly two versions ahead of main, and beta stays one version ahead.

| Channel | Version format | Tag examples | Audience |
|---------|---------------|-------------|----------|
| Main | `X.Y.Z` | `wpf-pilot-v0.1.0` / `web-v0.1.0` | Production VPUs |
| Beta | `X.Y.Z` | `beta-v0.2.0` / `web-beta-v0.2.0` | Field validation |
| Dev | `X.Y.Z-dev` | `dev-v0.3.0-dev-abc1234` / `web-dev-v0.3.0-dev-abc1234` | Internal testing |

**Version example at a point in time:**
- Main: `0.1.0` (current stable)
- Beta: `0.2.0` (next release, being validated)
- Dev: `0.3.0-dev` (bleeding edge, auto-tagged with commit SHA)

**Version source of truth per app:**
- Pulse.Web: `Pulse.Web/VERSION` file
- Pulse.WPF: `<Version>` in `Pulse.WPF/Pulse.WPF/Pulse.WPF.csproj`

#### Promotion workflow

1. **Dev → Beta:** Merge `dev` into `beta`. Update the version source to a clean semver (e.g., `0.2.0`). Push the appropriate beta tag.
2. **Beta → Main:** Merge `beta` into `main`. Push the production tag (same version that was validated in beta).
3. **Bump dev:** After promoting, update the version source on `dev` to the next version with `-dev` suffix (e.g., `0.3.0-dev`). Subsequent dev pushes auto-tag with commit SHA.

#### Rules

- Version bumps are manual — decide whether to increment minor or major when starting a new dev cycle.
- Dev auto-tags on push (Web via `web-auto-tag.yml`, WPF via branch-triggered CI). Beta and main tags are pushed manually.
- Only promote to main what was validated in beta. The beta tag version and main tag version should match for a given release.

## CI Workflows

- `.github/workflows/wpf-pilot-build.yml` — Windows build, triggers on `dev`/`beta`/`main` pushes (when `Pulse.WPF/` changes) and WPF tags
- `.github/workflows/web-build.yml` — Zips `Pulse.Web/`, triggers on web tags

Both mirror releases to the public `ianmoore-playon/pulse-releases` repo via `PUBLIC_RELEASE_PAT` secret.

## Key Directories

- `runners/` — Install scripts and `.bat` launchers for all channels
- `Pulse.Web/scripts/` — PowerShell data-collection scripts (WMI/CIM)
- `Pulse.Web/app/static/` — Frontend SPA (vanilla JS, hash routing)
- `Pulse.WPF/Pulse.WPF/Views/` — XAML panels
- `Pulse.WPF/Pulse.WPF/Services/` — WMI, registry, network probes

## MCP Tools

Claude in Chrome is **not enabled** for this org. Do not attempt to use browser automation MCP tools (`mcp__Claude_in_Chrome__*`). Use `mcp__Claude_Preview__*` for UI previewing instead. Preferably ask the user if they are running local dev server first, then proceed with running local servier if they are not running it already.
