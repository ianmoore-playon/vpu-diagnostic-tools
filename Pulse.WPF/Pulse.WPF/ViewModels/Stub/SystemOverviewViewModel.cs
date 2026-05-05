using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Input;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;

namespace Pulse.WPF.ViewModels.Stub
{
    /// <summary>
    /// Stub viewmodel for SystemOverviewView (the Home page). Pre-populates
    /// 8 hub tiles + a believable "last run" summary so the WPF designer
    /// renders something realistic before Agent B wires the real diagnostic
    /// engine.
    /// </summary>
    public class SystemOverviewViewModel : StatusViewModelBase
    {
        public ObservableCollection<HubTileViewModel> Tiles { get; } = new ObservableCollection<HubTileViewModel>();

        private string _lastRunSummary = "Last full diagnostic: 12 minutes ago — 1 Warning";
        public string LastRunSummary { get => _lastRunSummary; set => Set(ref _lastRunSummary, value); }

        private string _serialNumber = "VPU-2024-08134";
        public string SerialNumber { get => _serialNumber; set => Set(ref _serialNumber, value); }

        private string _hostName = "VPU-MAINFIELD-12";
        public string HostName { get => _hostName; set => Set(ref _hostName, value); }

        public ICommand RunFullDiagnosticCommand { get; }
        public ICommand OpenLastReportCommand { get; }

        public SystemOverviewViewModel()
        {
            // Status pill aggregates across all tiles. Mock state: one warning
            // on Network, otherwise green.
            SetStatus("1 Warning", "YellowBrush", "WarnBgBrush");

            // Tile click navigates via the parent MainViewModel — wired by
            // MainViewModel when it constructs this VM. For the designer
            // we leave NavigateCommand null; clicks no-op gracefully.
            RunFullDiagnosticCommand = new RelayCommand(() => { });
            OpenLastReportCommand    = new RelayCommand(() => { });

            AddTile("Home",     "HomeOutline",     "System Overview",       "All hubs at a glance",                   "Healthy",   "GreenBrush",  "OkBgBrush");
            AddTile("Network",  "WifiCog",         "Network Configuration", "Adapters, IP, NTP, connectivity",        "1 Warning", "YellowBrush", "WarnBgBrush");
            AddTile("Camera",   "CameraOutline",   "Camera Connectivity",   "Per-port link, speed, errors",           "Healthy",   "GreenBrush",  "OkBgBrush");
            AddTile("Hardware", "Memory",          "Hardware & Peripherals", "GPU, monitor, input, PoE",              "Healthy",   "GreenBrush",  "OkBgBrush");
            AddTile("Services", "ServerNetwork",   "Pixellot Services",     "Agent, Coordinator, Scoreconnect",       "Healthy",   "GreenBrush",  "OkBgBrush");
            AddTile("Disk",     "Harddisk",        "Disk & System Health",  "SMART, free space, errors",              "Healthy",   "GreenBrush",  "OkBgBrush");
            AddTile("SysInfo",  "Information",     "System Information",    "OS, BIOS, uptime, build",                "Not run",   "MutedForegroundBrush", "BorderColBrush");
            AddTile("Events",   "AlertOutline",    "Event Viewer",          "System / Application errors (48 h)",     "Not run",   "MutedForegroundBrush", "BorderColBrush");
        }

        private void AddTile(string nav, string icon, string title, string desc,
                             string statusLabel, string brushKey, string bgKey)
        {
            Tiles.Add(new HubTileViewModel
            {
                NavKey       = nav,
                IconKind     = icon,
                Title        = title,
                Description  = desc,
                StatusText   = statusLabel,
                StatusColor  = (System.Windows.Media.Brush)Application.Current.Resources[brushKey],
                StatusBg     = (System.Windows.Media.Brush)Application.Current.Resources[bgKey],
            });
        }
    }
}
