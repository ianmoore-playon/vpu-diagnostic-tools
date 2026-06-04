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
- **Share a report to another Pulse over the LAN.** A new **Share over LAN**
  page lets you send this VPU's full diagnostic snapshot straight to another
  Pulse on the same network — no USB or file copy. On the receiving machine,
  turn on **Receive over LAN** and read off its five-word pairing code (e.g.
  "tiger maple river copper dust"); on the sending machine, type those words
  and hit **Send**. Received reports show up in an
  in-app inbox you can view, download, or delete. Receiving is off by default,
  so Pulse only opens to the network when you ask it to (Windows may prompt to
  allow access the first time).

### Changed
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

### Fixed
- **Camera Connectivity no longer errors out when a port is down.** A page that
  showed only "Internal Server Error" now loads normally and tells you why the
  port is down (disabled / driver fault / no signal).
- **Cable unplug/replug now shows in ~2 seconds, not ~15.** Link status is read
  near-live instead of from a cached snapshot, so disconnecting or reconnecting
  a camera updates the port almost immediately.
- **The blue "connecting" state shows again on reconnect.** Plugging a cable
  back in now flashes the establishing-link cue before going green, instead of
  jumping straight from gray to linked.

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
