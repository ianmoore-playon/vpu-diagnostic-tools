using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One row in the Network panel "Adapters" card.
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
    /// One row in the Connectivity Tests card — port reachability test.
    /// Two field families coexist: aggregate (Target/Description/Result) used
    /// by Agent A's XAML, raw (Protocol/Port/Host/Purpose/Status) used by
    /// NetworkService. Status ↔ Result alias keeps both paths happy.
    /// </summary>
    public class PortTestResult : ObservableObject
    {
        public string Target      { get; set; } = "";    // "update.pixellot.com:443"
        public string Description { get; set; } = "";    // "Cloud upload"
        public string Result      { get; set; } = "";    // "Reachable", "Timed out", "Refused"
        public Brush  ResultColor { get; set; }

        // Raw fields populated by NetworkService.
        public string Protocol { get; set; } = "";       // "TCP" / "UDP"
        public int    Port     { get; set; }
        public string Host     { get; set; } = "";
        public string Purpose  { get; set; } = "";
        public string Status   { get => Result; set => Result = value; }
    }

    /// <summary>
    /// One row in the DNS resolution tests card.
    /// ResolvedTo ↔ Resolved + new Status field for the Agent B service.
    /// </summary>
    public class DomainTestResult : ObservableObject
    {
        public string Domain      { get; set; } = "";
        public string Resolved    { get; set; } = "";    // "203.0.113.10" or "Failed"
        public string Description { get; set; } = "";    // "Cloud control plane"
        public Brush  ResultColor { get; set; }

        // Aliases / additional fields used by NetworkService.
        public string ResolvedTo { get => Resolved; set => Resolved = value; }
        public string Status     { get; set; } = "";
    }

    /// <summary>
    /// IP / mask / gateway / DNS / NTP / DHCP block. Not a row — a
    /// dictionary-shaped VM so the XAML can render labelled key/value pairs
    /// without converters.
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
        public string Dhcp        { get; set; } = "";    // "Enabled" / "Disabled"
    }
}
