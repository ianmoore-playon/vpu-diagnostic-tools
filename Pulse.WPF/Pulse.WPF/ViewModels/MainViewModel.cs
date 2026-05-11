using System.Threading.Tasks;
using System.Windows.Input;
using Pulse.WPF.Helpers;
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
        public HardwareViewModel Hardware { get; }
        public DiskHealthViewModel DiskHealth { get; }
        public EventViewerViewModel EventViewer { get; }
        public ReportsViewModel Reports { get; }

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
        public bool IsHardware       => _selectedNav == "Hardware";
        public bool IsServices       => _selectedNav == "Services";
        public bool IsDisk           => _selectedNav == "DiskHealth";
        public bool IsEventViewer    => _selectedNav == "EventViewer";
        public bool IsReports        => _selectedNav == "Reports";

        private void RaisePillFlags()
        {
            OnPropertyChanged(nameof(IsHome));
            OnPropertyChanged(nameof(IsSystemOverview));
            OnPropertyChanged(nameof(IsNetwork));
            OnPropertyChanged(nameof(IsCamera));
            OnPropertyChanged(nameof(IsHardware));
            OnPropertyChanged(nameof(IsServices));
            OnPropertyChanged(nameof(IsDisk));
            OnPropertyChanged(nameof(IsEventViewer));
            OnPropertyChanged(nameof(IsReports));
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
            // DashboardService composes the other panel services so the
            // Dashboard can render a single-page snapshot.
            IDashboardService dashboard = new DashboardService(netAdapters, net, svcs, disk);
            ISystemOverviewService specs = new SystemOverviewService();

            Dashboard = new DashboardViewModel(dashboard);
            SystemOverview = new SystemOverviewViewModel(specs);
            Network = new NetworkViewModel(net);
            Camera = new CameraConnectivityViewModel(netAdapters, cfg);
            Services = new ServicesViewModel(svcs);
            Hardware = new HardwareViewModel(hw);
            DiskHealth = new DiskHealthViewModel(disk);
            EventViewer = new EventViewerViewModel(events);
            Reports = new ReportsViewModel(reports);

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
                case "Services":        CurrentView = Services;       _ = SafeRefresh(Services.RefreshAsync); break;
                case "Hardware":        CurrentView = Hardware;       _ = SafeRefresh(Hardware.RefreshAsync); break;
                case "DiskHealth":      CurrentView = DiskHealth;     _ = SafeRefresh(DiskHealth.RefreshAsync); break;
                case "EventViewer":     CurrentView = EventViewer;    _ = SafeRefresh(EventViewer.RefreshAsync); break;
                case "Reports":         CurrentView = Reports;        _ = SafeRefresh(Reports.RefreshAsync); break;
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
