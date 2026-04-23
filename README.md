# playon-pixellot-scripts

PowerShell diagnostic scripts for Pixellot VPU field support.

---

## TestCameraConnectivity.ps1

Diagnoses camera connection link speed issues on Pixellot VPUs. Determines whether a camera running at 100 Mbps is caused by a **physical layer fault** (bad cable, failed termination) or is simply a **100 Mbps-only device** (OCR scoreboard camera) that is working as expected.

### How to run

Open any PowerShell window on the VPU — no need to right-click "Run as Administrator", the script handles that automatically.

```powershell
irm 'https://raw.githubusercontent.com/ianmoore-playon/playon-pixellot-scripts/refs/heads/main/TestCameraConnectivity.ps1' | iex
```

A UAC prompt will appear. Click **Yes**. The script runs and saves results to the Desktop as `CameraLink_Results_YYYYMMDD_HHMMSS.txt`.

### What it checks

| Check | Detail |
|---|---|
| NIC detection | Finds all Intel 82574L and I210 camera NIC ports |
| Link speed | Reports current speed on each port |
| Remediation | For degraded 100 Mbps ports, forces 1 Gbps and re-checks after 30 seconds |
| Physical layer evidence | Scans Intel SmartSpeed event log (last 48 hours) for ID 40 downgrade events — irrefutable Layer 1 fault evidence |
| OCR detection | Ports with no SmartSpeed ID 40 history are identified as 100 Mbps-only devices (OCR scoreboard cameras) and skipped — 100 Mbps is expected on these ports |
| ARP table | Lists connected device MACs and OUIs for identification |

### How it distinguishes cable faults from OCR cameras

Intel SmartSpeed Event ID 40 fires only when the physical medium cannot sustain gigabit — it never fires when the connected device simply doesn't advertise gigabit capability. This means:

- **ID 40 history present** → the NIC tried and failed to hold a gigabit link → physical layer fault (cable, termination, RJ45 pins)
- **No ID 40 history** → the link never attempted gigabit → 100 Mbps-only device (OCR camera) → no action needed

### Requirements

- Windows PowerShell 5.1 (standard on all VPUs)
- Internet access to download the script (or run from a local copy)
- Admin rights — prompted automatically via UAC

### Output

Results are printed to the console and saved to a `.txt` file on the Desktop. Share the results file with support when escalating.

**Example summary:**

```
  [PASS] Ethernet 1            1 Gbps
  [PASS] Ethernet 2            1 Gbps
  [PASS] Ethernet 3            100 Mbps
         -> OCR scoreboard camera - 100 Mbps is expected
  [FAIL] Ethernet 4            100 Mbps - DEGRADED
         -> Physical layer issue - check cable, termination, RJ45 pins, and camera port
```

### Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.
