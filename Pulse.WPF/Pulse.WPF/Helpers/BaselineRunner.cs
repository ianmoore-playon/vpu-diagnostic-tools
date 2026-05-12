using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using Pulse.WPF.Models;
using Pulse.WPF.ViewModels;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Startup baseline orchestrator (v0.5.6). Walks the panel ViewModels in
    /// phases — Phase 1 cheap WMI in parallel, Phase 2 Network (sequential
    /// because the wire probe is heavy), Phase 3 Camera snapshot (waits ~2
    /// monitor ticks so tiles are populated), Phase 4 Dashboard last so its
    /// snapshot sees the freshly-written per-run reports.
    ///
    /// Failure isolation: each panel call is wrapped so a single WMI access
    /// denied / network hang doesn't block the rest. Failed panels are
    /// recorded in <see cref="BaselineResult.FailedPanels"/> and logged to
    /// <see cref="AppLogFile"/>.
    ///
    /// Single-instance: <see cref="IsRunning"/> guards against concurrent
    /// invocations from the App startup + the Dashboard "Re-run" button
    /// firing in the same window. A re-entrant call no-ops with a log line.
    /// </summary>
    public class BaselineRunner
    {
        // Camera Connectivity wait: the monitor's tick interval is 1 s. Two
        // ticks plus a small margin so the tiles always have at least one
        // resolved snapshot before we record the baseline. Larger than the
        // raw 2 s tick interval to avoid racing the dispatcher.
        private static readonly TimeSpan CameraTickWait = TimeSpan.FromMilliseconds(2200);

        private readonly DashboardViewModel _dashboard;
        private readonly SystemOverviewViewModel _systemOverview;
        private readonly NetworkViewModel _network;
        private readonly CameraConnectivityViewModel _camera;
        private readonly ServicesViewModel _services;
        private readonly HardwareViewModel _hardware;
        private readonly DiskHealthViewModel _diskHealth;
        private readonly EventViewerViewModel _eventViewer;

        // Mutex around the run — see the class doc for why a re-entrant call
        // is a no-op rather than an exception.
        private readonly object _runGate = new object();
        private bool _isRunning;

        public bool IsRunning { get { lock (_runGate) return _isRunning; } }

        // Last-known counters for read-only consumers that want a quick poll
        // (the Dashboard banner uses the ProgressChanged event instead).
        public int PanelsCompleted { get; private set; }
        public int PanelsTotal { get; private set; }
        public string CurrentPanelName { get; private set; } = "";

        /// <summary>Fired as each panel starts/finishes. The runner raises
        /// this from a background thread — the Dashboard subscriber marshals
        /// onto the UI thread itself.</summary>
        public event Action<BaselineProgress> ProgressChanged;

        /// <summary>Fired once after all phases complete (or the run is
        /// cancelled).</summary>
        public event Action<BaselineResult> Completed;

        public BaselineRunner(
            DashboardViewModel dashboard,
            SystemOverviewViewModel systemOverview,
            NetworkViewModel network,
            CameraConnectivityViewModel camera,
            ServicesViewModel services,
            HardwareViewModel hardware,
            DiskHealthViewModel diskHealth,
            EventViewerViewModel eventViewer)
        {
            _dashboard      = dashboard      ?? throw new ArgumentNullException(nameof(dashboard));
            _systemOverview = systemOverview ?? throw new ArgumentNullException(nameof(systemOverview));
            _network        = network        ?? throw new ArgumentNullException(nameof(network));
            _camera         = camera         ?? throw new ArgumentNullException(nameof(camera));
            _services       = services       ?? throw new ArgumentNullException(nameof(services));
            _hardware       = hardware       ?? throw new ArgumentNullException(nameof(hardware));
            _diskHealth     = diskHealth     ?? throw new ArgumentNullException(nameof(diskHealth));
            _eventViewer    = eventViewer    ?? throw new ArgumentNullException(nameof(eventViewer));
        }

        /// <summary>
        /// Run a full baseline pass. Safe to await from a fire-and-forget
        /// Task.Run at startup or directly from the Re-run command. Returns
        /// once the Completed event has been raised.
        /// </summary>
        public async Task RunAsync(CancellationToken ct = default)
        {
            // Single-instance guard. Concurrent invocation is treated as a
            // benign no-op (the operator hit Re-run while a startup run was
            // still in flight) rather than throwing.
            lock (_runGate)
            {
                if (_isRunning)
                {
                    AppLogFile.Instance.WriteLine("Baseline", "Info",
                        "RunAsync called while baseline already running — ignored.");
                    return;
                }
                _isRunning = true;
            }

            var sw = Stopwatch.StartNew();
            var result = new BaselineResult();
            // Total = 7 panels (Phase 1 = 5, Phase 2 = 1, Phase 3 = 1) + Dashboard.
            // Dashboard is intentionally counted in the total so the banner reads
            // "(8/8 done)" on completion, matching the user's mental model.
            PanelsTotal = 8;
            PanelsCompleted = 0;

            AppLogFile.Instance.WriteLine("Baseline", "Section",
                "Baseline run starting (8 panels)");

            try
            {
                // ---- Phase 1: cheap WMI reads in parallel ----
                // SystemOverview, Hardware, Disk Health, Services, Event Viewer.
                // Each call is independently wrapped — one failure doesn't
                // poison the others. Task.WhenAll then awaits the lot.
                var phase1 = new[]
                {
                    InvokePanelAsync("System Overview", () => _systemOverview.RefreshAsync(), result, ct),
                    InvokePanelAsync("Hardware",        () => _hardware.RefreshAsync(),       result, ct),
                    InvokePanelAsync("Disk Health",     () => _diskHealth.RefreshAsync(),     result, ct),
                    InvokePanelAsync("Services",        () => _services.RefreshAsync(),       result, ct),
                    InvokePanelAsync("Event Viewer",    () => _eventViewer.RefreshAsync(),    result, ct),
                };
                await Task.WhenAll(phase1).ConfigureAwait(false);

                RaiseProgress("", "Phase 1 done");
                if (ct.IsCancellationRequested) { result.Cancelled = true; goto Finish; }

                // ---- Phase 2: Network probe (sequential, ~10-20 s) ----
                // Don't parallelise with Phase 1 — the probe + parallel WMI
                // saturate small fanless VPU boards. Use RunTestAsync (not
                // RefreshAsync) so this matches what the panel's "Run Test"
                // button does.
                await InvokePanelAsync("Network",
                    () => _network.RunTestAsync(), result, ct).ConfigureAwait(false);

                if (ct.IsCancellationRequested) { result.Cancelled = true; goto Finish; }

                // ---- Phase 3: Camera Connectivity snapshot ----
                // The Camera VM self-refreshes via its 1 s DispatcherTimer
                // (started in its ctor). Wait ~2 monitor ticks so the tiles
                // are populated, then count the panel as "done" — the tiles'
                // current values become the baseline. No explicit refresh
                // call here; the per-tick PanelLogger writes already feed
                // AppLogFile.
                await InvokePanelAsync("Camera Connectivity",
                    () => Task.Delay(CameraTickWait, ct), result, ct).ConfigureAwait(false);

                if (ct.IsCancellationRequested) { result.Cancelled = true; goto Finish; }

                // ---- Phase 4: Dashboard last ----
                // Aggregates gauges + last-run + per-panel reports written by
                // Phases 1-3 so its snapshot sees the freshly-written files.
                await InvokePanelAsync("Dashboard",
                    () => _dashboard.RefreshAsync(), result, ct).ConfigureAwait(false);

                Finish:
                sw.Stop();
                result.Duration = sw.Elapsed;

                AppLogFile.Instance.WriteLine("Baseline",
                    result.FailedCount > 0 ? "Warn" : "Pass",
                    result.Cancelled
                        ? $"Baseline cancelled after {result.CompletedCount}/{PanelsTotal} panels ({sw.Elapsed.TotalSeconds:F1}s)"
                        : $"Baseline complete — {result.CompletedCount} ok, {result.FailedCount} failed in {sw.Elapsed.TotalSeconds:F1}s");

                Completed?.Invoke(result);
            }
            finally
            {
                lock (_runGate) { _isRunning = false; }
            }
        }

        // Per-panel wrapper. Always raises a "starting" ProgressChanged
        // before the call and a "finished" ProgressChanged after — both
        // counters are bumped post-call so partial failures still register.
        private async Task InvokePanelAsync(
            string panelName,
            Func<Task> action,
            BaselineResult result,
            CancellationToken ct)
        {
            if (ct.IsCancellationRequested) return;
            CurrentPanelName = panelName;
            RaiseProgress(panelName, "Running");

            try
            {
                await action().ConfigureAwait(false);
                result.CompletedCount++;
                AppLogFile.Instance.WriteLine("Baseline", "Pass",
                    $"{panelName} baseline ok");
            }
            catch (OperationCanceledException)
            {
                // Cancellation propagated from Task.Delay or downstream — let
                // the outer flow handle the "cancelled" branch; don't count
                // as a failure.
                throw;
            }
            catch (Exception ex)
            {
                result.FailedCount++;
                result.FailedPanels.Add(panelName);
                AppLogFile.Instance.WriteLine("Baseline", "Fail",
                    $"{panelName} baseline failed: {ex.Message}");
            }

            PanelsCompleted++;
            RaiseProgress(panelName, "Finished");
        }

        private void RaiseProgress(string panel, string status)
        {
            try
            {
                ProgressChanged?.Invoke(new BaselineProgress
                {
                    CurrentPanel = panel ?? "",
                    Completed    = PanelsCompleted,
                    Total        = PanelsTotal,
                    Status       = status ?? "",
                });
            }
            catch
            {
                // Subscriber bug must not kill the orchestrator.
            }
        }
    }
}
