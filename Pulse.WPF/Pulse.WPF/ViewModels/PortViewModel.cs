using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// One port detail card. Bound 1:1 from the XAML in CameraConnectivityView.
    /// All UI updates flow through Set() so XAML auto-refreshes when a value
    /// changes (no Invalidate / Refresh calls anywhere).
    /// </summary>
    public class PortViewModel : ObservableObject
    {
        private string _name = "Port 1";
        public string Name { get => _name; set => Set(ref _name, value); }

        private string _device = "—";
        public string Device { get => _device; set => Set(ref _device, value); }

        private Brush _deviceColor = Brushes.Gray;
        public Brush DeviceColor { get => _deviceColor; set => Set(ref _deviceColor, value); }

        private string _speed = "—";
        public string Speed { get => _speed; set => Set(ref _speed, value); }

        private string _ip = "—";
        public string Ip { get => _ip; set => Set(ref _ip, value); }

        private string _mac = "—";
        public string Mac { get => _mac; set => Set(ref _mac, value); }

        private string _errors = "—";
        public string Errors { get => _errors; set => Set(ref _errors, value); }

        private Brush _errorsColor = Brushes.Gray;
        public Brush ErrorsColor { get => _errorsColor; set => Set(ref _errorsColor, value); }

        private string _statusText = "No Link";
        public string StatusText { get => _statusText; set => Set(ref _statusText, value); }

        private Brush _statusColor = Brushes.Gray;
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }

        // Drives the pulsing animation on the status dot when a diagnostic is running.
        private bool _isPulsing;
        public bool IsPulsing { get => _isPulsing; set => Set(ref _isPulsing, value); }
    }
}
