# Handoff — Canopy Script Adoption

**Source folder:** `/Users/ian.moore/Code/Resources/Canopy/Leaf/`
**Authorization:** We have full authorization from leadership to use, adapt, or vendor any script in that folder.
**Branch:** Work on `dev` (small additions) or short-lived feature branches off `dev` (anything > ~100 lines).

This doc is the master inventory. The per-session paste prompts above (or the messages this links from) point each owning session at specifically which scripts they should pick up.

---

## Architectural notes (read once before adapting any script)

The Canopy scripts post results to a Banyan "Leaf" agent at `http://localhost:8000` with a consistent envelope:

```powershell
$leafBody = @{
    messageType = "statistic" | "event"
    statisticType / eventType = "..."   # e.g. "system.gpu"
    data = @{ ... }
}
Invoke-RestMethod -Method 'Post' -Uri 'http://localhost:8000' -Body ($leafBody | ConvertTo-Json -depth 32)
```

Pulse doesn't use that pattern. **When adapting these scripts, strip out the HTTP POST entirely** and return the result as JSON to stdout (Pulse's standard `run_ps` pattern). Just replace the final `Invoke-RestMethod` block with `$leafBody.data | ConvertTo-Json -Compress`.

**Auth credentials** for Dynacolor camera CGI probes are hardcoded as `Admin / 1234`. Pulse already has this pattern in `_cgi_probe_sync` in `main.py`. Reuse the existing infrastructure for any new CGI work.

**Log-file parsing** uses `Select-String` against `C:\Pixellot\Data\Log\*Coordinator*` or `*Agent*`. We learned during VPU log work that these files may be UTF-16 encoded and `Select-String` can silently miss matches. Prefer `findstr` (native, encoding-safe) as `Get-SystemIdentity.ps1` already proves.

---

## Per-session inventory

### 📸 Camera Connectivity (HIGH value)

| Canopy file | Pulse adaptation | Notes |
|---|---|---|
| **`getConnectedS1Cameras.ps1`** ⭐ | **New script:** `Pulse.Web/scripts/Get-S1Cameras.ps1` | Uses `Jai_FactoryDotNet.dll` (JAI SDK) to discover 4-cam S1 systems. We currently can't see S1 cameras — they don't use Dynacolor. Adds support for older fleet. Returns SN/IP/model. |
| **`videoTest.ps1`** ⭐ | **New script:** `Pulse.Web/scripts/Test-CameraVideo.ps1` | ffmpeg/ffprobe RTSP capture (60s per camera) to validate codec + frame rate. ffmpeg already ships with Pixellot at `C:\Pixellot\Bin\ffmpeg`. Wire as a slow "Verify Video" button on Camera Connectivity tab — not a default poll. |
| **`getFirmwareAndTvMode.ps1`** | Extend existing `_cgi_probe_sync()` in `main.py` | Adds **TV mode** field (ntsc_60 / pal_50). We already pull firmware via the same CGI. Add `ImageSource.I0.Video.DetectedType` to the field set. |
| `powertools/calibrationMonitor.ps1` | Future Sentinel feature | FileSystemWatcher pattern for monitoring calibration drift. Don't implement now — interesting pattern for when Pulse gets continuous-monitoring mode. |

### 🌐 Network (MEDIUM value)

| Canopy file | Pulse adaptation | Notes |
|---|---|---|
| **`reportWifiConnection.ps1`** ⭐ | **New script:** `Pulse.Web/scripts/Get-WifiAdapters.ps1` + new finding in `_compute_findings` | NEW capability — VPUs should be wired only. Active WiFi adapter = warning finding ("WiFi adapter connected — VPUs should use wired network only"). |
| **`getIpStaticOrDynamic.ps1`** ⭐ | Extend `Get-NetworkConfig.ps1` to include `dhcpEnabled` per interface (we already partly have this) | DHCP-on-uplink is fine for most venues; static is sometimes required. Surface in Network tab UI; don't generate a finding unless `pulse-settings.json` specifies expected mode. |
| **`testConnections.ps1` + `connections.csv` + `portqry/`** | Audit `Test-NetworkPorts.ps1` against `connections.csv` | The CSV is the canonical Pixellot port list. Required entries: scorebot.sportzcast.net TCP 1400–1405, prod-echo.pixellot.tv TCP 443, UDP 123/443/2088. Verify our list matches; add anything missing. **Don't bundle portqry** — our pure-PS port test is fine. |
| **`powertools/speedtest.ps1` + `speedtest.exe`** | **Vendor `speedtest.exe`** into `Pulse.Web/bin/speedtest.exe` + new script `Pulse.Web/scripts/Test-InternetSpeed.ps1` | Replaces the current paste-URL flow with a direct CLI invocation. Cleaner UX, no manual paste. Check Ookla CLI licensing for redistribution; if blocked, leave the current flow alone. |
| `reportEthernetConnections.ps1` | Pattern reference only | We already have this functionality. Useful patterns for `Convert-IP2NetworkName` / `Convert-MAC2WmiObject` — borrow if needed. |

### 🏆 Score Connect (VERY HIGH value)

