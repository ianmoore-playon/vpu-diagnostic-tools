using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// Common shape returned by the ScoreConnect III "list" endpoints —
    /// vendors, vendor sports, vendor configurations, devices. Every list
    /// row carries an opaque id plus a display name; the typed wrappers below
    /// preserve type-distinctness at call sites so e.g. a vendor-sport id
    /// can't be silently passed to <c>SetVendorAsync</c>.
    ///
    /// All type names are fully namespaced ("ScoreConnect" prefix) to avoid
    /// the v0.5.0-era BCL-collision class — "Vendor", "Device", "Configuration"
    /// are all popular names in framework assemblies.
    /// </summary>
    public abstract class ScoreConnectListItem : ObservableObject
    {
        private string _id = "";
        public string Id { get => _id; set => Set(ref _id, value); }

        private string _name = "";
        public string Name { get => _name; set => Set(ref _name, value); }

        public override string ToString() => Name ?? "";
    }

    /// <summary>One row from <c>get-vendor-list</c>.</summary>
    public class ScoreConnectVendorListItem : ScoreConnectListItem { }

    /// <summary>One row from <c>get-vendor-sports/{vendorId}</c>.</summary>
    public class ScoreConnectVendorSportListItem : ScoreConnectListItem { }

    /// <summary>One row from <c>get-vendor-configurations/{vendorSportId}</c>.</summary>
    public class ScoreConnectVendorConfigurationListItem : ScoreConnectListItem { }

    /// <summary>One row from <c>get-devices-list</c>.</summary>
    public class ScoreConnectDeviceListItem : ScoreConnectListItem
    {
        private string _vendor = "";
        public string Vendor { get => _vendor; set => Set(ref _vendor, value); }

        private string _sport = "";
        public string Sport { get => _sport; set => Set(ref _sport, value); }
    }
}
