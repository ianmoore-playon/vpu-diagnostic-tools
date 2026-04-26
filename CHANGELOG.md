# Changelog - Pixellot VPU Camera Link Diagnostic

All notable changes to `TestCameraConnectivity.ps1` are documented here.

---

## [3.4] - 2026-04-26

### Changed
- **Actions buttons relocated** — Export Report, Copy Results, Save Log moved from right panel to a horizontal button strip at the bottom of the center panel (aligned to the status card grid at x=10/200/390)
- **Next Steps text** — guidance now stored as complete paragraph strings and word-wrapped naturally by the RichTextBox, replacing the previous manually pre-broken lines
- **Next Steps render** — numbered step headers rendered at 9pt Semibold with a blank-line gap between items; body text at 8.5pt, fully wrapped without manual newlines
- **Right panel rtbSteps height** — expanded from 218px to 450px since Actions section was removed; Detected Hardware section pushed down to y=546
- **rtbLog height** — reduced from 308px to 270px to accommodate the action button strip below

### Fixed
- Next Steps text was split mid-sentence across dozens of short lines making it hard to read — now renders as flowing paragraphs

---

## [3.3] - 2026-04-26

### Changed
- **Status card icons** — each card now shows a decorative Segoe MDL2 Assets glyph watermarked in the lower-right corner (link bars, network, signal, globe, list, camera)
- **Cable fault guidance** — removed specific wire-pair reference; now states "a wire inside the cable is damaged or broken, or the RJ45 connector is not crimped correctly" with instructions to try a known-good replacement cable first
- **Camera fault guidance** — expanded "Monitor" directive with explicit step-by-step instructions: PoE reset via VPU Manager path, 2-minute wait, re-run, and replacement escalation if failures persist
- **Re-run reminder** — trailing step now only appears when there are multiple issue types (cable + RTSP or camera faults) to avoid redundancy

---

## [3.2] - 2026-04-26

### Changed
- **Rounded status cards** — cards now render with 8px corner radius using GDI+ Region clipping and an anti-aliased 1px border, replacing sharp-cornered rectangles
- **Circular indicator dots** — the per-card status dot (upper-right of each card) is clipped to a circle via Region
- **Pill-shaped badge** — the status badge (Ready / Running / All Clear / Issues Found) uses a 13px radius giving a full pill shape at 26px height
- **Rounded buttons** — Run Full Diagnostic, Retest Last Step, Export Report, Copy Results, and Save Log buttons all have 5–6px corner radius via Region

### Added
- `GfxHelper` C# helper class (loaded via `Add-Type`) providing `RoundedRect(Rectangle, radius)` returning a `GraphicsPath` — used for all rounded Region and border painting

---

## [3.1] - 2026-04-26

### Fixed
- Status card value labels truncated to "Degrade", "Reachabl" at display scale — font reduced from 15pt to 13pt Semibold, label width increased from `$W-30` to `$W-20`
- VPU Model "Not detected" on live VPU — agent log search now also searches one level of subdirectories under each `$PixellotLogPaths` entry

---

## [3.0] - 2026-04-26

### Changed
- **Full rewrite as a WinForms GUI application** — all diagnostic logic preserved, surfaced through a three-panel interface matching the design mockup

### Added
- **Left sidebar:** nav buttons (Overview, Tests, Results, History, Settings), NIC selector dropdown, Quick Info block (OS, host, user), VPU model display
- **Center panel:** Run Full Diagnostic + Retest Last Step buttons; six live status cards (Link Speed, NIC Status, Ping CHU, Gateway, ARP Entry, CHU Detection); Last Run Summary; color-coded scrollable Live Log (dark terminal style)
- **Right panel:** status badge (Ready / Running / All Clear / Issues Found); dynamically generated Next Steps / Guidance list post-run; Detected Hardware table (CHU MAC, Camera Port, Cable Status); Export Report / Copy Results / Save Log action buttons
- Diagnostic engine runs in a background PowerShell runspace; UI timer polls shared synchronized hashtable every 300ms — GUI never freezes during the 30s re-negotiation wait or 12s blink-sample window
- Tests nav item shows placeholder for guided isolation workflow (Tests A–D, coming in a future version)
- Self-elevation uses `-WindowStyle Hidden` so only the GUI window appears (no console behind it)
- One-liner `irm | iex` deployment unchanged

