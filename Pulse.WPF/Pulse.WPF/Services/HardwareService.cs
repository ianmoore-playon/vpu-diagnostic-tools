using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
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
        // Lazy-init so a missing SmartPoE.dll doesn't fault during DI / unit
        // tests. The Hardware panel only needs the service at refresh time.
        private static readonly System.Lazy<IPoeTelemetryService> _poe =
            new System.Lazy<IPoeTelemetryService>(() => new WindowsPoeTelemetryService());

        /// <inheritdoc />
        public bool PoeTelemetryAvailable => _poe.Value.IsAvailable;
        /// <inheritdoc />
        public string PoeTelemetryUnavailableReason => _poe.Value.UnavailableReason;
        /// <inheritdoc />
        public PoeBudgetReading GetPoeBudget() => _poe.Value.GetBudget();

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

        // PoE telemetry, real port (v0.5.0). Returns an empty list when the
        // SmartPoE.dll driver bundle isn't installed; the Hardware VM picks
        // up the empty state via PoeTelemetryAvailable / Reason.
        public List<PoePortReading> GetPoePortReadings()
        {
            try { return _poe.Value.GetPortReadings(); }
            catch { return new List<PoePortReading>(); }
        }
    }
}
