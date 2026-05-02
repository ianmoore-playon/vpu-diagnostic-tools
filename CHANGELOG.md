# Changelog - Pulse — Pixellot Diagnostic Toolset

All notable changes to `Pulse.ps1` are documented here.

Version format: `MAJOR.MINOR.PATCH`

- **MAJOR** — full rewrites or fundamental architecture changes
- **MINOR** — new functional flows, significant new features, new tabs or workflows
- **PATCH** — bug fixes, UI polish, text changes, minor improvements

---

## [1.0.47] - 2026-05-02

### Changed

- **NIC Port Layout moved from Hardware tab → Camera Connectivity tab.** The diagram (stylized NIC bracket with 4 RJ45 jacks + status light + per-port LEDs), the 4 port detail boxes (Port N / Status / Speed / Duplex / MAC / Errors), the NIC Information sidebar, and the Status Legend all now live on Camera Connectivity, where they belong alongside the camera-port diagnostic results. The Hardware tab focuses on peripherals: GPU, monitor, input devices, PoE budget, and NIC link uptime.
- **Hardware tab renamed** "PoE / NIC Hardware" → "Hardware & Peripherals" everywhere (sidebar nav, home tile, section header, tooltip).
- **Camera Connectivity layout reflowed** to fit the diagram: removed the per-NIC P1..P4 status cards row (the diagram + port detail boxes carry that information now); status cards row (SmartSpeed/Ping/ARP/CHU/PoE) shifts down to Y=384; two-column main (Live Log + Guidance) shifts to Y=482 with reduced height (198px). Per-NIC `$cards[$NicName]` entries become hidden stub cards so the diagnostic timer keeps working without NPE.
- **Diagnostic results mirror onto port detail boxes.** When the camera diagnostic writes per-NIC results into `$sync.Cards[<NicName>]`, the matching port detail box's Status text is updated to show the result (PASS, DEGRADED, etc.) with the appropriate color. Live link state still drives the diagram on every panel show and again after diagnostic completion.
- **Hardware tab Hardware Details log + Summary panel resized** to fill the 460px gap freed by relocating the diagram.

---

## [1.0.46] - 2026-05-02

### Changed

- **Camera Connectivity panel redesign** — adopts the same section-header pattern as Network/Disk/Services/etc. Single full-width panel (no separate right column) with: section title + Overall Status pill at top; toolbar strip with Test Scope dropdown and detected NIC card; port cards row; status cards row (SmartSpeed / Ping / ARP / CHU / PoE); two-column main with Live Log on the left and "Next Steps & Guidance" card on the right; bottom action bar (Export / Run / Cancel + Copy Summary, Copy Log, Save Log). The Open Fault Isolator button is the primary action inside the guidance card. The old standalone "Last Run Summary" strip is folded into the guidance card.
- **Camera section header pill** — driven by the timer: shows "Running" (neutral) during a run, "All Clear" (green) on success, "Issues Found" (red) on failure. Mirrors the Pulse-wide overall status pattern.

### Fixed

- **Home page tile positioning** — tiles 4, 7, and 8 (Pixellot Services, Event Viewer, Reports) intermittently rendered one row lower than intended, leaving holes in row 0 col 3 and row 1 cols 2–3 and overlapping the bottom action bar. Root cause was the foreach loop reading `$pnlSysOverview.Width` before the form's window handle was created, which produced an inconsistent first-pass layout. Tiles are now built at (0,0) and positioned by a single deterministic `Update-HubTileLayout` call that runs again on `HandleCreated` and `VisibleChanged`. Layout is purely index-based; the `R`/`C` fields in `$hubCardDefs` are documentation only.
- **`Show-Panel $center $true`** — second arg dropped now that Camera Connectivity owns its guidance card. `$right` and `$rightBorder` remain as zero-sized hidden stubs to keep the rest of `Show-Panel` happy.

---

## [1.0.45] - 2026-05-02

### Fixed

- **`DotPanel` errors during diagnostic runs** — Network stub cards (added in v1.0.42 to keep `Update-CardStatus` happy after the visible cards moved into the section header) lacked a `DotPanel` field. `Update-CardStatus` set `$Card.DotPanel.BackColor` and crashed five times per run. Added a hidden Panel as `DotPanel` so all three stubs cover every field the function touches.
- **Home tile titles dropped the `&` character** — "System & Disk Health" rendered as "System  Disk Health" because WinForms Label treats `&` as an Alt-key accelerator hint by default. Set `UseMnemonic = $false` on the tile title label.
- **Storage card text overflowed** — "669 GB free of 930.5 GB (28% used)" wrapped to two lines and truncated. Shortened to `"669 GB free  (28% used)"` which fits in the 200-wide card.
- **PoE port LED color wrong for 10 Gbps** — the regex `^1\s*Gbps` doesn't match "10 Gbps" (`\s*Gbps` can't follow the "0" character), so a 10 Gbps adapter rendered as info-tier (blue) instead of healthy (green). Replaced with a numeric extraction that treats anything ≥ 1 Gbps as healthy.

