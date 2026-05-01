# Changelog - VPU Diagnostic Tool Suite

All notable changes to `TestCameraConnectivity.ps1` are documented here.

Version format: `MAJOR.MINOR.PATCH`

- **MAJOR** — full rewrites or fundamental architecture changes
- **MINOR** — new functional flows, significant new features, new tabs or workflows
- **PATCH** — bug fixes, UI polish, text changes, minor improvements

---

## [1.0.15] - 2026-04-30

### Fixed

- **Launcher `->` redirect bug** — the version update line (`v1.0.13 → v1.0.14`) was being parsed by CMD as a stdout redirect (`>`), swallowing the line and generating `'update' is not recognized` errors. Escaped as `-^>`.
- **Pipe operators in BAT `if` blocks** — `|` characters inside PowerShell `-Command` strings nested in parenthesised `if (...)` blocks were misinterpreted by CMD. All SHA-fetch, SHA-record, and Unblock-File calls rewritten to avoid `|` entirely.
- **Header logo** — the `logo-horizontal.png` asset has no alpha channel (solid white background), which clashed with the dark navy header. Image loading removed; header now always renders with the icon glyph + text labels.

### Changed

- **Launcher console UI** — the CMD window is now sized (72×32), cleared on launch, and shows a formatted header with the tool name and subtitle. Version tracking added: shows installed version on up-to-date runs, "v1.0.14 → v1.0.15" on updates, and "Installing for the first time" on fresh installs. A persistent close-warning is printed before any download or launch step. Error messages are clearly prefixed with `ERROR:`.
- **`version.txt`** added to repo root — a single-line file containing the current version string, read by the launcher to display human-readable version numbers without parsing the PS1 source.
- **`Build.ps1` silenced** — `Write-Host` calls replaced with `Write-Verbose` so the BAT owns all console messaging; Build errors still surface via `Write-Error` and the ERRORLEVEL check.

---

## [1.0.14] - 2026-04-30

### Changed

- **Hub tiles enlarged** — Home page cards increased from 234×128 to 296×200 px (4 columns, 296 px each, 16 px gap, 24 px margins — fills the full 1280 px width). Icon glyph 16 pt → 22 pt, title font 9.5 pt → 11 pt Semibold, description font 8 pt → 8.5 pt with more vertical space for wrapping.
- **Tab bar taller** — `$TabH` 52 → 64 px. Icon font 13 → 15 pt, label font 7.5 → 8.5 pt. Both positioned dynamically so the icon + label stack is always vertically centred regardless of tab height.
- **Completion toast notification** — a 430×62 px floating panel appears anchored to the top-right of the content area whenever any module's diagnostic finishes. Shows module name, All Clear / Warning / Issues Found status with matching color (green/amber/red), a timestamp, and a dismiss button. Auto-hides when the next run starts. Driven by a 400 ms watcher timer; does not modify any individual module.

---

## [1.0.13] - 2026-04-30

### Changed

- **Launcher now installs to `%ProgramFiles%\VPU-DiagTool`** — the tool is no longer re-downloaded to `%TEMP%` on every run. On first launch it installs to Program Files and builds `Run.ps1`; on subsequent launches it checks the latest GitHub commit SHA and only re-downloads when an update is available.
- **Smart update detection** — a `.commit` file stores the installed GitHub commit SHA. The launcher compares it against the remote SHA on each run via one lightweight GitHub API call. If the SHA matches, the tool launches instantly. If the check fails (no internet), it falls back to the installed version gracefully.
- **Self-elevation** — the launcher now prompts for administrator privileges via UAC if not already elevated, since writing to Program Files requires admin access.
- **Re-download safety net** — if `Run.ps1` is missing for any reason (failed build, manual deletion) the launcher forces a fresh download regardless of the stored SHA.

---

## [1.0.6] - 2026-04-30

### Fixed

- **Full Diagnostic encoding garbage** (`Ã‚Â·`, `Ã¢â‚¬â€œ`) - non-ASCII characters (middle dot, em dash) in FullDiagnostic strings were double-encoded by `Get-Content`'s default ANSI read in Build.ps1. Replaced all non-ASCII separators with ASCII `|` and `-`.
- **"View E" / "< E" button glyphs** - MDL2 Assets Private Use Area glyphs in a Segoe UI font button rendered as garbage. Changed to plain ASCII `View  >` and `<  Back to Home`.
- **"Disk  System Health" label** - WinForms Label `UseMnemonic` defaults to true, eating the `&` in "Disk & System Health". Set `UseMnemonic = $false` on module name labels.
- **Network Configuration shows no value** - the network runspace writes to `$sync["NetCard_X_V"]` flat keys, not `$sync.Cards["NetX"]`. Updated `Set-NetCard` in NetworkDiagnostics to also mirror values into `$sync.Cards` so the Full Diagnostic summary reads them correctly.

---

## [1.0.5] - 2026-04-30

### Fixed

- **Full Diagnostic — modules stuck at "Waiting"** — `PerformClick()` silently does nothing when a button's parent panel is not visible (`CanSelect` requires all ancestors to be visible). Added `Invoke-ButtonClick` helper that calls `OnClick` via reflection to bypass this check, so all six module diagnostics now start correctly when triggered from the Home page.
- **Full Diagnostic — Re-run button never enabled** — a consequence of the above; since no modules were completing, `$allDone` was never `$true`. Fixed by the above.
- **Full Diagnostic — `anyIssue` evaluated incorrectly** — the `continue` in the already-painted branch of the timer tick skipped the `anyIssue` accumulation for all but the last module to complete, potentially showing an incorrect overall banner. Restructured the loop to always evaluate `anyIssue` for completed modules before deciding whether to repaint.

---

## [1.0.4] - 2026-04-30

### Added

