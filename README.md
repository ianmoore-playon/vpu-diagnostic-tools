# Pulse — Pixellot VPU Diagnostic Tool

A WPF diagnostic tool for Pixellot VPU field support. Covers camera-NIC and
cable health, network connectivity, Pixellot services, hardware, disk &
system health, the Windows event log, and a Reports panel — all live, with
plain-language next-step guidance and a per-panel Recommended Actions card.

The active development line is **`Pulse.WPF/`** — a C# / WPF .NET Framework
4.8 project. There is no longer a separate PowerShell / WinForms tool;
the original `Pulse.ps1` + `Modules/*.psm1` tool was retired and removed in
v0.5.3. Earlier history is preserved in git (`v1.0.0` → `v1.0.52` tags).

## Install on a VPU

The supported install path is the public release feed at
[`ianmoore-playon/pulse-releases`](https://github.com/ianmoore-playon/pulse-releases).
Two equivalent options:

**Option 1 — drag-and-drop launcher (recommended for field use)**

Download [`Pulse.WPF.bat`](https://raw.githubusercontent.com/ianmoore-playon/pulse-releases/main/Pulse.WPF.bat)
to the VPU desktop and double-click. The launcher pulls the latest tagged
release, extracts to `%LOCALAPPDATA%\Pulse.WPF`, and runs `Pulse.WPF.exe`.
Subsequent double-clicks auto-update to the latest tag.

**Option 2 — PowerShell one-liner**

```powershell
irm 'https://raw.githubusercontent.com/ianmoore-playon/pulse-releases/main/install.ps1' | iex
```

Requires Windows 10+ and .NET Framework 4.8 (both pre-installed on every VPU).

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
