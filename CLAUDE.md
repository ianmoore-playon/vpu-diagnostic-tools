# CLAUDE.md

## Project

Pulse — diagnostic tools for Pixellot VPU field support. Two variants:

- **Pulse.WPF** (`Pulse.WPF/`) — C# / WPF / .NET Framework 4.8 desktop app
- **Pulse.Web** (`Pulse.Web/`) — Python + vanilla JS web app (FastAPI + Uvicorn)

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

## Build

```bash
# WPF (requires .NET 8 SDK, targets net48)
dotnet build Pulse.WPF/Pulse.WPF/Pulse.WPF.csproj -c Release

# Web — no build step, just run
cd Pulse.Web && run.bat
```

## Branches & Releases

Code flows `dev` → `beta` → `main`. Each branch has CI builds; tags create releases on `playon/pulse` (the single source + distribution repo).

| App | Dev tag | Beta tag | Production tag |
|-----|---------|----------|----------------|
| Pulse.WPF | `dev-v*` | `beta-v*` | `wpf-pilot-v*` |
| Pulse.Web | `web-dev-v*` | `web-beta-v*` | `web-v*` |

Dev and beta tags create pre-releases. Production tags create full releases.

Launchers in `runners/` are per-channel: `run_pulse.bat` (production → latest `web-v*` release), `run_pulse_beta.bat` (beta → latest `web-beta-v*` pre-release), `run_pulse_dev.bat` (dev → latest commit on the `dev` branch; pass a branch name to test another). All install to `C:\Pulse` (one channel at a time) and auto-update every launch. (The old Pulse.WPF launchers + `install*.ps1` were removed when WPF was deprecated.)

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

#### Changelog (shown to testers on update)

`Pulse.Web/CHANGELOG.md` is the source for the "what's new" notes the in-app **Check for Update** displays. **When you ship a user-facing change, add a one-line bullet under `## [Unreleased]`** (Added / Changed / Fixed), written for a field tech, not a developer. At a beta/main promotion, rename `[Unreleased]` to the version — that section becomes the release notes the mirror release publishes. Dev builds surface the current `[Unreleased]` list automatically, so there's no per-push curation. The release workflow reads the top changelog section; don't hand-edit release bodies.

## CI Workflows

- `.github/workflows/wpf-pilot-build.yml` — Windows build, triggers on `dev`/`beta`/`main` pushes (when `Pulse.WPF/` changes) and WPF tags
- `.github/workflows/web-build.yml` — Zips `Pulse.Web/`, triggers on web tags

Both publish releases directly to `playon/pulse` using the workflow's built-in `GITHUB_TOKEN` — no separate PAT or mirror step required.

## Key Directories

- `runners/` — Install scripts and `.bat` launchers for all channels
- `Pulse.Web/scripts/` — PowerShell data-collection scripts (WMI/CIM)
- `Pulse.Web/app/static/` — Frontend SPA (vanilla JS, hash routing)
- `Pulse.WPF/Pulse.WPF/Views/` — XAML panels
- `Pulse.WPF/Pulse.WPF/Services/` — WMI, registry, network probes

## MCP Tools

Claude in Chrome is **not enabled** for this org. Do not attempt to use browser automation MCP tools (`mcp__Claude_in_Chrome__*`). Use `mcp__Claude_Preview__*` for UI previewing instead. Preferably ask the user if they are running local dev server first, then proceed with running local servier if they are not running it already.
