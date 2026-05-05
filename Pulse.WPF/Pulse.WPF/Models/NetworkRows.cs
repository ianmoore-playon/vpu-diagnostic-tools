using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One row in the Network panel "Adapters" card. Mirrors the columns the
    /// WinForms NetworkDiagnostics.psm1 renders (Name, MAC, IP, Speed, Purpose).
    /// "Purpose" is the v1.0.48 column — labels each NIC as Camera/Internet/PoE.
    /// </summary>
    public class NetworkAdapterRow : ObservableObject
    {
        public string Name        { get; set; } = "";
        public string Description { get; set; } = "";
        public string Mac         { get; set; } = "";
        public string Ip          { get; set; } = "";
        public string Speed       { get; set; } = "";
        public string Purpose     { get; set; } = "";   // "Camera", "Internet", "Management", etc.
        public string LinkState   { get; set; } = "";   // "1 Gbps", "100 Mbps", "Down"
        public Brush  LinkColor   { get; set; }
        public Brush  PurposeColor { get; set; }
    }

    /// <summary>
    /// One row in the Connectivity Tests card — port reachability test
    /// (e.g. "TCP 443 to update.pixellot.com").
    /// </summary>
    public class PortTestResult : ObservableObject
    {
        public string Target      { get; set; } = "";    // "update.pixellot.com:443"
        public string Description { get; set; } = "";    // "Cloud upload"
        public string Result      { get; set; } = "";    // "Reachable", "Timed out", "Refused"
        public Brush  ResultColor { get; set; }
    }

    /// <summary>
    /// One row in the DNS resolution tests card.
    /// </summary>
    public class DomainTestResult : ObservableObject
    {
        public string Domain      { get; set; } = "";
        public string Resolved    { get; set; } = "";    // "203.0.113.10" or "Failed"
        public string Description { get; set; } = "";    // "Cloud control plane"
        public Brush  ResultColor { get; set; }
    }

    /// <summary>
    /// IP / mask / gateway / DNS / NTP block. Not a row — a dictionary-shaped
    /// VM so the XAML can render labelled key/value pairs without converters.
    /// </summary>
    public class IpConfigurationViewModel : ObservableObject
    {
        public string AdapterName { get; set; } = "";
        public string IpAddress   { get; set; } = "";
        public string SubnetMask  { get; set; } = "";
        public string Gateway     { get; set; } = "";
        public string DnsServers  { get; set; } = "";
        public string NtpServer   { get; set; } = "";
        public string NtpSource   { get; set; } = "";    // "Group Policy", "Local config", etc.
    }
}
