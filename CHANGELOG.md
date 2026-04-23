# Changelog - Pixellot VPU Camera Link Diagnostic

All notable changes to `TestCameraConnectivity.ps1` are documented here.

---

## [2.1] - 2026-04-23

### Added
- Pixellot application log analysis: parses the most recent `CamerasTester_*.log` file for camera connection failures, camera model names, session counts, and process exit codes
- IP-to-NIC-port correlation for failing cameras — tries ARP/neighbor table first, then /24 subnet match as fallback
- Cross-reference between application log failures and NIC port results: confirms physical fault when both app failures and NIC degradation are present; flags camera-side fault when NIC link is healthy
- `$PixellotLogPaths` config variable with confirmed primary path (`C:\Pixellot\Data\Log`) and common fallback locations
- `PIXELLOT APPLICATION LOG` section added to the final summary screen
- `$cameraAppIssues` list tracked and shown in summary alongside SmartSpeed and port results

---

## [2.0] - 2026-04-23

### Added
- Spinner animation during all wait periods — shows elapsed/remaining time and a spinning `|/-\` character so the screen is never frozen
- GitHub hosting support via `irm URL | iex` one-liner — no file transfer needed
- `$ScriptUrl` config variable for self-elevation re-launch in iex context
- Desktop fallback for output file path when `$PSScriptRoot` is null (iex context)

### Changed
- Self-elevation now detects whether script is running from a local file or via iex, and re-launches appropriately in each case
- Output file saves to Desktop when run via the GitHub one-liner; saves next to script when run locally

---

## [1.8] - 2026-04-22

### Fixed
- Parse error on older Windows PowerShell caused by em-dash character (U+2014) in `Write-Log` strings — replaced with plain hyphens

---

## [1.7] - 2026-04-22

### Added
- Intel I210 NIC detection alongside existing 82574L support (`$NicDriverPatterns`)
- SmartSpeed pre-scan to gate remediation decisions before the script's own actions can falsify event log stats
- `$ScriptStartTime` guard — pre-scan query uses `EndTime = $ScriptStartTime` so script-generated events are excluded
- OCR scoreboard camera detection via SmartSpeed history: absence of Event ID 40 history = 100 Mbps-only device, skip remediation

### Fixed
- OCR camera ports being incorrectly remediated every run (ARP-based detection replaced with SmartSpeed history approach)
- "Irrefutable Layer 1 evidence" label appearing incorrectly when only ID 27/33 events present (no ID 40 downgrades)

### Removed
- ARP/neighbor table-based OCR detection (unreliable after adapter restart)

---

## [1.6] - 2026-04-21

### Fixed
- `SpeedDuplex` registry keyword not found on modern Intel drivers — now tries `*SpeedDuplex` first, then `SpeedDuplex`
- SpeedDuplex forced value corrected: `"6"` = 1 Gbps Full Duplex (was incorrectly using `"4"` = 100 Mbps)
- Adapter name showing blank in SmartSpeed event output — added `Get-EventAdapterName` with 3-method fallback (message text, XML data elements, Properties collection)

---

## [1.5] - 2026-04-21

### Added
- `Get-EventAdapterName` helper function for reliable per-adapter event correlation
- Per-adapter SmartSpeed event display with Time / Adapter / Event / Message fields

### Fixed
- Event log scan missing all events — provider filter changed from `*Intel*` (incorrect) to direct provider names `e1iexpress`, `e1dexpress`, `e1rexpress`
- Event log error "description string for parameter reference" — moved filtering into `FilterHashtable` (ProviderName + Id) instead of post-query `$_.Message` access

---

## [1.4] - 2026-04-20

### Fixed
- Self-elevation: replaced `#Requires -RunAsAdministrator` (caused instant close if not elevated) with manual elevation block using `Start-Process PowerShell -Verb RunAs`
- Link speed returning -1/Unknown — `LinkSpeed` on Windows Server/PS 5.1 is a formatted string, not UInt64; added regex string parsing
- False "ALL PORTS AT 1 GBPS" all-clear — `$allClear` now also checks `$unknownCount` and `$chuDowngradeCount`
- ARP section multicast noise — replaced single IP exclusion with MAC first-octet LSB multicast bit check

---

## [1.3] - 2026-04-20

### Added
- Post-reset link monitoring: after resetting to Auto Negotiation, polls every 2 seconds and confirms link speed once restored
- `$allClear` verdict logic in summary

---

## [1.0 - 1.2] - 2026-04-19

### Initial versions
- Core NIC detection and link speed reporting for Intel 82574L
- SmartSpeed event log scan (System log, last 48 hours)
- Force-to-1Gbps remediation with 30-second re-negotiation wait
- Auto Negotiation reset on failure
- Results saved to timestamped `.txt` file alongside script
