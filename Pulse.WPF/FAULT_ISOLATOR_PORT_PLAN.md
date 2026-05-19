# Fault Isolator — WPF Port Plan

**Status:** draft for review. No code changes from this plan yet.
**Target:** v0.8 (separate ship from the v0.7 scoreboard work).
**Source:** `legacy-powershell` branch, `Modules/CameraConnectivity.psm1`
lines ~2300-2900.
**Surface:** Camera Connectivity tab.

## Goal

Port the four-phase fault-isolation wizard from the legacy PowerShell
tool into Pulse.WPF as a **modal dialog** opened from the Camera
Connectivity panel. The wizard walks the tech through swap tests
that isolate a camera-link fault to one of: **NIC port**, **cable**,
**camera (CHU)**, or **NIC hardware / motherboard**.

The legacy implementation is field-proven (it shipped through v1.0.x
of the PS tool). The port preserves the same state machine, copy,
and result wording — just re-skinned to WPF + MVVM.

## The four phases (transcribed from legacy)

| # | Phase | Setup | If link at 1 Gbps | If still degraded |
|---|---|---|---|---|
| **1** | **Baseline** | Tech selects the suspect port (the one showing 100 Mbps). Pulse reads current link speed. | **Port is already healthy** — no fault on this port. Tech picks a different port or runs the full diagnostic. | Capture base speed. Continue to Phase 2. |
| **2** | **NIC Port test** | Tech moves the **same cable + camera** from the suspect port to a different (known-good) NIC port — the **test port**. Pulse pre-checks that the test port is itself healthy *before* the move so a self-faulted test port doesn't invalidate the test. | **NIC PORT FAULT** — the fault followed the port. Replace / repair the NIC port. → Phase 4 concluded. | Continue to Phase 3 (fault is in cable or camera). |
| **3** | **Cable test** | Tech stays on the test port + original camera. Swaps **cable only** for a known-good cable. | **CABLE FAULT** — the cable / termination is bad. Replace the cable end-to-end. → Phase 4 concluded. | Continue to Phase 4 (fault is in camera). |
| **4** | **Camera test** | Tech stays on the test port + new cable. Swaps **camera only** for a known-good unit. | **CAMERA (CHU) FAULT** — the original camera is bad. Replace the camera unit. → Phase 4 concluded. | **NIC / MOTHERBOARD FAULT** — known-good equipment still fails on the test port. Escalate to hardware repair. → Phase 4 concluded. |

After Phase 4 (any conclusion), the wizard's final action button is
**"Run Full Diagnostic"** — closes the modal, returns to the Camera
Connectivity tab, kicks off a full re-run so the result is captured
in the run history.

### Per-phase invariants

- **Pre-check before Phase 2.** If the chosen test port is itself
  showing degraded speed (< 1 Gbps) *before* the cable+camera move,
  prompt the tech: "Test port already degraded — Phase 2 will be
  unreliable; pick a different test port or proceed anyway?". The
  legacy implementation uses a MessageBox; the WPF port uses a
  Material Dialog confirmation.
- **History.** Every phase's outcome is recorded with `Add-GuideHistory`
  (Phase name, configuration string, speed reading, verdict text,
  severity Pass / Warn / Info / Fail). Survives the wizard's lifetime
  so the tech can scroll back through what they tried.
- **Session save.** Conclusion phases (NIC, Cable, Camera, NIC-MB)
  trigger `Save-GuideSession` which writes to the per-run report.
  The WPF port writes to the same `%LOCALAPPDATA%\Pulse.WPF\Reports`
  directory the existing ReportsService uses.
- **Reset.** The wizard exposes a "Start Over" link that returns to
  Phase 0 (port-selection) without closing the modal.

## Architecture

### Modal dialog approach

Per the v0.7 decision — modal dialog over inline expander. Rationale:

- The wizard owns the tech's attention while running. A modal closes
  the focus mode cleanly when the conclusion is reached.
- The Camera Connectivity panel is already dense (port tiles, status
  cards, live log, recommendations). Adding a 6-step inline wizard
  would push everything below the fold on a 1366×768 LogMeIn session.
- The wizard's state machine is genuinely separate from the live
  monitoring loop — they shouldn't share visual real-estate.

Concretely: `FaultIsolatorDialog.xaml` + `FaultIsolatorDialog.xaml.cs`
opened via `dialog.ShowDialog(Owner = MainWindow)`. Sized ~720×640
so it fits inside the parent at 1366×768 with breathing room.

### New types

