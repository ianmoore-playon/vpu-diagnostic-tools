# pixellot-vpu-tools

PowerShell diagnostic tools for Pixellot VPU field support.

---

## TestCameraConnectivity.ps1

A GUI diagnostic tool for troubleshooting camera connection issues on Pixellot VPUs. It runs a full diagnostic, displays live results in an interactive interface, and provides plain-language next-step guidance for both technical and non-technical users.

### How to run

Open any PowerShell window on the VPU — no need to right-click "Run as Administrator", the script handles elevation automatically.

```powershell
irm 'https://raw.githubusercontent.com/ianmoore-playon/pixellot-vpu-tools/refs/heads/main/TestCameraConnectivity.ps1' | iex
```

A UAC prompt will appear. Click **Yes**. A GUI window opens and the diagnostic begins when you click **Run Full Diagnostic**.

Results are also saved automatically to a `.txt` file in `CameraLink_Results\` next to the script (or on the Desktop when run via the one-liner).

### What it checks

| Check | Detail |
|---|---|
| NIC detection | Finds all Intel 82574L and I210 camera NIC ports |
| Link speed | Reports current speed on each port; samples for 12 seconds to catch intermittent (blinking) links |
| Remediation | For degraded 100 Mbps ports with SmartSpeed history, forces 1 Gbps and re-checks after 30 seconds |
| Physical layer evidence | Scans Intel SmartSpeed event log (last 48 hours) for ID 40 downgrade events — irrefutable Layer 1 fault evidence |
| OCR detection | Ports with no SmartSpeed ID 40 history are identified as 100 Mbps-only devices (OCR scoreboard cameras) — 100 Mbps is expected and no action is taken |
| ARP | Lists connected device MACs on the camera link-local subnet |
| Camera ping + RTSP | Tests each camera IP (169.254.16.50–.52) for ping response and RTSP port 554 reachability |
| App log analysis | Parses the most recent `CamerasTester_*.log` for connection failures, cross-referenced against NIC port health |
| VPU model detection | Reads `agent_*.log` (written every 5 minutes by the Pixellot agent service) to identify the VPU model and unit ID |

### How it distinguishes cable faults from OCR cameras

Intel SmartSpeed Event ID 40 fires only when the physical medium cannot sustain gigabit — it never fires when the connected device simply doesn't advertise gigabit capability. This means:

- **ID 40 history present** → the NIC tried and failed to hold a gigabit link → physical layer fault (cable, termination, or RJ45 pins)
- **No ID 40 history** → the link never attempted gigabit → 100 Mbps-only device (OCR camera) → no action needed

### GUI overview

The interface is a three-panel window:

- **Left sidebar** — Navigation (Overview, Guide, History), NIC selector with connected status indicator, quick system info, VPU model
- **Center panel** — Run/Retest buttons, per-port speed cards (P1–P4, one per Intel NIC), three diagnostic cards (Ping CHU, ARP Entry, CHU Detection), Last Run Summary card, color-coded live log, and Export / Copy / Save action buttons
- **Right panel** — Status badge (Ready / Running / All Clear / Issues Found) and plain-language Next Steps / Guidance

The diagnostic engine runs in a background runspace so the GUI never freezes during the 30-second re-negotiation wait or 12-second blink-sample window.

### Requirements

- Windows PowerShell 5.1 (standard on all VPUs)
- Windows 10 or later (uses WinForms and Segoe MDL2 Assets icon font)
- Internet access to download the script (or run from a local copy)
- Admin rights — prompted automatically via UAC

### Output files

Each run saves a timestamped `.txt` file to `CameraLink_Results\` in the script directory (or Desktop when run via the one-liner). Use **Export Report** in the GUI to open the file, **Copy Results** to copy the log to clipboard, or **Save Log** to save to a custom location.

### Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.