| Canopy file | Pulse adaptation | Notes |
|---|---|---|
| **`scoreboardModeSet.ps1`** ⭐⭐ | Extend `Get-ScoreConnectStatus.ps1` to handle **all three SC versions** | Reads SC1 (`C:\Program Files (x86)\Sportzcast LLC\ScoreConnect\Files\Parms.json`), SC2 (`...\ScoreConnectII\Files\settings.json`), SC3 (HTTP `/api/configuration/get-current-configuration-extended`). Our current implementation only covers SC3. Field reality: legacy SC1/SC2 installs exist. |
| **`usbConnectionCheck.ps1`** | Reference for ScoreLink detection | Win 8/8.1 reports `USB Serial Port`, others report `USB Serial Device`. Use the OS-version-aware lookup pattern in our existing ScoreLink check. |

### 🖥️ System Tabs (MEDIUM value)

| Canopy file | Pulse adaptation | Notes |
|---|---|---|
| **`checkDedicatedGpu.ps1`** ⭐ | Extend `Get-Hardware.ps1` + new finding | We already pull GPU info. New finding: `[Hardware] No dedicated GPU detected` (warning) — a VPU without NVIDIA/AMD is the wrong hardware. |
| **`getVpuDepsFromRegistry.ps1`** ⭐ | New script: `Pulse.Web/scripts/Get-PixellotDependencies.ps1` | Reads `HKLM:\SOFTWARE\Pixellot\dependencies` registry key. Ties directly into your existing "Reinstall Pixellot Dependencies" action (PDF #2). Returns installed deps version. Surface in Pixellot Services tab. |
| **`getGpuDriverVersion.ps1`** | Combine with `Get-Hardware.ps1` | NVIDIA driver version specifically. Pulse already pulls this via WMI — verify our extraction matches. |
| `powertools/eventMonitor.ps1` | Pattern reference only | Continuous Event Log monitoring with throttling. We have snapshot via `Get-EventLogs.ps1`. Useful pattern for future Sentinel mode. |

### 🏠 Dashboard / General (LOW-MEDIUM value)

| Canopy file | Pulse adaptation | Notes |
|---|---|---|
| **`systemDataCollector.ps1`** ⭐ | Extend `Get-SystemIdentity.ps1` | Currently extracts `vpuName` from logs. Add **`venueId`** extraction from `*Coordinator*` logs matching `got for key /GENERAL/VenueID result:` — this is the Pixellot Cloud venueId we need for the API integration (handoff in `HANDOFF-pixellot-cloud-integration.md`). Also extract camera count, graphics type, camera URLs while you're in there. |
| `userAndDomain.ps1` | Optional minor enhancement | Current Windows user + domain on VPU Identity card. Low priority. |

### 🔌 API (Pixellot Cloud Integration session)

| Canopy file | Pulse adaptation | Notes |
|---|---|---|
| **`systemDataCollector.ps1`** ⭐ | The **venueId** that this script extracts solves the self-identification problem | Coordinate with the Dashboard/General session — once `Get-SystemIdentity.ps1` returns `venueId`, the API session can use that as the direct lookup key into Pixellot Cloud's `/api/v3/venues/{venueId}?include=metrics`. No more MAC-matching needed. |

### 🔧 Setup Tabs / General (LOW value)

| Canopy file | Pulse adaptation |
|---|---|
| `reboot_system.bat` | Optional: add a "Reboot VPU" quick action in Settings (with a confirmation modal) |
| `trigger_screenshot.bat` + `do_screenshot.json` | Optional: attach a desktop screenshot to Support Bundle exports |
| `playon*.bat`, `splashtop_*.bat`, `desktop_app_check.bat`, `leaf_process_check.bat` | **Skip** — Banyan/Canopy-internal, not relevant to Pulse |

---

## Top-5 ranked by ROI

| Rank | Item | Owning session | Why |
|---|---|---|---|
| 1 | `scoreboardModeSet.ps1` (SC1/SC2/SC3 handling) | ScoreConnect | Unblocks the long tail of older ScoreConnect installs in field |
| 2 | `videoTest.ps1` (ffmpeg RTSP validation) | Camera Connectivity | "Camera actually streams" is a stronger claim than "camera responds to ping" |
| 3 | `systemDataCollector.ps1` venueId extraction | Dashboard/General + API | Solves Pixellot Cloud self-identification cleanly |
| 4 | `checkDedicatedGpu.ps1` + `getVpuDepsFromRegistry.ps1` | System Tabs | Two cheap, high-value findings |
| 5 | `reportWifiConnection.ps1` + `getIpStaticOrDynamic.ps1` | Network | Two new network findings |

## Anti-recommendations (skip these)

- The entire `powertools/` continuous-monitoring framework — interesting patterns but Pulse's WebSocket already gives us live polling
- Splashtop scripts — out of scope
- `playon*.bat`, `leaf_*.bat` — Banyan internal tooling
- Don't bundle `portqry` — we already do port checks in pure PowerShell
- Don't vendor `Jai_FactoryDotNet.dll` blindly — check whether Pixellot ships it with the VPU (it should, since `C:\Program Files\JAI\SDK\bin\` is the canonical path on S1 systems)
