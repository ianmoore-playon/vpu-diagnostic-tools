using System.Collections.Generic;
using System.Threading.Tasks;

namespace Pulse.WPF.Services
{
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
    }
}
