using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Net.NetworkInformation;
using System.Text.RegularExpressions;
using Microsoft.Win32;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Dashboard (home) panel data source. Hub tiles and last-run summary
    /// keep the v0.2.0 API; CollectSnapshot() is the new aggregator that
    /// gathers identity, gauges, NIC ports, network config, services and
    /// volumes by composing the other panel services + a few direct WMI
    /// reads (the gauges, which would otherwise duplicate logic). Each
    /// section is wrapped in try/catch — a missing component must not
    /// crash the entire dashboard.
    /// </summary>
    public class DashboardService : IDashboardService
    {
        // Composed dependencies — every other panel service the dashboard
        // pulls a one-paragraph view from. Wired up by MainViewModel.
        private readonly INetworkAdapterService _adapters;
        private readonly INetworkService _network;
        private readonly IServicesService _services;
        private readonly IDiskHealthService _disk;

        public DashboardService(
            INetworkAdapterService adapters,
            INetworkService network,
            IServicesService services,
            IDiskHealthService disk)
        {
            _adapters = adapters;
            _network  = network;
            _services = services;
            _disk     = disk;
        }

        // Parameterless ctor kept so unit tests / design-time XAML still build.
        public DashboardService() : this(null, null, null, null) { }

        // ---- Hub tiles + last-run (preserved from v0.2.0) -----------------------
        private static readonly HubTileViewModel[] Tiles =
        {
            new HubTileViewModel { Title="System Overview",        Description="Hardware specs, OS version, uptime, and Pixellot software inventory.",      IconKey="Information",      TargetNav="SystemOverview" },
            new HubTileViewModel { Title="Network Configuration",  Description="IP, DNS, firewall, and connectivity tests for required ports.",            IconKey="Lan",              TargetNav="Network"        },
            new HubTileViewModel { Title="Camera Connectivity",    Description="Cameras, NICs, link status, and the Fault Isolator wizard.",               IconKey="VideoVintage",     TargetNav="Camera"         },
            new HubTileViewModel { Title="Pixellot Services",      Description="Pixellot agent, encoder, watchdog, and remote service status.",            IconKey="CogPlay",          TargetNav="Services"       },
            new HubTileViewModel { Title="Hardware & Peripherals", Description="GPU, monitor, input devices, PoE budget, and NIC link uptime.",            IconKey="Monitor",          TargetNav="Hardware"       },
            new HubTileViewModel { Title="System & Disk Health",   Description="Free space, SMART health, and disk-related event log errors.",             IconKey="Harddisk",         TargetNav="DiskHealth"     },
            new HubTileViewModel { Title="Event Viewer",           Description="Recent OS errors filtered to VPU-relevant providers.",                     IconKey="ClipboardTextClock", TargetNav="Events"       },
            new HubTileViewModel { Title="Reports",                Description="View, copy, and export saved diagnostic reports.",                         IconKey="FileDocumentOutline", TargetNav="Reports"     },
        };

        public List<HubTileViewModel> GetHubTiles() => Tiles.ToList();

        public LastRunSummary GetLastRunSummary()
        {
            var candidates = new List<string>
            {
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments) + @"\PulseReports",
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments) + @"\Pulse",
                @"C:\Pixellot\Pulse",
            };

            FileInfo latest = null;
            foreach (var dir in candidates)
            {
                if (string.IsNullOrEmpty(dir)) continue;
                try
                {
                    if (!Directory.Exists(dir)) continue;
                    var found = new DirectoryInfo(dir).GetFiles("Pulse_Results_*.txt");
                    foreach (var f in found)
                    {
                        if (latest == null || f.LastWriteTime > latest.LastWriteTime) latest = f;
                    }
                }
                catch { }
            }
            if (latest == null) return null;

            string vpuModel = null;
            string overall = null;
            try
            {
                using (var r = new StreamReader(latest.FullName))
                {
                    int read = 0;
                    string line;
                    while ((line = r.ReadLine()) != null && read < 25)
                    {
                        read++;
                        var modelMatch = Regex.Match(line, @"^VPU Model\s*:\s*(.+)$", RegexOptions.IgnoreCase);
                        if (modelMatch.Success && vpuModel == null) vpuModel = modelMatch.Groups[1].Value.Trim();
                        var resultMatch = Regex.Match(line, @"^(Overall|Result|Status)\s*:\s*(.+)$", RegexOptions.IgnoreCase);
                        if (resultMatch.Success && overall == null) overall = resultMatch.Groups[2].Value.Trim();
                    }
                }
            }
            catch { }

            string sev;
            if (!string.IsNullOrEmpty(overall) && Regex.IsMatch(overall, "fail|error|critical", RegexOptions.IgnoreCase)) sev = "Fail";
            else if (!string.IsNullOrEmpty(overall) && Regex.IsMatch(overall, "warn|issue|degrad", RegexOptions.IgnoreCase)) sev = "Warn";
            else if (!string.IsNullOrEmpty(overall)) sev = "Pass";
            else sev = "Gray";

            return new LastRunSummary
            {
                When = latest.LastWriteTime,
                VpuModel = vpuModel,
                Result = overall ?? "",
                Severity = sev,
                ReportPath = latest.FullName,
            };
        }

        // ---- One-shot snapshot for the new Dashboard layout ---------------------
        public async System.Threading.Tasks.Task<DashboardSnapshot> CollectSnapshotAsync()
        {
            var snap = new DashboardSnapshot();
            CollectIdentity(snap);
            CollectPixellotSoftware(snap);
            CollectLastRun(snap);
            CollectGauges(snap);
            await CollectNicPortsAsync(snap).ConfigureAwait(false);
            CollectNetworkConfig(snap);
            CollectServices(snap);
            CollectVolumes(snap);
            BuildFindings(snap);
            return snap;
        }

        // -- Identity ------------------------------------------------------------
        private static void CollectIdentity(DashboardSnapshot snap)
        {
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT * FROM Win32_ComputerSystem"))
                foreach (ManagementObject o in s.Get())
                {
                    snap.Hostname     = (o["Name"] as string) ?? Environment.MachineName;
                    snap.Manufacturer = ((o["Manufacturer"] as string) ?? "").Trim();
                    snap.ProductName  = ((o["Model"]        as string) ?? "").Trim();
                    break;
                }
            }
            catch { snap.Hostname = Environment.MachineName; }

            try
            {
                using (var s = new ManagementObjectSearcher("SELECT SerialNumber FROM Win32_BIOS"))
                foreach (ManagementObject o in s.Get())
                {
                    var serial = ((o["SerialNumber"] as string) ?? "").Trim();
                    if (!string.IsNullOrEmpty(serial) &&
                        !serial.Equals("System Serial Number", StringComparison.OrdinalIgnoreCase) &&
                        !serial.Equals("To Be Filled By O.E.M.", StringComparison.OrdinalIgnoreCase) &&
                        !serial.Equals("Default string", StringComparison.OrdinalIgnoreCase))
                    {
                        snap.SerialNumber = serial;
                    }
                    break;
                }
            }
            catch { }

            // VPU label: walk the agent_*.log under C:\Pixellot\Data\Log for a
            // line that names the unit. Best-effort — most fields work without it.
            try { snap.VpuLabel = ParseVpuLabelFromAgentLogs() ?? snap.Hostname; }
            catch { snap.VpuLabel = snap.Hostname; }
        }

        private static string ParseVpuLabelFromAgentLogs()
        {
            // Mirrors the Camera Connectivity engine: look in known Pixellot log
            // dirs for the newest agent_*.log, scan for vpuName + presentedProductType.
            var roots = new[]
            {
                @"C:\Pixellot\Data\Log",
                @"C:\Pixellot\Logs",
                @"C:\Pixellot\Pulse",
                @"C:\ProgramData\Pixellot\Log",
            };
            FileInfo newest = null;
            foreach (var root in roots)
            {
                try
                {
                    if (!Directory.Exists(root)) continue;
                    var paths = new List<string> { root };
                    paths.AddRange(Directory.GetDirectories(root));
                    foreach (var p in paths)
                    {
                        var ag = new DirectoryInfo(p).GetFiles("agent_*.log");
                        foreach (var f in ag)
                            if (newest == null || f.LastWriteTime > newest.LastWriteTime) newest = f;
                    }
                }
                catch { }
            }
            if (newest == null) return null;

            string model = null, type = null;
            try
            {
                foreach (var line in File.ReadLines(newest.FullName))
                {
                    if (model == null)
                    {
                        var m = Regex.Match(line,
                            "\"paramName\"\\s*:\\s*\"vpuName\"[^}]*\"paramValue\"\\s*:\\s*\"([^\"]+)\"");
                        if (m.Success) model = m.Groups[1].Value;
                    }
                    if (type == null)
                    {
                        var m = Regex.Match(line,
                            "\"paramName\"\\s*:\\s*\"presentedProductType\"[^}]*\"paramValue\"\\s*:\\s*\"([^\"]+)\"");
                        if (m.Success) type = m.Groups[1].Value;
                    }
                    if (model != null && type != null) break;
                }
            }
            catch { }

            if (string.IsNullOrEmpty(model)) return null;
            return string.IsNullOrEmpty(type) ? model : $"{model}  ({type})";
        }

        // -- Pixellot software (registry) ---------------------------------------
        private static void CollectPixellotSoftware(DashboardSnapshot snap)
        {
            try
            {
                using (var k = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)
                                    .OpenSubKey(@"SOFTWARE\Pixellot"))
                {
                    if (k == null) return;
                    snap.PixellotApp   = (k.GetValue("Version")      as string) ?? "—";
                    snap.PixellotImage = (k.GetValue("ImageVersion") as string) ?? "—";
                    snap.PixellotDeps  = (k.GetValue("Dependencies") as string) ?? "—";

                    // Convention seen on PXLS2: ImageVersion's prefix doubles as the
                    // VPU model family — e.g. "PXLS2-2024.04.10" → "Pixellot S2".
                    if (!string.IsNullOrEmpty(snap.PixellotImage))
                    {
                        var m = Regex.Match(snap.PixellotImage, @"^(PXLS\d+|PXL\w+)");
                        if (m.Success)
                        {
                            var fam = m.Value;
                            snap.VpuModel = fam.StartsWith("PXLS")
                                ? "Pixellot " + fam.Substring(3)   // "PXLS2" → "Pixellot S2"
                                : "Pixellot " + fam.Substring(3);
                        }
                    }
                }
            }
            catch { /* registry key absent on dev machines — keep the placeholders */ }
        }

        // -- Last diagnostic run (formatted from GetLastRunSummary) -------------
        private void CollectLastRun(DashboardSnapshot snap)
        {
            var last = GetLastRunSummary();
            if (last == null) return;
            snap.LastRunWhen     = last.When.ToString("MMM d, h:mm tt");
            snap.LastRunResult   = string.IsNullOrEmpty(last.Result) ? "Run complete" : last.Result;
            snap.LastReportPath  = last.ReportPath;
            snap.LastRunSeverity = last.Severity == "Fail" ? "fail"
                                : last.Severity == "Warn" ? "warn"
                                : last.Severity == "Pass" ? "ok"
                                :                            "neutral";
        }

        // -- Gauges (CPU / Memory / Storage / Uptime / CPU name) ----------------
        private static void CollectGauges(DashboardSnapshot snap)
        {
            // CPU usage. PerformanceCounter's first read is always 0; sleep
            // briefly between reads so the second sample is meaningful. Total
            // delay ~250ms, runs once per dashboard refresh.
            try
            {
                using (var pc = new PerformanceCounter("Processor", "% Processor Time", "_Total", true))
                {
                    pc.NextValue();
                    System.Threading.Thread.Sleep(250);
                    snap.CpuUsagePct = Math.Round(pc.NextValue(), 0);
                }
            }
            catch { snap.CpuUsagePct = 0; }

            // Memory totals + free.
            try
            {
                using (var s = new ManagementObjectSearcher(
                    "SELECT TotalVisibleMemorySize,FreePhysicalMemory FROM Win32_OperatingSystem"))
                foreach (ManagementObject o in s.Get())
                {
                    var totalKb = Convert.ToDouble(o["TotalVisibleMemorySize"] ?? 0);
                    var freeKb  = Convert.ToDouble(o["FreePhysicalMemory"]    ?? 0);
                    if (totalKb <= 0) break;
                    var totalGb = totalKb / 1048576.0;
                    var freeGb  = freeKb  / 1048576.0;
                    var usedGb  = totalGb - freeGb;
                    snap.MemoryUsedPct   = Math.Round((usedGb / totalGb) * 100, 0);
                    snap.MemoryUsedLabel = $"{usedGb:F1} / {totalGb:F0} GB";
                    break;
                }
            }
            catch { }

            // Uptime + CPU name + cores.
            try
            {
                using (var s = new ManagementObjectSearcher("SELECT LastBootUpTime FROM Win32_OperatingSystem"))
                foreach (ManagementObject o in s.Get())
                {
                    var lbu = ManagementDateTimeConverter.ToDateTime(o["LastBootUpTime"].ToString());
                    var up = DateTime.Now - lbu;
                    snap.Uptime = $"{(int)Math.Floor(up.TotalDays)}d {up.Hours}h {up.Minutes}m";
                    break;
                }
            }
            catch { }

            try
            {
                using (var s = new ManagementObjectSearcher(
                    "SELECT Name,NumberOfLogicalProcessors FROM Win32_Processor"))
                foreach (ManagementObject o in s.Get())
                {
                    var name = ((o["Name"] as string) ?? "").Trim()
                        .Replace("Intel(R) Core(TM) ", "Core ")
                        .Replace("(R)", "")
                        .Replace("(TM)", "");
                    var atIdx = name.IndexOf(" @ ", StringComparison.OrdinalIgnoreCase);
                    if (atIdx >= 0) name = name.Substring(0, atIdx);
                    while (name.Contains("  ")) name = name.Replace("  ", " ");
                    snap.CpuName  = name.Trim();
                    snap.CpuCores = Convert.ToInt32(o["NumberOfLogicalProcessors"] ?? 0);
                    break;
                }
            }
            catch { }

            // Storage — system drive only for the headline gauge.
            try
            {
                var sysDrive = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.System))
                                  ?.TrimEnd('\\') ?? "C:";
                using (var s = new ManagementObjectSearcher(
                    $"SELECT FreeSpace,Size FROM Win32_LogicalDisk WHERE DeviceID='{sysDrive}'"))
                foreach (ManagementObject o in s.Get())
                {
                    var free = Convert.ToDouble(o["FreeSpace"] ?? 0);
                    var size = Convert.ToDouble(o["Size"]      ?? 0);
                    if (size <= 0) break;
                    var freeGb = free / 1073741824.0;
                    var sizeGb = size / 1073741824.0;
                    snap.DiskUsedPct   = Math.Round((1 - free / size) * 100, 0);
                    snap.DiskUsedLabel = $"{freeGb:F0} / {sizeGb:F0} GB free";
                    break;
                }
            }
            catch { }
        }

        // -- NIC ports (camera link snapshot) -----------------------------------
        private async System.Threading.Tasks.Task CollectNicPortsAsync(DashboardSnapshot snap)
        {
            if (_adapters == null) return;
            try { snap.NicPorts = await _adapters.GetCameraPortsAsync().ConfigureAwait(false)
                                  ?? new List<CameraNicSnapshot>(); }
            catch { }
        }

        // -- Network configuration + internet reachability ----------------------
        private void CollectNetworkConfig(DashboardSnapshot snap)
        {
            if (_network == null) return;
            try { snap.NetworkConfig = _network.GetIpConfiguration() ?? new IpConfigurationViewModel(); }
            catch { }
            snap.UplinkAdapterName = snap.NetworkConfig?.AdapterName ?? "—";

            // Internet reachability — a quick ping to a stable host. The full
            // Network panel runs the proper TCP/UDP/DNS suite; here we just
            // need a true/false for the dashboard tile.
            try
            {
                using (var p = new Ping())
                {
                    var reply = p.Send("8.8.8.8", 1500);
                    snap.InternetReachable = reply != null && reply.Status == IPStatus.Success;
                }
            }
            catch { snap.InternetReachable = false; }
        }

        // -- Pixellot services snapshot -----------------------------------------
        private void CollectServices(DashboardSnapshot snap)
        {
            if (_services == null) return;
            try { snap.Services = _services.GetServiceStatuses() ?? new List<ServiceStatusRow>(); }
            catch { }
        }

        // -- Volumes -------------------------------------------------------------
        private void CollectVolumes(DashboardSnapshot snap)
        {
            if (_disk == null) return;
            try { snap.Volumes = _disk.GetVolumes() ?? new List<VolumeRow>(); }
            catch { }
        }

        // -- Roll up the worst items into a short Active Findings list ---------
        // Keeps the Dashboard honest — if anything is broken it shows up here
        // without the user having to drill into each panel.
        private static void BuildFindings(DashboardSnapshot snap)
        {
            var findings = snap.Findings;

            // NIC ports — any down link on a known-camera-NIC is worth surfacing.
            if (snap.NicPorts != null)
            {
                int n = 1;
                foreach (var nic in snap.NicPorts)
                {
                    if (!nic.IsUp)
                    {
                        findings.Add(new DashboardFinding
                        {
                            Severity = "fail",
                            Title    = $"Port {n} ({nic.Name}) — link down",
                            Source   = "Camera",
                        });
                    }
                    else if (nic.LinkSpeedBps > 0 && nic.LinkSpeedBps < 1_000_000_000UL)
                    {
                        findings.Add(new DashboardFinding
                        {
                            Severity = "warn",
                            Title    = $"Port {n} ({nic.Name}) — sub-gigabit ({nic.LinkSpeedBps / 1_000_000UL} Mbps)",
                            Source   = "Camera",
                        });
                    }
                    n++;
                }
            }

            // Internet
            if (!snap.InternetReachable)
            {
                findings.Add(new DashboardFinding
                {
                    Severity = "warn",
                    Title    = "Internet not reachable (ping 8.8.8.8 failed)",
                    Source   = "Network",
                });
            }

            // Services — anything not Running on Automatic.
            if (snap.Services != null)
            {
                foreach (var s in snap.Services)
                {
                    if (string.Equals(s.Status, "Running", StringComparison.OrdinalIgnoreCase)) continue;
                    findings.Add(new DashboardFinding
                    {
                        Severity = "fail",
                        Title    = $"Service stopped: {s.DisplayName ?? s.Name}",
                        Source   = "Services",
                    });
                }
            }

            // Volumes — any volume below 15% free counts as warn, below 5% fail.
            if (snap.Volumes != null)
            {
                foreach (var v in snap.Volumes)
                {
                    if (v.TotalGb <= 0) continue;
                    var freePct = (v.FreeGb / v.TotalGb) * 100;
                    if (freePct < 5)
                    {
                        findings.Add(new DashboardFinding
                        {
                            Severity = "fail",
                            Title    = $"Volume {v.Drive} critically low ({freePct:F0}% free)",
                            Source   = "DiskHealth",
                        });
                    }
                    else if (freePct < 15)
                    {
                        findings.Add(new DashboardFinding
                        {
                            Severity = "warn",
                            Title    = $"Volume {v.Drive} low on space ({freePct:F0}% free)",
                            Source   = "DiskHealth",
                        });
                    }
                }
            }

            // Truncate to a reasonable headline count — full lists live in
            // their respective panels.
            if (findings.Count > 8) findings.RemoveRange(8, findings.Count - 8);
        }
    }
}