- **Full Diagnostic** (`FullDiagnostic.psm1`) — "Run Full Diagnostic" on the Home page now fires all seven diagnostic modules in parallel (System Overview, Network Config, Camera Connectivity, Pixellot Services, VPU Hardware, Disk & System Health, Event Viewer) and presents a one-page summary. Each module row shows a live spinning status while running, then resolves to Pass / Warning / Issues Found with a one-line value summary and a "View →" button that jumps directly to that module's tab. An overall banner (green All Clear / red Issues Found) appears when all checks complete. A "Re-run" button re-fires everything; "Back to Home" returns to the hub card grid.
- **System Overview summary card** — `HardwareOverview.psm1` now writes `sync.Cards["SysInfo"]` (e.g. `Core i7-8700  ·  16 GB RAM`) at collection end so the Full Diagnostic summary can display a one-line hardware snapshot.

---

## [1.0.3] - 2026-04-30

### Added

- **NIC Card header on Camera Connectivity tab** — a "NIC Card" label now appears in the toolbar area showing the detected ADLINK card model, Intel chip, and port count (e.g. `ADLINK GIE74P  (Intel I210 x4)`). Derived at form load from `InterfaceDescription`; covers GIE64, GIE74P, and GIE74P-AN variants.

### Fixed

- **PoE power management false positives on GIE64 (82574L) systems** — `Get-AdlinkCardInfo` maps each detected NIC chip to its ADLINK card family and a `PoeMgmtSupported` flag. On GIE64/82574L and GIE74P-AN/I350/I354 systems that do not support PoE power management, the diagnostic now skips all `SmartPoE_Get_*` budget/port queries and shows "N/A (GIE64)" on the PoE Budget card in gray. The "Check Molex connector" next step is also suppressed on unsupported cards.
- **Port card click not opening Fault Isolator** — clicking the port tile only fired when the user hit the panel background; clicks on child labels (title, value, sub-label, status dot) were silently swallowed because WinForms clicks don't bubble to parent panels. The handler is now attached to all child controls via a loop so clicking anywhere on the card navigates to the Fault Isolation guide.

---

## [1.0.2] - 2026-04-30

### Added

- **System Overview tab** — new `HardwareOverview.psm1` module adds a dedicated "System Overview" tab that collects and displays OS edition/version/build/uptime, system manufacturer/model/BIOS/serial, CPU name/cores/speed, RAM total/available/per-slot, GPU name/VRAM/driver, disk models/sizes/interfaces, and physical NIC names/MACs/speed/status. Data is collected via CIM in a background runspace; a Refresh button re-runs collection. Auto-starts on first tab visit.

### Changed

- **"System Overview" home hub renamed to "Home"** — the landing page tile grid is now labelled "Home" in both the tab bar and the panel title. The "System Overview" hub card now navigates to the new hardware panel instead of looping back.
- **Tab width reduced from 160 px to 142 px** to accommodate the new 9th tab while staying within the 1280 px window width.

---

## [1.0.1] - 2026-04-30

### Fixed

- **`op_Subtraction`/`op_Addition` failures in Run.ps1** — Layout constants (`$HdrH`, `$TabH`, `$SbarH`, `$RightX`) and `[int]`-typed function parameters (`$CardW`, `$W`) were coerced to `[System.Object[]]` at runtime in the Build.ps1-combined script on Win 10 LTSC, causing `"[System.Object[]] does not contain op_Subtraction"` errors. Fixed by adding explicit `[int]` cast expressions at every arithmetic use site in `UIHelpers.psm1` (`New-StatusCard`), `SystemOverview.psm1` (`New-SectionCard`), `CameraConnectivity.psm1`, and `TestCameraConnectivity.ps1`. These casts are picked up by `Build.ps1`'s inlining and applied to the generated `Run.ps1`. Note: `.psm1` files cannot be dot-sourced on Windows (they open in Notepad or are blocked by security policy) — `Build.ps1`'s single-file inlining approach is required and is retained.

---

## [1.0.0] - 2026-04-29

### Fixed (post-test hotfix)

- **Camera timer handler split across two modules (root cause of three failures)** — The `else {}` block inside `$timer.Add_Tick({` in `CameraConnectivity.psm1` was never closed in that file; lines 215–233 of `NetworkDiagnostics.psm1` were the orphan tail that closed it. This caused all `$btnRun.Add_Click` handlers, `Show-OverviewSteps`, `Update-GuideStepDots`, `$guideStepDots`, and the entire guide panel construction to be nested inside the timer's else block — they only executed after a diagnostic completed with issues, never at startup. Fixed by inserting the missing `else` closure code at the end of `CameraConnectivity.psm1`'s timer block and removing the orphan tail from `NetworkDiagnostics.psm1`.
- **Network Configuration showing "Starting" with no results** — `$NetScript` (the background runspace script) was defined inside the camera timer's else block (a consequence of the split above). Clicking "Run Network Test" before any camera diagnostic had run started the runspace with a null script body, so it returned immediately with no output. Resolved by the timer handler fix above, which moves `$NetScript` to true top-level scope.
- **System Overview hub tiles not navigating** — Click handlers used `Get-Variable -Name $hc.Nav -ValueOnly` to resolve nav buttons at event-fire time; this lookup fails inside WinForms event context. Replaced with a pre-built hashtable (`$hubNavLookup`) of direct variable references captured via `GetNewClosure()`.
- **Layout constants becoming `[System.Object[]]` at runtime** — `$HdrH` and related constants were occasionally coerced to arrays on the lab VPU (Win 10 LTSC), causing `$HdrH - 1` to fail with "does not contain op_Subtraction". Added explicit `[int]` type constraints to all layout constants in `TestCameraConnectivity.ps1`.
- **RunDiagnostic.bat** reverted to `Build.ps1` → `Run.ps1` path. A prior session incorrectly changed the bat to launch `TestCameraConnectivity.ps1` directly; on the VPU, `.psm1` files cannot be dot-sourced and open in Notepad instead. The `Build.ps1` inlining step is required for VPU deployment.

