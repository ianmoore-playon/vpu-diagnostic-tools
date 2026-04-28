# Changelog - VPU Cable & NIC Troubleshooter

All notable changes to `TestCameraConnectivity.ps1` are documented here.

Version format: `MAJOR.MINOR.PATCH`
- **MAJOR** — full rewrites or fundamental architecture changes
- **MINOR** — new functional flows, significant new features, new tabs or workflows
- **PATCH** — bug fixes, UI polish, text changes, minor improvements

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

## [1.0.5] - 2026-04-26

### Changed
- **Camera-level fault note reworded** — clarified to distinguish between physical layer ruled out (NIC 1 Gbps) vs. camera-side issue; added PoE reset guidance before assuming hardware failure

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
