using Pulse.WPF.Helpers;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Top-level viewmodel. Owns each panel's VM and exposes a "selected nav"
    /// so the sidebar can light up the active tab. For the pilot, only the
    /// Camera Connectivity VM is real — the other nav buttons are stubs that
    /// don't switch panels yet.
    /// </summary>
    public class MainViewModel : ObservableObject
    {
        public CameraConnectivityViewModel Camera { get; }

        private string _selectedNav = "Camera";
        public string SelectedNav { get => _selectedNav; set => Set(ref _selectedNav, value); }

        public MainViewModel()
        {
            // Tiny composition root for the pilot — DI container is overkill here.
            INetworkAdapterService net = new NetworkAdapterService();
            IPixellotConfigService cfg = new PixellotConfigService();
            Camera = new CameraConnectivityViewModel(net, cfg);
        }
    }
}