```csharp
public enum FaultIsolatorPhase
{
    PickPort         = 0,  // tech is selecting the suspect port
    Baseline         = 1,  // baseline completed, awaiting Phase 2
    NicPortTest      = 2,  // awaiting Phase 3
    CableTest        = 3,  // awaiting Phase 4
    Concluded        = 4,
}

public enum FaultConclusion
{
    None,
    NicPort,                // Phase 2 → fault followed the port
    Cable,                  // Phase 3 → fault followed the cable
    Camera,                 // Phase 4 → fault followed the camera
    NicHardware,            // Phase 4 → fault persists with known-good
    BaselineHealthy,        // Phase 1 → port wasn't actually degraded
}

public class FaultIsolatorHistoryRow
{
    public DateTime  TimestampLocal { get; set; }
    public string    PhaseName      { get; set; }   // "Phase 1 - Baseline" etc.
    public string    Configuration  { get; set; }   // "Port: X | Cable: original | Camera: original"
    public string    SpeedReading   { get; set; }   // "1 Gbps" / "100 Mbps" / "No link"
    public string    Verdict        { get; set; }   // free-text verdict
    public string    Severity       { get; set; }   // "Pass" | "Warn" | "Info" | "Fail"
}

public class FaultIsolatorViewModel : ObservableObject
{
    public FaultIsolatorPhase Phase { get; }
    public FaultConclusion    Conclusion { get; }
    public string PhaseTitle           { get; }    // "PHASE 2 - DOES THE FAULT FOLLOW THE NIC PORT?"
    public string PhaseInstruction     { get; }    // "Move the same cable + camera to a different NIC port..."
    public string ActionButtonLabel    { get; }    // "Start Baseline" / "Check Now" / "Run Full Diagnostic"
    public bool   ActionButtonEnabled  { get; }
    public bool   IsPickingSuspectPort { get; }    // Phase 0 - cboSuspectPort visible
    public bool   IsPickingTestPort    { get; }    // Phase 1 - cboTestPort visible

    public ObservableCollection<PortChoice>          SuspectPortChoices { get; }
    public ObservableCollection<PortChoice>          TestPortChoices    { get; }
    public PortChoice SelectedSuspectPort { get; set; }
    public PortChoice SelectedTestPort    { get; set; }

    public ObservableCollection<FaultIsolatorHistoryRow> History { get; }

    public ICommand ActionCommand    { get; }
    public ICommand StartOverCommand { get; }
    public ICommand CancelCommand    { get; }
}

public class PortChoice
{
    public string AdapterName { get; set; }       // "Ethernet 3"
    public string DisplayLabel { get; set; }      // "Ethernet 3  · FAULT"
    public bool   IsFlaggedFault { get; set; }    // for dropdown styling
}
```

### State machine (pure C#)

The legacy `$btnGuideAction.Add_Click` `switch ($script:guide.Phase)`
block transcribes to a single async method:

```csharp
public async Task RunActionAsync()
{
    switch (Phase)
    {
        case FaultIsolatorPhase.PickPort:        await DoBaselineAsync();        break;
        case FaultIsolatorPhase.Baseline:        await DoNicPortCheckAsync();    break;
        case FaultIsolatorPhase.NicPortTest:     await DoCableCheckAsync();      break;
        case FaultIsolatorPhase.CableTest:       await DoCameraCheckAsync();     break;
        case FaultIsolatorPhase.Concluded:       LaunchFullDiagnostic();         break;
    }
}
```

Each Do* method:
1. Disables the action button, sets label to "Checking…".
2. Reads the live link speed for the relevant port via
   `INetworkService.GetCameraPortLinkSpeedBpsAsync(portName)` — a new
   method we'll add (the existing `NetworkService.GetCameraPortsAsync`
   already returns this info; we just need a one-shot variant).
3. For Phase 2 only: runs the **test-port pre-check** first; if the
   test port is < 1 Gbps and the tech hasn't acknowledged, pop the
   confirmation dialog.
4. Computes verdict, appends to `History`, calls `Show-GuideResult`
   equivalent (updates ResultText + Severity bindings).
5. Advances `Phase`, updates `PhaseTitle` + `PhaseInstruction` +
   `ActionButtonLabel`.

No background runspaces needed — each Do* is a single async call to
the existing NetworkService.

### XAML layout

Single dialog, fixed size, four regions stacked vertically:

```
+---------------------------------------------------------------+
|  Camera Fault Isolator                              [×]       |
|  Walk through cable / NIC / camera swap tests to isolate      |
|  the source of a degraded camera link.                        |
+---------------------------------------------------------------+
|  STEP DOTS                                                    |
|  ●——●——○——○——○   (filled dots = phases visited)               |
|  Baseline · NIC Port · Cable · Camera · Conclusion            |
+---------------------------------------------------------------+
|  PHASE 2 — DOES THE FAULT FOLLOW THE NIC PORT?                |
|  Move the same cable + camera to a different NIC port.        |
|  Then press Check.                                            |
|                                                               |
|  Suspect port: [Ethernet 3 · FAULT  ▼]    (Phase 0 only)      |
|  Test port:    [Ethernet 2          ▼]    (Phase 1 only)      |
+---------------------------------------------------------------+
|  RESULT (shown after each phase)                              |
|  [severity icon] Phase 2: 1 Gbps — Fault follows the port.    |
|  Replace / repair the NIC port. Phase 4 concluded.            |
+---------------------------------------------------------------+
|  HISTORY (scrollable, newest at top)                          |
|  15:14:22  Phase 2 - NIC Port Test  PASS   1 Gbps             |
|            Port: Ethernet 2 · Cable: orig · Camera: orig      |
|  15:13:05  Phase 1 - Baseline       FAIL   100 Mbps           |
|            Port: Ethernet 3 · Cable: orig · Camera: orig      |
+---------------------------------------------------------------+
|  [Start Over]                  [Cancel]   [Action button]     |
+---------------------------------------------------------------+
```

