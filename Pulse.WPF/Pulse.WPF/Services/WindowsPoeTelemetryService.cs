using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Real C# port of the SmartPoE shim used by the PowerShell side
    /// (Modules/UIHelpers.psm1 + Modules/CameraConnectivity.psm1 →
    /// "PoE Budget" / "PoE Status" sections). Probes the same locations
    /// the PowerShell tool searches, then P/Invokes against SmartPoE.dll
    /// when present.
    ///
    /// Behaviour when the DLL isn't installed: <see cref="IsAvailable"/>
    /// stays false and <see cref="UnavailableReason"/> contains a copy-
    /// paste-able explanation. The Hardware panel renders that string in
    /// an empty-state card and adds a Finding row so the tech can see
    /// what's missing.
    /// </summary>
    public sealed class WindowsPoeTelemetryService : IPoeTelemetryService, IDisposable
    {
        private string _resolvedDllPath;
        private bool _registered;
        private const ushort CardNumber = 0;

        public bool IsAvailable { get; private set; }
        public string UnavailableReason { get; private set; } = "";

        public WindowsPoeTelemetryService()
        {
            try { TryInitialise(); }
            catch (Exception ex)
            {
                IsAvailable = false;
                UnavailableReason = $"SmartPoE init threw {ex.GetType().Name}: {ex.Message}";
            }
        }

        private void TryInitialise()
        {
            _resolvedDllPath = LocateDll();
            if (_resolvedDllPath == null)
            {
                UnavailableReason = "PoE telemetry requires the ADLINK SmartPoE driver bundle (SmartPoE.dll). Not installed at any of the standard locations on this host.";
                return;
            }

            // SetDllDirectory so the late-bound P/Invoke finds it. Same trick
            // the PowerShell tool uses via the implicit working directory.
            try
            {
                var dir = Path.GetDirectoryName(_resolvedDllPath);
                if (!string.IsNullOrEmpty(dir)) NativeMethods.SetDllDirectory(dir);
            }
            catch { }

            short rc = NativeMethods.SmartPoE_Register_Card(CardNumber);
            if (rc != 0)
            {
                UnavailableReason = $"SmartPoE_Register_Card returned {rc} — PoE card not detected on this system. " +
                                    "Common cause: GIE64 / 82574L NIC variants do not expose PoE telemetry.";
                return;
            }
            _registered = true;
            IsAvailable = true;
        }

        public PoeBudgetReading GetBudget()
        {
            if (!IsAvailable) return new PoeBudgetReading();
            double consumed = 0, remaining = 0, temp = 0;
            try
            {
                NativeMethods.SmartPoE_Get_POEConsPowbudget(CardNumber, out consumed);
                NativeMethods.SmartPoE_Get_POELeftPowbudget(CardNumber, out remaining);
                NativeMethods.SmartPoE_Get_Temperature(CardNumber, out temp);
            }
            catch { }
            return new PoeBudgetReading
            {
                ConsumedW  = consumed,
                RemainingW = remaining,
                TotalW     = consumed + remaining,
                TempC      = temp,
            };
        }

        public List<PoePortReading> GetPortReadings()
        {
            var rows = new List<PoePortReading>();
            if (!IsAvailable) return rows;
            for (ushort port = 0; port < 4; port++)
            {
                double voltage = 0, current = 0;
                try
                {
                    NativeMethods.SmartPoE_Get_PSEPortVoltage(CardNumber, port, out voltage);
                    NativeMethods.SmartPoE_Get_PSEPortCurrent(CardNumber, port, out current);
                }
                catch { }
                var watts = voltage * current;
                var on = voltage > 1.0;
                rows.Add(new PoePortReading
                {
                    Port    = $"P{port + 1}",
                    Voltage = $"{voltage:F2} V",
                    Current = $"{current:F3} A",
                    Wattage = $"{watts:F1} W",
                    State   = on ? "Powered" : "Off",
                    PoeOn   = on,
                    Watts   = watts,
                });
            }
            return rows;
        }

        public void Dispose()
        {
            if (_registered)
            {
                try { NativeMethods.SmartPoE_Release_Card(CardNumber); } catch { }
                _registered = false;
            }
        }

        // -----------------------------------------------------------------
        // DLL location — mirrors the PowerShell ADLINK SmartPoE search path.
        // -----------------------------------------------------------------
        private static readonly string[] CandidatePaths = new[]
        {
            @"C:\Program Files\ADLINK\GIE Series\Library\Dll\x64\SmartPoE.dll",
            Path.Combine(Environment.SystemDirectory, "SmartPoE.dll"),
            @"C:\Program Files\ADLINK\SmartPoE\SmartPoE.dll",
            @"C:\Program Files (x86)\ADLINK\SmartPoE\SmartPoE.dll",
            @"C:\Program Files\ADLINK\PCIe-GIE7x\SmartPoE.dll",
            @"C:\ADLINK\SmartPoE\SmartPoE.dll",
        };

        private static readonly string[] RegistryRoots = new[]
        {
            @"SOFTWARE\ADLINK\SmartPoE",
            @"SOFTWARE\WOW6432Node\ADLINK\SmartPoE",
            @"SOFTWARE\ADLINK\GigE Tool",
        };

        private static string LocateDll()
        {
            foreach (var p in CandidatePaths)
            {
                try { if (File.Exists(p)) return p; } catch { }
            }
            foreach (var root in RegistryRoots)
            {
                try
                {
                    using (var key = Registry.LocalMachine.OpenSubKey(root))
                    {
                        var install = key?.GetValue("InstallDir") as string;
                        if (!string.IsNullOrEmpty(install))
                        {
                            var c = Path.Combine(install, "SmartPoE.dll");
                            if (File.Exists(c)) return c;
                        }
                    }
                }
                catch { }
            }
            // Last-ditch — broad recursive search under C:\Program Files. The
            // PowerShell tool walks both Program Files trees; we do the same
            // but skip x86 hits because Pulse runs as x64.
            try
            {
                foreach (var root in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) })
                {
                    if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) continue;
                    var found = Directory.EnumerateFiles(root, "SmartPoE.dll", SearchOption.AllDirectories)
                                         .FirstOrDefault(p => p.IndexOf("x86", StringComparison.OrdinalIgnoreCase) < 0);
                    if (!string.IsNullOrEmpty(found)) return found;
                }
            }
            catch { }
            return null;
        }

        private static class NativeMethods
        {
            // Mirrors Modules/UIHelpers.psm1 — same dll name, same signatures.
            [DllImport("SmartPoE.dll")]
            public static extern short SmartPoE_Register_Card(ushort wCardNumber);
            [DllImport("SmartPoE.dll")]
            public static extern short SmartPoE_Release_Card(ushort wCardNumber);
            [DllImport("SmartPoE.dll")]
            public static extern short SmartPoE_Get_Temperature(ushort wCardNumber, out double wTemperature);
            [DllImport("SmartPoE.dll")]
            public static extern short SmartPoE_Get_POEConsPowbudget(ushort wCardNumber, out double wPower);
            [DllImport("SmartPoE.dll")]
            public static extern short SmartPoE_Get_POELeftPowbudget(ushort wCardNumber, out double wPower);
            [DllImport("SmartPoE.dll")]
            public static extern short SmartPoE_Get_PSEPortCurrent(ushort wCardNumber, ushort PortNumber, out double wCurrent);
            [DllImport("SmartPoE.dll")]
            public static extern short SmartPoE_Get_PSEPortVoltage(ushort wCardNumber, ushort PortNumber, out double wVoltage);

            [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
            public static extern bool SetDllDirectory(string lpPathName);
        }
    }
}
