# Pulse.WPF - Pixellot VPU Diagnostic Tool

Pulse.WPF is the active WPF line of Pulse, a Windows diagnostic tool for
Pixellot VPU field support. It targets .NET Framework 4.8 and is intended to
run on Windows 10+ VPUs.

The v1 direction is a field-triage cockpit: open Pulse, let the startup
baseline run, review the Dashboard findings, then drill into the panel that
owns the issue. Every shipped diagnostic should answer:

1. What is wrong?
2. Where is it?
3. What should the tech do next?
4. What evidence can support attach to a ticket?

## Panels

- Dashboard - one-page baseline summary, gauges, top findings, and report
  shortcuts.
- System Overview - hardware, peripherals, OS, Pixellot software, network
  adapter, and software inventory.
- Network - uplink adapter, IP/DNS/DHCP/NTP state, required port probes, and
  domain checks.
- Camera Connectivity - live camera-NIC port map, link speed, ARP/device
  resolution, flap/error detection, and snapshots.
- Score Connect - local ScoreConnect III API probe, scoreboard configuration,
  serial ports, BOT/cloud context, and live WebSocket feed when available.
- Pixellot Services - Pixellot process/service health and guarded restart
  actions.
- Disk & System Health - volume free space, Pixellot path sizes, SMART status,
  and disk-related event-log errors.
- Event Viewer - recent VPU-relevant Windows events with filtered findings.
- Reports - saved per-panel reports, zipped support bundles, and the rolling
  app log.
- Settings / About - ScoreConnect URL, folder shortcuts, manual baseline, and
  app identity.

## Runtime Shape

`MainViewModel` is the composition root. It constructs the concrete services,
creates each panel viewmodel once, and switches panels by setting
`CurrentView`. Views are resolved through the implicit DataTemplates in
`App.xaml`.

`BaselineRunner` starts after the main window paints. It runs cheap panel
refreshes in parallel, runs the heavier Network diagnostic sequentially, waits
for the live Camera monitor to populate, then refreshes Dashboard last so the
home screen sees the newest reports and findings.

`PanelLogger`, `AppLogFile`, and `ReportWriter` provide the shared logging and
reporting path:

- Rolling log: `%LOCALAPPDATA%\Pulse.WPF\Logs\Pulse-YYYYMMDD.log`
- Reports: `%LOCALAPPDATA%\Pulse.WPF\Reports`
- Last baseline: `%LOCALAPPDATA%\Pulse.WPF\State\last-baseline.xml`
- Settings: `%LOCALAPPDATA%\Pulse.WPF\settings.json`

## Project Layout

```
Pulse.WPF/
├── Pulse.WPF.sln
├── README.md
├── STYLE_GUIDE.md
├── UX_REVIEW.md
└── Pulse.WPF/
    ├── App.xaml / App.xaml.cs
    ├── MainWindow.xaml / MainWindow.xaml.cs
    ├── Views/
    ├── ViewModels/
    ├── Services/
    ├── Helpers/
    ├── Models/
    ├── Controls/
    ├── Themes/
    └── Assets/
```

## Build

Build from Windows or a Windows CI runner:

```powershell
dotnet restore Pulse.WPF/Pulse.WPF/Pulse.WPF.csproj
dotnet build Pulse.WPF/Pulse.WPF/Pulse.WPF.csproj -c Release
```

The source can be edited on macOS, but the WPF UI and most diagnostics require
Windows to run. A real verification pass should happen on a Windows machine or
through the GitHub Actions workflow.

## Release Flow

The workflow in `.github/workflows/wpf-pilot-build.yml` builds on
`windows-latest`. Pushes to `dev` or `main` build and upload a runnable zip.
`wpf-pilot-v*` tags create a release and mirror the artifact to the public
`ianmoore-playon/pulse-releases` repo used by the field launcher.

For hands-on VPU validation, use `V1_LAB_CHECKLIST.md`.

## V1 Readiness Bar

- Startup baseline completes without freezing the UI.
- Startup-only network settling does not create a false all-failed network
  baseline; the Network panel defers and asks for a manual run when Windows is
  still bringing the uplink online.
- Dashboard reflects real panel findings and does not duplicate them across
  baseline re-runs.
- Network required and optional ports are classified correctly.
- ScoreConnect settings changes are reflected without misleading the user.
- No shipped button presents a fake action.
- Each shipped panel has a clear status pill, findings when appropriate,
  recommended actions, and report output.
- Reports can generate a single support bundle with baseline summary, panel
  reports, and app log evidence.
- The Windows build passes in CI and the public launcher installs/updates the
  release successfully.
