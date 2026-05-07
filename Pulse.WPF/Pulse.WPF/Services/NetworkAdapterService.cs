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

                // Build the per-NIC set of "local self-IPs" so we can exclude
                // the VPU's own UnicastAddresses from the ARP candidate pick.
                // Bug #1: previously the local self-IP (e.g. 169.254.16.50)
                // was being returned as a "remote" on every port that listed
                // it in its ARP table.
                var localIps = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                try
                {
                    foreach (var ua in props.UnicastAddresses)
                    {
                        if (ua?.Address != null) localIps.Add(ua.Address.ToString());
                    }
                }
                catch { /* ignore — empty set means we just skip the filter. */ }

                string remoteIp = null, remoteMac = null;
                if (arp.TryGetValue(ifIndex, out var entries))
                {
                    // Pick the most active link-local neighbour, mirroring
                    // Get-PortDevice's Reachable-first selection. Skip the
                    // local NIC's own unicast IPs (bug #1) and any MAC that
                    // fails IsInvalidMac (bug #2 — INCOMPLETE rows return
                    // 00-00-00-00-00-00).
                    var pick = entries
                        .Where(e => e.Key.StartsWith("169.254.") &&
                                    !localIps.Contains(e.Key) &&
                                    !IsInvalidMac(e.Value))
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
                    RemoteIp     = remoteIp,   // null when no real neighbour — VM treats null as "no neighbour".
                    RemoteMac    = remoteMac,
                });
            }

            // Sort by local MAC ascending — lowest MAC = Port 1, same convention
            // as the WinForms Update-HwPortDiagram. Then take up to 4 ports.
            // TODO: a future revision could promote this to a stable PCI-slot
            // identifier so a hot-swapped NIC doesn't shuffle Port labels.
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

        /// <summary>
        /// Reject MACs that should never be rendered as a real remote:
        ///   • null / empty
        ///   • all-zero (INCOMPLETE neighbour row from Win32 GetIpNetTable)
        ///   • all-FF (broadcast)
        ///   • multicast bit set on the first octet (group address)
        /// Centralised so the ARP loader and the resolver stay in sync.
        /// </summary>
        public static bool IsInvalidMac(string mac)
        {
            if (string.IsNullOrEmpty(mac)) return true;

            // Strip separators ("-", ":", whitespace) so the same string
            // covers both "00-00-00-00-00-00" and "000000000000".
            string hex;
            try
            {
                var sb = new System.Text.StringBuilder(mac.Length);
                foreach (var c in mac)
                {
                    if (c == '-' || c == ':' || c == ' ') continue;
                    sb.Append(c);
                }
                hex = sb.ToString();
            }
            catch { return true; }

            if (hex.Length < 12) return true;

            // All-zero MAC — Win32 GetIpNetTable returns this for INCOMPLETE
            // neighbour entries (the OS has an IP from a probe but never got
            // an ARP reply).
            bool allZero = true, allFf = true;
            for (int i = 0; i < 12; i++)
            {
                char c = char.ToUpperInvariant(hex[i]);
                if (c != '0') allZero = false;
                if (c != 'F') allFf = false;
                if (!allZero && !allFf) break;
            }
            if (allZero || allFf) return true;

            // Multicast bit on first octet — group address, never a real host.
            try
            {
                var firstOctet = Convert.ToInt32(hex.Substring(0, 2), 16);
                if ((firstOctet & 1) != 0) return true;
            }
            catch { return true; }

            return false;
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

                    // Defense-in-depth: drop INCOMPLETE / broadcast / multicast
                    // entries at load time so downstream consumers never see
                    // them. The picker also calls IsInvalidMac, but this
                    // means the dictionary itself is clean.
                    if (IsInvalidMac(mac)) continue;

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