### Entry point on the Camera Connectivity panel

Add a button to the existing Recommendations / Actions row:
`Open Fault Isolator →`. When clicked:

1. Pre-select the first port currently showing FAIL or DEGRADED as
   the suspect port (legacy behaviour — `$btnGoGuide.Add_Click`
   block).
2. Open the dialog with `Owner = MainWindow` so it modals correctly.
3. On dialog close (regardless of outcome), the Camera Connectivity
   panel refreshes once so any new state from the wizard's
   `Run Full Diagnostic` action is reflected.

If no port is currently flagged FAIL, the button stays enabled — the
tech can still pick a port manually from the dropdown.

## Phased rollout

Single ship — the wizard isn't worth splitting. v0.8.0-beta covers
the full port. Sub-tasks:

1. **`FaultIsolatorViewModel.cs`** + types — ~250 LOC
2. **`FaultIsolatorDialog.xaml` + .cs`** — ~300 LOC XAML + 50 LOC code-behind
3. **`INetworkService.GetCameraPortLinkSpeedBpsAsync(portName)`** —
   ~25 LOC service method (one-shot variant of existing port-scan)
4. **Entry button** on `CameraConnectivityView.xaml` — ~10 LOC
5. **Wire history rows into `ReportWriter`** so the wizard run
   appears in the Reports panel like every other panel's output
6. **Camera Connectivity panel refresh on dialog close**
7. **End-to-end smoke test on the test VPU** — verify each phase
   transitions correctly, the pre-check warning fires when the test
   port is already degraded, and the "Run Full Diagnostic" exit
   action returns to the right tab.

Estimated ~700 LOC total; one focused ship.

## Edge cases (preserved from legacy)

- **Suspect port becomes healthy mid-wizard** (e.g. tech reseats the
  cable while Pulse is on Phase 0). Phase 1 baseline reads 1 Gbps
  → "BASELINE — PORT HEALTHY" verdict, no further phases, button
  text changes to "Recheck Port" so the tech can re-run baseline
  without restarting.
- **Test port itself degraded before the move.** Phase 2 pre-check
  prompts the tech to either pick a different test port or proceed
  anyway. Acknowledged proceed-anyway logs a Warn row in History so
  the conclusion stays in context.
- **Tech closes the dialog mid-wizard.** Discard the wizard's
  in-progress state. The History captured up to that point is still
  written to the per-run report so escalation has the partial
  results.
- **`Run Full Diagnostic` exit action.** Closes the dialog, navigates
  to Camera Connectivity, kicks the full diagnostic. The WPF
  equivalent: dialog `DialogResult = true`, owner reads a
  "ReRunFullDiagnostic" hint property on the VM and dispatches.
- **No detected NICs.** The suspect-port dropdown is empty. Show a
  guard banner: "No camera NICs detected. Open the Camera
  Connectivity panel and run a baseline scan first." Disable the
  Start button. Matches the legacy behaviour where the wizard would
  no-op silently.

## Open questions — decided 2026-05-19

1. **History persistence: separate file.** Each wizard run writes
   `FaultIsolator-YYYYMMDD-HHMMSS.txt` to the existing Reports
   directory. Easy to attach to a ticket; shows up alongside the
   other per-panel reports in the Reports panel.
2. **Dialog modality: modal to MainWindow.** Whole-shell modality so
   the tech is fully focused on the wizard while it's running.
3. **Conclusion default action: preserve.** "Run Full Diagnostic"
   stays as the primary action button on the conclusion phase
   (matches the legacy behaviour). Cancel still available.
4. **Entry button: always visible.** The "Open Fault Isolator →"
   button on the Camera Connectivity Recommendations card stays
   enabled even when no port is flagged FAIL — techs can dry-run
   the wizard.

All four answers unblock implementation.

## Next decision

If the plan reads right, the first concrete step is implementation —
this is a single-ship effort. Estimated 1-2 days of focused work to
v0.8.0-beta on the test VPU.

If you want adjustments before implementation — different layout,
dropped phases, different conclusion behaviour — say so here and
I'll revise before any code lands.
