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

        // ===== Adapter Details (v0.5.2 §6) =====
        //
        // Resolve one NIC by local MAC and populate a fully-flat POCO for
        // the in-app Adapter Details dialog. Every reader is wrapped in its
        // own try/catch so a partial failure (e.g. the WMI driver lookup
        // throws on a locked-down box) doesn't blank the rest of the sheet.
        public AdapterDetails GetAdapterDetails(string localMac)
        {
            if (string.IsNullOrWhiteSpace(localMac)) return null;
            var wanted = NormaliseMac(localMac);

            NetworkInterface match = null;
            try
            {
                foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
                {
                    string raw = null;
                    try { raw = nic.GetPhysicalAddress()?.ToString(); }
                    catch { /* keep iterating */ }
                    if (string.IsNullOrEmpty(raw)) continue;
                    if (NormaliseMac(FormatMac(raw)) == wanted) { match = nic; break; }
                }
            }
            catch { /* fall through — match stays null. */ }

            if (match == null) return null;

            var d = new AdapterDetails
            {
                LocalMac = FormatMac(match.GetPhysicalAddress()?.ToString() ?? ""),
            };

            try { d.Name        = match.Name; }        catch { }
            try { d.Description = match.Description; } catch { }
            try
            {
                d.Status = match.OperationalStatus == OperationalStatus.Up ? "Up"
                         : match.OperationalStatus == OperationalStatus.Down ? "Down"
                         : match.OperationalStatus.ToString();
            }
            catch { d.Status = "Unknown"; }
            try { d.LinkSpeed = FormatSpeedBps(match.Speed); } catch { d.LinkSpeed = "—"; }
            // Duplex isn't surfaced by NetworkInterface in .NET Framework.
            // Leave empty so the dialog hides the row rather than show "Unknown".
            d.Duplex = "";

            IPInterfaceProperties props = null;
            try { props = match.GetIPProperties(); } catch { }

            if (props != null)
            {
                // IPv4 unicast
                try
                {
                    var v4 = props.UnicastAddresses.FirstOrDefault(a =>
                        a.Address != null &&
                        a.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork);
                    if (v4 != null)
                    {
                        d.IPv4Address = v4.Address.ToString();
                        d.SubnetMask  = v4.IPv4Mask?.ToString() ?? PrefixToMask(v4.PrefixLength);
                    }
                }
                catch { }

                // IPv4 gateway
                try
                {
                    var gw = props.GatewayAddresses.FirstOrDefault(g =>
                        g?.Address != null &&
                        g.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork);
                    if (gw != null) d.DefaultGateway = gw.Address.ToString();
                }
                catch { }

                // DNS servers — IPv4 only is sufficient on a VPU.
                try
                {
                    var dns = props.DnsAddresses
                        .Where(a => a != null &&
                                    a.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                        .Select(a => a.ToString())
                        .ToArray();
                    if (dns.Length > 0) d.DnsServers = string.Join(", ", dns);
                }
                catch { }

                // DHCP — enabled flag + server + lease.
                try
                {
                    var v4Props = props.GetIPv4Properties();
                    if (v4Props != null)
                    {
                        d.IsDhcpEnabled   = v4Props.IsDhcpEnabled;
                        d.DhcpEnabledText = v4Props.IsDhcpEnabled ? "Enabled" : "Disabled";
                    }
                }
                catch { d.DhcpEnabledText = "Unknown"; }

                try
                {
                    var dhcp = props.DhcpServerAddresses?
                        .Where(a => a != null)
                        .Select(a => a.ToString())
                        .ToArray();
                    if (dhcp != null && dhcp.Length > 0) d.DhcpServer = string.Join(", ", dhcp);
                }
                catch { }

                // IPv6 unicast addresses + gateways.
                try
                {
                    var v6Addrs = props.UnicastAddresses
                        .Where(a => a?.Address != null &&
                                    a.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6)
                        .Select(a => a.Address.ToString())
                        .ToArray();
                    if (v6Addrs.Length > 0) d.IPv6Addresses = string.Join(", ", v6Addrs);

                    var v6Gws = props.GatewayAddresses
                        .Where(g => g?.Address != null &&
                                    g.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6)
                        .Select(g => g.Address.ToString())
                        .ToArray();
                    if (v6Gws.Length > 0) d.IPv6Gateways = string.Join(", ", v6Gws);
                }
                catch { }
            }

            // DHCP lease — not exposed by NetworkInterface; query the registry
            // / WMI Win32_NetworkAdapterConfiguration when available.
            TryFillDhcpLease(d, match);

            // Error counters from IPInterfaceStatistics.
            try
            {
                var stats = match.GetIPStatistics();
                if (stats != null)
                {
                    d.IncomingPacketsWithErrors = stats.IncomingPacketsWithErrors;
                    d.OutgoingPacketsWithErrors = stats.OutgoingPacketsWithErrors;
                    d.IncomingPacketsDiscarded  = stats.IncomingPacketsDiscarded;
                    d.OutgoingPacketsDiscarded  = stats.OutgoingPacketsDiscarded;
                }
            }
            catch { }

            // Driver info via WMI Win32_PnPSignedDriver. Best-effort; on a
            // locked-down box this throws and we leave the driver fields
            // empty.
            TryFillDriverInfo(d, match.Description);

            return d;
        }

        // ---- Adapter Details helpers ----
        private static string NormaliseMac(string mac)
        {
            if (string.IsNullOrEmpty(mac)) return "";
            var sb = new System.Text.StringBuilder(mac.Length);
            foreach (var c in mac)
            {
                if (c == ':' || c == '-' || c == '.' || c == ' ') continue;
                sb.Append(char.ToUpperInvariant(c));
            }
            return sb.ToString();
        }

        private static string FormatSpeedBps(long bps)
        {
            if (bps <= 0) return "—";
            if (bps >= 1_000_000_000L) return $"{bps / 1_000_000_000L} Gbps";
            if (bps >= 1_000_000L)     return $"{bps / 1_000_000L} Mbps";
            return $"{bps} bps";
        }

        private static string PrefixToMask(int prefix)
        {
            if (prefix < 0 || prefix > 32) return "/" + prefix;
            if (prefix == 0) return "0.0.0.0";
            uint mask = uint.MaxValue << (32 - prefix);
            return $"{(mask >> 24) & 0xFF}.{(mask >> 16) & 0xFF}.{(mask >> 8) & 0xFF}.{mask & 0xFF}";
        }

        // DHCP lease — query Win32_NetworkAdapterConfiguration by MAC. The
        // System.Management reference is already present (System Overview
        // panel uses it). Wrap every read independently.
        private static void TryFillDhcpLease(AdapterDetails d, NetworkInterface nic)
        {
            try
            {
                string mac = NormaliseMac(FormatMac(nic.GetPhysicalAddress()?.ToString() ?? ""));
                if (string.IsNullOrEmpty(mac)) return;
                using (var s = new System.Management.ManagementObjectSearcher(
                    "SELECT MACAddress, DHCPLeaseObtained, DHCPLeaseExpires FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = TRUE"))
                {
                    foreach (var mo in s.Get())
                    {
                        string moMac = null;
                        try { moMac = mo["MACAddress"] as string; } catch { }
                        if (string.IsNullOrEmpty(moMac)) continue;
                        if (NormaliseMac(moMac) != mac) continue;

                        try { d.DhcpLeaseObtained = FormatCimDate(mo["DHCPLeaseObtained"] as string); } catch { }
                        try { d.DhcpLeaseExpires  = FormatCimDate(mo["DHCPLeaseExpires"]  as string); } catch { }
                        break;
                    }
                }
            }
            catch { /* WMI unavailable — leave lease fields empty. */ }
        }

        // Win32_NetworkAdapterConfiguration returns a CIM DATETIME string
        // ("yyyyMMddHHmmss.ffffff±UUU"). Render the local DateTime.
        private static string FormatCimDate(string s)
        {
            if (string.IsNullOrEmpty(s) || s.Length < 14) return "";
            try
            {
                var dt = System.Management.ManagementDateTimeConverter.ToDateTime(s);
                return dt.ToString("yyyy-MM-dd HH:mm:ss");
            }
            catch { return ""; }
        }

        private static void TryFillDriverInfo(AdapterDetails d, string description)
        {
            if (string.IsNullOrEmpty(description)) return;
            try
            {
                // Match by DeviceName == description. The signed-driver class
                // has DriverName / DriverVersion / DriverDate (CIM DATETIME).
                using (var s = new System.Management.ManagementObjectSearcher(
                    "SELECT DeviceName, DriverName, DriverVersion, DriverDate FROM Win32_PnPSignedDriver"))
                {
                    foreach (var mo in s.Get())
                    {
                        string dev = null;
                        try { dev = mo["DeviceName"] as string; } catch { }
                        if (string.IsNullOrEmpty(dev)) continue;
                        if (!string.Equals(dev, description, System.StringComparison.OrdinalIgnoreCase)) continue;

                        try { d.DriverName    = (mo["DriverName"]    as string) ?? dev; } catch { d.DriverName = dev; }
                        try { d.DriverVersion = mo["DriverVersion"]  as string; } catch { }
                        try { d.DriverDate    = FormatCimDate(mo["DriverDate"] as string); } catch { }
                        break;
                    }
                }
            }
            catch { /* WMI unavailable or class missing — leave driver fields empty. */ }
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
        /// Forwarder kept for source-compat with existing callers in this file.
        /// The real implementation lives in <see cref="Pulse.WPF.Helpers.MacOuiTable.IsInvalidMac(string)"/>
        /// alongside the other MAC helpers (moved v0.5.0).
        /// </summary>
        public static bool IsInvalidMac(string mac) => Helpers.MacOuiTable.IsInvalidMac(mac);

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
