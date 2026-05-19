using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Top-level viewmodel. Constructs every panel VM at startup so navigation
    /// is instant — each panel's ViewModel owns its data and keeps it across
    /// nav switches. Each panel's RefreshAsync() is invoked when it becomes
    /// the CurrentView so techs see live data on first visit.
    /// </summary>
    public class MainViewModel : ObservableObject
    {
        // Panel ViewModels — exposed so XAML can bind regardless of CurrentView.
        public DashboardViewModel Dashboard { get; }
        public SystemOverviewViewModel SystemOverview { get; }   // hardware/OS specs page (was "System Information" in legacy)
        public NetworkViewModel Network { get; }
        public CameraConnectivityViewModel Camera { get; }
        public ServicesViewModel Services { get; }
        public DiskHealthViewModel DiskHealth { get; }
        public EventViewerViewModel EventViewer { get; }
        public ReportsViewModel Reports { get; }
        // v0.6.7 — two minimal sidebar entries that used to be IsEnabled=False
        // placeholders. Settings exposes the ScoreConnect URL editor + folder
        // shortcuts + a manual "Run baseline now" trigger; About is an identity
        // card (icon + version + hostname + GitHub link).
        public SettingsViewModel Settings { get; }
        public AboutViewModel About { get; }
        public ScoreConnectViewModel ScoreConnect { get; }

        // v0.5.6 — startup baseline orchestrator. Owned here so App.xaml.cs
        // can kick the first run after the main window shows, and the
        // Dashboard re-run button can fire the same instance.
        public Pulse.WPF.Helpers.BaselineRunner Baseline { get; }
        private readonly IReportsService _reportsService;
        private readonly SupportBundleService _supportBundleService;

        // Sidebar state. SelectedNav drives CurrentView.
        // Accepts a few alias keys ("Home" → "Dashboard", "Disk" → "DiskHealth",
        // and the legacy "SystemOverview" → "Dashboard" mapping is gone now —
        // "SystemOverview" canonically points to the specs page).
        private string _selectedNav = "Dashboard";
        public string SelectedNav
        {
            get => _selectedNav;
            set
            {
                var canonical = NormaliseNavKey(value);
                if (Set(ref _selectedNav, canonical))
                {
                    // v0.5.5: stamp every nav switch into the rolling log so
                    // a tech reading the daily log can see the user's
                    // breadcrumb trail through the panels.
                    try
                    {
                        Pulse.WPF.Helpers.AppLogFile.Instance.WriteLine(
                            "Nav", "Info", $"Navigated to {canonical}");
                    }
                    catch { }
                    UpdateCurrentView();
                    RaisePillFlags();
                }
            }
        }

        private static string NormaliseNavKey(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return "Dashboard";
            switch (value.Trim())
            {
                case "Home":           return "Dashboard";
                case "Disk":           return "DiskHealth";
                case "Hardware":       return "SystemOverview";
                // The Dashboard Quick Nav tile for Event Viewer uses the
                // legacy "Events" key from when the panel hadn't shipped —
                // map it through here so a single rename is enough.
                case "Events":         return "EventViewer";
                default:               return value.Trim();
            }
        }

        // ---- IsXxx flags (used by sidebar ToggleButton.IsChecked bindings) ----
        public bool IsHome           => _selectedNav == "Dashboard";
        public bool IsSystemOverview => _selectedNav == "SystemOverview";
        public bool IsNetwork        => _selectedNav == "Network";
        public bool IsCamera         => _selectedNav == "Camera";
        public bool IsScoreConnect   => _selectedNav == "ScoreConnect";
        public bool IsServices       => _selectedNav == "Services";
        public bool IsDisk           => _selectedNav == "DiskHealth";
        public bool IsEventViewer    => _selectedNav == "EventViewer";
        public bool IsReports        => _selectedNav == "Reports";
        public bool IsSettings       => _selectedNav == "Settings";
        public bool IsAbout          => _selectedNav == "About";

        private void RaisePillFlags()
        {
            OnPropertyChanged(nameof(IsHome));
            OnPropertyChanged(nameof(IsSystemOverview));
            OnPropertyChanged(nameof(IsNetwork));
            OnPropertyChanged(nameof(IsCamera));
            OnPropertyChanged(nameof(IsScoreConnect));
            OnPropertyChanged(nameof(IsServices));
            OnPropertyChanged(nameof(IsDisk));
            OnPropertyChanged(nameof(IsEventViewer));
            OnPropertyChanged(nameof(IsReports));
            OnPropertyChanged(nameof(IsSettings));
            OnPropertyChanged(nameof(IsAbout));
        }

        private object _currentView;
        public object CurrentView
        {
            get => _currentView;
            private set => Set(ref _currentView, value);
        }

        // Convenience command for sidebar buttons — bound with CommandParameter
        // = "Network", "Camera", etc.
        public ICommand NavigateCommand { get; }

        public MainViewModel()
        {
            // Tiny composition root — full DI container is overkill here.
            INetworkAdapterService netAdapters = new NetworkAdapterService();
            IPixellotConfigService cfg = new PixellotConfigService();
            INetworkService net = new NetworkService();
            IHardwareService hw = new HardwareService();
            IServicesService svcs = new ServicesService();
            IDiskHealthService disk = new DiskHealthService();
            IEventViewerService events = new EventViewerService();
            IReportsService reports = new ReportsService();
            _reportsService = reports;
            _supportBundleService = new SupportBundleService(reports.ReportsDirectory);
            // v0.6.0: shared HttpClient for the ScoreConnect HTTP API. One
            // instance lives for the lifetime of the app (recommended
            // pattern — new-per-call exhausts loopback sockets under
            // repeated panel refreshes). The Timeout knob is set generously
            // and each call layers its own per-request CancellationToken.
            var scoreConnectHttp = new System.Net.Http.HttpClient
            {
                Timeout = System.TimeSpan.FromSeconds(15),
            };
            IScoreConnectService scoreConnect = new ScoreConnectService(scoreConnectHttp);
            // DashboardService composes the other panel services so the
            // Dashboard can render a single-page snapshot.
            IDashboardService dashboard = new DashboardService(netAdapters, net, svcs, disk);
            ISystemOverviewService specs = new SystemOverviewService();

            Dashboard = new DashboardViewModel(dashboard);
            SystemOverview = new SystemOverviewViewModel(specs, hw);
            Network = new NetworkViewModel(net);
            // v0.8.16-beta: Camera Connectivity now pulls NIC driver events
            // from the System log on a slow secondary timer for per-port
            // fault correlation (Intel SmartSpeed downgrades, link
            // disconnects, etc.). The event service is optional - the
            // panel functions normally without it but skips the supplemental
            // event-log signal.
            Camera = new CameraConnectivityViewModel(netAdapters, cfg, events);
            ScoreConnect = new ScoreConnectViewModel(scoreConnect);
            Services = new ServicesViewModel(svcs);
            DiskHealth = new DiskHealthViewModel(disk);
            EventViewer = new EventViewerViewModel(events);
            Reports = new ReportsViewModel(reports);
            // v0.6.7 — Settings + About. Settings exposes a hook that
            // MainViewModel populates below so the panel can fire the
            // baseline runner without taking a hard dependency on it.
            Settings = new SettingsViewModel();
            About = new AboutViewModel();

            // v0.5.6 — wire the baseline orchestrator with references to every
            // panel VM. The Dashboard subscribes for the banner UI; App.xaml.cs
            // kicks the first run once the main window shows.
            Baseline = new Pulse.WPF.Helpers.BaselineRunner(
                Dashboard, SystemOverview, Network, Camera,
                Services, DiskHealth, EventViewer, ScoreConnect);
            Dashboard.AttachBaseline(Baseline);
            Dashboard.ApplyPersistedBaseline(Baseline.LastSnapshot);
            Dashboard.GenerateSupportBundleAsyncHook = GenerateSupportBundleAsync;
            Reports.GenerateSupportBundleAsyncHook = GenerateSupportBundleAsync;
            CommandManager.InvalidateRequerySuggested();
            // v0.6.7 — wire the Settings panel's "Run baseline now" button
            // back through the orchestrator. Kept as a Func hook so Settings
            // doesn't take a direct dependency on BaselineRunner.
            Settings.RunBaselineAsyncHook = () => Baseline.RunAsync();

            // Hub tile clicks request a nav change — wire that back through us.
            Dashboard.RequestNavigate = target =>
            {
                if (!string.IsNullOrEmpty(target)) SelectedNav = target;
            };

            // "Open Last Report" — switch to Reports and pre-select the
            // supplied filename. If no filename is supplied (no on-disk
            // report yet) the navigation alone is still useful: the Reports
            // panel will show its own muted empty state.
            Dashboard.RequestOpenReport = fileName =>
            {
                if (!string.IsNullOrEmpty(fileName)) Reports.PreselectFileName = fileName;
                SelectedNav = "Reports";
            };

            // Push the top-of-list report into the Dashboard "Last Diagnostic
            // Run" card as soon as Reports loads. Reports populates on its
            // own Task.Run in its ctor; we poll its CollectionChanged so the
            // Dashboard updates without us needing a second background
            // fetch here.
            Reports.Reports.CollectionChanged += (_, __) => PushTopReportToDashboard();
            // First-paint push — in case the collection populates before
            // we hook the event, we still want the card to update once.
            PushTopReportToDashboard();

            NavigateCommand = new NavigateImpl(target =>
            {
                var s = target as string;
                if (!string.IsNullOrEmpty(s)) SelectedNav = s;
            });

            UpdateCurrentView();
        }

        // Dispatch the panel switch + fire the panel's refresh in the background.
        // Errors during refresh are swallowed — diagnostic services must not
        // crash the UI when a probe fails. The Dashboard's live-update
        // DispatcherTimer is started when navigating to it and stopped when
        // navigating away so we don't waste a PerformanceCounter sample +
        // WMI query every 2 s while the user is on a different panel.
        private void UpdateCurrentView()
        {
            // Stop the dashboard live timer before switching away.
            if (CurrentView == Dashboard) Dashboard?.StopLiveUpdates();

            switch (_selectedNav)
            {
                case "Network":         CurrentView = Network;        _ = SafeRefresh(Network.RefreshAsync); break;
                case "Camera":          CurrentView = Camera;         break; // Camera VM self-refreshes via its DispatcherTimer.
                case "ScoreConnect":    CurrentView = ScoreConnect;   _ = SafeRefresh(ScoreConnect.RefreshAsync); break;
                case "Services":        CurrentView = Services;       _ = SafeRefresh(Services.RefreshAsync); break;
                case "DiskHealth":      CurrentView = DiskHealth;     _ = SafeRefresh(DiskHealth.RefreshAsync); break;
                case "EventViewer":     CurrentView = EventViewer;    _ = SafeRefresh(EventViewer.RefreshAsync); break;
                case "Reports":         CurrentView = Reports;        _ = SafeRefresh(Reports.RefreshAsync); break;
                case "Settings":        CurrentView = Settings;       break; // no refresh — read from AppSettings on construction
                case "About":           CurrentView = About;          break; // pure identity card
                case "SystemOverview":  CurrentView = SystemOverview; _ = SafeRefresh(SystemOverview.RefreshAsync); break;
                case "Dashboard":
                default:
                    CurrentView = Dashboard;
                    Dashboard.StartLiveUpdates();
                    _ = SafeRefresh(Dashboard.RefreshAsync);
                    break;
            }
        }

        // Hand the most-recent report from the Reports panel to the
        // Dashboard so the "Last Diagnostic Run" card shows a real value
        // (or its muted empty state when there are no reports yet).
        private void PushTopReportToDashboard()
        {
            if (Reports == null || Dashboard == null) return;
            var top = Reports.Reports.Count > 0 ? Reports.Reports[0] : null;
            if (top == null) Dashboard.ApplyLastReport(null, null, null);
            else              Dashboard.ApplyLastReport(top.FileName, top.Timestamp, top.SizeLabel);
        }

        private async Task<string> GenerateSupportBundleAsync()
        {
            var snapshot = CaptureCurrentBaselineSnapshot();
            var sections = CaptureSupportBundleSections();
            var logLines = _reportsService.GetRecentAppLogLines(80);

            var path = await Task.Run(() =>
                _supportBundleService.Create(snapshot, sections, logLines)).ConfigureAwait(false);

            if (snapshot != null)
            {
                snapshot.SupportBundlePath = path;
                Baseline.SaveSnapshot(snapshot);
            }

            AppLogFile.Instance.WriteLine("Reports", "Info",
                $"Support bundle created: {path}");

            await Reports.RefreshAsync().ConfigureAwait(false);
            var fileName = string.IsNullOrEmpty(path) ? "" : Path.GetFileName(path);
            var app = Application.Current;
            if (app != null)
            {
                app.Dispatcher.Invoke(() =>
                {
                    if (!string.IsNullOrEmpty(fileName)) Reports.PreselectFileName = fileName;
                    PushTopReportToDashboard();
                });
            }
            return path;
        }

        private BaselineSnapshot CaptureCurrentBaselineSnapshot()
        {
            BaselineSnapshot snapshot = null;
            void collect()
            {
                snapshot = Baseline.CaptureCurrentSnapshot();
            }

            var app = Application.Current;
            if (app != null && !app.Dispatcher.CheckAccess()) app.Dispatcher.Invoke(collect);
            else collect();
            return snapshot;
        }

        private List<SupportBundleSection> CaptureSupportBundleSections()
        {
            List<SupportBundleSection> sections = null;
            void collect()
            {
                sections = new List<SupportBundleSection>
                {
                    Section("Dashboard", "Dashboard.txt", Dashboard.BuildReportText()),
                    Section("System Overview", "SystemOverview.txt", SystemOverview.BuildReportText()),
                    Section("Network", "Network.txt", Network.BuildReportText()),
                    Section("Camera", "Camera.txt", Camera.BuildReportText()),
                    Section("ScoreConnect", "ScoreConnect.txt", ScoreConnect.BuildReportText()),
                    Section("Services", "Services.txt", Services.BuildReportText()),
                    Section("Disk Health", "DiskHealth.txt", DiskHealth.BuildReportText()),
                    Section("Event Viewer", "EventViewer.txt", EventViewer.BuildReportText()),
                };
            }

            var app = Application.Current;
            if (app != null && !app.Dispatcher.CheckAccess()) app.Dispatcher.Invoke(collect);
            else collect();
            return sections ?? new List<SupportBundleSection>();
        }

        private static SupportBundleSection Section(string title, string fileName, string content)
        {
            return new SupportBundleSection
            {
                Title = title,
                FileName = fileName,
                Content = content ?? "",
            };
        }

        private static async Task SafeRefresh(System.Func<Task> refresh)
        {
            try { await refresh().ConfigureAwait(false); } catch { /* logged in panel VM */ }
        }

        // Local ICommand that takes a parameter — for sidebar buttons.
        private class NavigateImpl : ICommand
        {
            private readonly System.Action<object> _execute;
            public NavigateImpl(System.Action<object> execute) { _execute = execute; }
            public bool CanExecute(object parameter) => true;
            public void Execute(object parameter) => _execute(parameter);
            public event System.EventHandler CanExecuteChanged
            {
                add { System.Windows.Input.CommandManager.RequerySuggested += value; }
                remove { System.Windows.Input.CommandManager.RequerySuggested -= value; }
            }
        }
    }
}
