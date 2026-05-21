# CLAUDE.md

## Project

Pulse — diagnostic tools for Pixellot VPU field support. Two variants:

- **Pulse.WPF** (`Pulse.WPF/`) — C# / WPF / .NET Framework 4.8 desktop app
- **Pulse.Web** (`Pulse.Web/`) — Python + vanilla JS web app (FastAPI + Uvicorn)

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
