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

## [0.3.1] - 2026-06-11

### Changed
- The Audio tab is temporarily hidden while audio diagnostics are being
  finished. No loss of function — audio checks were not yet in field use.

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
