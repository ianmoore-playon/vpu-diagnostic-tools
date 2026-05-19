using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Input;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Camera Fault Isolator state machine.
    ///
    /// 4-phase swap test ported from the legacy PowerShell tool. The state
    /// transitions, verdict copy, and severity values match the source of
    /// truth at <c>legacy-powershell:Modules/CameraConnectivity.psm1</c>
    /// (lines ~2660-2810). The plan + agent review live at
    /// <c>Pulse.WPF/FAULT_ISOLATOR_PORT_PLAN.md</c>.
    ///
    /// Threading model: every Do* method is async and uses the existing
    /// <see cref="INetworkAdapterService.GetCameraPortsAsync"/> to read per-
    /// port link speed. While the wizard is open the caller pauses the live
    /// <see cref="CameraNicMonitor"/> so concurrent reads + the monitor's
    /// transition debounce don't conflict with the wizard's poll loops.
    /// </summary>
    public class FaultIsolatorViewModel : ObservableObject
    {
        // Poll budgets mirror legacy Get-GuideLinkSpeed.
        // Live-phase checks run up to 12 s peak-hold and short-circuit on 1 Gbps;
        // the Phase-2 test-port pre-check is capped at 4 s.
        private const int LivePhasePollSeconds = 12;
        private const int PreCheckPollSeconds  = 4;
        private const int PollIntervalMs       = 1_000;

        private readonly INetworkAdapterService _net;
        private readonly Action<FaultConclusion> _onConcluded;   // host signal to fire SaveSnapshotCommand
        private readonly Action _requestRunFullDiagnostic;       // Conclusion phase exit action

        public FaultIsolatorViewModel(
            INetworkAdapterService net,
            Action<FaultConclusion> onConcluded,
            Action requestRunFullDiagnostic)
        {
            _net = net ?? throw new ArgumentNullException(nameof(net));
            _onConcluded = onConcluded;
            _requestRunFullDiagnostic = requestRunFullDiagnostic;

            SuspectPortChoices = new ObservableCollection<PortChoice>();
            TestPortChoices    = new ObservableCollection<PortChoice>();
            History            = new ObservableCollection<FaultIsolatorHistoryRow>();

            ActionCommand    = new AsyncCommand(RunActionAsync, () => ActionButtonEnabled);
            StartOverCommand = new RelayCommand(Reset);
            CancelCommand    = new RelayCommand(() => RequestClose?.Invoke());
            // v0.8.6-beta: "No spare CHU" path on Phase 4. Visibility on the
            // dialog is gated by CanInferCameraConclusion which is true only
            // while Phase == AwaitingCameraTest.
            InferCameraConclusionCommand = new AsyncCommand(
                InferCameraConclusionWithoutSwapAsync,
                () => CanInferCameraConclusion && ActionButtonEnabled);

            Reset();
        }

        /// <summary>Raised when the dialog should close (Cancel button).</summary>
        public event Action RequestClose;

        // -- Bindable state -----------------------------------------------

        private FaultIsolatorPhase _phase;
        public FaultIsolatorPhase Phase
        {
            get => _phase;
            private set
            {
                if (Set(ref _phase, value))
                {
                    OnPropertyChanged(nameof(IsPickingSuspectPort));
                    OnPropertyChanged(nameof(IsPickingTestPort));
                    OnPropertyChanged(nameof(StepDot1));
                    OnPropertyChanged(nameof(StepDot2));
                    OnPropertyChanged(nameof(StepDot3));
                    OnPropertyChanged(nameof(StepDot4));
                    OnPropertyChanged(nameof(StepDot5));
                    // v0.8.6-beta: gates the "No spare CHU - infer" button.
                    OnPropertyChanged(nameof(CanInferCameraConclusion));
                    System.Windows.Input.CommandManager.InvalidateRequerySuggested();
                }
            }
        }

        private FaultConclusion _conclusion;
        public FaultConclusion Conclusion
        {
            get => _conclusion;
            private set
            {
                if (Set(ref _conclusion, value))
                {
                    OnPropertyChanged(nameof(CanInferCameraConclusion));
                    System.Windows.Input.CommandManager.InvalidateRequerySuggested();
                }
            }
        }

        private string _phaseTitle = "";
        public string PhaseTitle { get => _phaseTitle; private set => Set(ref _phaseTitle, value); }

        private string _phaseInstruction = "";
        public string PhaseInstruction { get => _phaseInstruction; private set => Set(ref _phaseInstruction, value); }

        private string _actionButtonLabel = "";
        public string ActionButtonLabel { get => _actionButtonLabel; private set => Set(ref _actionButtonLabel, value); }

        private bool _actionButtonEnabled = true;
        public bool ActionButtonEnabled
        {
            get => _actionButtonEnabled;
            private set
            {
                if (Set(ref _actionButtonEnabled, value))
                    System.Windows.Input.CommandManager.InvalidateRequerySuggested();
            }
        }

        private string _resultText = "";
        public string ResultText { get => _resultText; private set => Set(ref _resultText, value); }

        private string _resultSeverity = "";
        public string ResultSeverity
        {
            get => _resultSeverity;
            private set
            {
                if (Set(ref _resultSeverity, value))
                    OnPropertyChanged(nameof(ResultSeverityLabel));
            }
        }

        /// <summary>Uppercase form bound by the LATEST RESULT chip.</summary>
        public string ResultSeverityLabel =>
            string.IsNullOrEmpty(_resultSeverity) ? "INFO" : _resultSeverity.ToUpperInvariant();

        public bool IsPickingSuspectPort => Phase == FaultIsolatorPhase.PickPort;
        public bool IsPickingTestPort    => Phase == FaultIsolatorPhase.AwaitingNicPortTest && Conclusion == FaultConclusion.None;

        public ObservableCollection<PortChoice>          SuspectPortChoices { get; }
        public ObservableCollection<PortChoice>          TestPortChoices    { get; }
        public ObservableCollection<FaultIsolatorHistoryRow> History        { get; }

        private PortChoice _selectedSuspectPort;
        public PortChoice SelectedSuspectPort
        {
            get => _selectedSuspectPort;
            set
            {
                if (Set(ref _selectedSuspectPort, value))
                    RebuildTestPortChoices();
            }
        }

        private PortChoice _selectedTestPort;
        public PortChoice SelectedTestPort
        {
            get => _selectedTestPort;
            set => Set(ref _selectedTestPort, value);
        }

        // Step-dot fill markers (true = visited / active).
        public bool StepDot1 => (int)Phase >= 0;
        public bool StepDot2 => (int)Phase >= 1;
        public bool StepDot3 => (int)Phase >= 2;
        public bool StepDot4 => (int)Phase >= 3;
        public bool StepDot5 => (int)Phase >= 4;

        public ICommand ActionCommand    { get; }
        public ICommand StartOverCommand { get; }
        public ICommand CancelCommand    { get; }
        public ICommand InferCameraConclusionCommand { get; }

        /// <summary>
        /// v0.8.6-beta: true only while the wizard is sitting on Phase 4
        /// (AwaitingCameraTest). Binds the "No spare CHU - infer" button's
        /// Visibility so it only appears when the tech can actually use it.
        /// </summary>
        public bool CanInferCameraConclusion =>
            Phase == FaultIsolatorPhase.AwaitingCameraTest &&
            Conclusion == FaultConclusion.None;

        // -- Population from the parent VM --------------------------------

        /// <summary>
        /// Seed the suspect-port dropdown from the parent's live PortViewModel list.
        /// Called once when the dialog opens.
        /// </summary>
        public void SeedFromPorts(IEnumerable<PortViewModel> ports, string preselectLocalMac = null)
        {
            SuspectPortChoices.Clear();
            if (ports == null) return;
            foreach (var p in ports)
            {
                if (string.IsNullOrEmpty(p.LocalMac)) continue;
                // Skip totally absent ports (no link, no remote, never seen).
                // A port that's currently down but has a cached identity is
                // still a valid suspect — the tech may have just unplugged it.
                var choice = BuildChoice(p);
                SuspectPortChoices.Add(choice);
            }
            if (!string.IsNullOrEmpty(preselectLocalMac))
            {
                var match = SuspectPortChoices.FirstOrDefault(c =>
                    string.Equals(c.LocalMac, preselectLocalMac, StringComparison.OrdinalIgnoreCase));
                if (match != null) SelectedSuspectPort = match;
            }
            // Otherwise leave the first item selected if any.
            if (SelectedSuspectPort == null && SuspectPortChoices.Count > 0)
                SelectedSuspectPort = SuspectPortChoices[0];
        }

        private static PortChoice BuildChoice(PortViewModel p)
        {
            string speed;
            if (!p.IsUp) speed = "no link";
            else if (p.LinkSpeedBps >= 1_000_000_000UL) speed = "1 Gbps";
            else if (p.LinkSpeedBps > 0) speed = $"{p.LinkSpeedBps / 1_000_000UL} Mbps";
            else speed = "no link";

            string suffix = "";
            if (p.IsOcr)       suffix = " · OCR (100 Mbps is expected)";
            else if (p.IsDegraded) suffix = " · FAULT";

            // v0.8.6-beta: prefer the physical "Port N" label (set by the
            // host VM when laying out the tile row) over the Windows-assigned
            // adapter name ("Ethernet 24" etc). Field tech feedback: techs
            // can map "Port 3" to the chassis instantly; "Ethernet 26"
            // requires them to look at Pulse and then mental-map. AdapterName
            // is preserved as the secondary fallback.
            var name = !string.IsNullOrEmpty(p.Name) ? p.Name
                     : !string.IsNullOrEmpty(p.AdapterName) ? p.AdapterName
                     : "Port ?";

            return new PortChoice
            {
                LocalMac      = p.LocalMac,
                AdapterName   = name,
                DisplayLabel  = $"{name} — {speed}{suffix}",
                LinkSpeedBps  = p.LinkSpeedBps,
                IsUp          = p.IsUp,
                IsOcr         = p.IsOcr,
                IsDegraded    = p.IsDegraded,
            };
        }

        private void RebuildTestPortChoices()
        {
            TestPortChoices.Clear();
            var sel = SelectedSuspectPort;
            if (sel == null) return;
            foreach (var c in SuspectPortChoices)
            {
                if (string.Equals(c.LocalMac, sel.LocalMac, StringComparison.OrdinalIgnoreCase)) continue;
                TestPortChoices.Add(c);
            }
            if (TestPortChoices.Count > 0) SelectedTestPort = TestPortChoices[0];
        }

        // -- State transitions --------------------------------------------

        public void Reset()
        {
            Phase = FaultIsolatorPhase.PickPort;
            Conclusion = FaultConclusion.None;
            ResultText = "";
            ResultSeverity = "";
            History.Clear();
            PhaseTitle = "SELECT A PORT TO BEGIN";
            PhaseInstruction = "Select the NIC port that is showing degraded speed (100 Mbps) and click Start Baseline.";
            ActionButtonLabel = "Start Baseline";
            ActionButtonEnabled = true;
        }

        private async Task RunActionAsync()
        {
            switch (Phase)
            {
                case FaultIsolatorPhase.PickPort:            await DoBaselineAsync();    break;
                case FaultIsolatorPhase.AwaitingNicPortTest: await DoNicPortCheckAsync(); break;
                case FaultIsolatorPhase.AwaitingCableTest:   await DoCableCheckAsync();   break;
                case FaultIsolatorPhase.AwaitingCameraTest:  await DoCameraCheckAsync();  break;
                case FaultIsolatorPhase.Concluded:
                    // Concluded-phase action: hand the "what to do next"
                    // signal back to the host and close the modal so the
                    // tech lands on the live Camera Connectivity panel.
                    _requestRunFullDiagnostic?.Invoke();
                    RequestClose?.Invoke();
                    break;
            }
        }

        // -- Phase 1: Baseline ---------------------------------------------

        private async Task DoBaselineAsync()
        {
            var suspect = SelectedSuspectPort;
            if (suspect == null) return;
            ActionButtonEnabled = false;
            ActionButtonLabel = "Checking...";
            ResultText = "";
            ResultSeverity = "";

            int speed = await PollPeakLinkSpeedMbpsAsync(suspect.LocalMac, LivePhasePollSeconds).ConfigureAwait(true);
            ActionButtonEnabled = true;

            var speedLabel = FormatSpeedLabel(speed);
            var config = $"Port: {suspect.AdapterName}  |  Cable: (original)  |  Camera: (original)";

            if (speed >= 1000)
            {
                // Port is healthy — no fault to isolate. Stay in PickPort,
                // relabel the button so the tech can re-run.
                AddHistory("Phase 1 - Baseline", config, speedLabel,
                    "Port healthy - no fault on this port.", "Pass");
                ShowResult($"Baseline: {speedLabel} - Port is operating normally.",
                    "The selected port is already running at 1 Gbps. No fault detected. Select a different port or close the wizard.",
                    "Pass");
                PhaseTitle = "BASELINE - PORT HEALTHY";
                PhaseInstruction = "Select a different port or close the wizard.";
                ActionButtonLabel = "Recheck Port";
                return;
            }

            string baseMsg;
            string baseInstr;
            if (speed <= 0)
            {
                baseMsg = "No link detected";
                baseInstr = "Verify the camera is powered on and the cable is seated firmly. Then click Check Now to continue.";
            }
            else
            {
                baseMsg = $"Link is degraded at {speedLabel} (expected 1 Gbps)";
                baseInstr = $"Move the SAME cable and camera from {suspect.AdapterName} to a known-good test port. Then click Check Now.";
            }
            AddHistory("Phase 1 - Baseline", config, speedLabel, $"{baseMsg} - beginning isolation.", "Fail");
            ShowResult($"Baseline: {speedLabel} - {baseMsg}.", baseInstr, "Fail");

            Phase = FaultIsolatorPhase.AwaitingNicPortTest;
            PhaseTitle = "PHASE 2 - DOES THE FAULT FOLLOW THE NIC PORT?";
            PhaseInstruction = baseInstr;
            ActionButtonLabel = "Check Now";
        }

        // -- Phase 2: NIC Port test ----------------------------------------

        private async Task DoNicPortCheckAsync()
        {
            var test = SelectedTestPort;
            if (test == null)
            {
                ShowResult("No test port selected.",
                    "Pick a test port from the dropdown before continuing.", "Fail");
                return;
            }
            ActionButtonEnabled = false;

            // Pre-check: test port must itself be at least nominally healthy
            // (>= 1 Gbps with no link OR a normal-speed link) before the
            // cable+camera move. A pre-degraded test port invalidates the test.
            ActionButtonLabel = "Pre-checking port...";
            int preSpeed = await PollPeakLinkSpeedMbpsAsync(test.LocalMac, PreCheckPollSeconds).ConfigureAwait(true);
            if (preSpeed > 0 && preSpeed < 1000)
            {
                ActionButtonEnabled = true;
                ActionButtonLabel = "Check Now";
                ShowResult($"Pre-check: {test.AdapterName} is already at {preSpeed} Mbps.",
                    $"{test.AdapterName} is already degraded before you moved anything. Phase 2 results will be unreliable - the test needs a known-good port. Pick a different test port from the dropdown, or click Start Over.",
                    "Fail");
                return;
            }

            ActionButtonLabel = "Checking...";
            int speed = await PollPeakLinkSpeedMbpsAsync(test.LocalMac, LivePhasePollSeconds).ConfigureAwait(true);
            ActionButtonEnabled = true;
            var speedLabel = FormatSpeedLabel(speed);
            var config = $"Port: {test.AdapterName} (test port)  |  Cable: (original)  |  Camera: (original)";

            if (speed >= 1000)
            {
                var verdict = "Link restored on the test port. The fault follows the original NIC port.";
                AddHistory("Phase 2 - NIC Port Test", config, speedLabel, verdict, "Pass");
                ShowResult($"Phase 2: {speedLabel} - Fault follows the original NIC port.", verdict, "Pass");
                Conclude(FaultConclusion.NicPort, "CONCLUSION - FAULTY NIC PORT",
                    $"Moving the cable and camera to {test.AdapterName} restored the link. The original NIC port is the source of the fault. Escalate for NIC or motherboard repair.");
                return;
            }

            // v0.8.6-beta: no-link branch. A speed=0 reading after a swap is
            // ambiguous (cable might be unseated, camera might have lost
            // power, link still negotiating > 12 s) and must not produce a
            // verdict. Stay on the same phase and ask the tech to verify
            // the physical connection, then click Check Now again.
            if (speed <= 0)
            {
                var nolinkVerdict = "No link detected - test inconclusive.";
                AddHistory("Phase 2 - NIC Port Test", config, speedLabel, nolinkVerdict, "Info");
                PhaseInstruction = $"No link on {test.AdapterName}. Verify the cable is fully seated on the test port and the camera is powered on, then click Check Now to re-measure. The link can take up to ~15 s to renegotiate after a swap.";
                ShowResult("Phase 2: No link - test inconclusive.", PhaseInstruction, "Info");
                // Stay in AwaitingNicPortTest; do not advance.
                return;
            }

            // Fault stayed with the cable+camera — continue to Phase 3.
            var carryVerdict = "Fault stayed with the cable / camera. The original NIC port is not the source.";
            AddHistory("Phase 2 - NIC Port Test", config, speedLabel, carryVerdict, "Info");
            ShowResult($"Phase 2: {speedLabel} - Fault follows cable / camera, not the NIC port.", carryVerdict, "Info");

            Phase = FaultIsolatorPhase.AwaitingCableTest;
            PhaseTitle = "PHASE 3 - DOES THE FAULT FOLLOW THE CABLE?";
            PhaseInstruction = $"Stay on {test.AdapterName} with the same camera. Swap the cable for a known-good cable. Then click Check Now.";
            ActionButtonLabel = "Check Now";
        }

        // -- Phase 3: Cable test -------------------------------------------

        private async Task DoCableCheckAsync()
        {
            var test = SelectedTestPort;
            if (test == null) return;
            ActionButtonEnabled = false;
            ActionButtonLabel = "Checking...";
            int speed = await PollPeakLinkSpeedMbpsAsync(test.LocalMac, LivePhasePollSeconds).ConfigureAwait(true);
            ActionButtonEnabled = true;

            var speedLabel = FormatSpeedLabel(speed);
            var config = $"Port: {test.AdapterName}  |  Cable: (NEW - known good)  |  Camera: (original)";

            if (speed >= 1000)
            {
                var verdict = "Link restored with a known-good cable. The original cable is the source of the fault.";
                AddHistory("Phase 3 - Cable Test", config, speedLabel, verdict, "Pass");
                ShowResult($"Phase 3: {speedLabel} - Fault follows the cable.", verdict, "Pass");
                Conclude(FaultConclusion.Cable, "CONCLUSION - FAULTY CABLE",
                    "Replacing the cable restored the link. The original cable (or its termination) is the source of the fault. Replace the cable end-to-end.");
                return;
            }

            // v0.8.6-beta: no-link branch (mirrors Phase 2). A speed=0 after
            // the cable swap is inconclusive - cable might be unseated, the
            // camera might have lost power during the swap. Stay on Phase 3
            // and let the tech retry. This was field-flagged as misleading
            // before the fix: a no-link reading falsely produced "fault
            // stayed with the camera" when the new cable just wasn't fully
            // seated.
            if (speed <= 0)
            {
                var nolinkVerdict = "No link detected - test inconclusive.";
                AddHistory("Phase 3 - Cable Test", config, speedLabel, nolinkVerdict, "Info");
                PhaseInstruction = $"No link on {test.AdapterName}. Verify the new cable is fully seated on both ends and the camera is powered on, then click Check Now to re-measure.";
                ShowResult("Phase 3: No link - test inconclusive.", PhaseInstruction, "Info");
                // Stay in AwaitingCableTest; do not advance.
                return;
            }

            var carryVerdict = "Fault stayed with the camera. The original cable is not the source.";
            AddHistory("Phase 3 - Cable Test", config, speedLabel, carryVerdict, "Info");
            ShowResult($"Phase 3: {speedLabel} - Fault is not the cable.", carryVerdict, "Info");

            Phase = FaultIsolatorPhase.AwaitingCameraTest;
            PhaseTitle = "PHASE 4 - DOES THE FAULT FOLLOW THE CAMERA?";
            PhaseInstruction = $"Stay on {test.AdapterName} with the new cable. Connect a known-good camera, then click Check Now. If you don't have a spare camera, click \"No spare CHU - infer\" to conclude based on what we've already ruled out.";
            ActionButtonLabel = "Check Now";
        }

        // -- Phase 4: Camera test ------------------------------------------

        private async Task DoCameraCheckAsync()
        {
            var test = SelectedTestPort;
            if (test == null) return;
            ActionButtonEnabled = false;
            ActionButtonLabel = "Checking...";
            int speed = await PollPeakLinkSpeedMbpsAsync(test.LocalMac, LivePhasePollSeconds).ConfigureAwait(true);
            ActionButtonEnabled = true;

            var speedLabel = FormatSpeedLabel(speed);
            var config = $"Port: {test.AdapterName}  |  Cable: (NEW)  |  Camera: (NEW - known good)";

            if (speed >= 1000)
            {
                var verdict = "Link restored with a known-good camera. The original camera is the source of the fault.";
                AddHistory("Phase 4 - Camera Test", config, speedLabel, verdict, "Pass");
                ShowResult($"Phase 4: {speedLabel} - Fault follows the camera.", verdict, "Pass");
                Conclude(FaultConclusion.Camera, "CONCLUSION - FAULTY CAMERA (CHU)",
                    "Replacing the camera restored the link. The original camera (CHU) is the source of the fault. Replace the camera unit.");
                return;
            }

            // v0.8.6-beta: no-link on Phase 4 stays inconclusive too. Even
            // though Phase 4 fail normally drops into NIC hardware, a
            // speed=0 reading is more likely a swap-process issue than a
            // genuine NIC hardware fault (NIC hardware usually still
            // negotiates *something*). Stay on phase and let the tech retry.
            if (speed <= 0)
            {
                var nolinkVerdict = "No link detected - test inconclusive.";
                AddHistory("Phase 4 - Camera Test", config, speedLabel, nolinkVerdict, "Info");
                PhaseInstruction = $"No link on {test.AdapterName}. Verify the known-good camera is connected and powered on, then click Check Now to re-measure.";
                ShowResult("Phase 4: No link - test inconclusive.", PhaseInstruction, "Info");
                // Stay in AwaitingCameraTest; do not advance.
                return;
            }

            var verdictFail = "Fault persists with known-good cable and camera. The fault is likely in the NIC hardware or the VPU motherboard.";
            AddHistory("Phase 4 - Camera Test", config, speedLabel, verdictFail, "Fail");
            ShowResult($"Phase 4: {speedLabel} - Fault persists with known-good equipment.", verdictFail, "Fail");
            Conclude(FaultConclusion.NicHardware, "CONCLUSION - NIC / HARDWARE FAULT",
                $"Known-good cable and camera still fail on {test.AdapterName}. This indicates a fault in the NIC hardware or the VPU motherboard. Run the full diagnostic from the Camera Connectivity panel and escalate to hardware repair.");
        }

        // v0.8.6-beta: "No spare CHU" inference. Field tech feedback - spare
        // cameras (CHUs) are rare in the field. If a tech has reached Phase 4
        // without a replacement camera, we can still produce a useful verdict
        // from what we've already ruled out:
        //   - Phase 2 cleared the original NIC port (cable+camera moved, fault
        //     followed).
        //   - Phase 3 cleared the original cable (known-good cable, fault
        //     stayed).
        //   - The only remaining suspect is the camera (CHU). The test port's
        //     NIC hardware is implicitly trusted (we picked a known-good port).
        // Verdict: LikelyCamera. The tech knows to replace the camera if/when
        // a spare becomes available.
        public async Task InferCameraConclusionWithoutSwapAsync()
        {
            if (Phase != FaultIsolatorPhase.AwaitingCameraTest) return;
            ActionButtonEnabled = false;
            try
            {
                var test = SelectedTestPort;
                var config = test != null
                    ? $"Port: {test.AdapterName}  |  Cable: (NEW)  |  Camera: (no spare available)"
                    : "Camera test skipped - no spare CHU available.";

                AddHistory("Phase 4 - SKIPPED", config, "—",
                    "No spare CHU available. Conclusion inferred from Phase 2 and Phase 3 outcomes.",
                    "Info");
                ShowResult("Phase 4 skipped - inferred conclusion.",
                    "Phase 2 cleared the original NIC port; Phase 3 cleared the original cable. The remaining suspect is the camera (CHU).",
                    "Info");
                Conclude(FaultConclusion.LikelyCamera, "LIKELY CAMERA (CHU) FAULT - UNVERIFIED",
                    "Cable replacement did not restore the link, and the original NIC port has already been cleared (Phase 2). The remaining suspect is the camera (CHU). Replace the camera unit when a known-good spare is available; if the link still fails with a known-good camera, the issue is likely NIC hardware and a full diagnostic + escalation is warranted. Capture a snapshot now for the ticket.");
            }
            finally
            {
                ActionButtonEnabled = true;
            }
            await System.Threading.Tasks.Task.CompletedTask.ConfigureAwait(true);
        }

        private void Conclude(FaultConclusion conclusion, string title, string instruction)
        {
            Conclusion = conclusion;
            Phase = FaultIsolatorPhase.Concluded;
            PhaseTitle = title;
            PhaseInstruction = instruction;
            ActionButtonLabel = "Run Full Diagnostic";
            ActionButtonEnabled = true;
            _onConcluded?.Invoke(conclusion);
        }

        // -- Helpers -------------------------------------------------------

        private void ShowResult(string headline, string detail, string severity)
        {
            // Composed in one bound string so the dialog's result panel
            // doesn't need extra panels.
            ResultText = string.IsNullOrEmpty(detail)
                ? headline
                : $"{headline}\n{detail}";
            ResultSeverity = severity;
        }

        private void AddHistory(string phaseName, string config, string speed, string verdict, string severity)
        {
            History.Insert(0, new FaultIsolatorHistoryRow
            {
                TimestampLocal = DateTime.Now,
                PhaseName      = phaseName,
                Configuration  = config,
                SpeedReading   = speed,
                Verdict        = verdict,
                Severity       = severity,
            });
        }

        private static string FormatSpeedLabel(int mbps)
        {
            if (mbps >= 1000) return "1 Gbps";
            if (mbps > 0)     return $"{mbps} Mbps";
            return "No link";
        }

        /// <summary>
        /// Polls the per-port link speed up to <paramref name="windowSeconds"/>
        /// seconds, returning the peak observed Mbps. Short-circuits as soon
        /// as the port reaches 1 Gbps. Mirrors legacy Get-GuideLinkSpeed.
        /// </summary>
        private async Task<int> PollPeakLinkSpeedMbpsAsync(string localMac, int windowSeconds)
        {
            int peak = 0;
            var deadline = DateTime.UtcNow.AddSeconds(windowSeconds);
            while (DateTime.UtcNow < deadline)
            {
                int sample = await ReadPortLinkSpeedMbpsAsync(localMac).ConfigureAwait(false);
                if (sample > peak) peak = sample;
                if (peak >= 1000) return peak;
                await Task.Delay(PollIntervalMs).ConfigureAwait(false);
            }
            return peak;
        }

        private async Task<int> ReadPortLinkSpeedMbpsAsync(string localMac)
        {
            try
            {
                var ports = await _net.GetCameraPortsAsync().ConfigureAwait(false);
                var match = ports?.FirstOrDefault(p =>
                    string.Equals(p.LocalMac, localMac, StringComparison.OrdinalIgnoreCase));
                if (match == null) return 0;
                return (int)(match.LinkSpeedBps / 1_000_000UL);
            }
            catch
            {
                return 0;
            }
        }

        // -- Report rendering ---------------------------------------------

        /// <summary>
        /// Render the wizard's history + current state as a plain-text report
        /// the host can hand to <see cref="ReportWriter"/>. Mirrors the per-
        /// panel report format used elsewhere in Pulse.
        /// </summary>
        public string BuildReportText()
        {
            var sb = new System.Text.StringBuilder();
            sb.AppendLine("Camera Fault Isolator Report");
            sb.AppendLine(new string('=', 48));
            sb.AppendLine($"Generated:    {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            sb.AppendLine($"Suspect port: {SelectedSuspectPort?.AdapterName ?? "(unset)"}");
            sb.AppendLine($"Test port:    {SelectedTestPort?.AdapterName    ?? "(unset)"}");
            // v0.8.6-beta: spell out the LikelyCamera caveat in plain English
            // so the ticket reader doesn't have to know the enum vocabulary.
            string conclusionLabel = Conclusion == FaultConclusion.LikelyCamera
                ? "LikelyCamera (UNVERIFIED - Phase 4 skipped, no spare CHU)"
                : Conclusion.ToString();
            sb.AppendLine($"Conclusion:   {conclusionLabel}");
            sb.AppendLine();
            sb.AppendLine("Verdict");
            sb.AppendLine(new string('-', 48));
            sb.AppendLine(PhaseTitle);
            sb.AppendLine(PhaseInstruction);
            sb.AppendLine();
            sb.AppendLine("Phase history (newest first)");
            sb.AppendLine(new string('-', 48));
            foreach (var row in History)
            {
                sb.AppendLine($"[{row.TimestampLabel}]  {row.PhaseName}  ({row.Severity})");
                sb.AppendLine($"   {row.Configuration}");
                sb.AppendLine($"   Speed: {row.SpeedReading}");
                sb.AppendLine($"   {row.Verdict}");
                sb.AppendLine();
            }
            return sb.ToString();
        }
    }
}
