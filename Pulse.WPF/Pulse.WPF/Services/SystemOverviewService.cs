using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Management;
using System.Net.NetworkInformation;
using System.ServiceProcess;
using Microsoft.Win32;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Pure-C# port of SystemInformation.psm1. Collects everything the
    /// legacy WinForms System Information tab showed — Pixellot software
    /// (registry), OS / Time-Locale / System / BIOS / CPU / Memory /
    /// Graphics / Storage / Network adapters / Pixellot calibrations /
    /// Installed software — and shapes it into the 6 summary cards plus
    /// the System Inventory grouped log + a short Summary bullet list.
    /// Each query is wrapped in try/catch — a missing component must not
    /// crash the panel.
    /// </summary>
    public class SystemOverviewService : ISystemOverviewService
    {
        public SystemOverviewSnapshot Collect()
        {
            var snap = new SystemOverviewSnapshot();
            var rows = snap.Inventory;

            CollectPixellotSoftware(rows);
            CollectOperatingSystem(rows, snap.Cards);
            CollectTimeLocale(rows);
            CollectSystem(rows, snap.Cards);
            CollectProcessor(rows, snap.Cards);
            CollectMemory(rows, snap.Cards);
            CollectGraphics(rows);
            CollectStorage(rows, snap.Cards);
            CollectNetworkAdapters(rows);
            CollectCalibrations(rows);
            CollectInstalledSoftware(rows);

            BuildSummary(snap);
            return snap;
        }

        // ---- Pixellot Software (registry HKLM:\SOFTWARE\Pixellot) ---------------
        private static void CollectPixellotSoftware(List<SystemOverviewRow> rows)
        {
            rows.Add(Section("Pixellot Software"));
            try
            {
                using (var k = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)
                                    .OpenSubKey(@"SOFTWARE\Pixellot"))
                {
                    if (k == null)
                    {
                        rows.Add(Warn("Pixellot", @"Registry key not found (HKLM:\SOFTWARE\Pixellot)"));
                        return;
                    }
                    rows.Add(Info("App Version",          (k.GetValue("Version")        as string) ?? "Not found"));
                    rows.Add(Info("System Image Version", (k.GetValue("ImageVersion")   as string) ?? "Not found"));
                    rows.Add(Info("Package Dependencies", (k.GetValue("Dependencies")   as string) ?? "Not found"));
                }
            }
            catch (Exception)
            {
                rows.Add(Warn("Pixellot", @"Registry key not found (HKLM:\SOFTWARE\Pixellot)"));
            }
        }

        // ---- Operating System (Win32_OperatingSystem) --------------------------
        private static void CollectOperatingSystem(List<SystemOverviewRow> rows, SystemOverviewCards cards)
        {
            rows.Add(Section("Operating System"));
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_OperatingSystem"))
                foreach (ManagementObject o in s.Get())
                {
                    var caption = (o["Caption"] as string ?? "").Trim();
                    var version = (o["Version"] as string ?? "").Trim();
                    var build   = Convert.ToString(o["BuildNumber"]) ?? "";
                    var arch    = (o["OSArchitecture"] as string ?? "").Trim();
                    var install = ToDate(o["InstallDate"]);
                    var boot    = ToDate(o["LastBootUpTime"]);

                    rows.Add(Info("Edition",      caption));
                    rows.Add(Info("Version",      version));
                    rows.Add(Info("Build",        build));
                    rows.Add(Info("Architecture", arch));
                    if (install.HasValue) rows.Add(Info("Install Date", install.Value.ToString("yyyy-MM-dd")));

                    if (boot.HasValue)
                    {
                        var up = DateTime.Now - boot.Value;
                        var upStr = string.Format("{0}d {1}h {2}m",
                            (int)Math.Floor(up.TotalDays), up.Hours, up.Minutes);
                        rows.Add(Info("Uptime", upStr));
                        cards.UptimeTitle  = upStr;
                        cards.UptimeStatus = up.TotalDays > 30 ? "warn" : "ok";
                    }

                    // OS card: shorten "Microsoft Windows 11 Pro" → "Win 11 Pro" + (build)
                    var osShort = (caption ?? "")
                        .Replace("Microsoft ", "")
                        .Replace("Windows ", "Win ")
                        .Trim();
                    cards.OsTitle  = string.IsNullOrEmpty(build) ? osShort : $"{osShort}  ({build})";
                    cards.OsStatus = "ok";
                    break;
                }
            }
            catch
            {
                rows.Add(Warn("OS", "Query failed"));
            }
        }

        // ---- Time & Locale ----------------------------------------------------
        private static void CollectTimeLocale(List<SystemOverviewRow> rows)
        {
            rows.Add(Section("Time & Locale"));
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_TimeZone"))
                foreach (ManagementObject o in s.Get())
                {
                    var caption = (o["Caption"] as string) ?? "";
                    var standard = (o["StandardName"] as string) ?? "";
                    rows.Add(Info("Timezone", caption));
                    rows.Add(Info("System Time", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")));

                    // UTC default usually means the deployment never set the venue's local zone.
                    if (standard.Equals("UTC", StringComparison.OrdinalIgnoreCase) ||
                        caption.StartsWith("(UTC) Coordinated", StringComparison.OrdinalIgnoreCase))
                    {
                        rows.Add(Warn("Timezone Check", "System is set to UTC — confirm this matches the venue's local timezone"));
                    }
                    break;
                }
            }
            catch { /* timezone query failed — skip silently */ }

            // NTP server (W32Time registry)
            try
            {
                using (var k = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)
                                    .OpenSubKey(@"SYSTEM\CurrentControlSet\Services\W32Time\Parameters"))
                {
                    var server = k?.GetValue("NtpServer") as string;
                    if (!string.IsNullOrEmpty(server)) rows.Add(Info("NTP Server", server));
                }
            }
            catch { }

            // W32Time service running?
            try
            {
                using (var sc = new ServiceController("W32Time"))
                {
                    if (sc.Status == ServiceControllerStatus.Running)
                        rows.Add(Info("Time Sync", "W32Time service running"));
                    else
                        rows.Add(Warn("Time Sync", "W32Time service NOT running — automatic time sync disabled"));
                }
            }
            catch { /* service not found / access denied — skip */ }
        }

        // ---- System (Win32_ComputerSystem + Win32_BIOS) -----------------------
        private static void CollectSystem(List<SystemOverviewRow> rows, SystemOverviewCards cards)
        {
            rows.Add(Section("System"));
            string mfr = "", model = "";
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_ComputerSystem"))
                foreach (ManagementObject o in s.Get())
                {
                    rows.Add(Info("Computer Name", (o["Name"] as string) ?? ""));
                    mfr   = ((o["Manufacturer"] as string) ?? "").Trim();
                    model = ((o["Model"]        as string) ?? "").Trim();
                    rows.Add(Info("Manufacturer", mfr));
                    rows.Add(Info("Model",        model));

                    var partOfDomain = false;
                    try { partOfDomain = Convert.ToBoolean(o["PartOfDomain"]); } catch { }
                    var domain    = (o["Domain"] as string)   ?? "";
                    var workgroup = (o["Workgroup"] as string) ?? "";
                    rows.Add(Info("Network", partOfDomain ? $"Domain: {domain}" : $"Workgroup: {workgroup}"));
                    rows.Add(Info("System Type", (o["SystemType"] as string) ?? ""));
                    break;
                }
            }
            catch { rows.Add(Warn("System", "Query failed")); }

            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_BIOS"))
                foreach (ManagementObject o in s.Get())
                {
                    var smbios = (o["SMBIOSBIOSVersion"] as string) ?? "";
                    var release = ToDate(o["ReleaseDate"]);
                    var biosStr = release.HasValue
                        ? $"{smbios}  ({release.Value:yyyy-MM-dd})"
                        : smbios;
                    rows.Add(Info("BIOS", biosStr));

                    var serial = ((o["SerialNumber"] as string) ?? "").Trim();
                    if (!string.IsNullOrEmpty(serial) &&
                        !serial.Equals("System Serial Number", StringComparison.OrdinalIgnoreCase) &&
                        !serial.Equals("To Be Filled By O.E.M.", StringComparison.OrdinalIgnoreCase) &&
                        !serial.Equals("Default string", StringComparison.OrdinalIgnoreCase))
                    {
                        rows.Add(Gray("Serial Number", serial));
                    }
                    break;
                }
            }
            catch { /* BIOS unavailable — skip */ }

            // Model card — manufacturer + model truncated to 32 chars.
            string modelCard;
            if (!string.IsNullOrEmpty(mfr) && !string.IsNullOrEmpty(model)) modelCard = $"{mfr}  {model}";
            else if (!string.IsNullOrEmpty(model))                          modelCard = model;
            else                                                            modelCard = "Unknown";
            if (modelCard.Length > 32) modelCard = modelCard.Substring(0, 29) + "...";
            cards.ModelTitle  = modelCard;
            cards.ModelStatus = "neutral";
        }

        // ---- Processor (Win32_Processor) --------------------------------------
        private static void CollectProcessor(List<SystemOverviewRow> rows, SystemOverviewCards cards)
        {
            rows.Add(Section("Processor"));
            string cardVal = "Unknown CPU";
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_Processor"))
                foreach (ManagementObject o in s.Get())
                {
                    var name = ((o["Name"] as string) ?? "").Trim();
                    rows.Add(Info("Name", name));
                    rows.Add(Info("Manufacturer", (o["Manufacturer"] as string) ?? ""));
                    var maxMhz = Convert.ToDouble(o["MaxClockSpeed"] ?? 0);
                    if (maxMhz > 0) rows.Add(Info("Max Speed", $"{maxMhz / 1000.0:F2} GHz"));
                    var cores = Convert.ToInt32(o["NumberOfCores"] ?? 0);
                    var lps   = Convert.ToInt32(o["NumberOfLogicalProcessors"] ?? 0);
                    rows.Add(Info("Cores", $"{cores} physical / {lps} logical"));
                    var socket = (o["SocketDesignation"] as string) ?? "";
                    if (!string.IsNullOrEmpty(socket)) rows.Add(Info("Socket", socket));

                    // Card label: Intel(R) Core(TM) i9-12900K → Core i9-12900K
                    if (cardVal == "Unknown CPU" && !string.IsNullOrEmpty(name))
                    {
                        cardVal = name
                            .Replace("Intel(R) Core(TM) ", "Core ")
                            .Replace("(R)", "")
                            .Replace("(TM)", "");
                        var atIdx = cardVal.IndexOf(" @ ", StringComparison.OrdinalIgnoreCase);
                        if (atIdx >= 0) cardVal = cardVal.Substring(0, atIdx);
                        // Squeeze repeated spaces.
                        while (cardVal.Contains("  ")) cardVal = cardVal.Replace("  ", " ");
                        cardVal = cardVal.Trim();
                    }
                }
            }
            catch { rows.Add(Warn("CPU", "Query failed")); }

            cards.CpuTitle  = cardVal.Length > 32 ? cardVal.Substring(0, 29) + "..." : cardVal;
            cards.CpuStatus = "neutral";
        }

        // ---- Memory (Win32_OperatingSystem totals + Win32_PhysicalMemory slots)
        private static void CollectMemory(List<SystemOverviewRow> rows, SystemOverviewCards cards)
        {
            rows.Add(Section("Memory"));
            int totalGB = 0;
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT TotalVisibleMemorySize, FreePhysicalMemory FROM Win32_OperatingSystem"))
                foreach (ManagementObject o in s.Get())
                {
                    var totalKb = Convert.ToDouble(o["TotalVisibleMemorySize"] ?? 0);
                    var freeKb  = Convert.ToDouble(o["FreePhysicalMemory"]    ?? 0);
                    var totalGb = totalKb / 1048576.0;
                    var freeGb  = freeKb  / 1048576.0;
                    totalGB = (int)Math.Round(totalGb);
                    rows.Add(Info("Total RAM", $"{totalGb:F1} GB"));
                    rows.Add(Info("Available", $"{freeGb:F1} GB"));
                    cards.RamTitle  = $"{totalGB} GB total / {freeGb:F1} GB free";
                    cards.RamStatus = "ok";
                    break;
                }
            }
            catch { rows.Add(Warn("Memory", "Query failed")); }

            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_PhysicalMemory"))
                {
                    int n = 1;
                    foreach (ManagementObject o in s.Get())
                    {
                        var capBytes = Convert.ToInt64(o["Capacity"] ?? 0);
                        var capGb    = (int)(capBytes / 1073741824L);
                        var smbiosType = Convert.ToInt32(o["SMBIOSMemoryType"] ?? 0);
                        var memType  = smbiosType == 24 ? "DDR3"
                                     : smbiosType == 26 ? "DDR4"
                                     : smbiosType == 34 ? "DDR5"
                                     : "DDR";
                        var speed    = Convert.ToInt32(o["Speed"] ?? 0);
                        var speedStr = speed > 0 ? $"{speed} MHz" : "";
                        var mfr      = ((o["Manufacturer"] as string) ?? "").Trim();
                        var mfrStr   = (!string.IsNullOrEmpty(mfr) &&
                                        mfr.IndexOf("Unknown", StringComparison.OrdinalIgnoreCase) < 0 &&
                                        mfr.IndexOf("To Be",   StringComparison.OrdinalIgnoreCase) < 0)
                                            ? $"  ({mfr})" : "";
                        rows.Add(Info($"Slot {n}", $"{capGb} GB {memType} {speedStr}{mfrStr}".Trim()));
                        n++;
                    }
                }
            }
            catch { /* slot enumeration failed — skip silently */ }
        }

        // ---- Graphics (Win32_VideoController, prefer discrete) -----------------
        private static void CollectGraphics(List<SystemOverviewRow> rows)
        {
            rows.Add(Section("Graphics"));
            try
            {
                var gpus = new List<ManagementObject>();
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_VideoController"))
                foreach (ManagementObject o in s.Get())
                {
                    var name = (o["Name"] as string) ?? "";
                    if (name.IndexOf("Remote",  StringComparison.OrdinalIgnoreCase) < 0 &&
                        name.IndexOf("Virtual", StringComparison.OrdinalIgnoreCase) < 0)
                        gpus.Add(o);
                }
                var discrete = gpus.Where(g =>
                {
                    var n = (g["Name"] as string) ?? "";
                    return n.IndexOf("Intel",     StringComparison.OrdinalIgnoreCase) < 0 &&
                           n.IndexOf("Microsoft", StringComparison.OrdinalIgnoreCase) < 0;
                }).ToList();
                if (discrete.Count > 0) gpus = discrete;
                if (gpus.Count == 0) { rows.Add(Warn("GPU", "None detected")); return; }

                foreach (var g in gpus)
                {
                    rows.Add(Info("Name", (g["Name"] as string) ?? ""));
                    var ramBytes = Convert.ToInt64(g["AdapterRAM"] ?? 0);
                    if (ramBytes > 0)
                    {
                        var mb = (int)(ramBytes / 1048576);
                        rows.Add(Info("VRAM", mb >= 1024 ? $"{mb / 1024} GB" : $"{mb} MB"));
                    }
                    var driver = (g["DriverVersion"] as string) ?? "";
                    if (!string.IsNullOrEmpty(driver)) rows.Add(Gray("Driver", driver));
                }
            }
            catch { rows.Add(Warn("GPU", "Query failed")); }
        }

        // ---- Storage (Win32_DiskDrive + Win32_LogicalDisk for system drive) ---
        private static void CollectStorage(List<SystemOverviewRow> rows, SystemOverviewCards cards)
        {
            rows.Add(Section("Storage"));
            try
            {
                var ordered = new List<(int idx, ManagementObject mo)>();
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_DiskDrive"))
                foreach (ManagementObject o in s.Get())
                    ordered.Add((Convert.ToInt32(o["Index"] ?? 0), o));

                if (ordered.Count == 0)
                {
                    rows.Add(Warn("Disks", "None detected"));
                }
                else
                {
                    foreach (var pair in ordered.OrderBy(p => p.idx))
                    {
                        var d = pair.mo;
                        var sizeGb = Convert.ToDouble(d["Size"] ?? 0) / 1073741824.0;
                        var iface  = (d["InterfaceType"] as string) ?? "";
                        var model  = (d["Model"] as string) ?? "";
                        rows.Add(Info($"Disk {pair.idx} - {model}", $"{sizeGb:F0} GB  [{iface}]"));
                        var serial = ((d["SerialNumber"] as string) ?? "").Trim();
                        if (!string.IsNullOrEmpty(serial)) rows.Add(Gray("  Serial", serial));
                    }
                }
            }
            catch { rows.Add(Warn("Storage", "Query failed")); }

            // Card 6 — system drive free space.
            try
            {
                var sysDriveLetter = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.System))
                                         ?.TrimEnd('\\') ?? "C:";
                using (var s = new ManagementObjectSearcher(
                    $"SELECT FreeSpace,Size FROM Win32_LogicalDisk WHERE DeviceID='{sysDriveLetter}'"))
                foreach (ManagementObject o in s.Get())
                {
                    var freeBytes = Convert.ToDouble(o["FreeSpace"] ?? 0);
                    var sizeBytes = Convert.ToDouble(o["Size"]      ?? 0);
                    if (sizeBytes <= 0) break;
                    var freeGb = Math.Round(freeBytes / 1073741824.0, 1);
                    var usedPct = (int)Math.Round((1 - freeBytes / sizeBytes) * 100);
                    cards.StorageTitle = $"{freeGb} GB free  ({usedPct}% used)";
                    cards.StorageStatus = freeGb < 5 ? "fail" : (freeGb < 15 ? "warn" : "ok");
                    break;
                }
            }
            catch { /* logical-disk query failed — leave card placeholder */ }
        }

        // ---- Network adapters (Win32_NetworkAdapter, physical only) -----------
        private static void CollectNetworkAdapters(List<SystemOverviewRow> rows)
        {
            rows.Add(Section("Network Adapters"));
            try
            {
                var nics = new List<ManagementObject>();
                using (var s = new ManagementObjectSearcher(
                    "SELECT * FROM Win32_NetworkAdapter WHERE PhysicalAdapter=true"))
                foreach (ManagementObject o in s.Get()) nics.Add(o);

                if (nics.Count == 0) { rows.Add(Warn("NICs", "None detected")); return; }

                foreach (var nic in nics.OrderBy(n => Convert.ToInt32(n["Index"] ?? 0)))
                {
                    var name = (nic["Name"] as string) ?? "";
                    var mac  = (nic["MACAddress"] as string) ?? "-";
                    rows.Add(Info(name, mac));

                    var speed = Convert.ToInt64(nic["Speed"] ?? 0);
                    if (speed > 0)
                    {
                        string spdStr = speed >= 1_000_000_000L ? $"{speed / 1_000_000_000L} Gbps"
                                      : speed >= 1_000_000L     ? $"{speed / 1_000_000L} Mbps"
                                      :                            $"{speed} bps";
                        rows.Add(Info("  Speed", spdStr));
                    }

                    int connStatus;
                    try { connStatus = Convert.ToInt32(nic["NetConnectionStatus"] ?? -1); }
                    catch { connStatus = -1; }
                    string connStr = connStatus == 2 ? "Connected"
                                  : connStatus == 7 ? "Media disconnected"
                                  :                    "Not connected";
                    rows.Add(connStatus == 2 ? Pass("  Status", connStr) : Gray("  Status", connStr));
                }
            }
            catch { rows.Add(Warn("NICs", "Query failed")); }
        }

        // ---- Pixellot Calibrations (filesystem) -------------------------------
        private static void CollectCalibrations(List<SystemOverviewRow> rows)
        {
            rows.Add(Section("Pixellot Calibrations"));
            var paths = new[]
            {
                @"C:\Pixellot\calibration",
                @"C:\Pixellot\Calibration",
                @"C:\Pixellot\Data\Calibration",
                @"C:\Program Files\Pixellot\calibration",
                @"C:\ProgramData\Pixellot\calibration",
            };
            bool found = false;
            foreach (var p in paths)
            {
                try
                {
                    if (!Directory.Exists(p)) continue;
                    found = true;
                    rows.Add(Info("Calibration Path", p));
                    var di = new DirectoryInfo(p);
                    var files = di.GetFiles().OrderByDescending(f => f.LastWriteTime).Take(12).ToList();
                    if (files.Count == 0)
                    {
                        rows.Add(Warn("  Files", "Directory exists but is empty"));
                    }
                    else
                    {
                        var now = DateTime.Now;
                        foreach (var f in files)
                        {
                            var age = now - f.LastWriteTime;
                            string ageStr = age.TotalDays  >= 1 ? $"{(int)age.TotalDays}d ago"
                                          : age.TotalHours >= 1 ? $"{(int)age.TotalHours}h ago"
                                          :                        $"{(int)age.TotalMinutes}m ago";
                            rows.Add(Gray($"  {f.Name}", $"{ageStr}   ({f.Length / 1024.0:F0} KB)"));
                        }
                    }
                }
                catch { /* skip unreadable paths */ }
            }
            if (!found) rows.Add(Gray("Calibrations", "No calibration directory found in standard locations"));
        }

        // ---- Installed Software (registry uninstall keys) ---------------------
        private static readonly string[] UnwantedPatterns = new[]
        {
            "OBS Studio", "vMix", "Wirecast", "XSplit",
            "Norton", "McAfee", "Avast", "AVG", "Bitdefender", "Kaspersky",
            "Bonjour", "iTunes", "QuickTime",
            "Yahoo", "Ask Toolbar", "Coupon", "WebDiscover",
            "Steam", "Epic Games", "Origin", "Battle.net",
            "BitTorrent", "uTorrent", "qBittorrent",
        };
        private static readonly string[] UninstallRoots = new[]
        {
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        };

        private static void CollectInstalledSoftware(List<SystemOverviewRow> rows)
        {
            rows.Add(Section("Installed Software"));
            try
            {
                var apps = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                var flagged = new List<(string Name, string Publisher)>();
                foreach (var root in UninstallRoots)
                {
                    using (var k = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64).OpenSubKey(root))
                    {
                        if (k == null) continue;
                        foreach (var sub in k.GetSubKeyNames())
                        {
                            using (var ek = k.OpenSubKey(sub))
                            {
                                if (ek == null) continue;
                                var sysComp = ek.GetValue("SystemComponent");
                                if (sysComp != null && Convert.ToInt32(sysComp) == 1) continue;
                                var name = ek.GetValue("DisplayName") as string;
                                if (string.IsNullOrEmpty(name)) continue;
                                if (!apps.Add(name)) continue;
                                foreach (var pat in UnwantedPatterns)
                                {
                                    if (name.IndexOf(pat, StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        flagged.Add((name, ek.GetValue("Publisher") as string ?? ""));
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
                rows.Add(Info("Total Installed", $"{apps.Count} applications"));
                if (flagged.Count == 0)
                {
                    rows.Add(Pass("Flagged Apps", "None — no known-conflicting software detected"));
                }
                else
                {
                    rows.Add(Warn("Flagged Apps", $"{flagged.Count} potentially-conflicting applications detected"));
                    foreach (var (name, publisher) in flagged)
                        rows.Add(Warn($"  {name}", $"{publisher} — confirm this is intentional"));
                }
            }
            catch { rows.Add(Warn("Installed Software", "Scan failed")); }
        }

        // ---- Build the right-side Summary bullets -----------------------------
        private static void BuildSummary(SystemOverviewSnapshot snap)
        {
            var c = snap.Cards;
            void Add(string text, string status) =>
                snap.Summary.Add(new SystemOverviewSummaryItem { Status = status, Text = text });

            Add($"Model: {c.ModelTitle}",                 c.ModelStatus   == "neutral" ? "ok" : c.ModelStatus);
            Add($"OS: {c.OsTitle}",                       c.OsStatus      == "neutral" ? "ok" : c.OsStatus);
            Add($"Uptime: {c.UptimeTitle}",               c.UptimeStatus);
            Add($"CPU: {c.CpuTitle}",                     c.CpuStatus     == "neutral" ? "ok" : c.CpuStatus);
            Add($"RAM: {c.RamTitle}",                     c.RamStatus);
            Add($"Storage: {c.StorageTitle}",             c.StorageStatus);
        }

        // ---- Row helpers ------------------------------------------------------
        private static SystemOverviewRow Section(string title) =>
            new SystemOverviewRow { Section = title, Level = "Section" };
        private static SystemOverviewRow Info(string label, string value) =>
            new SystemOverviewRow { Label = label, Value = value, Level = "Info",
                                    ValueColor = StatusHelpers.BrushForLogLevel("Info") };
        private static SystemOverviewRow Pass(string label, string value) =>
            new SystemOverviewRow { Label = label, Value = value, Level = "Pass",
                                    ValueColor = StatusHelpers.BrushForLogLevel("Pass") };
        private static SystemOverviewRow Warn(string label, string value) =>
            new SystemOverviewRow { Label = label, Value = value, Level = "Warn",
                                    ValueColor = StatusHelpers.BrushForLogLevel("Warn") };
        private static SystemOverviewRow Gray(string label, string value) =>
            new SystemOverviewRow { Label = label, Value = value, Level = "Gray",
                                    ValueColor = StatusHelpers.BrushForLogLevel("Gray") };

        // WMI dates come back as strings ("20240414120000.000000-300") — parse to DateTime.
        private static DateTime? ToDate(object cimValue)
        {
            try
            {
                if (cimValue == null) return null;
                if (cimValue is DateTime dt) return dt;
                var s = cimValue.ToString();
                return ManagementDateTimeConverter.ToDateTime(s);
            }
            catch { return null; }
        }
    }
}