### Added

- **VPU Hardware tab** (replaces "PoE / NIC Hardware" stub) — "Check Hardware" runs a background diagnostic showing GPU model (`Win32_VideoController`), monitor connection status (`Win32_DesktopMonitor` with PnP fallback), and MMK peripheral status (mouse via `Win32_PointingDevice`, keyboard via `Win32_Keyboard`). NIC port link uptime and PoE per-port data are read from the Camera Connectivity cache — no second DLL call. Follows the same pattern as all other panel modules: independent runspace, 300ms timer, Run/Cancel buttons, live spinner, and dark RichTextBox log.
- **NIC link uptime** — Camera Connectivity runspace now calculates per-port link uptime after the SmartSpeed pre-scan, reusing the already-fetched event log (`$events`, IDs 27/32). Results cached in `$sync.NicLinkUptimes`; `>48h` indicates a stable link (positive result, not a warning).
- **PoE data cache** — Camera Connectivity runspace writes per-port PoE readings (voltage, current, watts, state) to `$sync.PoePortData` and budget summary to `$sync.PoeTotal/PoeConsumed/PoeTemp`. VPU Hardware tab reads from this cache.

### Fixed

- **PoE port level** — `$portLvl` was referencing undefined `$pgGood`; corrected to `$voltage -gt 1.0` so PoE-active ports correctly show green instead of always gray.

### Changed

- **"PoE / NIC Hardware"** nav button and hub card renamed to **"VPU Hardware"** throughout (sidebar, System Overview hub).
- Version renumbered from 2.x to 1.0.0, marking first production-ready release for field deployment.

---

## [0.2.2] - 2026-04-29

### Changed

- Version renumbered from 2.3.0 to 0.2.2 to reflect pre-release / alpha status ahead of the planned v1.0.0 milestone.

---

## [2.3.0] - 2026-04-29

### Changed

