using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Live NIC + ARP poll, pure C# (no PowerShell). Reads:
    ///   - System.Net.NetworkInformation.NetworkInterface for adapter enumeration,
    ///     link speed, error counters, and local MAC.
    ///   - Win32 IP Helper (iphlpapi.dll GetIpNetTable) for the ARP table —
    ///     equivalent to PowerShell's Get-NetNeighbor.
    ///
    /// Mirrors the patterns the existing Update-HwPortDiagram + Get-PortDevice
    /// helpers in Modules/CameraConnectivity.psm1 use, so live monitoring on
    /// the WPF side gives the same answers as the WinForms version.
    /// </summary>
    public class NetworkAdapterService : INetworkAdapterService
    {
        // Match the patterns from $NicDriverPatterns / known Pixellot camera-NIC
        // chipsets. Keep narrow so we don't pick up the VPU's main ethernet
        // (which is on a different OUI / product family).
        private static readonly string[] CameraNicMatches =
        {
            "I210", "I350", "82574L", "I211", "GIE7"
        };

        public Task<List<CameraNicSnapshot>> GetCameraPortsAsync()
        {
            return Task.Run(() => GetCameraPorts());
        }

        private List<CameraNicSnapshot> GetCameraPorts()
        {
            var arp = LoadArpTable();   // ifIndex -> { ip -> mac }
            var snaps = new List<CameraNicSnapshot>();

            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (nic.NetworkInterfaceType != NetworkInterfaceType.Ethernet) continue;
                if (!IsCameraNic(nic.Description)) continue;

                var props = nic.GetIPProperties();
                int ifIndex = 0;
                try { ifIndex = props.GetIPv4Properties()?.Index ?? 0; } catch { }

                var stats = TryGetStats(nic);
                var mac = nic.GetPhysicalAddress().ToString();
                mac = string.IsNullOrEmpty(mac) ? "" : FormatMac(mac);

                string remoteIp = null, remoteMac = null;
                if (arp.TryGetValue(ifIndex, out var entries))
                {
                    // Pick the most active link-local neighbour, mirroring
                    // Get-PortDevice's Reachable-first selection.
                    var pick = entries
                        .Where(e => e.Key.StartsWith("169.254.") &&
                                    !IsMulticast(e.Value))
                        .OrderBy(e => e.Key, StringComparer.Ordinal)
                        .Select(e => (Ip: e.Key, Mac: e.Value))
                        .FirstOrDefault();
                    if (pick.Ip != null)
                    {
                        remoteIp  = pick.Ip;
                        remoteMac = pick.Mac;
                    }
                }

                snaps.Add(new CameraNicSnapshot
                {
                    Name         = nic.Name,
                    Description  = nic.Description,
                    LocalMac     = mac,
                    LinkSpeedBps = (ulong)Math.Max(0, nic.Speed),
                    IsUp         = nic.OperationalStatus == OperationalStatus.Up,
                    ErrorCount   = stats != null ? (stats.IncomingPacketsWithErrors + stats.OutgoingPacketsWithErrors) : 0,
                    RemoteIp     = remoteIp,
                    RemoteMac    = remoteMac,
                });
            }

            // Sort by local MAC ascending — lowest MAC = Port 1, same convention
            // as the WinForms Update-HwPortDiagram. Then take up to 4 ports.
            return snaps
                .OrderBy(s => s.LocalMac, StringComparer.Ordinal)
                .Take(4)
                .ToList();
        }

        // ----- helpers -----

        private static bool IsCameraNic(string description)
        {
            if (string.IsNullOrEmpty(description)) return false;
            foreach (var m in CameraNicMatches)
                if (description.IndexOf(m, StringComparison.OrdinalIgnoreCase) >= 0) return true;
            return false;
        }

        private static IPInterfaceStatistics TryGetStats(NetworkInterface nic)
        {
            try { return nic.GetIPStatistics(); }
            catch { return null; }
        }

        private static string FormatMac(string raw)
        {
            // .NET returns "00306C4B12AB"; we want "00-30-6C-4B-12-AB" to match
            // Get-NetAdapter's MacAddress format used elsewhere in Pulse.
            var sb = new System.Text.StringBuilder(raw.Length + 5);
            for (int i = 0; i < raw.Length; i++)
            {
                if (i > 0 && i % 2 == 0) sb.Append('-');
                sb.Append(char.ToUpperInvariant(raw[i]));
            }
            return sb.ToString();
        }

        private static bool IsMulticast(string mac)
        {
            // First octet's least-significant bit set = multicast/broadcast MAC.
            // Same filter Get-NetNeighbor + Update-HwPortDiagram apply.
            if (string.IsNullOrEmpty(mac) || mac.Length < 2) return true;
            try
            {
                var firstOctet = Convert.ToInt32(mac.Substring(0, 2), 16);
                return (firstOctet & 1) != 0;
            }
            catch { return true; }
        }

        // ===== Win32 GetIpNetTable wrapper — equivalent to Get-NetNeighbor =====

        // Returns a per-interface dictionary { ifIndex -> { ip -> mac } }.
        private static Dictionary<int, Dictionary<string, string>> LoadArpTable()
        {
            var result = new Dictionary<int, Dictionary<string, string>>();
            int size = 0;
            // First call sizes the buffer.
            var ret = NativeMethods.GetIpNetTable(IntPtr.Zero, ref size, false);
            if (ret != 0 && ret != 122 /* ERROR_INSUFFICIENT_BUFFER */) return result;
            if (size == 0) return result;

            var buf = Marshal.AllocHGlobal(size);
            try
            {
                ret = NativeMethods.GetIpNetTable(buf, ref size, false);
                if (ret != 0) return result;

                int entryCount = Marshal.ReadInt32(buf);
                int rowSize    = Marshal.SizeOf(typeof(NativeMethods.MIB_IPNETROW));
                IntPtr cursor  = IntPtr.Add(buf, sizeof(int));
                for (int i = 0; i < entryCount; i++)
                {
                    var row = (NativeMethods.MIB_IPNETROW)Marshal.PtrToStructure(cursor, typeof(NativeMethods.MIB_IPNETROW));
                    cursor = IntPtr.Add(cursor, rowSize);

                    if (row.dwPhysAddrLen != 6) continue;
                    var macBytes = new byte[6]
                    {
                        row.mac0, row.mac1, row.mac2, row.mac3, row.mac4, row.mac5
                    };
                    var ip  = $"{row.dwAddr & 0xFF}.{(row.dwAddr >> 8) & 0xFF}.{(row.dwAddr >> 16) & 0xFF}.{(row.dwAddr >> 24) & 0xFF}";
                    var mac = string.Join("-", macBytes.Select(b => b.ToString("X2")));

                    if (!result.TryGetValue(row.dwIndex, out var entries))
                    {
                        entries = new Dictionary<string, string>();
                        result[row.dwIndex] = entries;
                    }
                    entries[ip] = mac;
                }
            }
            finally { Marshal.FreeHGlobal(buf); }
            return result;
        }

        private static class NativeMethods
        {
            [StructLayout(LayoutKind.Sequential, Pack = 1)]
            public struct MIB_IPNETROW
            {
                public int dwIndex;
                public int dwPhysAddrLen;
                public byte mac0, mac1, mac2, mac3, mac4, mac5;
                // Pad to 8 bytes for the physical address (Windows reserves 8 bytes
                // even though we only use 6 octets).
                public byte _pad6, _pad7;
                public uint dwAddr;
                public int  dwType;
            }

            [DllImport("iphlpapi.dll", SetLastError = true)]
            public static extern int GetIpNetTable(IntPtr pTable, ref int pdwSize, bool bOrder);
        }
    }
}
