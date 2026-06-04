# Pulse — Pixellot VPU Diagnostic Tool

Diagnostic tools for Pixellot VPU field support. Covers camera-NIC and
cable health, network connectivity, Pixellot services, system overview
hardware/peripherals, disk health, the Windows event log, and a Reports panel
with support bundles — all live, with plain-language next-step guidance and
per-panel Recommended Actions.

There are two variants:

- **`Pulse.WPF/`** — C# / WPF .NET Framework 4.8 desktop app (the original)
- **`Pulse.Web/`** — Lightweight web-based version (Python + vanilla JS, no install required)

## Install on a VPU

The supported install path runs the installer from
[`playon/pulse`](https://github.com/playon/pulse)
with admin elevation so the build lands in `Program Files`.

**Option 1 — elevated launcher (recommended for field use)**

Download [`runners/run_pulse.bat`](https://raw.githubusercontent.com/playon/pulse/main/runners/run_pulse.bat)
to the VPU desktop and double-click. The launcher requests UAC
elevation, then pulls the latest tagged release and runs
`install.ps1` in an admin context so Pulse can install system-wide
under `Program Files`. Subsequent double-clicks auto-update to the
latest tag.

**Option 2 — elevated PowerShell one-liner**

Open an **Administrator** PowerShell and run:

```powershell
irm 'https://raw.githubusercontent.com/playon/pulse/main/install.ps1' | iex
```

Same installer the launcher uses — the only difference is you provide
the admin shell yourself instead of letting the bat trigger UAC.

Requires Windows 10+ and .NET Framework 4.8 (both pre-installed on every VPU).

---

## Pulse Web

A self-contained, browser-based diagnostic tool. No Node.js, npm, or .NET
required — just double-click and it bootstraps everything.

### Install on a VPU

Download [`runners/run_pulse_web.bat`](https://raw.githubusercontent.com/playon/pulse/main/runners/run_pulse_web.bat)
to the VPU desktop and double-click. The launcher pulls the latest
`web-v*` release from GitHub, extracts it to `%LOCALAPPDATA%\PulseWeb`,
and runs the app. Subsequent double-clicks auto-update to the latest
release.

On first launch, the embedded `run.bat`:
1. Downloads embedded Python 3.12.8 from python.org
2. Installs pip and dependencies (FastAPI, Uvicorn)
3. Starts the server at **http://localhost:8765**
4. Opens the browser automatically

Subsequent launches skip the Python setup and start in seconds.
Falls back to a cached version if the VPU is offline.

### How it works

```
Pulse.Web/
├── run.bat                 — Windows launcher (bootstraps Python)
├── app/
│   ├── main.py             — FastAPI server (REST + WebSocket)
│   ├── powershell.py       — async PowerShell subprocess runner
│   ├── requirements.txt    — fastapi, uvicorn
│   └── static/
│       ├── index.html      — SPA shell (Tailwind CSS via CDN)
│       ├── app.js          — client-side router, 12 page renderers
│       └── style.css       — dark theme styles
└── scripts/                — 16 PowerShell data-collection scripts
    ├── Get-SystemIdentity.ps1
    ├── Get-Hardware.ps1
    ├── Get-Performance.ps1
    ├── Get-NetworkConfig.ps1
    ├── Get-NicAdapters.ps1
    ├── Get-Services.ps1
    ├── Get-DiskHealth.ps1
    ├── Get-EventLogs.ps1
    ├── Get-ScoreConnectStatus.ps1
    ├── Get-PixellotConfig.ps1
    ├── Get-InstalledSoftware.ps1
    ├── Get-Temperature.ps1
    ├── Test-NetworkDomains.ps1
    ├── Test-NetworkPorts.ps1
    ├── Test-NtpDrift.ps1
    └── Restart-Service.ps1
```

The backend runs PowerShell scripts to collect WMI/CIM data and returns
JSON over REST. The frontend is a vanilla JS single-page app with hash
routing — no build step, no bundler.

### Pages

| Page | Description |
|------|-------------|
| Dashboard | Live CPU/Memory/Disk/Temp gauges, identity, findings |
| System Overview | OS, CPU, RAM, GPU, disk drives, installed software |
| Network | IP config, internet reachability, DNS, port tests, NTP |
| Cameras | Camera-facing NIC ports, Pixellot OUI detection, ARP |
| Services | Pixellot service status with restart controls |
| Disk Health | Logical/physical disks, events, Pixellot directory sizes |
| Event Viewer | Filterable Windows event log (hours, severity) |
| Reports | Full diagnostic JSON export |
| ScoreConnect | Local ScoreConnect API probe |
| Fault Isolator | Sequential 6-step guided troubleshooting wizard |
| Settings | ScoreConnect URL, poll interval |
| About | Version and technology info |

### Run on macOS (demo mode)

On non-Windows systems, Pulse Web runs in demo mode with synthetic data
(PowerShell scripts are stubbed out). Useful for UI development and testing.

```bash
brew install python3
pip3 install fastapi 'uvicorn[standard]'
cd Pulse.Web/app
python3 main.py
```

Then open **http://localhost:8765** in your browser.

### Requirements

- **VPU (production):** Windows 10+ (for PowerShell + WMI), internet on first run
- **macOS/Linux (dev):** Python 3.10+, pip

---

## Pulse WPF (Desktop)

## Develop

The project lives under `Pulse.WPF/`:

```
Pulse.WPF/
├── Pulse.WPF.sln
├── README.md         — architecture overview
├── STYLE_GUIDE.md    — design tokens, naming, vocabulary
├── UX_REVIEW.md      — running per-panel UX ledger
└── Pulse.WPF/        — the project itself
    ├── App.xaml      — composition root + DI
    ├── MainWindow.xaml
    ├── Views/        — one .xaml per panel
    ├── ViewModels/
    ├── Services/     — WMI, registry, network probes, etc.
    ├── Helpers/      — converters, status helpers, OUI lookup
    ├── Models/
    ├── Controls/     — reusable XAML (NicCardDiagram, JackVisual, ...)
    └── Themes/       — colours, styles, design tokens
```

Build (requires .NET 8 SDK; the SDK builds the net48 target):

```bash
dotnet build Pulse.WPF/Pulse.WPF/Pulse.WPF.csproj -c Release
```

Or rely on GitHub Actions — every push to `dev` runs the Windows build
and uploads the runnable zip as a workflow artifact. Every `wpf-pilot-v*`
tag push publishes a real release and mirrors it to `pulse-releases`.

See `Pulse.WPF/README.md`, `Pulse.WPF/STYLE_GUIDE.md`, and
`Pulse.WPF/UX_REVIEW.md` for the architecture, design tokens, and
panel-by-panel UX history.
