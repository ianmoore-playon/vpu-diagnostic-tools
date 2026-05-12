using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One row in the "Available serial ports" card. Populated from the
    /// <c>get-available-ports</c> endpoint (returns the COM ports the OS sees
    /// plus a flag indicating whether ScoreConnect III is currently holding
    /// one open).
    ///
    /// Type name is fully namespaced ("ScoreConnect" prefix) so it doesn't
    /// collide with <see cref="System.IO.Ports.SerialPort"/> at usage sites.
    /// </summary>
    public class ScoreConnectSerialPortInfo : ObservableObject
    {
        private string _name = "";
        /// <summary>COM port name, e.g. "COM3".</summary>
        public string Name { get => _name; set => Set(ref _name, value); }

        private bool _isInUse;
        /// <summary>True when another process (or ScoreConnect itself) is
        /// currently holding the port open. Used to highlight conflicts.</summary>
        public bool IsInUse { get => _isInUse; set => Set(ref _isInUse, value); }

        private string _owningVendor = "";
        /// <summary>Vendor / sport that's currently bound to this port, when
        /// known. Empty when the port is free or the owner is opaque.</summary>
        public string OwningVendor { get => _owningVendor; set => Set(ref _owningVendor, value); }
    }
}
