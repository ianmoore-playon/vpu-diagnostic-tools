using System;
using System.Collections.Generic;
using System.Diagnostics.Eventing.Reader;
using System.IO;
using System.Linq;
using System.Management;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Pure-C# port of DiskHealth.psm1. Uses WMI (Win32_LogicalDisk) for
    /// volumes, root\wmi MSStorageDriver_FailurePredictStatus for SMART,
    /// and EventLogReader for the 48h disk-error tally.
    /// </summary>
    public class DiskHealthService : IDiskHealthService
    {
        // Path patterns to look for inside each volume to identify a "Recording / Storage" drive.
        private static readonly string[] PixStorePaths = { @"Pixellot\recordings", @"Pixellot\data", @"Pixellot\Data", "recordings" };

        // Pixellot-managed paths to size up. Same set as DiskHealth.psm1 ($pixPaths).
        private class PathSpec
        {
            public string Path;
            public string Label;
            public long WarnBytes;
            public long CritBytes;
        }

        private static List<PathSpec> BuildPathSpecs()
        {
            var temp = Environment.GetEnvironmentVariable("TEMP") ?? "";
            const long GB = 1024L * 1024L * 1024L;
            // v0.6.5: C:\Pixellot\recordings and C:\Pixellot\temp dropped —
            // both always render "Path not found" on production VPUs, so the
            // rows were noise. Keep Pixellot Logs / Data / Root + Windows
            // Temp / User Temp / User Profiles.
            return new List<PathSpec>
            {
                new PathSpec { Path = @"C:\Pixellot\Data\Log",  Label = "Pixellot Logs",        WarnBytes = 2  * GB, CritBytes = 5  * GB },
                new PathSpec { Path = @"C:\Pixellot\Data",       Label = "Pixellot Data",        WarnBytes = 5  * GB, CritBytes = 20 * GB },
                new PathSpec { Path = @"C:\Pixellot",            Label = "Pixellot Root (total)",WarnBytes = 20 * GB, CritBytes = 80 * GB },
                new PathSpec { Path = @"C:\Windows\Temp",        Label = "Windows Temp",         WarnBytes = 2  * GB, CritBytes = 5  * GB },
                new PathSpec { Path = temp,                      Label = "User Temp",            WarnBytes = 2  * GB, CritBytes = 5  * GB },
                new PathSpec { Path = @"C:\Users",               Label = "User Profiles (total)",WarnBytes = 10 * GB, CritBytes = 30 * GB },
            };
        }

        // ---------------- Volumes -------------------------------------------

        public List<VolumeRow> GetVolumes()
        {
            var rows = new List<VolumeRow>();
            string osDrive = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:").TrimEnd('\\');

            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_LogicalDisk WHERE DriveType=3"))
                {
                    foreach (ManagementObject vol in s.Get())
                    {
                        string deviceId = vol["DeviceID"] as string ?? "";
                        string label = vol["VolumeName"] as string ?? "";
                        ulong size = ToUlong(vol["Size"]);
                        ulong free = ToUlong(vol["FreeSpace"]);
                        if (size == 0)
                        {
                            rows.Add(new VolumeRow
                            {
                                DeviceId = deviceId,
                                Label = label,
                                Role = "Inaccessible",
                                FreeGb = 0,
                                TotalGb = 0,
                                PercentUsed = "0%", PercentUsedValue = 0,
                                Severity = "Warn",
                            });
                            continue;
                        }
                        double totalGb = Math.Round(size / 1_073_741_824.0, 1);
                        double freeGb = Math.Round(free / 1_073_741_824.0, 1);
                        int pctUsed = (int)Math.Round((1.0 - (double)free / size) * 100.0);

                        // Drive role ----------------------------------------
                        string role;
                        if (string.Equals(deviceId, osDrive, StringComparison.OrdinalIgnoreCase))
                            role = "OS Drive";
                        else if (PixStorePaths.Any(p => SafeDirExists(Path.Combine(deviceId + @"\", p))))
                            role = "Recording / Storage";
                        else
                            role = totalGb > 200 ? "Storage" : "Data";

                        // Threshold -----------------------------------------
                        string sev;
                        if (freeGb < 5 || pctUsed > 97) sev = "Fail";
                        else if (freeGb < 15 || pctUsed > 90) sev = "Warn";
                        else sev = "Pass";

                        // Pre-format the human-readable Free / Total strings
                        // so consumers (e.g. the Dashboard volume row) don't
                        // need a converter or a second formatter. StatusColor
                        // and BarColor pre-resolved against the active theme
                        // for the same reason.
                        var (statusColor, barColor) = ResolveSeverityBrushes(sev);
                        rows.Add(new VolumeRow
                        {
                            DeviceId    = deviceId,
                            Label       = label,
                            Role        = role,
                            FreeGb      = freeGb,
                            TotalGb     = totalGb,
                            Free        = $"{freeGb:F1} GB",
                            Total       = $"{totalGb:F1} GB",
                            PercentUsed = pctUsed + "%",
                            PercentUsedValue = pctUsed,
                            Severity    = sev,
                            StatusColor = statusColor,
                            BarColor    = barColor,
                        });
                    }
                }
            }
            catch { }

            return rows;
        }

        private static bool SafeDirExists(string p)
        {
            try { return Directory.Exists(p); } catch { return false; }
        }

        // Resolve "Pass"/"Warn"/"Fail" → (text colour, bar colour) using the
        // shared theme brushes. Lives in the service so every consumer of
        // VolumeRow (Dashboard storage card, Disk Health panel) gets the
        // same colour-coding without re-implementing the rule.
        private static (System.Windows.Media.Brush textBrush, System.Windows.Media.Brush barBrush) ResolveSeverityBrushes(string severity)
        {
            string colourKey;
            switch (severity)
            {
                case "Fail": colourKey = "RedBrush";    break;
                case "Warn": colourKey = "YellowBrush"; break;
                default:      colourKey = "GreenBrush";  break;
            }
            try
            {
                var b = Pulse.WPF.Helpers.StatusHelpers.Brush(colourKey);
                return (b, b);
            }
            catch
            {
                return (System.Windows.Media.Brushes.Gray, System.Windows.Media.Brushes.Gray);
            }
        }

        private static ulong ToUlong(object o)
        {
            try { return o == null ? 0UL : Convert.ToUInt64(o); } catch { return 0UL; }
        }

        // ---------------- Pixellot paths ------------------------------------

        public List<PixellotPathRow> GetPixellotPaths()
        {
            var rows = new List<PixellotPathRow>();
            // Cap the work we do here. DiskHealth.psm1 uses a 30 s budget over
            // multiple recursive scans; we mirror that with a wall-clock check.
            var budget = System.Diagnostics.Stopwatch.StartNew();
            const long BudgetMs = 30_000;

            foreach (var spec in BuildPathSpecs())
            {
                if (budget.ElapsedMilliseconds > BudgetMs) break;
                if (string.IsNullOrEmpty(spec.Path) || !SafeDirExists(spec.Path))
                {
                    rows.Add(new PixellotPathRow
                    {
                        Path = spec.Path,
                        Label = spec.Label,
                        SizeFormatted = "Path not found",
                        Severity = "Gray",
                    });
                    continue;
                }
                long size = 0;
                try { size = DirectorySizeBytes(spec.Path, depthRemaining: 3, budget: budget, budgetMs: BudgetMs); }
                catch { }

                string sev;
                if (size >= spec.CritBytes) sev = "Fail";
                else if (size >= spec.WarnBytes) sev = "Warn";
                else sev = "Pass";

                rows.Add(new PixellotPathRow
                {
                    Path = spec.Path,
                    Label = spec.Label,
                    SizeFormatted = FormatSize(size),
                    Severity = sev,
                });
            }

            return rows;
        }

        // Recursive byte-sum with a depth cap and a shared time budget.
        // The 3-deep limit matches "Get-ChildItem -Recurse -Depth 3 -File" in
        // the PowerShell version.
        private static long DirectorySizeBytes(string path, int depthRemaining,
            System.Diagnostics.Stopwatch budget, long budgetMs)
        {
            if (budget.ElapsedMilliseconds > budgetMs) return 0;
            long total = 0;
            try
            {
                foreach (var f in Directory.EnumerateFiles(path))
                {
                    if (budget.ElapsedMilliseconds > budgetMs) return total;
                    try { total += new FileInfo(f).Length; } catch { }
                }
                if (depthRemaining > 0)
                {
                    foreach (var d in Directory.EnumerateDirectories(path))
                    {
                        if (budget.ElapsedMilliseconds > budgetMs) return total;
                        total += DirectorySizeBytes(d, depthRemaining - 1, budget, budgetMs);
                    }
                }
            }
            catch (UnauthorizedAccessException) { }
            catch (IOException) { }
            return total;
        }

        private static string FormatSize(long bytes)
        {
            const double TB = 1024.0 * 1024.0 * 1024.0 * 1024.0;
            const double GB = 1024.0 * 1024.0 * 1024.0;
            const double MB = 1024.0 * 1024.0;
            if (bytes >= TB) return $"{bytes / TB:F2} TB";
            if (bytes >= GB) return $"{bytes / GB:F1} GB";
            if (bytes >= MB) return $"{bytes / MB:F0} MB";
            return $"{bytes / 1024.0:F0} KB";
        }

        // ---------------- SMART ---------------------------------------------

        public bool? SmartPredictsFailure()
        {
            try
            {
                using (var s = new ManagementObjectSearcher(
                    @"\\.\root\wmi", "SELECT * FROM MSStorageDriver_FailurePredictStatus"))
                {
                    foreach (ManagementObject o in s.Get())
                    {
                        var pf = o["PredictFailure"];
                        if (pf is bool b && b) return true;
                    }
                }
                return false;
            }
            catch
            {
                // root\wmi often requires admin / some VPU images don't expose it.
                return null;
            }
        }

        // ---------------- Disk error events --------------------------------

        public int CountDiskErrorEvents48h()
        {
            // Mirror the disk-related provider/id list from DiskHealth.psm1.
            var providers = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "disk", "Ntfs", "volmgr", "partmgr", "stornvme", "msahci",
                "iaStorAVC", "iaStorV", "storahci", "cdrom"
            };
            var ids = new HashSet<int> { 7, 11, 51, 52, 55, 50, 57, 140, 153 };

            try
            {
                // *[System[(Level=1 or Level=2) and TimeCreated[timediff(@SystemTime) <= 172800000]]]
                var query = "*[System[(Level=1 or Level=2) and TimeCreated[timediff(@SystemTime) <= 172800000]]]";
                var ev = new EventLogQuery("System", PathType.LogName, query) { ReverseDirection = true };
                int count = 0;
                using (var reader = new EventLogReader(ev))
                {
                    EventRecord rec;
                    while ((rec = reader.ReadEvent()) != null)
                    {
                        try
                        {
                            if (providers.Contains(rec.ProviderName ?? "") || ids.Contains(rec.Id))
                                count++;
                        }
                        catch { }
                        finally { rec.Dispose(); }
                        if (count > 1000) break; // safety bound
                    }
                }
                return count;
            }
            catch { return 0; }
        }
    }
}
