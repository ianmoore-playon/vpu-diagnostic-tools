using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Dashboard (home) panel VM. Renders the one-page snapshot returned by
    /// IDashboardService.CollectSnapshotAsync — identity, gauges, NIC ports,
    /// network config, services, volumes, and rolled-up findings — plus the
    /// Quick Nav row at the bottom for getting to a specific panel.
    /// </summary>
    public class DashboardViewModel : ObservableObject
    {
        private readonly IDashboardService _svc;
        private readonly ReportWriter _reportWriter = new ReportWriter();
        public string LastReportPath { get; private set; }

        // ---- Quick Nav tiles + last-run summary (kept from v0.2.0) ----------
        public ObservableCollection<HubTileViewModel> Tiles { get; } =
            new ObservableCollection<HubTileViewModel>();

        private string _lastRunSummary = "Last Run: Never";
        public string LastRunSummary { get => _lastRunSummary; set => Set(ref _lastRunSummary, value); }
        private Brush _lastRunColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush LastRunColor { get => _lastRunColor; set => Set(ref _lastRunColor, value); }

        // ---- Identity card --------------------------------------------------
        private string _vpuLabel = "—";
        public string VpuLabel { get => _vpuLabel; set => Set(ref _vpuLabel, value); }
        private string _vpuModel = "—";
        public string VpuModel { get => _vpuModel; set => Set(ref _vpuModel, value); }
        private string _hostname = "—";
        public string Hostname { get => _hostname; set => Set(ref _hostname, value); }
        private string _manufacturer = "—";
        public string Manufacturer { get => _manufacturer; set => Set(ref _manufacturer, value); }
        private string _productName = "—";
        public string ProductName { get => _productName; set => Set(ref _productName, value); }
        private string _serialNumber = "—";
        public string SerialNumber { get => _serialNumber; set => Set(ref _serialNumber, value); }

        // ---- Pixellot software card -----------------------------------------
        private string _pixellotApp = "—";
        public string PixellotApp { get => _pixellotApp; set => Set(ref _pixellotApp, value); }
        private string _pixellotImage = "—";
        public string PixellotImage { get => _pixellotImage; set => Set(ref _pixellotImage, value); }
        private string _pixellotDeps = "—";
        public string PixellotDeps { get => _pixellotDeps; set => Set(ref _pixellotDeps, value); }

        // ---- Last diagnostic run card ---------------------------------------
        private string _lastRunWhen = "Never";
        public string LastRunWhen { get => _lastRunWhen; set => Set(ref _lastRunWhen, value); }
        private string _lastRunResult = "—";
        public string LastRunResult { get => _lastRunResult; set => Set(ref _lastRunResult, value); }
        private Brush _lastRunResultColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush LastRunResultColor { get => _lastRunResultColor; set => Set(ref _lastRunResultColor, value); }
        private string _lastReportPath;

        // ---- System status gauges -------------------------------------------
        private double _cpuPct;
        public double CpuPct { get => _cpuPct; set => Set(ref _cpuPct, value); }
        private string _cpuPctText = "—";
        public string CpuPctText { get => _cpuPctText; set => Set(ref _cpuPctText, value); }
        private Brush _cpuColor = StatusHelpers.Brush("AccentBrush");
        public Brush CpuColor { get => _cpuColor; set => Set(ref _cpuColor, value); }

        private double _memPct;
        public double MemPct { get => _memPct; set => Set(ref _memPct, value); }
        private string _memPctText = "—";
        public string MemPctText { get => _memPctText; set => Set(ref _memPctText, value); }
        private string _memCaption = "—";
        public string MemCaption { get => _memCaption; set => Set(ref _memCaption, value); }
        private Brush _memColor = StatusHelpers.Brush("AccentBrush");
        public Brush MemColor { get => _memColor; set => Set(ref _memColor, value); }

        private double _diskPct;
        public double DiskPct { get => _diskPct; set => Set(ref _diskPct, value); }
        private string _diskPctText = "—";
        public string DiskPctText { get => _diskPctText; set => Set(ref _diskPctText, value); }
        private string _diskCaption = "—";
        public string DiskCaption { get => _diskCaption; set => Set(ref _diskCaption, value); }
        private Brush _diskColor = StatusHelpers.Brush("AccentBrush");
        public Brush DiskColor { get => _diskColor; set => Set(ref _diskColor, value); }

        private string _uptimeText = "—";
        public string UptimeText { get => _uptimeText; set => Set(ref _uptimeText, value); }
        private string _cpuName = "—";
        public string CpuName { get => _cpuName; set => Set(ref _cpuName, value); }
        private string _cpuCoresText = "—";
        public string CpuCoresText { get => _cpuCoresText; set => Set(ref _cpuCoresText, value); }

        // Temperature tile — hidden when WMI returns no thermal-zone data
        // (typical on consumer / desktop CPUs that don't expose ACPI temp).
        private string _temperatureText = "—";
        public string TemperatureText { get => _temperatureText; set => Set(ref _temperatureText, value); }
        private bool _temperatureVisible;
        public bool TemperatureVisible { get => _temperatureVisible; set => Set(ref _temperatureVisible, value); }
        private Brush _temperatureColor = StatusHelpers.Brush("AccentBrush");
        public Brush TemperatureColor { get => _temperatureColor; set => Set(ref _temperatureColor, value); }

        // ---- NIC ports / volumes / services / findings collections ---------
        public ObservableCollection<NicPortRow> NicPorts { get; } = new ObservableCollection<NicPortRow>();
        public ObservableCollection<VolumeRow> Volumes  { get; } = new ObservableCollection<VolumeRow>();
        public ObservableCollection<ServiceStatusRow> Services { get; } = new ObservableCollection<ServiceStatusRow>();
        public ObservableCollection<DashboardFinding> Findings { get; } = new ObservableCollection<DashboardFinding>();

        // v0.5.6 — split Findings into a top-10 list rendered inline + an
        // overflow list shown inside an expander below the inline list. Both
        // are derived from Findings; consumers re-call RebuildFindingViews()
        // after mutating Findings. (Severity-ranked: Critical -> Warning ->
        // Info; ties broken by panel order via the merge step's append
        // sequence.)
        public ObservableCollection<DashboardFinding> TopFindings { get; } =
            new ObservableCollection<DashboardFinding>();
        public ObservableCollection<DashboardFinding> OverflowFindings { get; } =
            new ObservableCollection<DashboardFinding>();
        public ObservableCollection<DashboardFinding> CommandFindings { get; } =
            new ObservableCollection<DashboardFinding>();
        private int _overflowFindingsCount;
        public int OverflowFindingsCount
        {
            get => _overflowFindingsCount;
            set { if (Set(ref _overflowFindingsCount, value)) OnPropertyChanged(nameof(HasOverflowFindings)); }
        }
        public bool HasOverflowFindings => _overflowFindingsCount > 0;
        private int _commandOverflowFindingsCount;
        public int CommandOverflowFindingsCount
        {
            get => _commandOverflowFindingsCount;
            set { if (Set(ref _commandOverflowFindingsCount, value)) OnPropertyChanged(nameof(HasCommandOverflowFindings)); }
        }
        public bool HasCommandOverflowFindings => _commandOverflowFindingsCount > 0;
        public bool HasFindings => Findings.Count > 0;
        public bool HasNoFindings => _hasSnapshot && Findings.Count == 0;

        // Cap kept here so the constant has a single source of truth.
        private const int ActiveFindingsCap = 10;
        private const int CommandFindingsCap = 3;

        // ---- Dashboard log sink -------------------------------------------
        // Lets formerly-silent catches surface low-severity log lines instead
        // of swallowing failures. Capped at 200 entries.
        public ObservableCollection<LogEntry> LogEntries { get; } = new ObservableCollection<LogEntry>();
        internal void AddLog(string message, string level = "Info")
        {
            var entry = new LogEntry
            {
                Label = "",
                Result = message,
                Level = level,
                ResultColor = StatusHelpers.BrushForLogLevel(level),
            };
            void apply()
            {
                LogEntries.Add(entry);
                while (LogEntries.Count > 200) LogEntries.RemoveAt(0);
            }
            var app = System.Windows.Application.Current;
            if (app != null && app.Dispatcher.CheckAccess()) apply();
            else app?.Dispatcher.Invoke(apply);
        }

        // ---- Network config block (read directly from snapshot) ------------
        private string _ipAddress = "—";
        public string IpAddress { get => _ipAddress; set => Set(ref _ipAddress, value); }
        private string _gateway = "—";
        public string Gateway { get => _gateway; set => Set(ref _gateway, value); }
        private string _dns = "—";
        public string DnsServers { get => _dns; set => Set(ref _dns, value); }
        private string _ntp = "—";
        public string NtpServer { get => _ntp; set => Set(ref _ntp, value); }
        private string _uplink = "—";
        public string UplinkAdapter { get => _uplink; set => Set(ref _uplink, value); }
        private string _internetText = "—";
        public string InternetText { get => _internetText; set => Set(ref _internetText, value); }
        private Brush _internetColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush InternetColor { get => _internetColor; set => Set(ref _internetColor, value); }

        // ---- Status pill (overall health) ----------------------------------
        // _hasSnapshot guards the pill against showing "Healthy" before the
        // first snapshot has been applied — that's a false-green that erodes
        // trust in a diagnostic tool. Until then, the pill reads "Checking…"
        // muted.
        private bool _hasSnapshot;
        private bool _hasBaselinePanelFindings;
        private string _statusLabel = "Checking…";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        // ---- Empty-state flag (non-VPU host) -------------------------------
        // True when DashboardService can't find Pixellot at all — drives the
        // top-of-page "Pixellot software not detected" empty state so a clean
        // dev box doesn't look like a healthy VPU.
        private bool _isNonVpuHost;
        public bool IsNonVpuHost { get => _isNonVpuHost; set => Set(ref _isNonVpuHost, value); }

        // Status dots beside the Network Configuration values — green when
        // the value is meaningfully populated, muted when it's blank/em-dash.
        private Brush _ipDotColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush IpDotColor { get => _ipDotColor; set => Set(ref _ipDotColor, value); }
        private Brush _gatewayDotColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush GatewayDotColor { get => _gatewayDotColor; set => Set(ref _gatewayDotColor, value); }
        private Brush _dnsDotColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush DnsDotColor { get => _dnsDotColor; set => Set(ref _dnsDotColor, value); }
        private Brush _ntpDotColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush NtpDotColor { get => _ntpDotColor; set => Set(ref _ntpDotColor, value); }

        // ---- Commands -------------------------------------------------------
        public ICommand NavigateCommand { get; }
        public ICommand OpenLastReportCommand { get; }
        public ICommand GenerateSupportBundleCommand { get; }
        public ICommand RefreshCommand { get; }
        public Action<string> RequestNavigate { get; set; }   // wired up by MainViewModel

        // Set by MainViewModel — called when "Open Last Report" fires with the
        // filename of the most recent report so the Reports panel can pre-
        // select it after navigation. Keeps the cross-VM coordination simple.
        public Action<string> RequestOpenReport { get; set; }
        public Func<Task<string>> GenerateSupportBundleAsyncHook { get; set; }

        // True when there are no diagnostic reports on disk — drives the
        // "No diagnostic runs yet" muted empty state in the Dashboard's
        // "Last Diagnostic Run" card. Populated from IReportsService when
        // available; otherwise falls back to _lastReportPath being empty.
        private bool _isLastRunEmpty = true;
        public bool IsLastRunEmpty
        {
            get => _isLastRunEmpty;
            set => Set(ref _isLastRunEmpty, value);
        }
        public bool HasLastRun => !_isLastRunEmpty;

        // Live-update timer — re-reads only the cheap gauges (CPU / memory /
        // disk / temperature) every 2 seconds. The heavy snapshot (NIC ports,
        // services, internet probe, volumes) refreshes on tab visit + manual
        // Refresh button only.
        private readonly System.Windows.Threading.DispatcherTimer _liveTimer;
        public DashboardViewModel(IDashboardService svc)
        {
            _svc = svc;
            NavigateCommand        = new NavigateCommandImpl(t => RequestNavigate?.Invoke(t as string));
            // CanExecute disables Open Last Report when no report exists —
            // the button used to silently no-op (rec #11 from the UX review).
            OpenLastReportCommand  = new RelayCommand(OpenLastReport, () => HasLastRun);
            GenerateSupportBundleCommand = new AsyncCommand(GenerateSupportBundleAsync,
                                                           () => GenerateSupportBundleAsyncHook != null);
            RefreshCommand         = new AsyncCommand(RefreshAsync);
            // Re-run only fires when a baseline isn't already in flight —
            // BaselineRunner has its own re-entrancy guard but disabling
            // the button avoids a confusing "click did nothing" UX.
            RerunBaselineCommand   = new AsyncCommand(RerunBaselineAsync,
                                                     () => !IsBaselineRunning && _baseline != null);
            DismissBaselineBannerCommand = new RelayCommand(() =>
            {
                StopBannerAutoDismissTimer();
                BaselineComplete = false;
            });

            // Route DashboardService's formerly-silent catches into the VM
            // log sink (v0.5.0) so collection failures finally show up.
            if (_svc is DashboardService concrete)
            {
                concrete.OnSilentError = (section, ex) =>
                    AddLog($"{section} failed: {ex?.Message}", "Warn");
            }

            _liveTimer = new System.Windows.Threading.DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(2),
            };
            _liveTimer.Tick += OnLiveTick;
        }

        // v0.5.6 — banner state. Drives the Dashboard banner row that sits
        // above Active Findings. IsBaselineRunning shows the "Gathering
        // baseline…" caption + spinner; BaselineComplete swaps to the
        // "complete" caption with a Dismiss button + 10 s auto-dismiss.
        private bool _isBaselineRunning;
        public bool IsBaselineRunning
        {
            get => _isBaselineRunning;
            set { if (Set(ref _isBaselineRunning, value)) OnPropertyChanged(nameof(IsBaselineBannerVisible)); }
        }

        private bool _baselineComplete;
        public bool BaselineComplete
        {
            get => _baselineComplete;
            set { if (Set(ref _baselineComplete, value)) OnPropertyChanged(nameof(IsBaselineBannerVisible)); }
        }

        // Composite visibility — banner shows while running OR for the 10 s
        // after completion. Dismissed by user click or by the auto-dismiss
        // timer flipping BaselineComplete back to false.
        public bool IsBaselineBannerVisible => IsBaselineRunning || BaselineComplete;

        private string _baselineStatusText = "";
        public string BaselineStatusText { get => _baselineStatusText; set => Set(ref _baselineStatusText, value); }

        private string _baselineResultText = "";
        public string BaselineResultText { get => _baselineResultText; set => Set(ref _baselineResultText, value); }

        private string _baselineSummaryText = "Baseline pending";
        public string BaselineSummaryText { get => _baselineSummaryText; set => Set(ref _baselineSummaryText, value); }
        private Brush _baselineSummaryColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush BaselineSummaryColor { get => _baselineSummaryColor; set => Set(ref _baselineSummaryColor, value); }
        private Brush _baselineSummaryBg = StatusHelpers.Brush("BorderColBrush");
        public Brush BaselineSummaryBg { get => _baselineSummaryBg; set => Set(ref _baselineSummaryBg, value); }

        // Re-run command — disabled while a baseline is already running so a
        // double-click can't kick a second pass. RelayCommand re-evaluates
        // CanExecute via CommandManager.RequerySuggested.
        public ICommand RerunBaselineCommand { get; }
        public ICommand DismissBaselineBannerCommand { get; }

        // v0.5.6 — wire the BaselineRunner's events into the banner properties
        // + the post-completion findings aggregation. Subscribed exactly once
        // by MainViewModel after construction; no need to support multiple
        // attaches.
        private Pulse.WPF.Helpers.BaselineRunner _baseline;
        private System.Windows.Threading.DispatcherTimer _bannerAutoDismissTimer;
        public void AttachBaseline(Pulse.WPF.Helpers.BaselineRunner runner)
        {
            if (runner == null) return;
            _baseline = runner;
            _baseline.ProgressChanged += OnBaselineProgress;
            _baseline.Completed       += OnBaselineCompleted;
            // RerunBaselineCommand's CanExecute reads _baseline != null;
            // force a requery now so the button enables after attach.
            System.Windows.Input.CommandManager.InvalidateRequerySuggested();
        }

        public void ApplyPersistedBaseline(BaselineSnapshot snapshot)
        {
            if (snapshot == null) return;
            void apply()
            {
                if (IsBaselineRunning) return;
                var completedAt = snapshot.CompletedAtLocal.ToString("MMM d, h:mm tt");
                var totalPanels = snapshot.PanelsTotal > 0 ? snapshot.PanelsTotal : 8;
                BaselineSummaryText =
                    $"Last baseline {completedAt} • {snapshot.CompletedCount}/{totalPanels} panels • {snapshot.FindingCount} finding(s)";

                if (snapshot.CriticalFindingCount > 0)
                {
                    BaselineSummaryColor = StatusHelpers.Brush("RedBrush");
                    BaselineSummaryBg = StatusHelpers.Brush("ErrBgBrush");
                }
                else if (snapshot.Cancelled || snapshot.FailedCount > 0)
                {
                    BaselineSummaryColor = StatusHelpers.Brush("YellowBrush");
                    BaselineSummaryBg = StatusHelpers.Brush("WarnBgBrush");
                }
                else if (snapshot.WarningFindingCount > 0)
                {
                    BaselineSummaryColor = StatusHelpers.Brush("YellowBrush");
                    BaselineSummaryBg = StatusHelpers.Brush("WarnBgBrush");
                }
                else
                {
                    BaselineSummaryColor = StatusHelpers.Brush("GreenBrush");
                    BaselineSummaryBg = StatusHelpers.Brush("OkBgBrush");
                }
            }

            var app = System.Windows.Application.Current;
            if (app != null && app.Dispatcher.CheckAccess()) apply();
            else app?.Dispatcher.Invoke(apply);
        }

        // ProgressChanged fires on a background thread (from BaselineRunner's
        // own Task) — marshal onto the dispatcher because we touch observable
        // properties that the UI binds to.
        private void OnBaselineProgress(BaselineProgress p)
        {
            void apply()
            {
                IsBaselineRunning = true;
                BaselineComplete  = false;
                StopBannerAutoDismissTimer();
                var status = string.IsNullOrEmpty(p.CurrentPanel)
                    ? p.Status
                    : $"{p.CurrentPanel} {p.Status.ToLowerInvariant()}";
                BaselineStatusText =
                    $"Gathering baseline — {status} ({p.Completed}/{p.Total} done)";
                BaselineSummaryText = $"Baseline running • {status} • {p.Completed}/{p.Total} panels";
                BaselineSummaryColor = StatusHelpers.Brush("InfoBrush");
                BaselineSummaryBg = StatusHelpers.Brush("InfoBgBrush");
            }
            var app = System.Windows.Application.Current;
            if (app != null && app.Dispatcher.CheckAccess()) apply();
            else app?.Dispatcher.Invoke(apply);
        }

        private void OnBaselineCompleted(BaselineResult r)
        {
            void apply()
            {
                IsBaselineRunning = false;
                BaselineComplete  = true;

                // Aggregate panel Findings into the Dashboard's Findings
                // collection (tagged with [Panel] prefix), then sort + cap
                // for the top-10 inline list.
                AggregateBaselineFindings();

                var snapshot = r.Snapshot;
                var totalFindings = snapshot != null ? snapshot.FindingCount : Findings.Count;
                var totalPanels = snapshot != null && snapshot.PanelsTotal > 0
                    ? snapshot.PanelsTotal
                    : r.CompletedCount + r.FailedCount;
                var criticalFindings = snapshot != null
                    ? snapshot.CriticalFindingCount
                    : CountFindingsBySeverity("fail");
                var completedAt = DateTime.Now.ToString("h:mm tt");
                if (r.Cancelled)
                {
                    BaselineResultText = $"Baseline cancelled — {totalFindings} finding(s) detected";
                    BaselineSummaryText = $"Baseline cancelled {completedAt} • {totalPanels} panel(s) checked • {totalFindings} finding(s)";
                    BaselineSummaryColor = StatusHelpers.Brush("YellowBrush");
                    BaselineSummaryBg = StatusHelpers.Brush("WarnBgBrush");
                }
                else if (r.FailedCount > 0)
                {
                    var panels = string.Join(", ", r.FailedPanels ?? new System.Collections.Generic.List<string>());
                    BaselineResultText =
                        $"Baseline complete with errors — {totalFindings} finding(s), {r.FailedCount} panel(s) failed" +
                        (string.IsNullOrEmpty(panels) ? "" : $" ({panels})");
                    BaselineSummaryText = $"Baseline completed {completedAt} • {r.CompletedCount}/{totalPanels} panels • {totalFindings} finding(s)";
                    BaselineSummaryColor = StatusHelpers.Brush("YellowBrush");
                    BaselineSummaryBg = StatusHelpers.Brush("WarnBgBrush");
                }
                else
                {
                    BaselineResultText = $"Baseline complete — {totalFindings} finding(s) detected";
                    BaselineSummaryText = $"Baseline completed {completedAt} • {totalPanels}/{totalPanels} panels • {totalFindings} finding(s)";
                    BaselineSummaryColor = criticalFindings > 0
                        ? StatusHelpers.Brush("RedBrush")
                        : (totalFindings > 0 ? StatusHelpers.Brush("YellowBrush") : StatusHelpers.Brush("GreenBrush"));
                    BaselineSummaryBg = criticalFindings > 0
                        ? StatusHelpers.Brush("ErrBgBrush")
                        : (totalFindings > 0 ? StatusHelpers.Brush("WarnBgBrush") : StatusHelpers.Brush("OkBgBrush"));
                }

                // 10 s auto-dismiss — DispatcherTimer (UI-thread) so we can
                // safely flip BaselineComplete back from the tick handler.
                StopBannerAutoDismissTimer();
                _bannerAutoDismissTimer = new System.Windows.Threading.DispatcherTimer
                {
                    Interval = TimeSpan.FromSeconds(10),
                };
                _bannerAutoDismissTimer.Tick += (s, e) =>
                {
                    StopBannerAutoDismissTimer();
                    BaselineComplete = false;
                };
                _bannerAutoDismissTimer.Start();
            }
            var app = System.Windows.Application.Current;
            if (app != null && app.Dispatcher.CheckAccess()) apply();
            else app?.Dispatcher.Invoke(apply);
        }

        private void StopBannerAutoDismissTimer()
        {
            if (_bannerAutoDismissTimer == null) return;
            try { _bannerAutoDismissTimer.Stop(); } catch { }
            _bannerAutoDismissTimer = null;
        }

        private int CountFindingsBySeverity(string severity)
        {
            int count = 0;
            foreach (var f in Findings)
            {
                if (f != null && string.Equals(f.Severity, severity, StringComparison.OrdinalIgnoreCase))
                    count++;
            }
            return count;
        }

        // Walk every panel VM's Findings collection, project each into a
        // DashboardFinding tagged with [Panel] prefix, replace the previous
        // baseline merge, sort by severity descending, then rebuild
        // Top/Overflow views. Panel-order tie-break: appended in fixed
        // sequence below so equal severities keep the sidebar order.
        private void AggregateBaselineFindings()
        {
            _hasBaselinePanelFindings = true;

            // Keep DashboardService's own findings, but remove the previous
            // panel-finding projection before adding the new baseline result.
            // Without this, every baseline re-run stacks another copy of the
            // same "[Network] ..." / "[Disk Health] ..." rows.
            var retained = new System.Collections.Generic.List<DashboardFinding>();
            foreach (var f in Findings)
            {
                if (f == null || IsBaselineAggregate(f)) continue;
                retained.Add(f);
            }
            Findings.Clear();
            foreach (var f in retained) Findings.Add(f);

            var mvm = ResolveMainViewModel();
            if (mvm == null)
            {
                RebuildFindingViews();
                UpdateTileStatuses();
                UpdatePill();
                return;
            }

            var seen = new System.Collections.Generic.HashSet<string>(
                System.StringComparer.OrdinalIgnoreCase);
            foreach (var f in Findings) seen.Add(FindingKey(f));

            // Helper local to project + append.
            void Merge(string panelLabel, string targetNav,
                       System.Collections.Generic.IEnumerable<Pulse.WPF.Models.Finding> src)
            {
                if (src == null) return;
                foreach (var f in src)
                {
                    if (f == null) continue;
                    var projected = new DashboardFinding
                    {
                        Severity  = MapFindingSeverity(f.Severity),
                        Title     = $"[{panelLabel}] {f.Title}",
                        Detail    = f.Recommendation ?? "",
                        Source    = panelLabel,
                        TargetNav = targetNav ?? "",
                        FromBaseline = true,
                    };
                    if (seen.Add(FindingKey(projected))) Findings.Add(projected);
                }
            }

            // Order here defines the panel-order tie-break for equal
            // severities. Mirrors the sidebar / dashboard quick-nav order.
            Merge("System Overview", "SystemOverview", mvm.SystemOverview?.Findings);
            Merge("Network",       "Network",      mvm.Network?.Findings);
            Merge("Camera",        "Camera",       mvm.Camera?.Findings);
            Merge("ScoreConnect",  "ScoreConnect", mvm.ScoreConnect?.Findings);
            Merge("Services",      "Services",     mvm.Services?.Findings);
            Merge("Disk Health",   "DiskHealth",   mvm.DiskHealth?.Findings);
            Merge("Event Viewer",  "EventViewer",  mvm.EventViewer?.Findings);

            // Stable severity sort (Critical first, Warning, Info/neutral,
            // ok) while preserving append order for ties.
            var indexed = new System.Collections.Generic.List<System.Tuple<DashboardFinding, int>>();
            int ordinal = 0;
            foreach (var f in Findings)
            {
                indexed.Add(System.Tuple.Create(f, ordinal++));
            }
            int Rank(string s) =>
                s == "fail" ? 3 :
                s == "warn" ? 2 :
                s == "ok"   ? 1 :
                              0;
            indexed.Sort((a, b) =>
            {
                int diff = Rank(b.Item1.Severity) - Rank(a.Item1.Severity);
                return diff != 0 ? diff : a.Item2 - b.Item2;
            });
            Findings.Clear();
            foreach (var item in indexed) Findings.Add(item.Item1);

            RebuildFindingViews();
            UpdateTileStatuses();
            UpdatePill();
        }

        private static bool IsBaselineAggregate(DashboardFinding f)
        {
            if (f == null) return false;
            if (f.FromBaseline) return true;
            var title = f.Title ?? "";
            return title.StartsWith("[System Overview]", StringComparison.OrdinalIgnoreCase)
                || title.StartsWith("[Network]", StringComparison.OrdinalIgnoreCase)
                || title.StartsWith("[Camera]", StringComparison.OrdinalIgnoreCase)
                || title.StartsWith("[ScoreConnect]", StringComparison.OrdinalIgnoreCase)
                || title.StartsWith("[Services]", StringComparison.OrdinalIgnoreCase)
                || title.StartsWith("[Disk Health]", StringComparison.OrdinalIgnoreCase)
                || title.StartsWith("[Event Viewer]", StringComparison.OrdinalIgnoreCase);
        }

        private static string FindingKey(DashboardFinding f)
        {
            if (f == null) return "";
            return string.Join("|",
                f.Severity ?? "",
                f.Source ?? "",
                f.Title ?? "",
                f.Detail ?? "",
                f.TargetNav ?? "");
        }

        // DashboardFinding uses string severities ("ok"/"warn"/"fail"). Panel
        // Findings use the FindingSeverity enum. Map for the merge step.
        private static string MapFindingSeverity(Pulse.WPF.Models.FindingSeverity s)
        {
            switch (s)
            {
                case Pulse.WPF.Models.FindingSeverity.Critical: return "fail";
                case Pulse.WPF.Models.FindingSeverity.Warning:  return "warn";
                default:                                          return "neutral";
            }
        }

        // Resolve the parent MainViewModel via the live MainWindow.
        // DashboardViewModel is constructed by MainViewModel and stored as
        // the panel VM; we don't keep a back-reference (would invite a
        // cycle). The window's DataContext is always the MainViewModel.
        private ViewModels.MainViewModel ResolveMainViewModel()
        {
            try
            {
                return System.Windows.Application.Current?.MainWindow?.DataContext
                    as ViewModels.MainViewModel;
            }
            catch { return null; }
        }

        // Bound to the "Re-run Baseline" outlined button on the Dashboard
        // top bar. Runs on a background task so the UI thread stays
        // responsive while the runner walks the panels.
        private async Task RerunBaselineAsync()
        {
            if (_baseline == null) return;
            // Don't await on the UI thread — the runner internally marshals
            // dispatcher work; we just need to keep the button responsive.
            await Task.Run(async () =>
            {
                try { await _baseline.RunAsync().ConfigureAwait(false); }
                catch (Exception ex)
                {
                    try
                    {
                        AppLogFile.Instance.WriteLine("Baseline", "Fail",
                            $"Re-run failed: {ex.Message}");
                    }
                    catch { }
                }
            }).ConfigureAwait(false);
        }

        private async Task GenerateSupportBundleAsync()
        {
            if (GenerateSupportBundleAsyncHook == null)
            {
                AddLog("Support bundle generator is not ready.", "Warn");
                return;
            }

            try
            {
                BaselineSummaryText = "Generating support bundle…";
                BaselineSummaryColor = StatusHelpers.Brush("InfoBrush");
                BaselineSummaryBg = StatusHelpers.Brush("InfoBgBrush");

                var path = await GenerateSupportBundleAsyncHook();
                var fileName = string.IsNullOrEmpty(path) ? "" : Path.GetFileName(path);
                BaselineSummaryText = string.IsNullOrEmpty(fileName)
                    ? "Support bundle created"
                    : $"Support bundle created • {fileName}";
                BaselineSummaryColor = StatusHelpers.Brush("InfoBrush");
                BaselineSummaryBg = StatusHelpers.Brush("InfoBgBrush");
                AddLog(string.IsNullOrEmpty(fileName)
                    ? "Support bundle created."
                    : $"Support bundle created: {fileName}", "Pass");

                if (!string.IsNullOrEmpty(fileName))
                    RequestOpenReport?.Invoke(fileName);
            }
            catch (Exception ex)
            {
                BaselineSummaryText = $"Support bundle failed • {ex.Message}";
                BaselineSummaryColor = StatusHelpers.Brush("RedBrush");
                BaselineSummaryBg = StatusHelpers.Brush("ErrBgBrush");
                AddLog($"Support bundle failed: {ex.Message}", "Fail");
                try
                {
                    AppLogFile.Instance.WriteLine("Dashboard", "Fail",
                        $"Support bundle failed: {ex.Message}");
                }
                catch { }
            }
        }

        /// <summary>
        /// Re-derive <see cref="TopFindings"/> + <see cref="OverflowFindings"/>
        /// from the current <see cref="Findings"/> collection. Caller must
        /// have already ordered Findings by severity desc.
        /// </summary>
        public void RebuildFindingViews()
        {
            TopFindings.Clear();
            OverflowFindings.Clear();
            CommandFindings.Clear();
            int n = 0;
            foreach (var f in Findings)
            {
                if (n < ActiveFindingsCap) TopFindings.Add(f);
                else                       OverflowFindings.Add(f);
                if (n < CommandFindingsCap) CommandFindings.Add(f);
                n++;
            }
            OverflowFindingsCount = OverflowFindings.Count;
            CommandOverflowFindingsCount = Math.Max(0, Findings.Count - CommandFindings.Count);
            OnPropertyChanged(nameof(HasFindings));
            OnPropertyChanged(nameof(HasNoFindings));
        }

        // Started by MainViewModel when the Dashboard becomes the current view;
        // stopped when navigating away. Matches what the legacy WinForms tool
        // did with its System.Windows.Forms.Timer.
        public void StartLiveUpdates()
        {
            if (_liveTimer != null && !_liveTimer.IsEnabled) _liveTimer.Start();
        }
        public void StopLiveUpdates()
        {
            if (_liveTimer != null && _liveTimer.IsEnabled) _liveTimer.Stop();
        }

        // ReadGauges does ~250 ms of CPU sampling; run it on a background task
        // so the tick doesn't block the UI thread, then marshal the result back
        // for the property assigns. Body is wrapped in a single try/catch so an
        // async-void exception can never tear down the dispatcher (v0.5.0).
        private async void OnLiveTick(object sender, EventArgs e)
        {
            try
            {
                var g = await Task.Run(() => _svc.ReadGauges()).ConfigureAwait(true);
                if (g != null) ApplyGaugeReadings(g);
            }
            catch (Exception ex)
            {
                AddLog($"Live tick failed: {ex.Message}", "Warn");
            }
        }

        private void ApplyGaugeReadings(GaugeReadings g)
        {
            CpuPct      = g.CpuUsagePct;
            CpuPctText  = $"{(int)g.CpuUsagePct}%";
            CpuColor    = LoadColour(g.CpuUsagePct);

            MemPct      = g.MemoryUsedPct;
            MemPctText  = $"{(int)g.MemoryUsedPct}%";
            MemCaption  = g.MemoryUsedLabel;
            MemColor    = LoadColour(g.MemoryUsedPct);

            DiskPct     = g.DiskUsedPct;
            DiskPctText = $"{(int)g.DiskUsedPct}%";
            DiskCaption = g.DiskUsedLabel;
            DiskColor   = LoadColour(g.DiskUsedPct);

            if (g.TemperatureAvailable)
            {
                TemperatureVisible = true;
                TemperatureText    = $"{g.TemperatureC:F0}°C";
                // Tier the tile colour by absolute °C. 65 / 78 °C bands tuned
                // for the small-form-factor / fanless boards the Pixellot S2
                // typically ships on, which throttle around 80 °C package.
                // (UX review rec #14 — confirm with platform team if tighter
                // limits become known.)
                TemperatureColor = g.TemperatureC >= 78 ? StatusHelpers.Brush("RedBrush")
                                : g.TemperatureC >= 65 ? StatusHelpers.Brush("YellowBrush")
                                :                          StatusHelpers.Brush("AccentBrush");
            }
            else
            {
                TemperatureVisible = false;
            }
        }

        public async Task RefreshAsync()
        {
            // The cheap-reads (GetHubTiles, GetLastRunSummary) and the pre-await
            // body of CollectSnapshotAsync (which still includes the 250 ms
            // Thread.Sleep in ReadGaugesCore) all used to run inline on the UI
            // thread. Push everything that touches the service onto a worker
            // task so the dispatcher stays free until we marshal results back.
            List<HubTileViewModel> tiles = null;
            LastRunSummary last = null;
            DashboardSnapshot snap = null;
            Exception snapErr = null;
            try
            {
                tiles = await Task.Run(() => _svc.GetHubTiles()).ConfigureAwait(false);
            }
            catch (Exception ex) { snapErr = ex; }
            try
            {
                last = await Task.Run(() => _svc.GetLastRunSummary()).ConfigureAwait(false);
            }
            catch (Exception ex) { if (snapErr == null) snapErr = ex; }
            try { snap = await _svc.CollectSnapshotAsync().ConfigureAwait(false); }
            catch (Exception ex) { snapErr = ex; }

            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                ApplyTilesAndLastRun(tiles ?? new List<HubTileViewModel>(), last);
                if (snap != null) ApplySnapshot(snap);
                if (snapErr != null) AddLog($"Snapshot collection failed: {snapErr.Message}", "Warn");

                // v0.5.5: per-run report file.
                try
                {
                    var path = _reportWriter.Save("Dashboard", BuildReportText());
                    if (!string.IsNullOrEmpty(path))
                    {
                        LastReportPath = path;
                        AppLogFile.Instance.WriteLine("Dashboard", "Info",
                            $"Report saved: {path}");
                    }
                }
                catch { }
            });
        }

        /// <summary>
        /// Compose the Dashboard panel's per-run report body — gauge
        /// readings, hub-tile statuses, the last diagnostic-run summary,
        /// and the Findings list.
        /// </summary>
        public string BuildReportText()
        {
            var sb = new System.Text.StringBuilder();

            sb.AppendLine("== Identity ==");
            sb.AppendLine($"  Hostname:    {Hostname}");
            sb.AppendLine($"  Model:       {VpuModel}");
            sb.AppendLine($"  Mfr/Product: {Manufacturer} / {ProductName}");
            sb.AppendLine($"  Serial:      {SerialNumber}");
            sb.AppendLine($"  App:         {PixellotApp}");
            sb.AppendLine($"  Image:       {PixellotImage}");
            sb.AppendLine($"  Deps:        {PixellotDeps}");

            sb.AppendLine();
            sb.AppendLine("== Gauges ==");
            sb.AppendLine($"  CPU:         {CpuPctText}  ({CpuName}, {CpuCoresText})");
            sb.AppendLine($"  Memory:      {MemPctText}  ({MemCaption})");
            sb.AppendLine($"  Disk:        {DiskPctText}  ({DiskCaption})");
            sb.AppendLine($"  Uptime:      {UptimeText}");
            if (TemperatureVisible)
                sb.AppendLine($"  Temperature: {TemperatureText}");

            sb.AppendLine();
            sb.AppendLine("== Network ==");
            sb.AppendLine($"  Uplink:      {UplinkAdapter}");
            sb.AppendLine($"  IP:          {IpAddress}");
            sb.AppendLine($"  Gateway:     {Gateway}");
            sb.AppendLine($"  DNS:         {DnsServers}");
            sb.AppendLine($"  NTP:         {NtpServer}");
            sb.AppendLine($"  Internet:    {InternetText}");

            if (NicPorts.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== NIC Ports ==");
                foreach (var p in NicPorts)
                    sb.AppendLine($"  Port {p.PortNumber}  {p.Name,-32}  {p.SpeedLabel,-10}  {p.StatusText}");
            }

            if (Tiles.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== Hub Tiles ==");
                foreach (var t in Tiles)
                    sb.AppendLine($"  [{t.StatusText,-10}] {t.Title,-22}  {t.Description}");
            }

            sb.AppendLine();
            sb.AppendLine("== Last Diagnostic Run ==");
            sb.AppendLine($"  {LastRunSummary}");
            sb.AppendLine($"  When:        {LastRunWhen}");
            sb.AppendLine($"  Result:      {LastRunResult}");

            if (Findings.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== Findings ==");
                foreach (var f in Findings)
                    sb.AppendLine($"  [{f.Severity}] {f.Title}\n      -> {f.Detail}");
            }

            sb.AppendLine();
            sb.AppendLine("## Live Log (last 50 entries)");
            var tail = LogEntries.Count > 50 ? 50 : LogEntries.Count;
            for (int i = LogEntries.Count - tail; i < LogEntries.Count; i++)
            {
                var e = LogEntries[i];
                var label = string.IsNullOrEmpty(e.Label) ? "" : e.Label + "  ";
                sb.AppendLine($"  [{e.Level,-5}] {label}{e.Result}");
            }

            return sb.ToString();
        }

        private void ApplyTilesAndLastRun(List<HubTileViewModel> tiles,
                                          LastRunSummary last)
        {
            Tiles.Clear();
            if (tiles != null)
            {
                foreach (var t in tiles)
                {
                    if (t == null) continue;
                    t.StatusText = "Not run";
                    t.StatusColor = StatusHelpers.Brush("MutedForegroundBrush");
                    t.StatusBg = StatusHelpers.Brush("BorderColBrush");
                    Tiles.Add(t);
                }
            }
            UpdateTileStatuses();

            if (last == null)
            {
                LastRunSummary = "Last Run: Never";
                LastRunColor   = StatusHelpers.Brush("MutedForegroundBrush");
                _lastReportPath = null;
            }
            else
            {
                var when  = last.When.ToString("MMM d, h:mm tt");
                var model = string.IsNullOrEmpty(last.VpuModel) ? "" : $" — {last.VpuModel}";
                var res   = string.IsNullOrEmpty(last.Result) ? "" : $"   |   {last.Result}";
                LastRunSummary = $"Last Run: {when}{model}{res}";
                LastRunColor =
                    last.Severity == "Fail" ? StatusHelpers.Brush("RedBrush") :
                    last.Severity == "Warn" ? StatusHelpers.Brush("YellowBrush") :
                    last.Severity == "Pass" ? StatusHelpers.Brush("GreenBrush") :
                                                StatusHelpers.Brush("MutedForegroundBrush");
                _lastReportPath = last.ReportPath;
            }
        }

        private void ApplySnapshot(DashboardSnapshot s)
        {
            // Identity + Pixellot software
            VpuLabel      = s.VpuLabel;
            VpuModel      = s.VpuModel;
            Hostname      = s.Hostname;
            Manufacturer  = s.Manufacturer;
            ProductName   = s.ProductName;
            SerialNumber  = s.SerialNumber;
            PixellotApp   = s.PixellotApp;
            PixellotImage = s.PixellotImage;
            PixellotDeps  = s.PixellotDeps;

            // Last diagnostic
            LastRunWhen        = s.LastRunWhen;
            LastRunResult      = s.LastRunResult;
            LastRunResultColor = SeverityBrush(s.LastRunSeverity);

            // Gauges — funnel through the same code path as the live tick so
            // tier colour rules stay in one place.
            ApplyGaugeReadings(new GaugeReadings
            {
                CpuUsagePct     = s.CpuUsagePct,
                MemoryUsedPct   = s.MemoryUsedPct,
                MemoryUsedLabel = s.MemoryUsedLabel,
                DiskUsedPct     = s.DiskUsedPct,
                DiskUsedLabel   = s.DiskUsedLabel,
                TemperatureC    = s.TemperatureC,
            });

            UptimeText   = s.Uptime;
            CpuName      = s.CpuName;
            CpuCoresText = s.CpuCores > 0 ? $"{s.CpuCores} threads" : "";

            // NIC ports — pad to 4 entries so the table always has 4 rows.
            NicPorts.Clear();
            for (int i = 0; i < Math.Max(4, s.NicPorts?.Count ?? 0); i++)
            {
                if (s.NicPorts != null && i < s.NicPorts.Count)
                {
                    var n = s.NicPorts[i];
                    NicPorts.Add(NicPortRow.From(i + 1, n));
                }
                else
                {
                    NicPorts.Add(NicPortRow.Empty(i + 1));
                }
            }

            // Network config + per-row status dots. A green dot reads at a
            // glance for non-tech users without them having to know what
            // "DNS" or "NTP" means; muted dot says "this hasn't been
            // populated" without sounding alarms.
            var ipPresent  = !string.IsNullOrEmpty(s.NetworkConfig?.IpAddress);
            var gwPresent  = !string.IsNullOrEmpty(s.NetworkConfig?.Gateway);
            var dnsPresent = !string.IsNullOrEmpty(s.NetworkConfig?.DnsServers);
            var ntpPresent = !string.IsNullOrEmpty(s.NetworkConfig?.NtpServer);
            IpAddress       = ipPresent  ? s.NetworkConfig.IpAddress    : "—";
            Gateway         = gwPresent  ? s.NetworkConfig.Gateway      : "—";
            DnsServers      = dnsPresent ? s.NetworkConfig.DnsServers   : "—";
            NtpServer       = ntpPresent ? s.NetworkConfig.NtpServer    : "—";
            UplinkAdapter   = string.IsNullOrEmpty(s.UplinkAdapterName) ? "—" : s.UplinkAdapterName;
            IpDotColor      = ipPresent  ? StatusHelpers.Brush("GreenBrush") : StatusHelpers.Brush("MutedForegroundBrush");
            GatewayDotColor = gwPresent  ? StatusHelpers.Brush("GreenBrush") : StatusHelpers.Brush("MutedForegroundBrush");
            DnsDotColor     = dnsPresent ? StatusHelpers.Brush("GreenBrush") : StatusHelpers.Brush("MutedForegroundBrush");
            NtpDotColor     = ntpPresent ? StatusHelpers.Brush("GreenBrush") : StatusHelpers.Brush("MutedForegroundBrush");

            // Plain-English internet status — the icon already encodes the
            // meaning, so the text reads the same way a non-tech user thinks.
            InternetText  = s.InternetReachable ? "Connected" : "No connection";
            InternetColor = s.InternetReachable ? StatusHelpers.Brush("GreenBrush") : StatusHelpers.Brush("RedBrush");

            IsNonVpuHost = s.IsNonVpuHost;

            // Services + volumes
            Services.Clear();
            if (s.Services != null) foreach (var svc in s.Services) Services.Add(svc);
            Volumes.Clear();
            if (s.Volumes  != null) foreach (var v   in s.Volumes)  Volumes.Add(v);

            // Findings — replace wholesale from the snapshot. The baseline
            // orchestrator merges panel Findings on top after Completed
            // (see AggregateBaselineFindings), so a panel Refresh that
            // re-fires this method will repaint just the DashboardService
            // rows — that's the same behaviour as before the v0.5.6 merge.
            Findings.Clear();
            if (s.Findings != null) foreach (var f in s.Findings) Findings.Add(f);

            // Mark the first snapshot as applied so the pill stops reading
            // "Checking…" — UpdatePill respects this flag.
            _hasSnapshot = true;

            // After the baseline has run, panel Findings are the source of
            // truth for specialized checks (especially Camera). A manual
            // Dashboard refresh should keep those panel findings merged on
            // top of the fresh snapshot instead of replacing them.
            if (_hasBaselinePanelFindings) AggregateBaselineFindings();
            else
            {
                RebuildFindingViews();
                UpdateTileStatuses();
                UpdatePill();
            }
        }

        private void UpdateTileStatuses()
        {
            if (Tiles == null) return;

            foreach (var tile in Tiles)
            {
                if (tile == null) continue;

                if (!_hasSnapshot)
                {
                    tile.StatusText = "Not run";
                    tile.StatusColor = StatusHelpers.Brush("MutedForegroundBrush");
                    tile.StatusBg = StatusHelpers.Brush("BorderColBrush");
                    continue;
                }

                if (string.Equals(NormalizeNav(tile.TargetNav), "Reports", StringComparison.OrdinalIgnoreCase))
                {
                    tile.StatusText = HasLastRun ? "Evidence ready" : "No report";
                    tile.StatusColor = HasLastRun ? StatusHelpers.Brush("InfoBrush")
                                                 : StatusHelpers.Brush("MutedForegroundBrush");
                    tile.StatusBg = HasLastRun ? StatusHelpers.Brush("InfoBgBrush")
                                               : StatusHelpers.Brush("BorderColBrush");
                    continue;
                }

                var worst = WorstFindingForTarget(tile.TargetNav);
                if (worst == "fail")
                {
                    tile.StatusText = "Critical";
                    tile.StatusColor = StatusHelpers.Brush("RedBrush");
                    tile.StatusBg = StatusHelpers.Brush("ErrBgBrush");
                }
                else if (worst == "warn")
                {
                    tile.StatusText = "Warning";
                    tile.StatusColor = StatusHelpers.Brush("YellowBrush");
                    tile.StatusBg = StatusHelpers.Brush("WarnBgBrush");
                }
                else
                {
                    tile.StatusText = "Healthy";
                    tile.StatusColor = StatusHelpers.Brush("GreenBrush");
                    tile.StatusBg = StatusHelpers.Brush("OkBgBrush");
                }
            }
        }

        private string WorstFindingForTarget(string targetNav)
        {
            var target = NormalizeNav(targetNav);
            string worst = "";
            foreach (var f in Findings)
            {
                if (f == null) continue;
                if (!string.Equals(NormalizeNav(f.TargetNav), target, StringComparison.OrdinalIgnoreCase)) continue;
                if (f.Severity == "fail") return "fail";
                if (f.Severity == "warn") worst = "warn";
            }
            return worst;
        }

        private static string NormalizeNav(string nav)
        {
            if (string.IsNullOrWhiteSpace(nav)) return "";
            var trimmed = nav.Trim();
            if (string.Equals(trimmed, "Events", StringComparison.OrdinalIgnoreCase)) return "EventViewer";
            if (string.Equals(trimmed, "Disk", StringComparison.OrdinalIgnoreCase)) return "DiskHealth";
            if (string.Equals(trimmed, "Hardware", StringComparison.OrdinalIgnoreCase)) return "SystemOverview";
            return trimmed;
        }

        // Pill reflects the worst Finding severity. Four states, in order of
        // priority:
        //   - Checking…  (no snapshot yet — first paint, before data lands)
        //   - Critical   (any Findings entry has severity "fail")
        //   - Warning    (any Findings entry has severity "warn")
        //   - Healthy    (no findings, snapshot applied)
        // Note: this rolls up Findings only — not raw card statuses — so the
        // pill cannot disagree with the Active Findings card visible above
        // it. (UX review rec #1, #2.)
        private void UpdatePill()
        {
            if (!_hasSnapshot)
            {
                StatusLabel = "Checking…";
                StatusColor = StatusHelpers.Brush("MutedForegroundBrush");
                StatusBg    = StatusHelpers.Brush("BorderColBrush");
                return;
            }

            // Route through StatusHelpers.PillFor so the Dashboard pill reads
            // the same way as the other four panels' pills (v0.5.0).
            int crit = 0, warn = 0;
            foreach (var f in Findings)
            {
                if (f.Severity == "fail") crit++;
                else if (f.Severity == "warn") warn++;
            }
            string worst = crit > 0 ? "Critical" : (warn > 0 ? "Warning" : "");
            var pill = StatusHelpers.PillFor(worst, warn, crit);
            StatusLabel = pill.Label;
            StatusColor = pill.Fg;
            StatusBg    = pill.Bg;
        }

        // 0–60% green, 60–85% yellow, ≥85% red — same threshold the legacy
        // PowerShell tool used for disk/memory bands.
        private static Brush LoadColour(double pct)
        {
            if (pct >= 85) return StatusHelpers.Brush("RedBrush");
            if (pct >= 60) return StatusHelpers.Brush("YellowBrush");
            return StatusHelpers.Brush("AccentBrush");
        }

        private static Brush SeverityBrush(string sev)
        {
            switch (sev)
            {
                case "ok":   return StatusHelpers.Brush("GreenBrush");
                case "warn": return StatusHelpers.Brush("YellowBrush");
                case "fail": return StatusHelpers.Brush("RedBrush");
                default:      return StatusHelpers.Brush("MutedForegroundBrush");
            }
        }

        // Prefer the in-app Reports panel — pre-select the top entry there so
        // the tech sees the bundle inline instead of being thrown into
        // Notepad. Falls back to shelling out for the legacy
        // Pulse_Results_*.txt path when the Reports service has no top
        // entry but the legacy report path does.
        private void OpenLastReport()
        {
            // Preferred path: hand control to Reports.
            if (RequestOpenReport != null)
            {
                RequestOpenReport.Invoke(_lastReportFileName);
                return;
            }

            if (string.IsNullOrEmpty(_lastReportPath))
            {
                AddLog("No saved report is available to open.", "Warn");
                return;
            }
            try
            {
                var psi = new ProcessStartInfo(_lastReportPath) { UseShellExecute = true };
                Process.Start(psi);
            }
            catch
            {
                // ShellExecute can fail when no association exists — fall
                // back to Notepad explicitly so the click is never lost.
                try { Process.Start("notepad.exe", _lastReportPath); }
                catch (Exception ex)
                {
                    AddLog($"Failed to open report: {ex.Message}", "Fail");
                }
            }
        }

        // Set by MainViewModel after refreshing the Reports list — populates
        // the "Last Diagnostic Run" card with the most recent on-disk report,
        // and lets the Open Last Report button know which one to pre-select.
        public void ApplyLastReport(string fileName, DateTime? timestamp, string sizeLabel)
        {
            _lastReportFileName = fileName;
            if (string.IsNullOrEmpty(fileName))
            {
                IsLastRunEmpty = true;
                OnPropertyChanged(nameof(HasLastRun));
                UpdateTileStatuses();
                return;
            }
            IsLastRunEmpty = false;
            OnPropertyChanged(nameof(HasLastRun));
            if (timestamp.HasValue) LastRunWhen = timestamp.Value.ToString("MMM d, h:mm tt");
            if (string.IsNullOrEmpty(LastRunResult) || LastRunResult == "—") LastRunResult = "Saved report";
            if (!string.IsNullOrEmpty(sizeLabel)) LastRunSummary = $"Bundle: {fileName} ({sizeLabel})";
            UpdateTileStatuses();
        }

        // Filename of the on-disk report that the breadcrumb should
        // pre-select in the Reports panel. Lives next to _lastReportPath so
        // both the legacy file-open and the new in-app-navigate paths stay
        // available to the OpenLastReport command.
        private string _lastReportFileName;

        // ICommand wrapper that takes the tile's TargetNav string.
        private class NavigateCommandImpl : ICommand
        {
            private readonly Action<object> _execute;
            public NavigateCommandImpl(Action<object> execute) { _execute = execute; }
            public bool CanExecute(object parameter) => true;
            public void Execute(object parameter) => _execute(parameter);
            public event EventHandler CanExecuteChanged
            {
                add    { System.Windows.Input.CommandManager.RequerySuggested += value; }
                remove { System.Windows.Input.CommandManager.RequerySuggested -= value; }
            }
        }
    }

    /// <summary>Dashboard NIC port row — one per detected camera-NIC port.</summary>
    public class NicPortRow
    {
        public int    PortNumber  { get; set; }
        public string Name        { get; set; }
        public string SpeedLabel  { get; set; }
        public string StatusText  { get; set; }
        public Brush  StatusColor { get; set; }

        public static NicPortRow From(int n, CameraNicSnapshot s)
        {
            var spd = s.LinkSpeedBps >= 1_000_000_000UL
                ? $"{s.LinkSpeedBps / 1_000_000_000UL} Gbps"
                : s.LinkSpeedBps >= 1_000_000UL
                    ? $"{s.LinkSpeedBps / 1_000_000UL} Mbps"
                    : "—";
            string status; Brush colour;
            if (!s.IsUp) { status = "Down"; colour = StatusHelpers.Brush("MutedForegroundBrush"); }
            else if (s.LinkSpeedBps >= 1_000_000_000UL) { status = "Linked"; colour = StatusHelpers.Brush("GreenBrush"); }
            else { status = "Sub-gigabit"; colour = StatusHelpers.Brush("YellowBrush"); }
            return new NicPortRow
            {
                PortNumber = n,
                Name       = s.Name ?? "—",
                SpeedLabel = s.IsUp ? spd : "—",
                StatusText = status,
                StatusColor = colour,
            };
        }

        public static NicPortRow Empty(int n) => new NicPortRow
        {
            PortNumber  = n,
            Name        = "Not detected",
            SpeedLabel  = "—",
            StatusText  = "—",
            StatusColor = StatusHelpers.Brush("MutedForegroundBrush"),
        };
    }
}