- **Module refactor** — monolithic `TestCameraConnectivity.ps1` (3,724 lines) split into a thin 468-line launcher plus 10 panel modules under `Modules\`. Each module is dot-sourced into the launcher's scope so all shared variables (`$form`, `$sync`, colors, layout constants) remain accessible without passing parameters.
  - `Modules\UIHelpers.psm1` — Add-Type, GfxHelper, AdlinkPoE P/Invoke, color/layout constants, `New-StatusCard`, `Update-CardStatus`, `Set-ActiveNav`, `Show-Panel`
  - `Modules\SystemOverview.psm1` — System Overview hub panel
  - `Modules\CameraConnectivity.psm1` — camera diagnostic engine, Guide/Isolate panel, all camera logic
  - `Modules\NetworkDiagnostics.psm1` — network test engine and panel
  - `Modules\PixellotServices.psm1` — Pixellot Services panel (added in v2.2.0, now extracted)
  - `Modules\DiskHealth.psm1` — System & Disk Health panel (added in v2.2.0, now extracted)
  - `Modules\EventViewer.psm1` — Event Viewer panel (added in v2.2.0, now extracted)
  - `Modules\ReportGenerator.psm1` — History/Reports panel
  - `Modules\HelpAbout.psm1` — Help/About panel
  - `Modules\PoeNicHardware.psm1` — PoE / NIC Hardware placeholder
- **`RunDiagnostic.bat`** updated to run the local `TestCameraConnectivity.ps1` directly (no longer fetches from GitHub via `irm | iex`). Self-elevation is handled inside the PS1.
- Update check now runs async on form load, comparing remote version to current.

---

## [2.2.0] - 2026-04-29

### Added

- **Pixellot Services panel** — "Check Services" runs a background diagnostic checking all `Pixellot*`, `pxl*`, `CanopyAgent*`, and `SportzCast*` Windows services plus key system dependencies (W32Time, DNS Client, DHCP, Event Log, Windows Update). Live log with status card showing running/total count.
- **System & Disk Health panel** — "Check System Health" reports OS caption, uptime, memory utilization, per-drive disk space with pass/warn/fail thresholds, and Pixellot data folder sizes. Two status cards: Disk Space and Memory.
- **Event Viewer panel** — "Check Event Log" scans the System and Application Windows event logs for errors and warnings in the last 24 hours. Shows error/warning counts and up to 10 most recent errors with timestamp, source, and first line of message. Status card reflects error count.
- All three panels follow the same pattern as the Network tab: independent Run/Cancel buttons, live spinner, colored RichTextBox log, graceful cancel support, and proper runspace/timer cleanup on form close.

---

## [2.1.3] - 2026-04-29

### Fixed

- Navigation now works correctly. `$script:allNavPanels` was being populated before `$pnlHistory`, `$pnlHelp`, and `$pnlNetwork` were created, so those entries were `$null` in the array — and a stale `$script:allNavPanels = $null` line later in the script wiped the whole array. Moved the array assignment to after all panels are created; removed the erroneous null assignment.
- Sidebar now highlights the correct active button on startup (`Set-ActiveNav $navSysOverview` called in form Load).

---

## [2.1.2] - 2026-04-29

### Fixed

- Hub section cards now navigate correctly to their target panels. The click handler was using `Get-Variable -Scope Script` inside a WinForms event context where that scope lookup doesn't resolve; replaced with direct button capture via `GetNewClosure()`.

---

## [2.1.1] - 2026-04-28

### Fixed

- Updated all script URLs and `RunDiagnostic.bat` to point to the new `vpu-diagnostic-tools` repository (previously referenced `pixellot-vpu-tools`).
- Fixed MD060 lint warning in README.md — table separator row changed from `|---|---|` to `| --- | --- |`.

---

## [2.1.0] - 2026-04-28

### Added

- **System Overview hub** — New default landing page with eight section cards (2×4 grid), each navigating to the corresponding diagnostic section. Includes "Run Full Diagnostic" and "Open Last Report" buttons.
- **Six new section stubs** — PoE / NIC Hardware, Pixellot Services, System & Disk Health, Event Viewer, Reports, and Settings panels added with correct headers, separators, and footer buttons (Run Full Diagnostic + Export Section). Functionality will be populated in subsequent versions.
- **Bottom status bar** — Thin dark bar at the bottom of the window shows a status dot, "Status: Ready/Running/All Clear/Issues Found", and last-run timestamp. Updates live on diagnostic completion.
- **Sidebar status dot** — Green/amber/red dot and label at the bottom of the sidebar mirrors overall tool state.

### Changed

- **Sidebar rebuilt** — Replaced 5-item nav (Overview, Isolate, History, Help, Network) with 10-item nav: System Overview, Network Configuration, Camera Connectivity, PoE / NIC Hardware, Pixellot Services, System & Disk Health, Event Viewer, Reports, Settings, About.
- **Header updated** — Title is now "VPU Diagnostic Tool Suite"; subtitle updated to "All-in-one diagnostic and troubleshooting tool for Pixellot VPU systems."; version label added top-right.
- **NIC test scope selector** moved from sidebar into the Camera Connectivity panel.
- **Network, History, Help panels** widened from 800 px to 1060 px (full content area, no right panel) to match new layout.
- **Camera Connectivity** retains the 800 px narrow layout with the right Next Steps panel.
- **Form border** changed from `FixedSingle` to `Sizable` to allow free resizing.

---

## [2.0.0] - 2026-04-28

### Added

- **Network tab** — New "Network" entry in the sidebar launches a dedicated network connectivity panel. Runs independently from the camera diagnostic with its own Run / Cancel buttons and live log. Tests include:
  - Basic internet reachability (ICMP ping to 8.8.8.8 / 1.1.1.1)
  - Per-adapter inventory (IP, gateway, link speed) for all active adapters
  - Port tests: real TCP connect probes for TCP 53 (DNS), TCP 443, and real protocol probes for UDP 53 (DNS query) and UDP 123 (NTP request); unreliable UDP ports (443/2088/5672) reported as INFO with explanation
  - Domain DNS tests: async resolution for all Pixellot-required domains (nfhsnetwork.com, pixellot.tv, pixellot.stream, software.pixellot.tv, sportzcast.net, app.singular.live, balena-cloud.com, logmein.com, s3.amazonaws.com, leaf-uploads/downloads.s3.amazonaws.com)
  - Three summary cards: Internet, Port Tests, Domain Tests
- **Tool rebrand** — Renamed from "VPU Cable & NIC Troubleshooter" to "VPU Diagnostic Tools" in form title, header bar, and CHANGELOG. Subtitle updated to reflect multi-tab scope.

### Changed

- **Sidebar** — Added "Network" navigation button; all controls below the nav group shifted down to accommodate the fifth nav entry.

---

## [1.9.5] - 2026-04-28

### Added

- **Fault flag in Isolate port dropdown** — After each diagnostic run, the suspect port dropdown in the Isolate tab appends `⚠ FAULT` to any port with a `FAIL` or `PASS (forced)` result, making the faulty port immediately visible without switching back to Overview. The selection is preserved across refreshes; port-card click-through and "Open Fault Isolator" navigation updated to match the new item text.

---

## [1.9.4] - 2026-04-28

### Changed

- **PoE log section renamed to "POE STATUS"** — PoE entries now appear under their own "POE STATUS" section header in the live log (Highlights and Detailed modes) instead of flowing under "SIGNAL QUALITY". Copy Summary header updated to match.

---

## [1.9.3] - 2026-04-28

### Fixed

- **PoE `RuntimeException: Unable to find type [ushort]`** — `[ushort]` and `[short]` are not valid PowerShell type accelerators; replaced with `[uint16]` and `[uint16]` respectively in the PoE diagnostic code. The C# declarations inside `Add-Type` were unaffected.

---

## [1.9.2] - 2026-04-28

### Fixed

- **PoE `RuntimeException` — `out byte` P/Invoke incompatibility** — PowerShell 5.1 cannot reliably call P/Invoke methods with `out byte` parameters via `[ref]`; removed `SmartPoE_Get_PortStatus` from the DllImport and loop; per-port PoE ON/OFF state is now inferred from measured voltage (> 1.0 V = PoE ON). Also corrected `PortNumber` parameter type from `short` to `ushort` to match the `U16` declaration in `SmartPoE.h`.

---

## [1.9.1] - 2026-04-28

### Added

- **Update Now button** — When a newer version is detected on GitHub, a yellow **Update Now** button appears in the sidebar below the version notice. Clicking it relaunches the script via the `irm | iex` one-liner in a new process and closes the current window. The script's built-in elevation check handles UAC automatically on relaunch.

---

## [1.9.0] - 2026-04-28

### Added

- **PoE power monitoring** — Diagnostic engine now queries the ADLINK PCIe-GIE7x SmartPoE card (via `SmartPoE.dll` P/Invoke) for per-port voltage, current, and wattage plus total power budget. If total budget < 55 W (Molex connector disconnected scenario), a "Issues Found" flag is raised with a "Check Molex power connector" next step. A new **PoE Budget** card appears in the Overview row alongside SmartSpeed, Ping, ARP, and CHU Detection. PoE data is included in the Copy Summary output. On systems without the ADLINK DLL the section logs "N/A" and is otherwise silent.
- **DLL auto-search** — Script probes standard ADLINK install paths and HKLM registry key at startup; if found, the DLL directory is added to PATH and the `AdlinkPoE` P/Invoke type is registered before the runspace launches.

### Fixed

- **Stale `$CameraIPs` reference in next steps** — The app-log "camera ruled out" next step was still referencing the removed `$CameraIPs` list (v1.8.0 removal). Fixed to use `$discoveredCameras` so the camera label (OCR Camera / S2 Camera) appears correctly in the next step text.

### Changed

- **Diagnostic card row resized** — Four cards resized from 187 px to 146 px each to make room for the fifth PoE Budget card; total row still fills the 780 px panel width.

---

## [1.8.0] - 2026-04-28

### Changed

- **Dynamic camera discovery — static IP list removed** — `$CameraIPs` (hardcoded 169.254.16.50–.52) has been replaced with ARP-based discovery; the diagnostic engine now reads `Get-NetNeighbor` on each camera NIC interface and builds the camera list at runtime; only link-local `169.254.x.x` addresses with unicast MACs are included, which automatically excludes any non-camera device accidentally connected to a camera port (e.g. an internet uplink, which receives a routable DHCP address); OCR cameras are identified by the `$OcrMacOui` (`00-D0-89`) prefix and marked optional; all other link-local neighbors are classified as S2/CHU cameras (required); if no cameras are found in the ARP table the connectivity section is skipped with an informational note rather than pinging addresses that may not be correct

---

## [1.7.0] - 2026-04-28

### Added

- **Log mode toggle** — Live log header now has Highlights / Detailed toggle buttons. Highlights shows only port speed results and SmartSpeed signal quality events; Detailed shows the full output including camera IP ping rows, ARP table, app log entries, and VPU model. Defaults to Highlights on launch and on each new run.
- **Open Adapter Settings button** — New button in the Actions panel launches `ncpa.cpl` (Network Connections) directly from the tool.
- **Port tile click always navigates to Isolate tab** — Previously only faulted ports were clickable; now all port tiles (OCR, no-link, pass) navigate to the Isolate tab for that port.

---

## [1.6.6] - 2026-04-28

### Fixed

- **Port card value clipped on long text** — `Update-CardStatus` now drops the value label font from 13pt to 11pt when the value exceeds 9 characters, preventing `100 Mbps (OCR)` from being clipped at the label boundary

---

## [1.6.5] - 2026-04-28

### Changed

- **OCR port card value** — card now shows `100 Mbps (OCR)` instead of `100 Mbps` to make the OCR classification explicit at a glance

---

## [1.6.4] - 2026-04-28

### Changed

- **OCR port card color** — confirmed OCR cameras (`PASS (OCR)`) now display green instead of yellow; uncertain OCR (`PASS (OCR?)`) remains yellow
- **OCR port card value** — card now shows `100 Mbps` instead of `100M OCR` / `100M OCR?`; color (green vs yellow vs red) conveys the meaning

---

## [1.6.3] - 2026-04-28

### Added

- **MAC-based OCR camera identification** — ARP table is now checked for the Pixellot OCR camera MAC OUI (`00:D0:89`) during the 100 Mbps port evaluation; a confirmed MAC promotes the port directly to `PASS (OCR)` regardless of SmartSpeed event history, eliminating the `PASS (OCR?)` false-uncertain state on new installs; `$OcrMacOui` is a top-level config variable threaded into the diagnostic runspace

---

## [1.6.2] - 2026-04-28

### Fixed

- **Forced-port next steps missing (flaw 1)** — ports that were successfully forced to 1 Gbps (`PASS (forced)`) were excluded from `$failPorts`, so `$allClear` stayed false (due to `$TotalDowngrades > 0`) but no next step was generated; replaced the `$TotalDowngrades` check in `$allClear` with explicit `$forcedPorts` and `$uncertainOcr` tracking; forced ports now generate a "replace cable — preventive" next step
- **App log timing false positive (flaw 2)** — the "camera issue / cable ruled out" next step assumed log failures were concurrent with the current NIC state; log last-modified timestamp (`$sync.AppLogTime`) is now shown in the next step with a note that failures may be stale if a cable was recently replaced
- **New-install cable fault misidentified as OCR (flaw 3)** — OCR detection used only ID 40 absence; a port with zero events of any kind (new installation, no prior history) was silently marked OCR; now checks for any events (ID 27/33/40): confirmed-OCR when link-at-100M events exist, flagged as `PASS (OCR?)` with a "verify" next step when there is no history at all
- **Isolate guide Phase 2 test port not pre-verified (flaw 4)** — the test port was never checked for its own health before Phase 2; a quick 4-second pre-check now runs before the full measurement; if the test port is already degraded, a warning dialog is shown with the option to cancel and select a different port
- **Guide baseline "No link" described as "Degraded link confirmed" (minor flaw 5)** — a completely disconnected port (0 Mbps) was shown the same "Degraded link confirmed" message as a 100 Mbps port; now shows "No link detected" with a prompt to verify camera power and cable seating before proceeding

---

## [1.6.1] - 2026-04-28

### Added

- **Maximize / restore support** — window can now be maximized to fill the screen; all structural panels (`header`, `sidebar`, `center`, `right`) and scrollable content areas (`rtbLog`, `rtbSteps`, `rtbGuide`, `lvHistory`, `rtbHelp`) are anchored so they resize correctly when maximized; action buttons and separator in the right panel remain pinned to the bottom; restoring from maximized snaps back to 1280×760; status badge in the header stays pinned to the top-right corner

---

## [1.6.0] - 2026-04-27

### Changed

- **UI redesign — wider, modern layout** — window expanded from 1024×680 to 1280×760; a new dark navy header bar (1280×68) holds the tool title, subtitle, and status badge; sidebar, center panel, and right panel all repositioned below the header; sidebar widened to 220px with taller nav buttons (205×44); center panel widened to 800px; right panel 259px; all overlay panels (Isolate, History, Help) updated to fill the new 800px center panel width; History Summary column expanded from 260px to 468px

---

## [1.5.0] - 2026-04-28

### Added

- **Cancel button** — red "Cancel" button appears next to "Retest Last Step" while a diagnostic is running; sets `$sync.Cancelled` to stop the background runspace (including the 30-second re-negotiation wait) and hides itself automatically when the run completes
- **Auto-update notice** — on form load, a background async `WebClient` fetch checks the remote `$ScriptVersion`; if a newer version is available, a yellow notice appears in the sidebar: "Update available: vX.Y.Z — Re-run the one-liner to update."
- **Log folder pruning** — at the start of each run, the `CameraLink_Results` folder is trimmed to the 50 most recent files; oldest files are silently deleted to prevent unbounded disk growth
- **Isolate session saved to report** — when the fault isolation wizard reaches a conclusion (Phase 2/3/4), the full phase history is appended to the current run's `.txt` report file under a "FAULT ISOLATION SESSION" header; escalation reports now capture both diagnostic and isolation results in one file
- **Structured STATUS line in report files** — each report now ends with `STATUS: ALL_CLEAR` or `STATUS: ISSUES_FOUND`; used by the History tab for fast, reliable result classification

### Fixed

- **Race condition on shared ArrayList reads** — `$sync.PortResults`, `$sync.CamResults`, `$sync.AppIssues`, and `$sync.NextSteps` are now snapshot-copied (`@(...)`) before iteration in the UI timer tick, Copy Summary handler, and Show-OverviewSteps; prevents intermittent exceptions if the background runspace adds an item mid-iteration
- **Isolate guide link-speed sampling too short for blinking links** — `Get-GuideLinkSpeed` default sampling window raised from 6 s to 12 s, matching the diagnostic engine; prevents false "No link" readings on ports undergoing Intel SmartSpeed retry cycles (~8–10 s period)

### Changed

- **History tab result classification uses STATUS line** — `Update-HistoryList` now reads the `STATUS:` line instead of grepping for "DEGRADED"; backward-compatible fallback retained for files written before v1.5.0
- **NIC detection in form Load de-duplicated** — `$form.Add_Load` now reuses the already-queried `$script:detectedNics` array instead of issuing a second `Get-NetAdapter` call; port card order and dropdown order are now consistent (both PCI function order)
- **Guide action handler refactored to switch** — replaced four chained `if ($phase -eq X)` blocks with a single `switch ($script:guide.Phase)` for clarity

---

## [1.4.2] - 2026-04-27

### Fixed

- **Content clipped at bottom of live log and action buttons** — `form.Size` was setting the outer window size (including title bar), so the client area was ~30px shorter than intended; changed to `form.ClientSize` so the content area is exactly 680px tall
- **Last Run Summary appears as empty white box** — summary text labels were siblings on the center panel rather than children of the white card panel, causing them to paint with the gray background color; moved labels into the card panel as children with white background

---

## [1.4.1] - 2026-04-27

### Changed

- **"Guide" tab renamed to "Isolate"** — nav button, panel title, action button ("Open Fault Isolator →"), Next Steps heading, and all Help tab references updated; eliminates confusion with the Help tab which is the actual usage guide

---

## [1.4.0] - 2026-04-27

### Added

- **NIC selector functional** — "Test Scope" dropdown in the sidebar now filters the diagnostic to a single NIC port when a specific port is selected; "All Ports" runs the full diagnostic as before; button text updates dynamically to reflect the current scope (e.g. "▶ Test Ethernet 45 Only")

### Changed

- **Next Steps condensed to 1–2 sentences** — all Next Steps body texts shortened for faster reading; full guidance for component isolation is now in the Guide tab
- **"Selected NIC" label renamed to "Test Scope"** — makes the purpose of the dropdown immediately clear

---

## [1.3.0] - 2026-04-27

### Added

- **SmartSpeed status card** — fourth card in the bottom row showing Intel SmartSpeed downgrade event count live after each run; red if any downgrades, green if none — gives the tech a number to quote when escalating
- **Copy Summary action** — generates a structured, ticket-ready summary (port status, SmartSpeed count, camera results, app log findings, recommended next steps) and copies it to clipboard
- **Help tab** — eight-section reference: what the tool does, how to read each tab, Guide workflow walkthrough, FAQ, escalation guide
- **Port card click-to-Guide** — clicking a red (degraded) port card on Overview navigates directly to the Guide tab with that port pre-selected; hand cursor on clickable cards

### Changed

- **History trend in summary card** — after each run, the Last Run Summary line appends which port has had issues most frequently across the last 15 runs
- **Right panel switches context per tab** — Guide tab shows a phase-by-phase reference rather than Overview next steps; Overview next steps restored on return
- **"Copy Log" relabelled** — raw log copy button renamed from "Copy Results" to "Copy Log" to distinguish it from the new Copy Summary
- **Nav wiring refactored** — `Show-Panel`, `Show-OverviewSteps`, `Show-GuideSteps` helpers extracted; all nav click handlers simplified

---

## [1.2.0] - 2026-04-27

### Added

- **History tab** — lists all past `CameraLink_Results_*.txt` runs with date/time (parsed from filename), inferred result (All Clear / Issues Found), a port-fault summary, and file size; double-click any row to open the full report in Notepad; Refresh link re-scans the output folder
- **"Open Fault Isolation Guide →" button** — appears in the right panel when port faults are detected; navigates to the Guide tab and pre-selects the first failed port

### Changed

- **Next Steps — port faults now direct to Guide** — degraded-port steps now say "Run Fault Isolation Guide — X" rather than prescribing a replacement action
- **Results and Settings nav tabs removed** — non-functional stubs removed; nav now has Overview, Guide, History, and Help

### Fixed

- **Nav handlers referenced removed buttons** — `$navResults` and `$navSettings` removed from all nav click handler loops

---

## [1.1.1] - 2026-04-27

### Added

- **Per-port speed cards** — one status card per detected Intel NIC (P1–P4) ordered by PCI function number for physical port position; each card updates live during the diagnostic
- **Card subtitles, summary card, actions header, badge dot, connected status indicator, version in title bar** — UI polish across the center panel and sidebar

### Changed

- **Aggregated cards replaced by per-port cards** — static Link Speed and NIC Status cards replaced by dynamic P1–P4 cards
- **NIC sort order** — port cards ordered by PCI function number rather than Windows adapter instance number
- **"Current Status" → "Current Results"** — label rename

### Removed

- **Gateway card** — gateway reachability check not relevant to camera link-local subnet
- **Detected Hardware section** — CHU MAC, camera port status, cable status table removed

### Fixed

- **Live Log always empty** — `$(if ...)` subexpression syntax bug silently discarded all log lines

---

## [1.1.0] - 2026-04-27

### Added

- **Fault Isolation Guide** — new Guide tab implements a 4-phase interactive wizard: Phase 1 captures baseline degraded link speed; Phase 2 tests whether the fault follows the NIC port; Phase 3 tests whether the fault follows the cable; Phase 4 tests whether the fault follows the camera. Each phase measures link speed and produces a plain-language verdict. Concluded phases transition the action button to "Run Full Diagnostic" to confirm the fix
- **Per-port NIC status cards (initial)** — one dynamic status card per detected Intel NIC, updating in real time during the diagnostic

### Changed

- **"Tests" nav → "Guide"** — nav button renamed; old static step-row panel replaced by the full wizard
- **Gateway ping removed** — not relevant to the camera-only link-local subnet; removed from engine and UI

### Fixed

- **VPU Model missing from live log** — inline `if` expression used as positional arg in background runspace; replaced with explicit variable
- **Per-port cards not rendering** — cards created inside `Add_Load` where color variables and `[GfxHelper]` fail silently; fixed by pre-querying NICs before form construction

---

## [1.0.8] - 2026-04-26

### Changed

- **Spinner status indicator** — replaced static pipeline hint label with a live `| / - \` spinner above the log showing current step text while running
- **Live log section headers** — log entries grouped into named sections (`SYSTEM`, `SIGNAL QUALITY`, `NETWORK`, `CAMERAS`, `APP LOG`) rendered as bold muted uppercase headers

---

## [1.0.7] - 2026-04-26

### Fixed

- **`$W`/`$H` crash in elevated PS** — parameter name collision in `New-StatusCard`; renamed to `$CardW`/`$CardH` throughout
- **`$allClear` false-positive** — non-optional cameras not responding to ping were not included in the all-clear check
- **Camera ping/RTSP entries missing from live log** — inline `if` expression in `Add-Summary` call silently failed in PS5.1 background runspace; replaced with explicit variable
- **NIC stuck at forced 1 Gbps after failed renegotiation** — `Restart-NetAdapter` added after both force-to-1Gbps and reset-to-auto calls
- **Misleading "Physical layer limitation confirmed" on ID 27 warnings only** — message and fail status now gated on `$dCnt -gt 0`
- **Duplicate summary entry on forced-renegotiation path** — intermediate "Forcing 1 Gbps, waiting 30s…" entry removed

### Added

- **No-hardware notice** — when no Intel NICs are found, Next Steps shows "Wrong machine — no VPU hardware detected" with plain-language explanation
- **PoE reset guidance for unreachable cameras** — added when a non-optional camera doesn't respond to ping and the NIC port is healthy

---

## [1.0.6] - 2026-04-26

### Changed

- **Summarized live log** — `rtbLog` now shows a two-column checkpoint summary (label / result) instead of raw output; detailed output still written to `.txt` file
- **Next Steps render** — step entries changed to `@{H=...; B=...}` hashtables; header in blue Semibold, body in muted gray with word-wrap
- **Action buttons relocated to right panel** — Export Report, Copy Results, Save Log moved from center panel to right panel

### Added

- **Tests tab — live diagnostic steps panel** — 7 step rows with colored status circles, names, descriptions, and result labels; timer tick derives live status from `$sync.StepsDone`
- `$sync.StepsDone` synchronized hashtable — diagnostic engine writes pass/fail after each major phase

---

## [1.0.6] - 2026-04-30

### Fixed

- **Full Diagnostic encoding garbage** (`Ã‚Â·`, `Ã¢â‚¬â€œ`) - non-ASCII characters (middle dot, em dash) in FullDiagnostic strings were double-encoded by `Get-Content`'s default ANSI read in Build.ps1. Replaced all non-ASCII separators with ASCII `|` and `-`.
- **"View E" / "< E" button glyphs** - MDL2 Assets Private Use Area glyphs in a Segoe UI font button rendered as garbage. Changed to plain ASCII `View  >` and `<  Back to Home`.
- **"Disk  System Health" label** - WinForms Label `UseMnemonic` defaults to true, eating the `&` in "Disk & System Health". Set `UseMnemonic = $false` on module name labels.
- **Network Configuration shows no value** - the network runspace writes to `$sync["NetCard_X_V"]` flat keys, not `$sync.Cards["NetX"]`. Updated `Set-NetCard` in NetworkDiagnostics to also mirror values into `$sync.Cards` so the Full Diagnostic summary reads them correctly.

---

## [1.0.5] - 2026-04-26

### Changed

- **Camera-level fault note reworded** — clarified to distinguish between physical layer ruled out (NIC 1 Gbps) vs. camera-side issue; added PoE reset guidance before assuming hardware failure

---

## [1.0.6] - 2026-04-30

### Fixed

- **Full Diagnostic encoding garbage** (`Ã‚Â·`, `Ã¢â‚¬â€œ`) - non-ASCII characters (middle dot, em dash) in FullDiagnostic strings were double-encoded by `Get-Content`'s default ANSI read in Build.ps1. Replaced all non-ASCII separators with ASCII `|` and `-`.
- **"View E" / "< E" button glyphs** - MDL2 Assets Private Use Area glyphs in a Segoe UI font button rendered as garbage. Changed to plain ASCII `View  >` and `<  Back to Home`.
- **"Disk  System Health" label** - WinForms Label `UseMnemonic` defaults to true, eating the `&` in "Disk & System Health". Set `UseMnemonic = $false` on module name labels.
- **Network Configuration shows no value** - the network runspace writes to `$sync["NetCard_X_V"]` flat keys, not `$sync.Cards["NetX"]`. Updated `Set-NetCard` in NetworkDiagnostics to also mirror values into `$sync.Cards` so the Full Diagnostic summary reads them correctly.

---

## [1.0.5] - 2026-04-30

### Fixed

- **Full Diagnostic — modules stuck at "Waiting"** — `PerformClick()` silently does nothing when a button's parent panel is not visible (`CanSelect` requires all ancestors to be visible). Added `Invoke-ButtonClick` helper that calls `OnClick` via reflection to bypass this check, so all six module diagnostics now start correctly when triggered from the Home page.
- **Full Diagnostic — Re-run button never enabled** — a consequence of the above; since no modules were completing, `$allDone` was never `$true`. Fixed by the above.
- **Full Diagnostic — `anyIssue` evaluated incorrectly** — the `continue` in the already-painted branch of the timer tick skipped the `anyIssue` accumulation for all but the last module to complete, potentially showing an incorrect overall banner. Restructured the loop to always evaluate `anyIssue` for completed modules before deciding whether to repaint.

---

## [1.0.4] - 2026-04-26

### Changed

- **Actions buttons relocated** — Export Report, Copy Results, Save Log moved from right panel to horizontal button strip at bottom of center panel
- **Next Steps text and render** — guidance stored as full paragraph strings, word-wrapped naturally by RichTextBox; numbered step headers at 9pt Semibold

---

## [1.0.3] - 2026-04-26

### Changed

- **Status card icons** — Segoe MDL2 Assets glyphs watermarked in lower-right corner of each card
- **Cable fault guidance** — removed specific wire-pair reference; states "damaged wire or incorrect RJ45 crimp" with known-good cable swap instruction
- **Re-run reminder** — only shown when multiple issue types are present

---

## [1.0.2] - 2026-04-26

### Added

- `GfxHelper` C# helper class providing `RoundedRect()` for all rounded Region and border painting

### Changed

- **Rounded status cards, circular dots, pill-shaped badge, rounded buttons** — all UI chrome uses 5–13px corner radius via GDI+ Region clipping

---

## [1.0.1] - 2026-04-26

### Fixed

- Status card value labels truncated at display scale — font reduced from 15pt to 13pt Semibold, label width increased
- VPU Model "Not detected" on live VPU — agent log search now also scans one level of subdirectories

---

## [1.0.0] - 2026-04-26

### Changed

- **Full rewrite as a WinForms GUI application** — all diagnostic logic preserved, surfaced through a three-panel interface

### Added

- Left sidebar: nav buttons, NIC selector dropdown, Quick Info block, VPU model display
- Center panel: Run / Retest buttons, live status cards, Last Run Summary, color-coded Live Log
- Right panel: status badge, Next Steps / Guidance, Detected Hardware table, action buttons
- Diagnostic engine runs in a background PowerShell runspace; UI timer polls shared synchronized hashtable every 300ms — GUI never freezes during long waits
- Self-elevation uses `-WindowStyle Hidden` so only the GUI window appears

---

## Legacy CLI Versions

The following versions were command-line only (no GUI). Included for historical reference.

### [2.8] - 2026-04-26

Redesigned on-screen summary with NIC PORT STATUS, CAMERA STATUS, DIAGNOSIS, and NEXT STEPS sections. Fixed SmartSpeed count using wrong variable; `$allClear` now checks `$cameraAppIssues`.

### [2.7] - 2026-04-25

VPU model and product type detection from `agent_*.log`; VPU Manager web scrape kept as fallback. Fixed optional OCR camera false-positive app log failures.

### [2.6] - 2026-04-25

Fixed em-dash rendering in PS 5.1 log files. Added exit code 11 mapping.

### [2.5] - 2026-04-25

Added 12-second multi-sample speed check for intermittent blinking links (Intel SmartSpeed retry cycles).

### [2.4] - 2026-04-24

Added VPU model detection, camera ping + RTSP port 554 tests, `Optional` flag for OCR camera.

### [2.3] - 2026-04-24

Results saved to `CameraLink_Results\` subfolder instead of Desktop root.

### [2.2] - 2026-04-23

Fixed exit code 0 overwriting meaningful failure codes. Improved subnet match fallback.

### [2.1] - 2026-04-23

Added Pixellot application log analysis, IP-to-NIC-port correlation, cross-reference with NIC port results.

### [2.0] - 2026-04-23

Added spinner animation, GitHub `irm | iex` one-liner support, `$ScriptUrl` config variable.

### [1.8] - 2026-04-22

Fixed parse error from em-dash character in PS 5.1.

### [1.7] - 2026-04-22

Added Intel I210 NIC support, SmartSpeed pre-scan, OCR camera detection via SmartSpeed history.

### [1.6] - 2026-04-21

Fixed `*SpeedDuplex` registry keyword lookup; corrected SpeedDuplex forced value to `"6"` (1 Gbps Full Duplex).

### [1.5] - 2026-04-21

Added `Get-EventAdapterName` helper. Fixed event log provider filter and description string error.

### [1.4] - 2026-04-20

Fixed self-elevation, link speed string parsing, false all-clear, and ARP multicast noise.

### [1.3] - 2026-04-20

Added post-reset link monitoring and `$allClear` verdict logic.

### [1.0 – 1.2] - 2026-04-19

Initial versions: NIC detection, link speed reporting, SmartSpeed event log scan, force-to-1Gbps remediation, Auto Negotiation reset, timestamped output file.
