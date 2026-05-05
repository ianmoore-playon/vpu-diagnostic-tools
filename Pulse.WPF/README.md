# Pulse.WPF — Camera Connectivity Pilot

A **WPF (Windows Presentation Foundation) pilot** of the Pulse VPU diagnostic
tool, focused on the Camera Connectivity panel only. This is a side-by-side
proof-of-concept against the existing `Pulse.ps1` (WinForms) implementation —
they coexist in this repo and can run independently.

## Goal

Validate that:

1. WPF gives a meaningful visual upgrade vs the existing WinForms UI
2. The responsive layout (`WrapPanel`, `Grid`-with-star-columns) solves the
   "right side cut off on 1366×768 monitors" problem permanently — without
   horizontal scrollbars
3. We can keep all the existing diagnostic intelligence by talking to the
   PowerShell modules (or, where it's cleaner, calling the same Win32 APIs
   directly from C#)
4. Material Design styling is enough to drop modern, themed UI on without
   bespoke painting code

If the pilot lands well we plan a phased migration of the remaining panels
(Home, Network, Hardware, Services, Disk, Events, System Info, Reports,
Settings, Help). The PowerShell version of Pulse keeps shipping in parallel
until WPF reaches feature parity.

## What's in this pilot

- **Sidebar nav** — visual placeholder for the other panels (System Overview,
  Network, Camera Connectivity, Hardware, etc.). Only Camera Connectivity is
  implemented.
- **Camera Connectivity panel** — full implementation:
  - Section header with live "Overall Status" pill
  - Test Scope dropdown (per-port targeting)
  - 4 port detail cards in a responsive `WrapPanel`
  - Status cards row (SmartSpeed, Ping, ARP, CHU, PoE)
  - Live Log + Next Steps Guidance two-column area
  - Bottom action bar (Export, Copy, Save Log, Run Test)
- **Live port monitoring** — polls `Get-NetAdapter` + ARP every 3 seconds
  while the panel is visible. Updates port cards without re-running the
  diagnostic.
- **Pixellot config parser** — reads `C:\Pixellot\Data\configuration\cameras.cfg`
  and `pip.cfg` to label each port by role (Main Camera 1/2, OCR / Scoreboard,
  Additional Angle).
- **Material Design theming** — dark theme by default. Card surfaces, ripple
  feedback on buttons, smooth status-pill colour transitions.

## What's deferred

- **Run Test** — the actual diagnostic engine (port-speed remediation, RTSP
  testing, SmartSpeed event-log scan, PoE telemetry) is not ported in this
  pilot. The button shows a "not implemented" toast. Live monitoring still
  works in real time.
- **Other panels** — every other tab on the sidebar is a stub.
- **Self-update / feedback flow** — also stubs.

## Building

### Prerequisites

- Windows 10+ (the VPUs)
- .NET Framework 4.8 (already on the VPUs)
- .NET SDK (any 6.0+ — we use the SDK only for the build CLI; the output
  binary still targets .NET Framework 4.8)
- Or open in Visual Studio 2019/2022 — either Community or Pro

### Command line

```powershell
cd Pulse.WPF\Pulse.WPF
dotnet restore
dotnet build -c Release
```

The output is `bin\Release\net48\Pulse.WPF.exe` — a single-folder app you
can drop on a VPU and run.

### From Visual Studio

Open `Pulse.WPF\Pulse.WPF.sln` and press F5.

## Project layout

```
Pulse.WPF/
├─ README.md                    (this file)
├─ Pulse.WPF.sln                (solution file)
└─ Pulse.WPF/
   ├─ Pulse.WPF.csproj          (.NET Framework 4.8 + WPF + MaterialDesign)
   ├─ App.xaml / App.xaml.cs    (app entry point, theme resources)
   ├─ MainWindow.xaml / .cs     (window with sidebar + content area)
   ├─ Views/
   │  └─ CameraConnectivityView.xaml / .cs   (the panel layout)
   ├─ ViewModels/
   │  ├─ MainViewModel.cs
   │  ├─ CameraConnectivityViewModel.cs
   │  ├─ PortViewModel.cs
   │  └─ LogEntry.cs
   ├─ Models/
   │  └─ PixellotCameraRole.cs
   ├─ Services/
   │  ├─ INetworkAdapterService.cs / NetworkAdapterService.cs
   │  └─ IPixellotConfigService.cs / PixellotConfigService.cs
   ├─ Helpers/
   │  ├─ ObservableObject.cs    (INotifyPropertyChanged base)
   │  └─ AsyncCommand.cs        (ICommand with async support)
   └─ Themes/
      ├─ Colors.xaml            (palette — matches existing dark theme)
      └─ Styles.xaml            (Card style, Button overrides)
```

## Compared to the WinForms version

| | WinForms (current) | WPF (this pilot) |
|---|---|---|
| Layout definition | Code (`Location` + `Size`) | XAML markup (`Grid`, `WrapPanel`) |
| Camera Connectivity panel size | ~2400 lines `.psm1` | ~150 lines XAML + ~200 lines C# |
| Responsive on small screens | Sidebar gets clipped | Wraps automatically |
| Animation | Manual timers | Built-in `Storyboard` + bindings |
| Hover effects | Manual paint events | One-line `<VisualStateManager>` |
| Theming | Hard-coded colors | `DynamicResource` + Material Design |
| Build artifact | `Pulse.ps1` (single file) | `Pulse.WPF.exe` + 4 small DLLs |
| Install footprint | Pure script | ~5 MB (vs 0 MB for the script) |
| Runtime dep | PowerShell 5.1 | .NET Framework 4.8 (both pre-installed) |

## How this fits with the existing Pulse

This is purely additive — `Pulse.ps1`, `Pulse.bat`, all the `.psm1` modules,
and the GitHub release pipeline are untouched. You can keep shipping
WinForms releases while WPF is being built out. When WPF reaches parity,
we'd flip the launcher and the WinForms project becomes a deprecation
candidate.
