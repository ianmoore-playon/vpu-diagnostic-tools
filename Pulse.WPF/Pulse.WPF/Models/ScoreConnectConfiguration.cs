using System.Collections.Generic;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// Typed projection of the ScoreConnect III "current configuration"
    /// response. The HTTP source is the v1 endpoint
    /// <c>api/v1/configuration/get-current-configuration-extended</c> (with a
    /// graceful fallback to <c>get-current-configuration</c>).
    ///
    /// The JSON shape isn't documented — every field is parsed defensively so
    /// a renamed or missing key surfaces as an empty string rather than an
    /// exception. The <see cref="ExtendedFields"/> dictionary captures
    /// anything the typed properties don't recognise so we can render the
    /// raw key/value pairs in the panel without losing data.
    ///
    /// Type name is fully namespaced ("ScoreConnect" prefix) — both
    /// <c>Configuration</c> and <c>Device</c> collide with too many BCL types
    /// to be safe as bare names.
    /// </summary>
    public class ScoreConnectConfiguration : ObservableObject
    {
        private string _vendor = "";
        public string Vendor { get => _vendor; set => Set(ref _vendor, value); }

        private string _sport = "";
        public string Sport { get => _sport; set => Set(ref _sport, value); }

        private string _device = "";
        public string Device { get => _device; set => Set(ref _device, value); }

        private string _serialPort = "";
        public string SerialPort { get => _serialPort; set => Set(ref _serialPort, value); }

        private string _firmware = "";
        public string Firmware { get => _firmware; set => Set(ref _firmware, value); }

        private string _eventType = "";
        public string EventType { get => _eventType; set => Set(ref _eventType, value); }

        /// <summary>Vendor configuration id. Used by SetVendorConfiguration
        /// write calls so the user's edit can round-trip on the ScoreConnect side.</summary>
        private string _vendorConfigurationId = "";
        public string VendorConfigurationId
        {
            get => _vendorConfigurationId;
            set => Set(ref _vendorConfigurationId, value);
        }

        /// <summary>Vendor configuration display name (v0.6.1). The real
        /// response shape uses <c>vendorConfigurationName</c> for the
        /// human-readable label (e.g. "Wired") — separate from the id.</summary>
        private string _vendorConfigurationName = "";
        public string VendorConfigurationName
        {
            get => _vendorConfigurationName;
            set => Set(ref _vendorConfigurationName, value);
        }

        /// <summary>Vendor id (numeric). Surfaced separately from the name
        /// since some ScoreConnect Set endpoints take id, not name.</summary>
        private string _vendorId = "";
        public string VendorId { get => _vendorId; set => Set(ref _vendorId, value); }

        /// <summary>Vendor-sport id (numeric).</summary>
        private string _vendorSportId = "";
        public string VendorSportId { get => _vendorSportId; set => Set(ref _vendorSportId, value); }

        /// <summary>Any extra fields the response carried that the typed
        /// properties above don't capture. Rendered as a raw key/value table
        /// in the configuration card so nothing is lost on a version drift.</summary>
        public Dictionary<string, string> ExtendedFields { get; }
            = new Dictionary<string, string>();

        /// <summary>True when every typed field is empty — used by the VM to
        /// emit the "No scoreboard device configured" warning.</summary>
        public bool IsEmpty
        {
            get
            {
                return string.IsNullOrWhiteSpace(Vendor)
                    && string.IsNullOrWhiteSpace(Sport)
                    && string.IsNullOrWhiteSpace(Device)
                    && string.IsNullOrWhiteSpace(SerialPort)
                    && string.IsNullOrWhiteSpace(Firmware)
                    && string.IsNullOrWhiteSpace(EventType);
            }
        }
    }
}
