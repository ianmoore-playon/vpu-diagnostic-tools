# Pulse.Web — Changelog

User-facing changes to Pulse.Web, newest first. This is the source the update
flow shows testers when a new build is available.

**How this is maintained (read before editing):**
- When you ship a change a tester would notice (feature, fix, or visible
  change), add a one-line bullet under `## [Unreleased]`, grouped under
  **Added**, **Changed**, or **Fixed**. Write it for a field tech, not a
  developer — "Fixed false low-speed warning on OCR camera ports", not the
  commit subject.
- At a beta/main promotion, rename `[Unreleased]` to the released version
  (e.g. `## [0.2.0] — 2026-06-15`) and start a fresh empty `[Unreleased]`.
  That version's section becomes the GitHub release notes the update flow
  displays.
- Dev auto-tags don't use this file — they get notes generated from commit
  messages automatically. Curate here for the builds testers and the fleet
  actually read (beta / main).

Format follows [Keep a Changelog](https://keepachangelog.com/). Versions track
`Pulse.Web/VERSION`.

## [Unreleased]

### Added
- **New "Power Events" tab — see why a VPU restarted, and whether one is pending.**
  Under System Information, Power Events shows the recent restart/shutdown history
  with the cause of each (planned vs. unexpected, who triggered it, and the
  reason), plus an up-front "reboot pending" banner and uptime. Reboots Pulse
  itself triggered are clearly labeled, so you can tell at a glance that an
  "unprovoked" restart came from Windows, a driver install, or an update — not
  from Pulse. Answers the "the box rebooted on its own" ticket in one click.
- **Pulse now catches the internet being plugged into a camera port.** On a VPU
  the internet/venue cable must go to the motherboard network port — the 4-port
  NIC is cameras-only. If the uplink is found on a camera-NIC port instead,
  Pulse raises a CRITICAL with the fix (move the cable to the motherboard port,
  enable it; the Wi-Fi card is for the Pixellot Connect app and stays enabled),
  and notes if the motherboard port is disabled or unplugged. It tells the
  motherboard port apart from the camera card by its hardware (PCI) location, so
  it works even when both use the same Intel chipset.
- **Pulse now flags a disabled Wi-Fi card.** The Wi-Fi card is how the Pixellot
  Connect app reaches the VPU. If it's been disabled in Windows, Pulse raises a
  warning with how to turn it back on — so a unit that's invisible to Connect is
  easy to spot. (Units without a Wi-Fi card aren't flagged.)
- **Restart Pulse or reboot the VPU from Settings.** The Settings page has a new
  Reboot Pulse panel. "Restart Pulse app" relaunches Pulse if the page is stuck
  or acting up — the VPU and any recording keep running, and the page reloads
  itself once Pulse is back. "Reboot VPU" restarts Windows on the unit; it
  interrupts any active recording, so it asks you to confirm first.
- **Disks now shows real drive wear and SMART health, not just Healthy/Unhealthy.**
  Each physical drive lists its SSD wear (percent of rated write-life used),
  temperature, and power-on hours next to the health badge. Pulse raises a
  warning when a drive crosses 80% wear, and a critical when a drive reports a
  SMART pre-failure or uncorrectable errors — so you can swap a dying SSD before
  it quits mid-game instead of after.
- **Network Test now lists every wired port, not just the internet uplink.** A new
  "Wired Ports" table shows each Ethernet port — the motherboard uplink and each
  camera-NIC port — with its link state, speed, and error/discard counts, so a
  bad cable or dirty switch port on a non-uplink port is no longer invisible. The
  live network monitor also gained a per-interface table (queue depth, errors,
  and packet rates per NIC).

### Changed
- **"Disk & Driver Errors" now catches filesystem corruption.** The disk-events
  panel used to watch only the disk / NVMe / storage-controller logs; it now also
  includes NTFS and volume-manager events (the "run chkdsk — the file system is
  corrupt" kind), which are the ones that usually come right before data loss.
- **Clearer Stream Readiness wording.** The middle verdict now reads "WARNING"
  instead of "WARN", and its summary explains it plainly: "Will likely stream,
  but there are issues found that should be addressed to improve the system's
  reliability."
- **Slimmed down the Settings page.** Settings now shows just Software Update and
  the new Reboot Pulse panel. The ScoreConnect URL, live-metrics interval, log
  file paths, and the Run All Diagnostics button were removed to keep the page
  focused. (Generating a report from **Exports** still re-runs every check.)
- **Reorganized the sidebar into six clearer groups.** Tabs are now grouped as
  Triage, Troubleshooting, Pixellot Configuration, System Information, Data
  Logs, and Pulse. A few tabs were renamed to say what they do —
  "Network Test", "ScoreConnect", "Service Status", "Disks",
  "Windows Events", and "Exports". Nothing moved out of reach; bookmarks/links
  still work.
- **Split the big "System Overview" tab into focused tabs.** Hardware (CPU,
  memory, graphics, storage), Applications (installed software + concern
  flags), and Environment (Windows OS, locale, uptime, users, peripherals) are
  now separate tabs, and Pixellot version + hardware-compatibility moved to a
  new Pixellot Software tab. Old "System Overview" links open Hardware.
- **Split the Pixellot Configuration tab into three.** Pixellot Software
  (version, install/agent, registry, and the Restart Agent button), Camera
  Hardware (per-camera role / IP / MAC / firmware / TV mode / serial), and
  Camera Calibrations (multisport + OCR scoreboard status) are now separate
  tabs. Old "Pixellot Configuration" links open Pixellot Software.
- **New Data Logs tabs.** Pixellot Logs (the Pixellot log-directory scan, moved
  off Windows Events into its own tab) and Pulse Logs (Pulse's own script-call
  and server logs) now live under Data Logs. The old slide-up log drawer at the
  bottom of the window is gone — its script + server logs are now the full-page
  Pulse Logs tab.
- **New Help tab.** A plain-English page covering what Pulse is, how to read the
  Dashboard, and the first things to try in the field, under the Pulse group.
- **The Wi-Fi warning now explains Wi-Fi's real job.** When the VPU is running
  its internet over Wi-Fi, the message now notes the Wi-Fi card is meant for the
  Pixellot Connect app — move the internet to the motherboard Ethernet port.
- **New Pixellot Configuration tab (under SYSTEM)** — camera calibration, firmware,
  and on-box config at a glance: install/agent version with the hardware-compatibility
  banner, a per-camera table (role / IP / MAC / firmware / TV mode / serial / calibration),
  main-camera multisport calibration (which sports, last calibrated) and OCR scoreboard
  calibration status, plus a one-click "Restart Pixellot Agent" action.
- **New Stream Readiness check.** Pulse now rolls every diagnostic into one
  PASS / WARN / FAIL call on whether the VPU can stream tonight's game, shown at
  the top of the Dashboard with the exact blockers and risks behind the verdict.
  FAIL means "don't expect a clean broadcast tonight."
- **Clearer wording across Pulse.** Findings and panels now lead with plain
  language and the fix — fewer unexplained acronyms up front, with the technical
  detail (exact values, commands, port numbers) still right there in the detail.

### Fixed
- **No more false "can't reach gateway" alarm when the gateway just ignores
  pings.** Plenty of routers and firewalls are set to drop pings (ICMP) to
  themselves while still routing traffic perfectly. Pulse used to read that as a
  CRITICAL "VPU can't reach its gateway — check the cable/switch/VLAN," sending
  techs to chase a fault that isn't there. Now, when the VPU is already reaching
  the internet, an unanswered gateway ping is shown as an informational note
  ("gateway doesn't answer ping, but traffic is routing normally") instead of a
  critical. A real dead gateway — where the internet is also unreachable — still
  raises the critical.
- **No more false "DNS blocked / can't resolve any hostname" alarm.** The DNS
  check was probing whatever resolver it found first across *all* network
  adapters — so a stale resolver on a disconnected or secondary adapter (e.g. a
  camera NIC) could be tested instead of the one the VPU actually uses, fail,
  and raise a critical while every domain on the same screen was resolving fine.
  Pulse now tests the resolver on the active internet uplink, and never reports
  DNS as blocked when name resolution is demonstrably working.
- **The Network panel no longer comes up blank / "no internet" on some VPUs.**
  The new adapter-role check was scanning every network device Windows has ever
  seen (VPUs accumulate dozens of stale ones), which could time out the whole
  network check — leaving the panel empty and falsely reporting "VPU has no
  internet connection." It now reads hardware location only for the adapters
  actually present, and a network-check hiccup no longer masquerades as "no
  internet" (Pulse says a check couldn't complete instead).
- **Pulse now opens directly in Chrome on launch.** On VPUs with no default
  browser set, Windows used to pop a "How do you want to open this?" picker
  (with Internet Explorer as the first option) instead of opening Pulse. The
  launcher now opens Chrome explicitly — no dialog, no IE.
- **The launcher no longer looks frozen while starting.** It used to run the
  server in the foreground window (a debug aid), so the window sat there
  showing the live server log and seemed stuck until you pressed Ctrl+C. It now
  starts the server in the background, opens the browser, and closes the window.
  Launch failures still stop and show the error, and everything is logged.

### Changed
- **Port Connectivity tiles now list in numeric order, two per row.** Within
  Required and within Optional, ports run ascending (53, 123, 443…) and wrap in
  pairs, so a given port is easy to find at a glance.
- The Audio tab is temporarily hidden while audio diagnostics are being
  finished. No loss of function — audio checks were not yet in field use.

### Fixed
- **A blocked Zixi streaming port (UDP/2088) is now flagged as a real outage.**
  Pulse used to treat UDP/2088 as one of three interchangeable streaming paths,
  so blocking it only showed a yellow "no failover" note. In the field the
  live broadcast rides UDP/2088 with no failover — so a block there now reads as
  a red "Streaming is blocked — the VPU can't broadcast." The failover/"backup
  connection" wording now applies only to the two port-443 paths (UDP/443 and
  the TCP/443 tunnel), which do back each other up.

### Fixed
- Fixed an error that could appear on the Audio screen and during full
  diagnostic collection (the audio device check failed to return results on
  some VPUs).

## [0.3.0] - 2026-06-11

### Added
- **Pulse records which VPUs it's run on.** On launch Pulse sends a small
  identity-only check-in — hostname, serial, venue, model, version — so we can
  see which units Pulse has been used on. It never runs on demo/dev machines and
  fails silently if the network blocks it; Pulse works exactly the same either way.
- **Share a report to another Pulse over the LAN.** A new **Share over LAN**
  page lets you send this VPU's full diagnostic snapshot straight to another
  Pulse on the same network — no USB or file copy. On the receiving machine,
  turn on **Receive over LAN** and read off its five-word pairing code (e.g.
  "tiger maple river copper dust"); on the sending machine, type those words
  and hit **Send**. On a VPU with more than one network, pick which one to
  share from the dropdown (so the other machine can actually reach it), and
  Pulse opens the Windows firewall for the share port automatically (one
  approval prompt). Received reports show up in an
  in-app inbox you can view, download, or delete. Receiving is off by default,
  so Pulse only opens to the network when you ask it to (Windows may prompt to
  allow access the first time).
- **Every port and domain Pulse tests now explains what happens if it's
  blocked.** Hover an entry in Port Connectivity or Domain Reachability — or
  open the matching issue — to see the real-world impact (e.g. the game won't
  stream, or scoreboard data won't come through). Makes it obvious which
  blocked endpoints actually matter at a given venue and which are harmless.

### Changed
- **Fixed the System Disk gauge reading the wrong number.** The dashboard donut
  was showing a whole-machine average across all drives, so a large near-empty
  D: dragged it down (e.g. **9%** when the C: system drive was really ~50% full).
  It now shows the **C: (system) drive's own usage**, matching the "free of"
  figure beneath it. The storage card also labels both drives by role —
  **System (C:) — OS & Pixellot** and **Recordings (D:) — local VOD storage** —
  so you can watch the recordings drive fill up.
- **System Overview cleanups (UX audit).** Install date shows as a plain date
  instead of a raw timestamp; the install-date and locale fields are now
  populated; blank hardware values show "—" instead of "null GB"; GPU cards
  label each adapter **Dedicated**/**Integrated** (not color-only); the
  hardware-compatibility note reads in plain language; and the software filter
  shows a "no matches" message. Wide tables now scroll on narrow screens instead
  of squashing the page. (Also fixes a stray "undefined GB free" on Disk &
  System Health.)
- **The build version now shows on the loading screen**, right under the Pulse
  logo — so you can see exactly which build you're on at a glance (handy when
  reporting an issue).
- **Simpler launchers.** One per channel, clearly named: `run_pulse.bat`
  (production), `run_pulse_beta.bat` (beta), `run_pulse_dev.bat` (dev). The dev
  launcher now always pulls the latest `dev`-branch commit instead of a stale
  tagged release. (The old `_web_`-prefixed names and the duplicate Pulse.WPF
  launchers are gone — WPF is deprecated.)
- **Pulse no longer leaves a desktop icon** — launch from the Start Menu
  instead (press **Win**, type "pulse", hit Enter). Cleaner footprint on the
  VPU. Existing installs auto-clean up the old desktop shortcut on next launch.
- **Removed the raw cameras.cfg table from Camera Connectivity.** Camera
  identity already shows on each port tile — the duplicate config dump just
  added clutter.
- **Clearer VPU orientation diagram + a port-layout toggle.** The "upright" and
  "on its side" pictures are now the same drawing (one is just rotated), so they
  can't disagree. New **Flip layout** button rotates the 4-port LED row between
  horizontal and vertical to match how the VPU is actually mounted.
- **Tighter Fault Isolator wording.** Phase steps, results, and conclusions are
  shorter and less repetitive — the same guidance, less to read on each screen.
- **Port Connectivity redesigned as port-led tiles.** Each tile leads with its
  protocol/port (e.g. `TCP/443`) and a Pass/Blocked status; services that share
  a port are combined into one tile (the HTTPS endpoints; Scorebot's port
  range), grouped into Required and Optional with a one-line summary at the top,
  replacing the old two-column TCP/UDP grid. Optional services (RTMP, Scorebot)
  are de-emphasized so a blocked optional port no longer looks like a failure.
- **Speed Test moved out of Advanced Diagnostics** to sit right under the
  internet adapter and domain checks — where you'd look for it first.
- **Internet Adapter details are grouped into labeled sections** (IP
  Configuration, Link, Connectivity, Time Sync) so the card reads top to bottom.
  Local Network Health regained its section icon, and the 4 / 10 / 20 / 50 ping
  presets now have a "Ping count" label.

### Fixed
- **"Install ScoreConnect III" no longer gets stuck at 5%.** The installer now
  opens in a visible window you complete on screen — approve the Windows
  administrator prompt, then follow the installer's prompts — and Pulse confirms
  ScoreConnect III is running once it finishes. If you decline the prompt or it
  stalls, Pulse now says so and offers **Retry** instead of spinning forever.
  (Also fixes the garbled text that used to appear in the progress message.)
- **Camera Connectivity no longer errors out when a port is down.** A page that
  showed only "Internal Server Error" now loads normally and tells you why the
  port is down (disabled / driver fault / no signal).
- **Cable unplug/replug now shows in ~2 seconds, not ~15.** Link status is read
  near-live instead of from a cached snapshot, so disconnecting or reconnecting
  a camera updates the port almost immediately.
- **The blue "connecting" state shows again on reconnect.** Plugging a cable
  back in now flashes the establishing-link cue before going green, instead of
  jumping straight from gray to linked.
- **Far fewer false network alarms.** Pulse no longer reports "no internet" on
  venues that simply block ping (it confirms reachability through real services
  instead); the DNS check now tests the VPU's actual configured resolver rather
  than a public one (8.8.8.8) that locked-down school networks block on purpose;
  harmless CDN address differences are no longer flagged; and the
  gateway-instability threshold was loosened so normal latency doesn't trip it.
- **Wi-Fi is only flagged when it's actually carrying the internet uplink** —
  idle or virtual wireless adapters no longer raise a warning, and the guidance
  now points to switching to Ethernet rather than disabling the adapter.
- **UDP port checks no longer show green on silently blocked ports.** The Zixi
  streaming ports (UDP 443 / 2088) previously passed whenever the firewall gave
  no answer at all — exactly what most school firewalls do when they block a
  port — so a venue could show all-green while streaming was actually blocked.
  Pulse now requires a real reply from Pixellot's echo server to pass (with
  retries so one lost packet doesn't cause a false alarm). If Pulse and another
  port tester now disagree, believe the one showing the failure.
- **The LogMeIn check now tests the real remote-access service.** It previously
  tested logmein.com, which now points at GoTo's marketing website — so it could
  pass while the actual LogMeIn gateways were blocked. It now tests
  secure.logmein.com, which lives on the same GoTo network the VPU's real
  LogMeIn sessions use.
- **Port Connectivity no longer cries "stream fails" when streaming actually
  works.** Pixellot can broadcast over any of three paths — UDP/2088 (primary),
  UDP/443 (backup), or the TCP/443 tunnel — so the stream only fails if all
  three are blocked. Pulse now treats one blocked streaming path with another
  still open as a yellow "no failover" warning, not a red failure, and only
  flags a true "stream cannot broadcast" critical when every path is down.
  (The UDP/443 row is also renamed from the misleading "Zixi QUIC" to "Zixi
  Backup.")
- **Network checks now read as one panel: ports on the left, domains on the
  right.** Port Connectivity and Domain Reachability share a single card.
  Each port tile leads with the port number and protocol (no hostnames — the
  domain detail all lives in the right-hand column), so the left is a clean
  "is this port open" view and the right is the full domain list.

## [0.2.1] - 2026-06-04

### Changed
- Removed the Repair Tools panel (DISM, System File Checker, and chkdsk) from
  the Disk & System Health page for this release. These run long or change
  boot state and shouldn't be triggered without guidance.

## [0.2.0] - 2026-06-02

### Added
- **Dashboard now flags missing main cameras.** If the VPU is configured for
  more cameras than are actually reporting on the camera NIC, you get a
  CRITICAL finding (none detected) or a WARNING (some missing, e.g.
  "1 of 2 main cameras detected"). Click it to jump straight to Camera
  Connectivity. Stays silent when expectations can't be read — never guesses.

### Changed
- **Launcher fails loud while we're in beta.** If something goes wrong on
  launch, the window stays open with the actual error/traceback instead of
  closing silently — and the browser still opens automatically once Pulse
  is ready.

### Fixed
- **Garbled box-line characters** in the launcher console output on VPUs
  whose console codepage isn't UTF-8. Output is now plain ASCII everywhere.

## [0.1.0] - 2026-05-29

### Added
- **Check for Update** in Settings — Pulse can now detect a newer build on its
  channel, install it, and restart on its own, with this changelog shown
  before you update. No more re-running the launcher by hand.
- **Full diagnostic report** now bundles the unit's complete state — every
  collector plus the detected cameras and Pulse's own findings — with a
  provenance header (which VPU, when, what build) for offline review.
- Launcher now **runs as Administrator** automatically so every diagnostic
  reads at full capability.

### Changed
- Findings are grouped by severity and each is tagged **CRITICAL** or
  **WARNING**; clicking one jumps to the relevant tab.
- The dashboard labels the gateway NIC as the **Motherboard Network Port**
  instead of an opaque "Ethernet 13".

### Fixed
- **OCR / scoreboard camera ports no longer raise a false low-speed warning** —
  they run at 100 Mbps by design; only the main 4K heads expect 1 Gbps.
- Sub-gigabit warnings now name the **physical port (Port 1–4)** and route to
  Camera Connectivity instead of Network.
- A disconnected port with stale ARP no longer reports a phantom camera/OCR.
