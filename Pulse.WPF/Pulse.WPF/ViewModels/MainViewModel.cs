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

        private void RaisePillFlags()
        {
            OnPropertyChanged(nameof(IsHome));
            OnPropertyChanged(nameof(IsSystemOverview));
            OnPropertyChanged(nameof(IsNetwork));
            OnPropertyChanged(nameof(IsCamera));
            OnPropertyChanged(nameof(IsHardware));
            OnPropertyChanged(nameof(IsServices));
            OnPropertyChanged(nameof(IsDisk));
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

            // Hub tile clicks request a nav change — wire that back through us.
            Dashboard.RequestNavigate = target =>
            {
                if (!string.IsNullOrEmpty(target)) SelectedNav = target;
            };

            NavigateCommand = new NavigateImpl(target =>
            {
                var s = target as string;
                if (!string.IsNullOrEmpty(s)) SelectedNav = s;
            });

            UpdateCurrentView();
        }

        // Dispatch the panel switch + fire the panel's refresh in the background.
        // Errors during refresh are swallowed — diagnostic services must not
        // crash the UI when a probe fails.
        private void UpdateCurrentView()
        {
            switch (_selectedNav)
            {
                case "Network":         CurrentView = Network;        _ = SafeRefresh(Network.RefreshAsync); break;
                case "Camera":          CurrentView = Camera;         break; // Camera VM self-refreshes via its DispatcherTimer.
                case "Services":        CurrentView = Services;       _ = SafeRefresh(Services.RefreshAsync); break;
                case "Hardware":        CurrentView = Hardware;       _ = SafeRefresh(Hardware.RefreshAsync); break;
                case "DiskHealth":      CurrentView = DiskHealth;     _ = SafeRefresh(DiskHealth.RefreshAsync); break;
                case "SystemOverview":  CurrentView = SystemOverview; _ = SafeRefresh(SystemOverview.RefreshAsync); break;
                case "Dashboard":
                default:
                    CurrentView = Dashboard;
                    _ = SafeRefresh(Dashboard.RefreshAsync);
                    break;
            }
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
