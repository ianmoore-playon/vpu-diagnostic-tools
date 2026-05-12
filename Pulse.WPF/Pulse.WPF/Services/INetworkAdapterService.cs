using System.Collections.Generic;
using System.Threading.Tasks;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Per-adapter "full details" POCO, populated for the Adapter Details
    /// dialog (v0.5.2 §6). Every field is best-effort — partial failure on
    /// any one reader must not blank the sheet; missing fields render as
    /// "—" or stay empty. Name chosen to avoid BCL collisions; there is no
    /// <c>System.Net.AdapterDetails</c> or similar.
    /// </summary>
    public class AdapterDetails
    {
        public string Name        { get; set; }
        public string Description { get; set; }
        public string Status      { get; set; }      // "Up" / "Down" / "Disconnected"
        public string LinkSpeed   { get; set; }      // e.g. "1 Gbps"
        public string Duplex      { get; set; }      // e.g. "Full" / "Half" — usually unknown on Windows

        // IPv4
        public string IPv4Address        { get; set; }
        public string SubnetMask         { get; set; }
        public string DefaultGateway     { get; set; }
        public bool   IsDhcpEnabled      { get; set; }
        public string DhcpEnabledText    { get; set; }   // "Enabled" / "Disabled" / "Unknown"
        public string DnsServers         { get; set; }
        public string DhcpServer         { get; set; }
        public string DhcpLeaseObtained  { get; set; }
        public string DhcpLeaseExpires   { get; set; }

        // IPv6 (collapsed by default — secondary)
        public string IPv6Addresses { get; set; }
        public string IPv6Gateways  { get; set; }

        // Identity
        public string LocalMac { get; set; }

        // Driver info — best-effort via WMI Win32_PnPSignedDriver.
        public string DriverName    { get; set; }
        public string DriverVersion { get; set; }
        public string DriverDate    { get; set; }

        // Counters — IPInterfaceStatistics.
        public long IncomingPacketsWithErrors { get; set; }
        public long OutgoingPacketsWithErrors { get; set; }
        public long IncomingPacketsDiscarded  { get; set; }
        public long OutgoingPacketsDiscarded  { get; set; }

        // Remote info copied from the live PortViewModel — the dialog
        // doesn't re-resolve. Empty when the tile has no remote.
        public string RemoteIp     { get; set; }
        public string RemoteMac    { get; set; }
        public string RemoteVendor { get; set; }
        public string RemoteRole   { get; set; }
    }


    /// <summary>
    /// Snapshot of one NIC port on the camera-NIC card. Returned from a
    /// fresh poll of Get-NetAdapter / GetIpNetTable. Equivalent to the
    /// per-port info the WinForms Update-HwPortDiagram pulls together.
    /// </summary>
    public class CameraNicSnapshot
    {
        public string Name { get; set; }                  // Windows adapter name, e.g. "Ethernet 24"
        public string Description { get; set; }           // e.g. "Intel(R) I210 Gigabit Network Connection #11"
        public string LocalMac { get; set; }              // Local NIC MAC (informational)
        public ulong  LinkSpeedBps { get; set; }          // 0 = down
        public bool   IsUp { get; set; }
        public long   ErrorCount { get; set; }            // OutboundPacketsWithErrors + ReceivedPacketsWithErrors
        public string RemoteIp { get; set; }              // ARP-discovered camera IP (link-local)
        public string RemoteMac { get; set; }             // ARP-discovered camera MAC
    }

    public interface INetworkAdapterService
    {
        /// <summary>
        /// Poll every Pixellot camera-NIC port (Intel I210 / I350 / 82574L /
        /// I211 / GIE7-pattern) and return per-port snapshots sorted by MAC
        /// (lowest MAC = Port 1, matching how WinForms maps physical port
        /// numbers in Update-HwPortDiagram).
        /// </summary>
        Task<List<CameraNicSnapshot>> GetCameraPortsAsync();

        /// <summary>
        /// Resolve a single adapter by its local MAC and return the full
        /// configuration block rendered in the Adapter Details dialog
        /// (v0.5.2 §6). Returns null when no adapter matches. Every field
        /// is wrapped independently so a partial failure (e.g. WMI driver
        /// lookup throws) still produces a usable POCO with the rest of
        /// the fields populated.
        /// </summary>
        AdapterDetails GetAdapterDetails(string localMac);
    }
}
