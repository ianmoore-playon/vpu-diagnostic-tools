using System.Windows.Input;
using Pulse.WPF.Helpers;
using Pulse.WPF.Services;
using Pulse.WPF.ViewModels.Stub;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Top-level viewmodel. Owns one VM per panel and exposes a SelectedNav
    /// string + CurrentView property so MainWindow.xaml can switch the
    /// content area via a single ContentControl + DataTemplates in App.xaml.
    /// Camera Connectivity uses the real wired-up VM. The other five panels
    /// use stub VMs with mock data until Agent B's diagnostic service work
    /// merges in.
    /// </summary>
    public class MainViewModel : ObservableObject
    {
        public CameraConnectivityViewModel Camera   { get; }
        public SystemOverviewViewModel     Home     { get; }
        public NetworkViewModel            Network  { get; }
        public HardwareViewModel           Hardware { get; }
        public ServicesViewModel           Services { get; }
        public DiskHealthViewModel         Disk     { get; }

        private string _selectedNav = "Camera";
        public string SelectedNav
        {
            get => _selectedNav;
            set
            {
                if (Set(ref _selectedNav, value))
                {
                    OnPropertyChanged(nameof(CurrentView));
                    OnPropertyChanged(nameof(IsHome));
                    OnPropertyChanged(nameof(IsNetwork));
                    OnPropertyChanged(nameof(IsCamera));
                    OnPropertyChanged(nameof(IsHardware));
                    OnPropertyChanged(nameof(IsServices));
                    OnPropertyChanged(nameof(IsDisk));
                }
            }
        }

        /// <summary>
        /// The currently visible panel viewmodel. App.xaml has a DataTemplate
        /// for each panel VM type so a single ContentControl can render any
        /// of them.
        /// </summary>
        public object CurrentView
        {
            get
            {
                switch (_selectedNav)
                {
                    case "Home":     return Home;
                    case "Network":  return Network;
                    case "Camera":   return Camera;
                    case "Hardware": return Hardware;
                    case "Services": return Services;
                    case "Disk":     return Disk;
                    default:         return Camera;
                }
            }
        }

        // IsX bindings drive the sidebar ToggleButton.IsChecked state. We use
        // bool flags + a one-way binding instead of a converter so the XAML
        // stays declarative.
        public bool IsHome     => _selectedNav == "Home";
        public bool IsNetwork  => _selectedNav == "Network";
        public bool IsCamera   => _selectedNav == "Camera";
        public bool IsHardware => _selectedNav == "Hardware";
        public bool IsServices => _selectedNav == "Services";
        public bool IsDisk     => _selectedNav == "Disk";

        /// <summary>
        /// Sidebar nav buttons bind this command with their nav-key as the
        /// CommandParameter (e.g. "Network").
        /// </summary>
        public ICommand NavigateCommand { get; }

        public MainViewModel()
        {
            // Tiny composition root for the pilot — DI container is overkill.
            INetworkAdapterService net = new NetworkAdapterService();
            IPixellotConfigService cfg = new PixellotConfigService();

            Camera   = new CameraConnectivityViewModel(net, cfg);
            Home     = new SystemOverviewViewModel();
            Network  = new NetworkViewModel();
            Hardware = new HardwareViewModel();
            Services = new ServicesViewModel();
            Disk     = new DiskHealthViewModel();

            NavigateCommand = new RelayCommand<string>(key =>
            {
                if (!string.IsNullOrEmpty(key)) SelectedNav = key;
            });

            // Wire the hub-tile "click" commands on the Home page to navigate.
            // Done here (not in the stub VM) so the stub VM stays free of
            // MainViewModel knowledge.
            foreach (var tile in Home.Tiles)
            {
                tile.NavigateCommand = NavigateCommand;
            }
        }
    }
}
