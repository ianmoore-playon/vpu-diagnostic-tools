using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Pulse.WPF.Models;
using Pulse.WPF.Services;
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
        private readonly DiskHealthViewModel _diskHealth;
        private readonly EventViewerViewModel _eventViewer;
        // v0.6.0 — ScoreConnect III panel. Joins Phase 1 because its probe
        // is a cheap HTTP GET against localhost; gracefully reports
        // IsDetected=false when the service isn't running on this VPU.
        private readonly ScoreConnectViewModel _scoreConnect;
        private readonly BaselineStateService _stateService = new BaselineStateService();

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
        public BaselineSnapshot LastSnapshot { get; private set; }

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
            DiskHealthViewModel diskHealth,
            EventViewerViewModel eventViewer,
            ScoreConnectViewModel scoreConnect)
        {
            _dashboard      = dashboard      ?? throw new ArgumentNullException(nameof(dashboard));
            _systemOverview = systemOverview ?? throw new ArgumentNullException(nameof(systemOverview));
            _network        = network        ?? throw new ArgumentNullException(nameof(network));
            _camera         = camera         ?? throw new ArgumentNullException(nameof(camera));
            _services       = services       ?? throw new ArgumentNullException(nameof(services));
            _diskHealth     = diskHealth     ?? throw new ArgumentNullException(nameof(diskHealth));
            _eventViewer    = eventViewer    ?? throw new ArgumentNullException(nameof(eventViewer));
            _scoreConnect   = scoreConnect   ?? throw new ArgumentNullException(nameof(scoreConnect));
            LastSnapshot    = _stateService.LoadLast();
        }

        /// <summary>
        /// Run a full baseline pass. Safe to await from a fire-and-forget
        /// Task.Run at startup or directly from the Re-run command. Returns
        /// once the Completed event has been raised.
        /// </summary>
        public async Task RunAsync(CancellationToken ct = default, bool startupNetworkReadinessGuard = false)
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
            // Total = 7 panels (Phase 1 = 5 with ScoreConnect, Phase 2 = 1,
            // Phase 3 = 1) + Dashboard. Dashboard is intentionally counted in
            // the total so the banner reads "(8/8 done)" on completion,
            // matching the user's mental model.
            PanelsTotal = 8;
            PanelsCompleted = 0;

            AppLogFile.Instance.WriteLine("Baseline", "Section",
                "Baseline run starting (8 panels)");

            try
            {
                // ---- Phase 1: cheap WMI reads in parallel ----
                // SystemOverview, Disk Health, Services, Event Viewer.
                // Each call is independently wrapped — one failure doesn't
                // poison the others. Task.WhenAll then awaits the lot.
                var phase1 = new[]
                {
                    InvokePanelAsync("System Overview", () => _systemOverview.RefreshAsync(), result, ct),
                    InvokePanelAsync("Disk Health",     () => _diskHealth.RefreshAsync(),     result, ct),
                    InvokePanelAsync("Services",        () => _services.RefreshAsync(),       result, ct),
                    InvokePanelAsync("Event Viewer",    () => _eventViewer.RefreshAsync(),    result, ct),
                    // v0.6.0 — ScoreConnect III HTTP probe. Cheap (2s timeout)
                    // and gracefully reports "not detected" when the service
                    // isn't running, so it's safe to fan out alongside the
                    // WMI reads here.
                    InvokePanelAsync("Score Connect",   () => _scoreConnect.RefreshAsync(),   result, ct),
                };
                await Task.WhenAll(phase1).ConfigureAwait(false);

                RaiseProgress("", "Phase 1 done");
                if (ct.IsCancellationRequested) { result.Cancelled = true; goto Finish; }

                // ---- Phase 2: Network probe (sequential, ~10-20 s) ----
                // Don't parallelise with Phase 1 — the probe + parallel WMI
                // saturate small fanless VPU boards. Use RunTestAsync (not
                // RefreshAsync) so this matches what the panel's "Run Test"
                // button does. The startup kick enables a short readiness guard
                // so route/DNS settling doesn't produce a false all-failed
                // Network baseline; manual re-runs stay immediate.
                await InvokePanelAsync("Network",
                    () => _network.RunTestAsync(startupNetworkReadinessGuard), result, ct).ConfigureAwait(false);

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
                result.Snapshot = CaptureCurrentSnapshot(result);
                SaveSnapshot(result.Snapshot);

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

        public BaselineSnapshot CaptureCurrentSnapshot(
            BaselineResult result = null,
            string supportBundlePath = null)
        {
            if (result == null && LastSnapshot != null && !IsRunning && PanelsCompleted == 0)
                return LastSnapshot;

            BaselineSnapshot snapshot = null;
            void collect()
            {
                snapshot = BuildSnapshotCore(result, supportBundlePath);
            }

            var app = System.Windows.Application.Current;
            if (app != null && !app.Dispatcher.CheckAccess()) app.Dispatcher.Invoke(collect);
            else collect();

            if (snapshot != null) LastSnapshot = snapshot;
            return snapshot;
        }

        public bool SaveSnapshot(BaselineSnapshot snapshot)
        {
            if (snapshot == null) return false;
            LastSnapshot = snapshot;
            return _stateService.Save(snapshot);
        }

        private BaselineSnapshot BuildSnapshotCore(BaselineResult result, string supportBundlePath)
        {
            var snapshot = new BaselineSnapshot
            {
                CompletedAtLocal = DateTime.Now,
                Hostname = Environment.MachineName,
                PulseVersion = AppVersion.Display,
                PanelsTotal = PanelsTotal > 0 ? PanelsTotal : 8,
                CompletedCount = result?.CompletedCount ?? LastSnapshot?.CompletedCount ?? 0,
                FailedCount = result?.FailedCount ?? LastSnapshot?.FailedCount ?? 0,
                Cancelled = result?.Cancelled ?? LastSnapshot?.Cancelled ?? false,
                DurationSeconds = result?.Duration.TotalSeconds ?? LastSnapshot?.DurationSeconds ?? 0,
                SupportBundlePath = supportBundlePath ?? LastSnapshot?.SupportBundlePath ?? "",
            };

            if (result?.FailedPanels != null)
                snapshot.FailedPanels.AddRange(result.FailedPanels);
            else if (LastSnapshot?.FailedPanels != null)
                snapshot.FailedPanels.AddRange(LastSnapshot.FailedPanels);

            var failed = new HashSet<string>(
                snapshot.FailedPanels ?? new List<string>(),
                StringComparer.OrdinalIgnoreCase);

            AddDashboardPanel(snapshot, failed);
            AddPanel(snapshot, "System Overview", "SystemOverview", "System Overview",
                _systemOverview.Findings, _systemOverview.LastReportPath, failed);
            AddPanel(snapshot, "Network", "Network", "Network",
                _network.Findings, _network.LastReportPath, failed);
            AddPanel(snapshot, "Camera", "Camera", "Camera Connectivity",
                _camera.Findings, _camera.LastReportPath, failed);
            AddPanel(snapshot, "ScoreConnect", "ScoreConnect", "Score Connect",
                _scoreConnect.Findings, _scoreConnect.LastReportPath, failed);
            AddPanel(snapshot, "Services", "Services", "Services",
                _services.Findings, _services.LastReportPath, failed);
            AddPanel(snapshot, "Disk Health", "DiskHealth", "Disk Health",
                _diskHealth.Findings, _diskHealth.LastReportPath, failed);
            AddPanel(snapshot, "Event Viewer", "EventViewer", "Event Viewer",
                _eventViewer.Findings, _eventViewer.LastReportPath, failed);

            snapshot.FindingCount = snapshot.Findings.Count;
            snapshot.CriticalFindingCount = snapshot.Findings.Count(f =>
                string.Equals(f.Severity, "Critical", StringComparison.OrdinalIgnoreCase));
            snapshot.WarningFindingCount = snapshot.Findings.Count(f =>
                string.Equals(f.Severity, "Warning", StringComparison.OrdinalIgnoreCase));
            return snapshot;
        }

        private void AddDashboardPanel(BaselineSnapshot snapshot, HashSet<string> failed)
        {
            var findings = (_dashboard.Findings ??
                new System.Collections.ObjectModel.ObservableCollection<DashboardFinding>())
                .Where(f => f != null && !f.FromBaseline)
                .ToList();

            foreach (var f in findings)
            {
                snapshot.Findings.Add(new BaselineFindingSnapshot
                {
                    Panel = string.IsNullOrWhiteSpace(f.Source) ? "Dashboard" : f.Source,
                    TargetNav = string.IsNullOrWhiteSpace(f.TargetNav) ? "Dashboard" : f.TargetNav,
                    Severity = DashboardSeverityLabel(f.Severity),
                    Title = f.Title ?? "",
                    Recommendation = f.Detail ?? "",
                });
            }

            var critical = findings.Count(f => f.Severity == "fail");
            var warning = findings.Count(f => f.Severity == "warn");
            snapshot.Panels.Add(new BaselinePanelSnapshot
            {
                Name = "Dashboard",
                NavKey = "Dashboard",
                Status = PanelStatus(failed.Contains("Dashboard"), critical, warning),
                FindingCount = findings.Count,
                CriticalCount = critical,
                WarningCount = warning,
                ReportPath = _dashboard.LastReportPath ?? "",
            });
        }

        private static void AddPanel(
            BaselineSnapshot snapshot,
            string name,
            string navKey,
            string failedPanelName,
            IEnumerable<Finding> findingsSource,
            string reportPath,
            HashSet<string> failed)
        {
            var findings = (findingsSource ?? Enumerable.Empty<Finding>())
                .Where(f => f != null)
                .ToList();

            foreach (var f in findings)
            {
                snapshot.Findings.Add(new BaselineFindingSnapshot
                {
                    Panel = name,
                    TargetNav = navKey,
                    Severity = SeverityLabel(f.Severity),
                    Category = f.Category ?? "",
                    Title = f.Title ?? "",
                    Recommendation = f.Recommendation ?? "",
                });
            }

            var critical = findings.Count(f => f.Severity == FindingSeverity.Critical);
            var warning = findings.Count(f => f.Severity == FindingSeverity.Warning);
            snapshot.Panels.Add(new BaselinePanelSnapshot
            {
                Name = name,
                NavKey = navKey,
                Status = PanelStatus(failed.Contains(failedPanelName), critical, warning),
                FindingCount = findings.Count,
                CriticalCount = critical,
                WarningCount = warning,
                ReportPath = reportPath ?? "",
            });
        }

        private static string PanelStatus(bool failed, int critical, int warning)
        {
            if (failed) return "Failed";
            if (critical > 0) return "Critical";
            if (warning > 0) return "Warning";
            return "Pass";
        }

        private static string SeverityLabel(FindingSeverity severity)
        {
            switch (severity)
            {
                case FindingSeverity.Critical: return "Critical";
                case FindingSeverity.Warning:  return "Warning";
                default:                       return "Info";
            }
        }

        private static string DashboardSeverityLabel(string severity)
        {
            switch ((severity ?? "").Trim().ToLowerInvariant())
            {
                case "fail": return "Critical";
                case "warn": return "Warning";
                default:     return "Info";
            }
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