### Changed

- **Service card icons** — all 6 cards used the same gear glyph; gave each a more specific Segoe MDL2 icon: Agent (server), KeepAgentUp (lightning/watchdog), Coordinator (gear-stack), LogMeIn (remote desktop), VPU (camera), Scoreconnect (clipboard).

### Note

- **Camera Connectivity panel** still uses its custom legacy layout (Fault Isolator wizard, port grid, NIC card label). Adding the section header pattern requires shifting ~30 controls down by 80px and is deferred to a focused Camera-only redesign pass.
- **Reports "Unknown" result** column reflects how the existing parser reads STATUS markers from older report files — not a redesign bug.

---

## [1.0.44] - 2026-05-01

### Fixed

- **`Set-SummaryItems` crashed with "Cannot overwrite variable Host"** — the helper used `$host` as a local variable, which collides with PowerShell's reserved `$host` (session host object). Renamed to `$itemHost`. Symptom was every section's Summary panel staying blank with `Cannot overwrite variable Host because it is read-only or constant` errors in the transcript.
- **Stack overflow when clicking buttons** — v1.0.42 introduced `$navOverview = $navCamera` (and similar aliases) so module compat code could find these names. Then `Add_Click` handlers on the alias called `.PerformClick()` on the same physical button — infinite recursion the moment a nav was clicked. Fixed by making `$navOverview / $navTests / $navHistory / $navHelp` separate hidden compat buttons whose Click forwards to the real nav button.

---

## [1.0.43] - 2026-05-01

### Changed

