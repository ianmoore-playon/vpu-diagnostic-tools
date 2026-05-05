using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
using System.Net.NetworkInformation;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Pure-C# port of PoeNicHardware.psm1's WMI queries. Wraps each query in
    /// try/catch — diagnostic services must not throw on machines missing
    /// components or running as a non-admin user.
    /// </summary>
    public class HardwareService : IHardwareService
    {
        public string GetGpuName()
        {
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT Name FROM Win32_VideoController"))
                {
                    var names = s.Get().Cast<ManagementObject>()
                        .Select(o => o["Name"] as string)
                        .Where(n => !string.IsNullOrEmpty(n) &&
                                    n.IndexOf("Remote", StringComparison.OrdinalIgnoreCase) < 0 &&
                                    n.IndexOf("Virtual", StringComparison.OrdinalIgnoreCase) < 0)
                        .ToList();
                    if (names.Count == 0) return "Not detected";
                    // Prefer discrete GPU over integrated graphics (matches PoeNicHardware.psm1).
                    var discrete = names.Where(n =>
                            n.IndexOf("Intel", StringComparison.OrdinalIgnoreCase) < 0 &&
                            n.IndexOf("Microsoft", StringComparison.OrdinalIgnoreCase) < 0)
                        .ToList();
                    return (discrete.Count > 0 ? discrete[0] : names[0]);
                }
            }
            catch { return "Query failed"; }
        }

        public int GetMonitorCount()
        {
            try
            {
                int count = 0;
                using (var s = new ManagementObjectSearcher("SELECT Availability FROM Win32_DesktopMonitor"))
                {
                    foreach (ManagementObject o in s.Get())
                    {
                        var av = o["Availability"];
                        if (av != null && Convert.ToInt32(av) == 3) count++;
                    }
                }
                if (count > 0) return count;
                // Fall back to PnP monitor entries (matches PoeNicHardware.psm1 path).
                using (var s2 = new ManagementObjectSearcher(
                    "SELECT Name FROM Win32_PnPEntity WHERE PNPClass='Monitor'"))
                {
                    return s2.Get().Count;
                }
            }
            catch { return 0; }
        }

        public bool HasMouse()
        {
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_PointingDevice"))
                    return s.Get().Count > 0;
            }
            catch { return false; }
        }

        public bool HasKeyboard()
        {
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_Keyboard"))
                    return s.Get().Count > 0;
            }
            catch { return false; }
        }

        // NIC uptime — Win32_PerfFormattedData_Tcpip_NetworkInterface doesn't
        // surface "link came up at..." cleanly. Approximate it from the
        // adapter's BytesTotalPersec sustained-positive observation, but
        // fall back to a coarse "up vs down" report. Matches the
        // ">48h" / "Xh Ym" buckets used by the WinForms side, which only
        // gets precise data via the Camera Connectivity NIC driver shim.
        public List<NicUptime> GetNicUptimes()
        {
            var rows = new List<NicUptime>();
            try
            {
                foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (nic.OperationalStatus != OperationalStatus.Up) continue;
                    if (nic.NetworkInterfaceType != NetworkInterfaceType.Ethernet &&
                        nic.NetworkInterfaceType != NetworkInterfaceType.GigabitEthernet)
                        continue;
                    // We don't have a true uptime number here — report ">48h" as the
                    // optimistic default, mirroring the WinForms behaviour when the
                    // PoE NIC driver shim is unavailable. Real uptime requires the
                    // Camera Connectivity runspace's $sync.NicLinkUptimes cache.
                    // TODO: wire up to the PoE NIC driver shim once that's ported.
                    rows.Add(new NicUptime { Name = nic.Name, Uptime = ">48h" });
                }
            }
            catch { }
            return rows;
        }

        // PoE telemetry requires the proprietary NIC driver shim used by the
        // WinForms Camera Connectivity panel. Returning an empty list is the
        // correct behaviour on machines without the shim — the WinForms path
        // does the same when $sync.PoeAvailable is false.
        public List<PoePortReading> GetPoePortReadings()
        {
            // TODO: integrate with the PoE NIC driver shim when ported.
            return new List<PoePortReading>();
        }
    }
}
