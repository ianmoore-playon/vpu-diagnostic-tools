# Pulse.WPF V1 Lab Checklist

Use this checklist on a real VPU after installing the latest public release.
Capture notes in the support bundle whenever a step behaves unexpectedly.

## Install / Launch

- Run the public one-liner:

  ```powershell
  irm https://raw.githubusercontent.com/ianmoore-playon/pulse-releases/main/install.ps1 | iex
  ```

- Confirm Pulse launches from the extracted latest release.
- Close Pulse and re-run the one-liner. Confirm it updates/launches cleanly
  without leaving a stale copy running.

## Startup Baseline

- Launch Pulse and let the baseline finish.
- Confirm the Dashboard baseline summary is not stuck on "Baseline pending".
- If Windows is still settling the uplink, confirm Network shows a warning
  that the startup network baseline was deferred instead of an all-failed
  critical result.
- Close and reopen Pulse. Confirm the Dashboard restores the previous baseline
  summary before the next baseline completes.

## Dashboard / Findings

- Confirm top findings are actionable and clicking a finding navigates to the
  owning panel.
- Re-run the baseline from Dashboard and confirm findings do not duplicate.
- Generate a Support Bundle from Dashboard and confirm Reports opens with the
  new bundle selected.

## Panel Smoke Tests

- System Overview: confirm identity, Pixellot software, hardware/peripherals,
  storage, network adapters, and software inventory populate.
- Network: click Run Test after the VPU is fully online. Required ports and
  domains should reflect the real venue network state.
- Camera Connectivity: confirm four camera ports render with live link/device
  states and Save Snapshot writes a report.
- ScoreConnect: confirm local API detection, scoreboard settings, serial ports,
  and live feed status make sense for the unit.
- Services: on a freshly booted VPU, confirm missing Pixellot processes show
  the fresh-boot grace notice/watchdog warning rather than an immediate
  Critical. After startup settles, refresh and confirm real missing processes
  become Critical and restart actions remain guarded.
- Disk Health: confirm SMART, volume space, Pixellot paths, and disk events
  populate.
- Event Viewer: confirm filtered events load and "Open Windows Event Viewer"
  reports success/failure in the app log.
- Reports: confirm `.txt` reports and `.zip` support bundles list newest-first,
  preview correctly, and folder/log buttons show visible status.

## Evidence Package

- Generate a Support Bundle from Reports.
- Confirm the zip contains:
  - `Pulse-Support-Summary.txt`
  - `Panels/*.txt`
  - `Logs/Pulse-log-tail.txt`
  - today's full `Pulse-YYYYMMDD.log` when available
- Confirm the summary's finding count matches the Dashboard's baseline
  finding count.

## Release Readiness Notes

- Record any false Critical finding.
- Record any button that appears to do nothing.
- Record any panel that stays empty without an explanation.
- Record baseline duration and whether the UI remains responsive during it.
