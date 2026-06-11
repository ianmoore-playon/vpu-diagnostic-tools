# Pulse — Pixellot VPU Diagnostic Tool

Diagnostic tools for Pixellot VPU field support. Covers camera-NIC and
cable health, network connectivity, Pixellot services, system overview
hardware/peripherals, disk health, the Windows event log, and a Reports panel
with support bundles — all live, with plain-language next-step guidance and
per-panel Recommended Actions.

**Pulse.Web** (`Pulse.Web/`) is the active product — a self-contained,
browser-based diagnostic tool (Python + vanilla JS). No Node.js, npm, or
.NET required; double-click a launcher and it bootstraps everything.

> `Pulse.WPF/` (the original C#/WPF desktop app) is **deprecated** in favor of
> Pulse.Web. Its source remains for reference but is no longer built or shipped.

## Install on a VPU

One launcher per channel — drop it on the VPU desktop and double-click. Each
self-elevates (UAC), installs to `C:\Pulse`, adds a Start Menu entry, and
auto-updates every launch.

| Launcher | Channel | Pulls |
|---|---|---|
| [`run_pulse.bat`](https://raw.githubusercontent.com/playon/pulse/main/runners/run_pulse.bat) | **Production** | latest `web-v*` release |
| [`run_pulse_beta.bat`](https://raw.githubusercontent.com/playon/pulse/main/runners/run_pulse_beta.bat) | **Beta** | latest `web-beta-v*` pre-release |
| [`run_pulse_dev.bat`](https://raw.githubusercontent.com/playon/pulse/main/runners/run_pulse_dev.bat) | **Dev** | latest commit on the `dev` branch |

All three install to `C:\Pulse` (one channel at a time), so run the launcher
for the channel you want. Field VPUs use **`run_pulse.bat`**; the beta testers
use **`run_pulse_beta.bat`**.

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

## Pulse WPF (Desktop) — deprecated

The original C#/WPF desktop app lives under `Pulse.WPF/`. It is **no longer
built, shipped, or supported** — Pulse.Web replaced it. The source is kept for
reference and history; its CI and channel launchers have been removed. Don't
build on it without first deciding to revive the line.
