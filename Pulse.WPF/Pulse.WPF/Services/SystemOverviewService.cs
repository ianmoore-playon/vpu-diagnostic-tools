using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Management;
using System.Net.NetworkInformation;
using Microsoft.Win32;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Pure-C# port of SystemInformation.psm1. Collects everything the
    /// legacy WinForms System Information tab showed — Pixellot software
    /// (registry), OS / Time-Locale / System / BIOS / CPU / Memory /
    /// Graphics / Storage / Network adapters / Installed software — and
    /// shapes it into:
    ///   * the 6 summary cards (top tile row),
    ///   * a structured per-card model graph (UX_REVIEW round 2 §3 / §5),
    ///   * a flat inventory list (kept for the Copy-as-text fallback path).
    /// Each query is wrapped in try/catch — a missing component must not
    /// crash the panel.
    /// </summary>
    public class SystemOverviewService : ISystemOverviewService
    {
        private const string NotReported = "Not reported";

        public SystemOverviewSnapshot Collect()
        {
            var snap = new SystemOverviewSnapshot();
            var rows = snap.Inventory;

            CollectPixellotSoftware(rows, snap.PixellotSoftware);
            CollectOperatingSystem(rows, snap.Cards, snap.OsLocale);
            CollectTimeLocale(rows, snap.OsLocale);
            CollectDotNetAndUpdates(snap.OsLocale);
            CollectSystem(rows, snap.Cards, snap.Identity);
            CollectProcessor(rows, snap.Cards, snap.Processor);
            CollectMemory(rows, snap.Cards, snap.Memory);
            CollectGraphics(rows, snap.Graphics);
            CollectStorage(rows, snap.Cards, snap.Storage);
            CollectNetworkAdapters(rows, snap.NetworkAdapters);
            CollectInstalledSoftware(rows, snap.SoftwareInventory);
            return snap;
        }

        // ---- Pixellot Software (registry HKLM:\SOFTWARE\Pixellot) ---------------
        private static void CollectPixellotSoftware(List<SystemOverviewRow> rows, PixellotSoftwareCardModel card)
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
                    }
                    else
                    {
                        card.AppVersion          = (k.GetValue("Version")        as string) ?? NotReported;
                        card.SystemImageVersion  = (k.GetValue("ImageVersion")   as string) ?? NotReported;
                        card.PackageDependencies = (k.GetValue("Dependencies")   as string) ?? NotReported;
                        rows.Add(Info("App Version",          card.AppVersion));
                        rows.Add(Info("System Image Version", card.SystemImageVersion));
                        rows.Add(Info("Package Dependencies", card.PackageDependencies));
                    }
                }
            }
            catch
            {
                rows.Add(Warn("Pixellot", @"Registry key not found (HKLM:\SOFTWARE\Pixellot)"));
            }

            // Install date from the uninstall registry, matching the Pixellot DisplayName.
            try
            {
                string installDate = null;
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
                                var name = ek.GetValue("DisplayName") as string;
                                if (string.IsNullOrEmpty(name)) continue;
                                if (name.IndexOf("Pixellot", StringComparison.OrdinalIgnoreCase) < 0) continue;
                                var raw = ek.GetValue("InstallDate") as string;
                                if (!string.IsNullOrEmpty(raw) && raw.Length == 8 &&
                                    DateTime.TryParseExact(raw, "yyyyMMdd", System.Globalization.CultureInfo.InvariantCulture,
                                        System.Globalization.DateTimeStyles.None, out var d))
                                {
                                    installDate = d.ToString("yyyy-MM-dd");
                                    break;
                                }
                            }
                        }
                        if (installDate != null) break;
                    }
                }
                card.InstallDate = installDate ?? NotReported;
                if (installDate != null) rows.Add(Info("Install Date", installDate));
            }
            catch { /* install date is best-effort */ }
        }

        // ---- Operating System (Win32_OperatingSystem) --------------------------
        private static void CollectOperatingSystem(List<SystemOverviewRow> rows, SystemOverviewCards cards, OsLocaleCardModel os)
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

                    os.Edition      = string.IsNullOrEmpty(caption) ? NotReported : caption;
                    os.Version      = string.IsNullOrEmpty(version) ? NotReported : version;
                    os.Build        = string.IsNullOrEmpty(build)   ? NotReported : build;
                    os.Architecture = string.IsNullOrEmpty(arch)    ? NotReported : arch;
                    os.InstallDate  = install.HasValue ? install.Value.ToString("yyyy-MM-dd") : NotReported;

                    rows.Add(Info("Edition",      os.Edition));
                    rows.Add(Info("Version",      os.Version));
                    rows.Add(Info("Build",        os.Build));
                    rows.Add(Info("Architecture", os.Architecture));
                    if (install.HasValue) rows.Add(Info("Install Date", os.InstallDate));

                    if (boot.HasValue)
                    {
                        var up = DateTime.Now - boot.Value;
                        var upStr = string.Format("{0}d {1}h {2}m",
                            (int)Math.Floor(up.TotalDays), up.Hours, up.Minutes);
                        os.Uptime = upStr;
                        rows.Add(Info("Uptime", upStr));
                        cards.UptimeTitle  = upStr;
                        // D11 fix: bumped from > 30 days to > 180 days to
                        // match the threshold used in the PowerShell-tool's
                        // post-review tuning. VPUs are designed to run 24/7;
                        // 30+ days was warning noise that eroded trust. Also
                        // emit an explicit row so the panel surfaces the
                        // recommendation instead of just a yellow card with
                        // no message.
                        if (up.TotalDays > 180)
                        {
                            cards.UptimeStatus = "warn";
                            rows.Add(Warn("Uptime",
                                $"{(int)Math.Floor(up.TotalDays)} days — Windows updates may be pending; schedule a reboot during the next maintenance window."));
                        }
                        else
                        {
                            cards.UptimeStatus = "ok";
                        }
                    }

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

        // ---- Time & Locale (also feeds OsLocale card) --------------------------
        private static void CollectTimeLocale(List<SystemOverviewRow> rows, OsLocaleCardModel os)
        {
            rows.Add(Section("Time & Locale"));
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_TimeZone"))
                foreach (ManagementObject o in s.Get())
                {
                    var caption = (o["Caption"] as string) ?? "";
                    os.Timezone   = string.IsNullOrEmpty(caption) ? NotReported : caption;
                    os.SystemTime = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
                    rows.Add(Info("Timezone",    os.Timezone));
                    rows.Add(Info("System Time", os.SystemTime));
                    break;
                }
            }
            catch { /* skip */ }

            try
            {
                using (var k = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)
                                    .OpenSubKey(@"SYSTEM\CurrentControlSet\Services\W32Time\Parameters"))
                {
                    var server = k?.GetValue("NtpServer") as string;
                    os.NtpServer = string.IsNullOrEmpty(server) ? NotReported : server;
                    rows.Add(Info("NTP Server", os.NtpServer));
                }
            }
            catch { os.NtpServer = NotReported; rows.Add(Info("NTP Server", NotReported)); }
        }

        // ---- .NET runtimes + last cumulative update ----------------------------
        private static void CollectDotNetAndUpdates(OsLocaleCardModel os)
        {
            // .NET 4.x release version (single value — covers the common installed runtime).
            try
            {
                using (var k = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)
                                    .OpenSubKey(@"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"))
                {
                    var rel = k?.GetValue("Release");
                    if (rel != null && int.TryParse(rel.ToString(), out var release))
                    {
                        // Map per https://learn.microsoft.com/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed
                        string label;
                        if (release >= 533320)      label = "4.8.1";
                        else if (release >= 528040) label = "4.8";
                        else if (release >= 461808) label = "4.7.2";
                        else if (release >= 461308) label = "4.7.1";
                        else if (release >= 460798) label = "4.7";
                        else if (release >= 394802) label = "4.6.2";
                        else if (release >= 394254) label = "4.6.1";
                        else if (release >= 393295) label = "4.6";
                        else                         label = $"4.x (release {release})";
                        os.DotNetRuntimes = $".NET Framework {label}";
                    }
                    else
                    {
                        os.DotNetRuntimes = NotReported;
                    }
                }
            }
            catch { os.DotNetRuntimes = NotReported; }

            // Last cumulative KB.
            try
            {
                DateTime? newest = null;
                string newestKb = null;
                using (var s = new ManagementObjectSearcher("SELECT HotFixID, InstalledOn FROM Win32_QuickFixEngineering"))
                foreach (ManagementObject o in s.Get())
                {
                    var id = (o["HotFixID"] as string) ?? "";
                    var raw = o["InstalledOn"];
                    DateTime? when = null;
                    if (raw is DateTime dt) when = dt;
                    else if (raw != null && DateTime.TryParse(raw.ToString(), out var d)) when = d;
                    if (when.HasValue && (!newest.HasValue || when.Value > newest.Value))
                    {
                        newest = when;
                        newestKb = id;
                    }
                }
                os.LastUpdate = newestKb != null
                    ? $"{newestKb} ({newest.Value:yyyy-MM-dd})"
                    : NotReported;
            }
            catch { os.LastUpdate = NotReported; }
        }

        // ---- System (Win32_ComputerSystem + Win32_BIOS + SystemEnclosure) ------
        private static void CollectSystem(List<SystemOverviewRow> rows, SystemOverviewCards cards, IdentityCardModel id)
        {
            rows.Add(Section("System"));
            string mfr = "", model = "";
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_ComputerSystem"))
                foreach (ManagementObject o in s.Get())
                {
                    var name = (o["Name"] as string) ?? "";
                    id.ComputerName = string.IsNullOrEmpty(name) ? NotReported : name;
                    rows.Add(Info("Computer Name", id.ComputerName));

                    mfr   = ((o["Manufacturer"] as string) ?? "").Trim();
                    model = ((o["Model"]        as string) ?? "").Trim();
                    id.Manufacturer = string.IsNullOrEmpty(mfr)   ? NotReported : mfr;
                    id.Model        = string.IsNullOrEmpty(model) ? NotReported : model;
                    rows.Add(Info("Manufacturer", id.Manufacturer));
                    rows.Add(Info("Model",        id.Model));

                    var partOfDomain = false;
                    try { partOfDomain = Convert.ToBoolean(o["PartOfDomain"]); } catch { }
                    var domain    = (o["Domain"] as string)   ?? "";
                    var workgroup = (o["Workgroup"] as string) ?? "";
                    id.Network = partOfDomain ? $"Domain: {domain}" : $"Workgroup: {workgroup}";
                    rows.Add(Info("Network", id.Network));

                    var sysType = (o["SystemType"] as string) ?? "";
                    id.SystemType = string.IsNullOrEmpty(sysType) ? NotReported : sysType;
                    rows.Add(Info("System Type", id.SystemType));
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
                    id.BiosVersion = string.IsNullOrEmpty(biosStr) ? NotReported : biosStr;
                    rows.Add(Info("BIOS", id.BiosVersion));

                    var serial = ((o["SerialNumber"] as string) ?? "").Trim();
                    if (!string.IsNullOrEmpty(serial) &&
                        !serial.Equals("System Serial Number", StringComparison.OrdinalIgnoreCase) &&
                        !serial.Equals("To Be Filled By O.E.M.", StringComparison.OrdinalIgnoreCase) &&
                        !serial.Equals("Default string", StringComparison.OrdinalIgnoreCase))
                    {
                        id.SerialNumber = serial;
                        rows.Add(Gray("Serial Number", serial));
                    }
                    break;
                }
            }
            catch { /* BIOS unavailable */ }

            // Asset tag + chassis type from Win32_SystemEnclosure.
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT SMBIOSAssetTag, ChassisTypes FROM Win32_SystemEnclosure"))
                foreach (ManagementObject o in s.Get())
                {
                    var tag = (o["SMBIOSAssetTag"] as string ?? "").Trim();
                    if (!string.IsNullOrEmpty(tag) &&
                        !tag.Equals("No Asset Tag", StringComparison.OrdinalIgnoreCase) &&
                        !tag.Equals("Default string", StringComparison.OrdinalIgnoreCase) &&
                        !tag.Equals("To Be Filled By O.E.M.", StringComparison.OrdinalIgnoreCase))
                    {
                        id.AssetTag = tag;
                    }
                    var chassis = o["ChassisTypes"] as ushort[];
                    if (chassis != null && chassis.Length > 0)
                    {
                        id.ChassisType = ChassisTypeName(chassis[0]);
                    }
                    break;
                }
            }
            catch { /* enclosure unavailable */ }

            string modelCard;
            if (!string.IsNullOrEmpty(mfr) && !string.IsNullOrEmpty(model)) modelCard = $"{mfr}  {model}";
            else if (!string.IsNullOrEmpty(model))                          modelCard = model;
            else                                                            modelCard = "Unknown";
            if (modelCard.Length > 32) modelCard = modelCard.Substring(0, 29) + "...";
            cards.ModelTitle  = modelCard;
            cards.ModelStatus = "neutral";
        }

        private static string ChassisTypeName(ushort code)
        {
            switch (code)
            {
                case 1:  return "Other";
                case 2:  return "Unknown";
                case 3:  return "Desktop";
                case 4:  return "Low-Profile Desktop";
                case 5:  return "Pizza Box";
                case 6:  return "Mini Tower";
                case 7:  return "Tower";
                case 8:  return "Portable";
                case 9:  return "Laptop";
                case 10: return "Notebook";
                case 11: return "Hand Held";
                case 12: return "Docking Station";
                case 13: return "All-in-One";
                case 14: return "Sub-Notebook";
                case 15: return "Space-Saving";
                case 16: return "Lunch Box";
                case 17: return "Main System Chassis";
                case 18: return "Expansion Chassis";
                case 19: return "Sub Chassis";
                case 20: return "Bus Expansion Chassis";
                case 21: return "Peripheral Chassis";
                case 22: return "Storage Chassis";
                case 23: return "Rack Mount";
                case 24: return "Sealed-Case PC";
                case 25: return "All-in-One (Multi-system)";
                case 26: return "CompactPCI";
                case 27: return "AdvancedTCA";
                case 28: return "Blade";
                case 29: return "Blade Enclosure";
                case 30: return "Tablet";
                case 31: return "Convertible";
                case 32: return "Detachable";
                case 33: return "IoT Gateway";
                case 34: return "Embedded PC";
                case 35: return "Mini PC";
                case 36: return "Stick PC";
                default: return $"Code {code}";
            }
        }

        // ---- Processor (Win32_Processor) --------------------------------------
        private static void CollectProcessor(List<SystemOverviewRow> rows, SystemOverviewCards cards, ProcessorCardModel proc)
        {
            rows.Add(Section("Processor"));
            string cardVal = "Unknown CPU";
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_Processor"))
                foreach (ManagementObject o in s.Get())
                {
                    var name = ((o["Name"] as string) ?? "").Trim();
                    proc.Name = string.IsNullOrEmpty(name) ? NotReported : name;
                    rows.Add(Info("Name", proc.Name));

                    var pmfr = (o["Manufacturer"] as string) ?? "";
                    proc.Manufacturer = string.IsNullOrEmpty(pmfr) ? NotReported : pmfr;
                    rows.Add(Info("Manufacturer", proc.Manufacturer));

                    var maxMhz = Convert.ToDouble(o["MaxClockSpeed"] ?? 0);
                    if (maxMhz > 0)
                    {
                        proc.MaxSpeed = $"{maxMhz / 1000.0:F2} GHz";
                        rows.Add(Info("Max Speed", proc.MaxSpeed));
                    }

                    var cores = Convert.ToInt32(o["NumberOfCores"] ?? 0);
                    var lps   = Convert.ToInt32(o["NumberOfLogicalProcessors"] ?? 0);
                    proc.Cores = $"{cores} physical / {lps} logical";
                    rows.Add(Info("Cores", proc.Cores));

                    var socket = (o["SocketDesignation"] as string) ?? "";
                    if (!string.IsNullOrEmpty(socket))
                    {
                        proc.Socket = socket;
                        rows.Add(Info("Socket", socket));
                    }

                    // Family / stepping / processor ID.
                    try
                    {
                        var fam = o["Family"];
                        if (fam != null) proc.Family = fam.ToString();
                    } catch { }
                    try
                    {
                        var step = o["Stepping"] as string;
                        if (!string.IsNullOrEmpty(step)) proc.Stepping = step;
                    } catch { }
                    try
                    {
                        var pid = o["ProcessorId"] as string;
                        if (!string.IsNullOrEmpty(pid)) proc.ProcessorId = pid;
                    } catch { }
                    try
                    {
                        var v = o["VirtualizationFirmwareEnabled"];
                        if (v != null) proc.Virtualization = Convert.ToBoolean(v) ? "Enabled" : "Disabled";
                    } catch { }
                    try
                    {
                        var l2 = Convert.ToInt32(o["L2CacheSize"] ?? 0);
                        if (l2 > 0) proc.L2Cache = l2 >= 1024 ? $"{l2 / 1024.0:F1} MB" : $"{l2} KB";
                    } catch { }
                    try
                    {
                        var l3 = Convert.ToInt32(o["L3CacheSize"] ?? 0);
                        if (l3 > 0) proc.L3Cache = l3 >= 1024 ? $"{l3 / 1024.0:F1} MB" : $"{l3} KB";
                    } catch { }

                    if (cardVal == "Unknown CPU" && !string.IsNullOrEmpty(name))
                    {
                        cardVal = name
                            .Replace("Intel(R) Core(TM) ", "Core ")
                            .Replace("(R)", "")
                            .Replace("(TM)", "");
                        var atIdx = cardVal.IndexOf(" @ ", StringComparison.OrdinalIgnoreCase);
                        if (atIdx >= 0) cardVal = cardVal.Substring(0, atIdx);
                        while (cardVal.Contains("  ")) cardVal = cardVal.Replace("  ", " ");
                        cardVal = cardVal.Trim();
                    }
                }
            }
            catch { rows.Add(Warn("CPU", "Query failed")); }

            cards.CpuTitle  = cardVal.Length > 32 ? cardVal.Substring(0, 29) + "..." : cardVal;
            cards.CpuStatus = "neutral";
        }

        // ---- Memory (totals + per-slot) ----------------------------------------
        private static void CollectMemory(List<SystemOverviewRow> rows, SystemOverviewCards cards, MemoryCardModel mem)
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
                    mem.TotalRam  = $"{totalGb:F1} GB";
                    mem.Available = $"{freeGb:F1} GB";
                    rows.Add(Info("Total RAM", mem.TotalRam));
                    rows.Add(Info("Available", mem.Available));
                    cards.RamTitle  = $"{totalGB} GB total / {freeGb:F1} GB free";
                    cards.RamStatus = "ok";
                    break;
                }
            }
            catch { rows.Add(Warn("Memory", "Query failed")); }

            // Slot total from Win32_PhysicalMemoryArray.
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT MemoryDevices FROM Win32_PhysicalMemoryArray"))
                foreach (ManagementObject o in s.Get())
                {
                    var devs = Convert.ToInt32(o["MemoryDevices"] ?? 0);
                    if (devs > 0) mem.SlotsTotal = devs.ToString();
                    break;
                }
            }
            catch { /* skip */ }

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
                        var pmfr     = ((o["Manufacturer"] as string) ?? "").Trim();
                        var locator  = ((o["DeviceLocator"] as string) ?? $"Slot {n}").Trim();
                        var part     = ((o["PartNumber"]    as string) ?? "").Trim();
                        var mfrStr   = (!string.IsNullOrEmpty(pmfr) &&
                                        pmfr.IndexOf("Unknown", StringComparison.OrdinalIgnoreCase) < 0 &&
                                        pmfr.IndexOf("To Be",   StringComparison.OrdinalIgnoreCase) < 0)
                                            ? $"  ({pmfr})" : "";

                        mem.Slots.Add(new DimmSlot
                        {
                            Locator      = locator,
                            Capacity     = capGb > 0 ? $"{capGb} GB" : "",
                            Type         = memType,
                            Speed        = speedStr,
                            PartNumber   = part,
                            Manufacturer = pmfr
                        });

                        rows.Add(Info($"Slot {n} ({locator})", $"{capGb} GB {memType} {speedStr}{mfrStr}".Trim()));
                        if (!string.IsNullOrEmpty(part)) rows.Add(Gray("  Part Number", part));
                        n++;
                    }
                    if (mem.SlotsTotal == NotReported) mem.SlotsTotal = mem.Slots.Count.ToString();
                    mem.SlotsUsed = mem.Slots.Count.ToString();
                }
            }
            catch { /* slot enumeration failed */ }
        }

        // ---- Graphics (Win32_VideoController, prefer discrete) -----------------
        private static void CollectGraphics(List<SystemOverviewRow> rows, GraphicsCardModel gfx)
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
                if (gpus.Count == 0) { rows.Add(Warn("GPU", "None detected")); }
                else
                {
                    foreach (var g in gpus)
                    {
                        var adapter = new GraphicsAdapter
                        {
                            Name = (g["Name"] as string) ?? ""
                        };
                        rows.Add(Info("Name", adapter.Name));
                        var ramBytes = Convert.ToInt64(g["AdapterRAM"] ?? 0);
                        if (ramBytes > 0)
                        {
                            var mb = (int)(ramBytes / 1048576);
                            adapter.Vram = mb >= 1024 ? $"{mb / 1024} GB" : $"{mb} MB";
                            rows.Add(Info("VRAM", adapter.Vram));
                        }
                        var driver = (g["DriverVersion"] as string) ?? "";
                        if (!string.IsNullOrEmpty(driver))
                        {
                            adapter.DriverVersion = driver;
                            rows.Add(Gray("Driver", driver));
                        }
                        var dDate = ToDate(g["DriverDate"]);
                        if (dDate.HasValue)
                        {
                            adapter.DriverDate = dDate.Value.ToString("yyyy-MM-dd");
                            rows.Add(Gray("Driver Date", adapter.DriverDate));
                        }
                        gfx.Adapters.Add(adapter);
                    }
                }
            }
            catch { rows.Add(Warn("GPU", "Query failed")); }

            // Display output count.
            try
            {
                int displays = 0;
                using (var s = new ManagementObjectSearcher("SELECT Availability FROM Win32_DesktopMonitor"))
                foreach (ManagementObject o in s.Get())
                {
                    var avail = Convert.ToInt32(o["Availability"] ?? 0);
                    if (avail == 3) displays++;
                }
                gfx.DisplayCount = displays > 0 ? displays.ToString() : NotReported;
            }
            catch { gfx.DisplayCount = NotReported; }
        }

        // ---- Storage (physical disks + every logical volume) -------------------
        private static void CollectStorage(List<SystemOverviewRow> rows, SystemOverviewCards cards, StorageCardModel storage)
        {
            rows.Add(Section("Storage"));

            // MSFT_PhysicalDisk lookup table (BusType / MediaType / FW). Optional —
            // some hosts deny access to root\Microsoft\Windows\Storage.
            var byPnp = new Dictionary<string, (string Bus, string Media, string Firmware)>(StringComparer.OrdinalIgnoreCase);
            try
            {
                var scope = new ManagementScope(@"\\.\root\Microsoft\Windows\Storage");
                scope.Connect();
                var query = new ObjectQuery("SELECT FriendlyName, BusType, MediaType, FirmwareVersion, SerialNumber FROM MSFT_PhysicalDisk");
                using (var s = new ManagementObjectSearcher(scope, query))
                foreach (ManagementObject o in s.Get())
                {
                    var serial = ((o["SerialNumber"] as string) ?? "").Trim();
                    var bt = Convert.ToInt32(o["BusType"] ?? 0);
                    var mt = Convert.ToInt32(o["MediaType"] ?? 0);
                    var fw = (o["FirmwareVersion"] as string) ?? "";
                    if (!string.IsNullOrEmpty(serial))
                        byPnp[serial] = (BusTypeName(bt), MediaTypeName(mt), fw);
                }
            }
            catch { /* MSFT_PhysicalDisk may be unavailable */ }

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
                        var serial = ((d["SerialNumber"] as string) ?? "").Trim();
                        var firmware = (d["FirmwareRevision"] as string) ?? "";

                        string bus = iface, media = "";
                        if (!string.IsNullOrEmpty(serial) && byPnp.TryGetValue(serial, out var meta))
                        {
                            if (!string.IsNullOrEmpty(meta.Bus))   bus = meta.Bus;
                            if (!string.IsNullOrEmpty(meta.Media)) media = meta.Media;
                            if (string.IsNullOrEmpty(firmware) && !string.IsNullOrEmpty(meta.Firmware))
                                firmware = meta.Firmware;
                        }

                        storage.Disks.Add(new PhysicalDisk
                        {
                            Index    = pair.idx.ToString(),
                            Model    = model,
                            Size     = $"{sizeGb:F0} GB",
                            BusType  = bus,
                            MediaType = media,
                            Serial   = serial,
                            Firmware = firmware
                        });

                        rows.Add(Info($"Disk {pair.idx} - {model}", $"{sizeGb:F0} GB  [{bus}]"));
                        if (!string.IsNullOrEmpty(media))    rows.Add(Gray("  Media",    media));
                        if (!string.IsNullOrEmpty(firmware)) rows.Add(Gray("  Firmware", firmware));
                        if (!string.IsNullOrEmpty(serial))   rows.Add(Gray("  Serial",   serial));
                    }
                }
            }
            catch { rows.Add(Warn("Storage", "Query failed")); }

            // Every logical volume — not just the system drive.
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT DeviceID, VolumeName, FileSystem, FreeSpace, Size, DriveType FROM Win32_LogicalDisk"))
                foreach (ManagementObject o in s.Get())
                {
                    var driveType = Convert.ToInt32(o["DriveType"] ?? 0);
                    if (driveType != 3) continue; // local disks only
                    var dev = (o["DeviceID"] as string) ?? "";
                    var label = (o["VolumeName"] as string) ?? "";
                    var fs    = (o["FileSystem"] as string) ?? "";
                    var freeBytes = Convert.ToDouble(o["FreeSpace"] ?? 0);
                    var sizeBytes = Convert.ToDouble(o["Size"] ?? 0);
                    var freeGb = sizeBytes > 0 ? freeBytes / 1073741824.0 : 0;
                    var sizeGb = sizeBytes / 1073741824.0;
                    var pct = sizeBytes > 0 ? (int)Math.Round((1 - freeBytes / sizeBytes) * 100) : 0;

                    storage.Volumes.Add(new LogicalVolume
                    {
                        DriveLetter = dev,
                        Label       = string.IsNullOrEmpty(label) ? "(no label)" : label,
                        FileSystem  = fs,
                        Size        = $"{sizeGb:F1} GB",
                        FreeSpace   = $"{freeGb:F1} GB",
                        PercentUsed = $"{pct}%"
                    });
                }
            }
            catch { /* logical-disk query failed */ }

            // System-drive card.
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
            catch { /* leave card placeholder */ }
        }

        private static string BusTypeName(int code)
        {
            switch (code)
            {
                case 1:  return "SCSI";
                case 2:  return "ATAPI";
                case 3:  return "ATA";
                case 4:  return "1394";
                case 5:  return "SSA";
                case 6:  return "FibreChannel";
                case 7:  return "USB";
                case 8:  return "RAID";
                case 9:  return "iSCSI";
                case 10: return "SAS";
                case 11: return "SATA";
                case 12: return "SD";
                case 13: return "MMC";
                case 15: return "FileBackedVirtual";
                case 16: return "StorageSpaces";
                case 17: return "NVMe";
                case 18: return "Microsoft Reserved";
                default: return code > 0 ? $"Bus {code}" : "";
            }
        }

        private static string MediaTypeName(int code)
        {
            switch (code)
            {
                case 0: return "";
                case 3: return "HDD";
                case 4: return "SSD";
                case 5: return "SCM";
                default: return $"Type {code}";
            }
        }

        // ---- Network adapters (Win32_NetworkAdapter, physical only) -----------
        private static void CollectNetworkAdapters(List<SystemOverviewRow> rows, List<NicInventoryRow> table)
        {
            rows.Add(Section("Network Adapters"));
            try
            {
                var nics = new List<ManagementObject>();
                using (var s = new ManagementObjectSearcher(
                    "SELECT * FROM Win32_NetworkAdapter WHERE PhysicalAdapter=true"))
                foreach (ManagementObject o in s.Get()) nics.Add(o);

                if (nics.Count == 0) { rows.Add(Warn("NICs", "None detected")); return; }

                // Build a PNP -> (driver version, driver date) map from Win32_PnPSignedDriver.
                var driverByPnp = new Dictionary<string, (string Ver, string Date)>(StringComparer.OrdinalIgnoreCase);
                try
                {
                    using (var s = new ManagementObjectSearcher(
                        "SELECT DeviceID, DriverVersion, DriverDate FROM Win32_PnPSignedDriver WHERE DeviceClass='NET'"))
                    foreach (ManagementObject o in s.Get())
                    {
                        var did = (o["DeviceID"] as string) ?? "";
                        if (string.IsNullOrEmpty(did)) continue;
                        var ver = (o["DriverVersion"] as string) ?? "";
                        var dt  = ToDate(o["DriverDate"]);
                        driverByPnp[did] = (ver, dt.HasValue ? dt.Value.ToString("yyyy-MM-dd") : "");
                    }
                }
                catch { /* signed-driver query may be unavailable */ }

                foreach (var nic in nics.OrderBy(n => Convert.ToInt32(n["Index"] ?? 0)))
                {
                    var name = (nic["Name"] as string) ?? "";
                    var mac  = (nic["MACAddress"] as string) ?? "-";
                    var pnp  = (nic["PNPDeviceID"] as string) ?? "";

                    var speed = Convert.ToInt64(nic["Speed"] ?? 0);
                    string spdStr = "";
                    if (speed > 0)
                    {
                        spdStr = speed >= 1_000_000_000L ? $"{speed / 1_000_000_000L} Gbps"
                              : speed >= 1_000_000L     ? $"{speed / 1_000_000L} Mbps"
                              :                            $"{speed} bps";
                    }

                    int connStatus;
                    try { connStatus = Convert.ToInt32(nic["NetConnectionStatus"] ?? -1); }
                    catch { connStatus = -1; }
                    string connStr = connStatus == 2 ? "Connected"
                                  : connStatus == 7 ? "Media disconnected"
                                  :                    "Not connected";

                    string driverVer = "", driverDate = "";
                    if (!string.IsNullOrEmpty(pnp) && driverByPnp.TryGetValue(pnp, out var d))
                    {
                        driverVer  = d.Ver;
                        driverDate = d.Date;
                    }

                    table.Add(new NicInventoryRow
                    {
                        Name          = name,
                        Mac           = mac,
                        Speed         = spdStr,
                        Status        = connStr,
                        DriverVersion = driverVer,
                        DriverDate    = driverDate
                    });

                    rows.Add(Info(name, mac));
                    if (!string.IsNullOrEmpty(spdStr)) rows.Add(Info("  Speed", spdStr));
                    rows.Add(connStatus == 2 ? Pass("  Status", connStr) : Gray("  Status", connStr));
                    if (!string.IsNullOrEmpty(driverVer))  rows.Add(Gray("  Driver",      driverVer));
                    if (!string.IsNullOrEmpty(driverDate)) rows.Add(Gray("  Driver Date", driverDate));
                }
            }
            catch { rows.Add(Warn("NICs", "Query failed")); }
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

        private static void CollectInstalledSoftware(List<SystemOverviewRow> rows, SoftwareInventoryCardModel card)
        {
            rows.Add(Section("Installed Software"));
            try
            {
                var byName = new Dictionary<string, InstalledApp>(StringComparer.OrdinalIgnoreCase);
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
                                if (byName.ContainsKey(name)) continue;

                                var publisher = ek.GetValue("Publisher") as string ?? "";
                                var version   = ek.GetValue("DisplayVersion") as string ?? "";
                                var installRaw = ek.GetValue("InstallDate") as string ?? "";
                                string installDate = "";
                                if (!string.IsNullOrEmpty(installRaw) && installRaw.Length == 8 &&
                                    DateTime.TryParseExact(installRaw, "yyyyMMdd",
                                        System.Globalization.CultureInfo.InvariantCulture,
                                        System.Globalization.DateTimeStyles.None, out var d))
                                {
                                    installDate = d.ToString("yyyy-MM-dd");
                                }

                                bool flagged = false;
                                foreach (var pat in UnwantedPatterns)
                                {
                                    if (name.IndexOf(pat, StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        flagged = true;
                                        break;
                                    }
                                }

                                byName[name] = new InstalledApp
                                {
                                    DisplayName    = name,
                                    DisplayVersion = version,
                                    Publisher      = publisher,
                                    InstallDate    = installDate,
                                    IsFlagged      = flagged
                                };
                            }
                        }
                    }
                }

                card.AllApps = byName.Values.OrderBy(a => a.DisplayName, StringComparer.OrdinalIgnoreCase).ToList();
                card.FlaggedApps = card.AllApps.Where(a => a.IsFlagged).ToList();
                card.TotalCount = card.AllApps.Count;
                card.FlaggedCount = card.FlaggedApps.Count;

                rows.Add(Info("Total Installed", $"{card.TotalCount} applications"));
                if (card.FlaggedCount == 0)
                {
                    rows.Add(Pass("Flagged Apps", "None — no known-conflicting software detected"));
                }
                else
                {
                    rows.Add(Warn("Flagged Apps", $"{card.FlaggedCount} potentially-conflicting applications detected"));
                    foreach (var a in card.FlaggedApps)
                        rows.Add(Warn($"  {a.DisplayName}", $"{a.Publisher} — confirm this is intentional"));
                }
            }
            catch { rows.Add(Warn("Installed Software", "Scan failed")); }
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