- **Redesign Wave B/C — full panel rollout** (closes #4 and #46) — every panel now uses the v1.0.42 design language: section header (title + subtitle + Overall Status pill), grouped content cards, Summary panel, and bottom action bar.
  - **Pixellot Services:** 6 service cards in a row, Service Details log card (left), Summary panel (right), action bar.
  - **Disk & System Health:** SMART / Disk Errors / per-volume cards row, Health Report log card (left), Summary panel (right), action bar.
  - **Event Viewer:** Event Status card, Event Log card (left), Summary panel (right), action bar.
  - **PoE / NIC Hardware:** GPU / Monitor / Input cards top row, NIC Port Layout (canvas + 4 port detail boxes) below, NIC Information + Status Legend sidebar, smaller Hardware Details log + Summary panel, action bar.
  - **System Information:** 6 summary cards top row, System Inventory log card (left), Summary panel (right), action bar with Refresh as the primary action.
  - **Reports:** Past Diagnostic Runs list inside a card, action bar with Refresh + Open Reports Folder.
  - **Settings:** grouped cards — General (theme toggle), Reports (output dir + open folder), Feedback (token state) on the left; About Pulse card on the right; action bar with Restore Defaults + Save Settings.
  - **About & Help:** section header with version pill, existing Help content + feedback form retained.
- **Camera Connectivity** kept its existing internal layout (interactive Fault Isolator wizard, port grid, history) — the new chrome wraps it but the body wasn't restructured.
- Each panel's completion handler now updates the Overall Status pill (auto-derived from worst card status) and the Summary panel (color-coded check-bullet list of outcomes).

---

## [1.0.42] - 2026-05-01

### Changed

- **Major chrome redesign — Wave A pilot** (closes part of #4, partial #46, #16) — replaces the dual top-header + tab-bar with a single left sidebar matching the user-provided mockup.
  - **Form:** bumped from 1280x760 → 1500x800 to accommodate the 220-wide sidebar without shrinking the content area.
  - **Sidebar:** vertical nav with icon + label rows: System Overview, Network Configuration, Camera Connectivity, PoE / NIC Hardware, Pixellot Services, Disk & System Health, System Information, Event Viewer, Reports. Settings and About pinned at the bottom of the sidebar.
  - **Active state:** left blue accent strip + subtle dark tint on the row, drawn in a custom Paint event.
  - **Removed:** the old top header bar, tab bar, and in-tab Run Diagnostic button. Each redesigned panel now provides its own bottom action bar (Export + Run).
  - **Bottom status bar:** unified across the form — green dot + "Status: Ready" on the left, "Last Run" mid-bar, "Tool Version: x.y.z" right-aligned.
- **Home page redesigned** — title "VPU Diagnostic Tool Suite" with descriptive subtitle, 8 mockup-style tiles in a 4×2 grid (each tile has a colored circular icon badge, semibold title, 2-line description). Tiles hover-highlight with the accent color. Bottom action row: prominent **Run Full Diagnostic** (primary) + **Open Last Report** (secondary) + last-run summary text aligned right.
- **Network Configuration panel redesigned** — full mockup-style layout:
  - Section header (title + subtitle + Overall Status pill that auto-derives from the worst test result)
  - Left column: Network Adapters / IP Configuration / Firewall Status cards populated from `Get-NetAdapter`, `Get-NetIPConfiguration`, `Get-NetFirewallProfile` (refresh on panel show, no runspace needed).
  - Right column: Connectivity Tests log + Summary panel (green-check / yellow-warn / red-fail bullet list of test outcomes).
  - Bottom action bar: Export Report + Open Network Settings + Run Full Diagnostic + Cancel.

### Added

- **`New-SectionHeader`** helper in `UIHelpers.psm1` — title / subtitle / status pill pattern, applied uniformly to redesigned panels via `Set-SectionPill`.
- **`New-SummaryPanel`** + **`Set-SummaryItems`** helpers — bordered card with a checklist of color-coded bullet rows, used at the bottom of redesigned panels.
- **`New-ActionBar`** helper — bottom row with Export (left, secondary) + primary action (right) for every redesigned panel.

### Note

Other panels (Camera, Services, Hardware, Disks, Event Logs, Reports, System Info) still use the previous internal layout — they're wrapped by the new chrome but haven't been redesigned yet. Wave B + C will roll them out one at a time.

---

## [1.0.41] - 2026-05-01

### Added

- **NIC port diagram on Hardware tab** (closes #7) — visual representation of the 4-port NIC inspired by the user-provided mockup. Stylized PCB + bracket render in the upper area with 4 RJ45 jack openings, each containing an in-jack LED that mirrors the link state (green / yellow / gray). A "PWR" status-light marker sits next to Port 1 to match the physical reference on the actual card.
- **4 port detail boxes** below the rendering — horizontal row, Port 1 leftmost (matching the photo orientation). Each box shows port number, status icon + label (Linked / Degraded / No Link / Not detected), Speed, Duplex, MAC address, and Errors counter (from `Get-NetAdapterStatistics`).
- **Right sidebar** with NIC Information card (Model from `Get-AdlinkCardInfo`, MAC base, Driver state, Total ports detected) and a Status Legend explaining the color coding.
- Port mapping uses ascending MAC sort — lowest MAC = Port 1, confirmed in field with Intel I210 / I350 cards. Falls back to all physical adapters sorted by MAC when the strict driver-pattern filter doesn't match.
- Refreshes when the panel becomes visible and when the Hardware diagnostic completes.

---

## [1.0.40] - 2026-05-01

### Fixed

- **PowerShell 5.1 syntax error spam during Full Diagnostic** — `Get-FdModuleSummary` had three `return if (...) { ... } else { ... }` patterns. PS 5.1 treats `if` as a statement (not an expression) so this throws `"The term 'if' is not recognized..."` repeatedly during module summary generation. Replaced with explicit `if/else { return X }` form. Pre-existing bug; surfaced in v1.0.38 testing.

---

## [1.0.39] - 2026-05-01

### Fixed

- **FullDiagnostic Network row reports correct severity when ports/domains fail** (closes #60) — the Network module's CardKeys are `NetInternet`, `NetPorts`, `NetDomains`, but `Get-WorstCardStatus` was reading the inner `$sync.Cards[$key].Status` which is the unsynchronized hashtable. The background runspace's `Set-NetCard` function couldn't reliably propagate writes to it (same function-scope quirk as v1.0.26). Fixed by:
  - `Get-WorstCardStatus` and `Get-ModuleSummaryText` now prefer the synchronized `_ncs_*` and `_nc_*` keys when present, falling back to `$sync.Cards` for modules that don't use the pattern.
  - Network timer completion handler now backfills `$sync.Cards` from the synchronized keys (defense in depth).
- **Home tile drift on resize fixed properly** (closes #61, supersedes v1.0.38 partial fix) — the previous SuspendLayout/ResumeLayout approach didn't fully prevent intermediate layout states. Replaced with:
  - Extracted layout to `Update-HubTileLayout` function for deterministic recalc.
  - Each tile pinned to `Anchor = None` to prevent any WinForms auto-positioning.
  - Tile bounds set via single `$tile.Bounds` assignment instead of separate Location + Size (atomic).
  - Debounced SizeChanged → 80ms timer coalesces drag events into one final recalc.
  - Parent panel `Invalidate(true)` forces a clean repaint with the new tile positions.

---

## [1.0.38] - 2026-05-01

### Fixed

- **Settings button now reliably navigates to Settings panel** (closes #56) — added `$Panel.BringToFront()` to `Show-Panel` (`Modules/UIHelpers.psm1`) so the target panel is always on top of any z-order siblings. Without this, the Settings panel could be masked by a later-added overlay control. Also guarded `$right.Visible` access against null.
- **Full Diagnostic page now scrolls when content exceeds height** (closes #59) — `$pnlFullDiag.AutoScroll = $true`. With the v1.0.33 row-height bump (54 → 64), the 7 module rows + bottom buttons could exceed the available content area on smaller windows. Bottom buttons (Re-run All / Issues Only / Back to Home) are now always reachable via scroll. Re-enabled `MaximizeBox` so users can also expand the window for full-height view.
- **Home tiles no longer drift after window resize-back** (closes #58) — added `SuspendLayout` / `ResumeLayout` around the resize handler, refreshed each tile's rounded-rect `Region` to match its new size, and added explicit `Invalidate()` so tiles repaint cleanly. Tiles now restore their original 4×2 grid when the window returns to its original size.

### Changed

- **Toast notifications consolidated during Full Diagnostic** (closes #57) — per-module toasts are suppressed via a new `$sync.FullDiagInProgress` flag while a Full Diagnostic is running. A single summary toast fires when all 7 modules complete: `"Full Diagnostic complete  -  2 critical, 1 warning"` with a detail line listing the affected module names. Per-module toasts still fire when modules are run independently from their own tabs.

---

## [1.0.37] - 2026-05-01

### Added

- **System Information summary cards** (closes #5) — six top-row cards surface the most-asked details at a glance: Model, OS edition + build, Uptime, CPU, RAM (total + free), and System Drive Storage. The detailed log stays below for full inventory. Cards are color-coded — Storage goes warn under 15 GB free / fail under 5 GB; Uptime warns above 30 days (suggesting the VPU is overdue for a reboot).

---

## [1.0.36] - 2026-05-01

### Changed

- **Toast notifications: detail + next-step hint** (closes #12) — toast subtitle now includes module-specific detail (e.g. `"2 port / 1 domain failure(s) — open Network tab to inspect"`) instead of a generic dismiss reminder. All-clear toasts auto-dismiss after 8 seconds; warning/issue toasts stay sticky until manually dismissed (so agents have time to read them).

---

## [1.0.35] - 2026-05-01

### Added

- **Event Logs categorization** (closes #29, #44) — `ProviderName` now mapped to one of six categories: Disk, Driver, Service, Network, App, Other. The summary card replaces the bare `"$totalErrors errors"` with a category breakdown like `"3 disk / 1 driver / 2 app"`. Per-row labels prepend a `[Disk]` / `[Driver]` / `[Service]` badge so agents can scan the log without reading every provider name.
- **SMART Health card** on the Disks tab (closes #8) — surfaces aggregate predictive-failure status across physical drives (`"All 2 healthy"` / `"1 of 2 unhealthy"`).
- **Disk Errors card** on the Disks tab (closes #9) — counts disk-related event log errors over the last 48h (already scanned by the existing `Disk Event Log Errors` section), promoted from log row to prominent card.
- **Home last-run summary** (closes #39) — Home tab now shows date, VPU model, and overall result of the most recent diagnostic next to the Open Last Report button. Refreshes whenever the Home panel becomes visible.

---

## [1.0.34] - 2026-05-01

### Added

- **System Information — Time & Locale section** (#20) — surfaces timezone, system time, NTP server (from W32Time registry), and W32Time service status. Flags UTC default as a likely misconfiguration.
- **System Information — Pixellot Calibrations section** (#18) — scans 5 known calibration paths under `C:\Pixellot\` and lists the most recent 12 files per path with last-modified age and size. Surfaces "no calibration directory found" when none exist.
- **System Information — Installed Software section** (#19) — counts installed applications via the registry uninstall keys (faster than Win32_Product) and flags known-conflicting software: third-party AV, broadcast/streaming tools (OBS, vMix, etc.), torrent clients, gaming launchers, and toolbar/coupon software.
- **Help — Camera Fault Isolator + System Information sections** (#17) — added two new help entries describing the existing Camera fault-isolation wizard and the System Information sub-sections.
- **Help — About Pulse section** (#24) — added an About entry with version pointer, repository link, and license note.

---

## [1.0.33] - 2026-05-01

### Added

- **Last-run timestamps on diagnostic status labels** (#42) — Network, Event Logs, Disk Health, Hardware, and Services tabs now append `Last run: h:mm tt` to the status line after a run completes. Helps agents tell at a glance whether the data on screen is fresh.
- **"Open Network Settings" button** in the Network tab (#21) — opens `ncpa.cpl` for direct access to adapter configuration.
- **Camera Connectivity dependency notice** on the Hardware tab (#27) — when navigated-to before Camera Connectivity has run, the subtitle changes to `"Run Camera Connectivity first to populate PoE budget and NIC uptime."`

### Changed

- **Larger Run Diagnostic header button** (#22) — bumped from 132×38 to 170×46, font from 8.5pt to 10pt semibold. More obvious as the primary action.
- **Network log section headers more visible** (#40) — switched from 7.5pt Consolas / muted color to 9pt Segoe UI Semibold / primary text color. Extra leading newline for separation.
- **FullDiagnostic row height** (#41) — bumped from 54px to 64px with action label at Y=32 / height=28. Action text no longer cramped against the row bottom; text wraps cleanly.
- **Network ETA hides on completion** (#36) — was showing `est. ~20 sec` indefinitely after the run; now hides until next run.
- **ETA estimates recalibrated** (#11) — Network 20→15s, Hardware 5→3s, Disk 30→15s based on observed runtimes.

---

## [1.0.32] - 2026-05-01

### Fixed

- **Wave 2 bug fixes (closes #47, #49, #50, #51, #52, #53, #54, #55)**:
  - Hardware GPU card now prefers discrete over integrated (#47) — was showing Intel UHD Graphics 630 even on systems with a discrete GPU. Filter mirrors SystemInformation.psm1.
  - CameraConnectivity Update Now button now uses `$global:ScriptUrl` defined in Pulse.ps1 (#49). Removed `-WindowStyle Hidden` so update errors are visible. Added empty-URL guard.
  - NetworkDiagnostics Test-TcpConnect / Test-UdpDns / Test-UdpNtp / Test-UdpEcho now use try/finally to dispose sockets on exception paths (#50). Same fix applied to CameraConnectivity Test-TcpPort.
  - CameraConnectivity Test-TcpPort now wraps EndConnect in try/catch (#51) — was reporting refused/RST connections as open. Mirrors NetworkDiagnostics pattern.
  - Pulse update-check WebClient and HelpAbout feedback WebClient now disposed properly (#52). Update-check event subscription unregistered on form close.
  - SystemInformation runspace no longer passes `$sync` twice via SetVariable + AddArgument (#53). PowerShell handle stored as `$script:sysInfoPs` and disposed on form close.
  - DiskHealth top-folder scan timeout now breaks out of the volume loop, not just the directory loop (#54) — was running up to 4× over budget on multi-volume systems.

### Added

- **TLS 1.2 enforcement** at startup (#55) — older VPU images defaulted to TLS 1.0/1.1 which GitHub no longer accepts, breaking the update check. Now bitwise-OR'd with whatever protocols are already enabled.
- **`$global:ScriptUrl`** variable defined at startup for the self-update flow.

### Note

- #48 (FullDiagnostic runspace serialization) is intentionally deferred — higher risk than the rest of Wave 2 and warrants standalone testing.

---

## [1.0.31] - 2026-05-01

### Changed

- **Wave 1 text/label polish (closes #25, #30, #31, #32, #33, #34, #37, #38, #43)** — agent-friendly language pass across the UI:
  - FullDiagnostic: severity default label "Complete" → "Healthy" (#25); "Re-run Failed Only" → "Re-run Issues Only" (#30); stripped `>>` prefix from action text (#31); subtitle replaced with task-focused description (#33).
  - SystemOverview: replaced product-tagline subtitle with action-oriented guidance (#32); rewrote all 8 tile descriptions to be specific and task-focused (#43).
  - PixellotServices: VPU.exe card "Idle" → "Not streaming" with sub-label "Only runs during active streams" (#34).
  - HelpAbout: removed "GitHub" reference from feedback subtitle (#37).
  - SystemInformation: renamed registry-derived labels to agent-friendly ("App Version", "System Image Version", "Package Dependencies") (#38).

---

## [1.0.30] - 2026-05-01

### Changed

- **TCP 5672 upgraded to reliable test** — `app.singular.live` is behind Cloudflare Spectrum which proxies TCP on arbitrary ports, so a plain TCP connect gives a valid firewall signal. Promoted to `Reliable=$true`. Failure note updated to explain the real-world impact: blocking TCP 5672 prevents scoreboards and watermarks from appearing on stream. UDP 5672 remains INFO pending a capture during an active Singular session.

---

## [1.0.29] - 2026-05-01

### Fixed

- **SportzCast port tests corrected** — TCP 1935 was pointing at `pixellot.stream` (wrong destination). Cross-referencing the official Pixellot firewall article and packet capture confirmed SportzCast traffic goes to `sportzcast.net`. Both entries now use `scorebot.sportzcast.net` and are promoted to `Reliable=$true` (plain TCP connect).

### Added

- **TCP 1402 port test** — added as a representative test for the 1400–1405 range, confirmed active in packet capture against `scorebot.sportzcast.net`.
- **gocanopy.io domain test** — missing from domain list despite being in the official Pixellot firewall article (Canopy remote monitoring).

---

## [1.0.28] - 2026-05-01

### Changed

- **UDP 443 and UDP 2088 upgraded to reliable tests** — Wireshark analysis of Pixellot's own VPU Manager network check revealed a dedicated echo server at `prod-echo.pixellot.tv`. The server responds to UDP packets with payload `"testing UDP on port <PORT>"` by echoing the same string back. Both ports now use this endpoint with a new `Test-UdpEcho` function and are promoted from gray INFO rows to real PASS/FAIL tests. TCP 1935 and TCP/UDP 5672 remain INFO-only pending stream capture analysis.

---

## [1.0.27] - 2026-05-01

### Fixed

- **INFO port rows rendered yellow** (issue #26) — `Reliable=$false` port tests (UDP 443, TCP/UDP 1935, UDP 2088, TCP/UDP 5672) and the `pixellot.stream` domain INFO row were logged with `"Warn"` level, rendering yellow. Changed to `"Gray"` since these are expected informational rows, not warnings.

### Added

- **Failure action banner** (issue #28) — after a network test completes with port or domain failures, a dark red banner appears below the status cards with IT-actionable text: port failures prompt checking firewall/router/content-filter policy; DNS failures prompt checking DNS server settings on the adapter. Banner is hidden on the next run and not shown when all tests pass.

---

## [1.0.26] - 2026-05-01

### Fixed

- **Port Tests and Domain Tests cards still stuck at "--" (root cause fix)** — diagnostic tracing revealed that writes to `$sync["_nc_*"]` keys inside the `Set-NetCard` helper function were silently not propagating to the main `$NetScript` scriptblock body, despite `Set-NetCard "NetInternet"` working correctly. Root cause appears to be a PowerShell function-scope / scriptblock closure interaction where subscript assignments on the synchronized hashtable inside a function do not reflect back to the enclosing scriptblock's variable view after a `foreach` loop has executed. Fixed by writing `_nc_*` and `_ncs_*` values directly from the main body of `$NetScript` after each `Set-NetCard` call, bypassing the function entirely for those keys.

---

## [1.0.25] - 2026-05-01

### Fixed

- **Port Tests and Domain Tests cards stuck at "--" (v2 fix)** — the v1.0.24 fix read card values from the inner `$sync.Cards` hashtable (unsynchronized), which was not guaranteed to be visible across threads even after the `$sync.NetComplete` memory barrier. Rewrote `Set-NetCard` to dual-write values directly into the synchronized `$sync` hashtable via `$sync["_nc_$Key"]` / `$sync["_ncs_$Key"]` keys; the timer tick and completion handler now read the same synchronized keys, ensuring full acquire/release visibility on every access via `Monitor.Enter/Exit`.

### Changed

- **Time format** — all user-visible timestamps (toast completion, Full Diagnostic sub-label, System Info "Collected at") now display in 12-hour AM/PM format (`h:mm:ss tt`) instead of 24-hour military time.

---

## [1.0.24] - 2026-05-01

### Fixed

- **Port Tests and Domain Tests cards stuck at "--"** — a memory-ordering race between the background network test runspace and the UI timer caused card values written to the inner (unsynchronized) `$sync.Cards` hashtable to be invisible to the timer tick that also detected test completion. The timer tick read the inner hashtable before the acquire memory barrier fired (from reading `$sync.NetComplete`), so it saw stale `"--"` values and skipped the update. Fixed by adding a forced card sync inside the completion handler, where the memory barrier from reading `$sync.NetComplete` guarantees all background-thread writes are visible.

---

## [1.0.23] - 2026-05-01

### Fixed

- **`op_Addition` crash on launch** — `$script:allNavPanels` was not initialized before module dot-sources, so the first `+=` in `SystemInformation.psm1` set it to a single Panel instead of an array. `FullDiagnostic.psm1`'s subsequent `+=` then crashed with "Panel does not contain method op_Addition". Fixed by initializing `$script:allNavPanels = @()` immediately before the module load block in `Pulse.ps1`.

---

## [1.0.22] - 2026-05-01

### Security

- **Feedback token now stored with Windows DPAPI encryption** — the GitHub PAT is no longer held in plain text. It is encrypted on each machine using `ProtectedData` with `LocalMachine` scope (AES-256, machine-specific key derived by Windows) and stored at `C:\ProgramData\Pulse\feedback.key`. The ciphertext is useless on any other machine. Pulse decrypts the token in memory at startup and clears the byte array immediately after. Plain text never touches disk or the repo.
- **`Set-FeedbackToken.ps1` added** — a one-time setup script (run as Administrator on each VPU) that accepts the token via secure prompt or `-Token` parameter, encrypts it, and writes the key file.

---

## [1.0.21] - 2026-05-01

### Added

- **In-app feedback form** — the Help/About panel now includes a "Submit Feedback" section at the bottom. Users select a type (Bug Report or Suggestion), enter details, and optionally attach system info (hostname, OS, Pulse version, VPU model). Submissions are POSTed directly to GitHub Issues via the API. If GitHub is unreachable, the formatted feedback is copied to the clipboard as a fallback.

---

## [1.0.20] - 2026-05-01

### Fixed

- **Full Diagnostic — Disk module never flagged issues** — `$DiskScript` now writes `$sync.Cards["DiskStatus"]` at completion so `Get-WorstCardStatus` can detect disk failures. Previously the card key was never written and the Full Diagnostic row always stayed neutral.
- **Full Diagnostic — reflection-based button invocation removed** — `Invoke-ButtonClick` used `GetType().GetMethod('OnClick', NonPublic)` to fire hidden panel buttons, which silently no-ops when a button's parent panel is not visible. Replaced with direct named-function calls (`Start-XxxDiagnostic`) across all seven modules; `FullDiagnostic.psm1` calls these functions directly via `& $Mod.RunFn`.
- **PowerShell runspace instances never disposed** — all modules stored `[powershell]::Create()` in a local `$ps` variable that was unreachable after `BeginInvoke()`. Each module now stores `$script:xPs` and calls `.Dispose()` at the start of the next run, preventing handle and memory leaks on re-runs.
- **Disk Health — SMART failure mis-attributed to wrong drive** — a single boolean flag was set when any disk predicted failure, then applied to all disks. Replaced with a per-disk hashtable keyed by `PhysicalDisk.Index`; only the drive that predicted failure is flagged.
- **Disk Health — free-space thresholds tightened** — critical threshold raised from >95% to >97% used; warning threshold raised from >85% to >90% used, reducing false positives on typical VPU storage layouts.
- **Disk Health — top-folder scan could freeze for minutes** — `Get-ChildItem -Recurse` on `C:\Users`, `C:\Windows\Temp`, and `C:\Pixellot` could run indefinitely. Added `-Depth 3` cap and a 30-second `Stopwatch` guard with `$sync.DiskCancelled` check to all recursive scans in Sections 3 and 4.
- **Event Logs — `Get-EventLog` replaced with `Get-WinEvent`** — `Get-EventLog` is absent from PowerShell 7+ and was the cause of silent event-log failures on newer PS builds. Both modules (EventLogs.psm1, DiskHealth.psm1) now use `Get-WinEvent -FilterHashtable` with correct `Level`, `TimeCreated`, and `ProviderName` property names.
- **Event Logs — display limits raised** — errors shown per log raised from 10 to 20; warnings raised from 5 to 10. Warning card threshold changed to trigger on any warnings (was >20).
- **Network Diagnostics — flat `$sync` key workaround removed** — `Set-NetCard` previously wrote duplicate entries to flat `$sync` keys in addition to `$sync.Cards`. `$sync.Cards` is itself a `[hashtable]::Synchronized`, so the flat-key workaround was redundant. Timer tick and click-handler reset updated to read `$sync.Cards` directly.
- **Network Diagnostics — duplicate `$script:allNavPanels` assignment removed** — `NetworkDiagnostics.psm1` contained a stale `$script:allNavPanels = @(...)` block that was missing `$pnlSysInfo` and `$pnlFullDiag`. This overwrote the authoritative assignment in `Pulse.ps1`. Removed; `Pulse.ps1` is now the single source of truth.
- **Network Diagnostics — hardcoded RGB colors replaced with theme variables** — timer tick log coloring used `[System.Drawing.Color]::FromArgb(...)` literals instead of `$Col*` theme variables, causing colors to break when switching between light and dark themes.
- **Hardware — degree symbol rendered as literal text** — temperature display showed `C` instead of `°C`. Fixed by using `[char]0xB0`.
- **Camera Connectivity — app log read unbounded** — `Get-Content` on the Pixellot application log read the entire file, which can exceed 500 MB. Now reads only the last 5 000 lines via `-Tail 5000`.
- **Camera Connectivity — `Get-AdapterPeakSpeedMbps` poll loop not cancellable** — the inner adapter polling loop had no cancellation check. Added `if ($sync.Cancelled) { break }` to respect the cancel signal.
- **Report Generator — full file read on every history load** — `Get-Content` read entire report files to parse result status; replaced with `Get-Content -Tail 100`. Duplicate DEGRADED-parsing code paths deduplicated into a single conditional chain.
- **WMI calls replaced with CIM** — `Get-WmiObject Win32_DiskDrive` and `Win32_LogicalDisk` replaced with `Get-CimInstance` equivalents in `DiskHealth.psm1`. `Get-WmiObject` is removed in PowerShell 7+.
- **Full Diagnostic — row and banner tint colors are now theme-aware** — previously hardcoded `FromArgb` values for fail/warn/ok row backgrounds and banners. Now use `$ColFailBg`, `$ColWarnBg`, `$ColOkBg` defined in both light and dark palettes in `UIHelpers.psm1`.
- **Full Diagnostic — `CardKeys` for Disk module corrected** — `CardKeys` previously included `"MemStatus"` which was never written, causing `Get-WorstCardStatus` to always return neutral. Fixed to `@("DiskStatus")` only.

### Changed

- **Help / About content rewritten** — all 11 help sections updated to match the current UI: tab names, card names, button labels, and known FAQ answers. Removed all references to stale features ("Isolate tab", "Copy Summary", "Phase 1/2/3/4", "Run ID").

---

## [1.0.19] - 2026-04-30

### Added

- **Launcher log** — `Pulse.bat` appends timestamped events to `%ProgramFiles%\Pulse\logs\launcher.log` on each run: version launched, errors, and exit status.
- **GUI session transcript** — `Pulse.ps1` calls `Start-Transcript` at startup, writing a per-session log to `Pulse_Results\logs\session_YYYYMMDD_HHMMSS.log`. Captures all PowerShell output and errors for the duration of the GUI session.

### Fixed

- **Launcher crash (red line, window closes)** — `Pulse.bat` now pauses with a clear error message if the UAC elevation request fails, if `Run.ps1` is missing after install, or if the application exits with a non-zero error code. Previously, the window closed immediately with no visible explanation.
- **`Build.ps1` comment corrected** — comment previously stated the build step was no longer used; corrected to explain why it is required (`.psm1` files open in Notepad on VPUs due to Windows file association).

---

## [1.0.18] - 2026-04-30

### Fixed

- **Build step restored** — `Pulse.bat` now runs `Build.ps1` → `Run.ps1` again. On VPUs, `.psm1` files cannot be dot-sourced directly — they open in Notepad instead of being executed. The Build step inlines all modules into a single `Run.ps1`, avoiding all `.psm1` execution entirely. The `[int]` layout-constant constraints already in `Pulse.ps1` prevent the `op_Subtraction` error that previously affected the combined file.

---

## [1.0.17] - 2026-04-30

### Changed

- **Rebrand to Pulse** — tool renamed from "VPU Diagnostic Tool Suite" to "Pulse — Pixellot Diagnostic Toolset". Main script renamed `VPUDiagnosticTool.ps1` → `Pulse.ps1`, launcher renamed to `Pulse.bat`, install directory changed to `%ProgramFiles%\Pulse`, output folder renamed `CameraLink_Results` → `Pulse_Results`.
- **Build step removed** — `Pulse.bat` now launches `Pulse.ps1` (modular dot-source) directly; `Build.ps1` / `Run.ps1` are no longer part of the deployment path. Fixes System Overview navigation, Camera Connectivity run, and Network Configuration results that were broken when all modules were inlined into a single file.
- **ETA labels** — estimated wait time shown next to each panel's Check button (Camera ~2 min, Network ~20 sec, Hardware ~5 sec, Disk ~30 sec, Services ~3 sec, Event Logs ~5 sec).

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
