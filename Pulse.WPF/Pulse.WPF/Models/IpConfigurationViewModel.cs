namespace Pulse.WPF.Models
{
    /// <summary>
    /// Snapshot of the primary (Internet-bound) interface's IPv4 settings + NTP.
    /// Despite the name, this is a plain DTO — the panel ViewModel exposes one
    /// of these as a property and re-creates it on each refresh.
    /// </summary>
    public class IpConfigurationViewModel
    {
        public string IpAddress { get; set; }
        public string SubnetMask { get; set; } // full dotted form
        public string Gateway { get; set; }
        public string DnsServers { get; set; }
        public string Dhcp { get; set; }       // "Enabled" / "Disabled"
        public string NtpServer { get; set; }  // configured peer (registry)
        public string NtpSource { get; set; }  // currently synced (w32tm /query /source)
    }
}