---

## [2.8] - 2026-04-26

### Changed
- Redesigned on-screen summary with distinct **NIC PORT STATUS**, **CAMERA STATUS**, **DIAGNOSIS**, and **NEXT STEPS** sections replacing the previous flat verdict block
- NEXT STEPS generated dynamically from actual findings: cable replacement per degraded port, PoE reset per RTSP fault, monitor advisory per camera-level app failure, re-run reminder

### Fixed
- SmartSpeed count in summary was using the capped 20-event sample (`$smartSpeedMessages`) instead of the real total from the event log scan — introduced `$totalSmartSpeedDowngrades` captured at scan time
- `$allClear` now also checks `$cameraAppIssues` so camera-level app warnings are not silently ignored in the verdict

---

## [2.7] - 2026-04-25

### Added
- VPU model and product type detection from `agent_*.log` as primary source (written every 5 min by Pixellot agent process, independent of browser state); web scrape of VPU Manager at `http://localhost:32323/` kept as fallback
- Product type (S2 / S2S) now shown alongside model and unit ID in the header

### Fixed
- "Not detected (VPU Manager offline?)" when VPU Manager browser was not open — agent log reading resolves this reliably
- App log analysis incorrectly flagged "Couldn't get response" failures for the optional OCR camera (.52) when it was simply not installed — suppressed when `Optional = $true` and ping had no response

---

## [2.6] - 2026-04-25

### Fixed
- Em dash (U+2014) in OCR camera RTSP skip note rendered as `?` in Windows PS 5.1 log files — replaced with plain hyphen
- Exit code 11 was unmapped and displayed as "Exit code 11" — added mapping: `11` → "Camera not found / no response before timeout"

---

## [2.5] - 2026-04-25

### Added
- `Get-AdapterPeakSpeedMbps`: 12-second multi-sample speed check to detect intermittent blinking links caused by Intel SmartSpeed retry cycles (NIC periodically drops 100 Mbps link to reattempt gigabit negotiation)
- Blinking status flag propagated to port results and on-screen summary

### Fixed
- A port cycling between 100 Mbps and disconnected was classified as NO LINK on the initial read — now correctly classified as DEGRADED (blinking)

---

## [2.4] - 2026-04-24

### Added
- VPU model detection via web scrape of VPU Manager SPA title at `http://localhost:32323/`
- Camera ping + RTSP port 554 connectivity test for all three camera IPs (169.254.16.50–.52)
- `Optional = $true` flag on OCR camera (.52): absence is not flagged as a fault
- `Test-TcpPort` helper using raw sockets (avoids `Test-NetConnection` verbose output)
- RTSP fault count included in `$allClear` check and summary verdict

---

## [2.3] - 2026-04-24

### Changed
- Results saved to `CameraLink_Results\` subfolder inside script directory (or Desktop when run via `irm | iex`) instead of Desktop root

---

## [2.2] - 2026-04-23

### Fixed
- Exit code 0 (clean application shutdown) no longer overwrites a meaningful failure code (e.g. exit 12) for the same camera IP — non-zero codes are now preferred and preserved
- Subnet match fallback now detects when a FAIL/degraded port is also on the same subnet as the matched port and surfaces a `[CAUTION]` warning directing the tech to verify physical cable mapping — prevents a healthy port from being reported as the likely camera host after adapter reset clears the ARP table
- Subnet match result now labelled `[subnet match - ARP unavailable]` to distinguish it from a confirmed ARP lookup

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
