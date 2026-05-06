using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Dashboard (home) panel data source. Hub-tile + last-run-summary logic
    /// ported from SystemOverview.psm1. Tile order kept stable; the first tile
    /// jumps to the new "System Overview" specs tab.
    /// </summary>
    public class DashboardService : IDashboardService
    {
        // Material Design Icons keys (kind="...") consumed by the XAML PackIcon
        // control. Picked to mirror the Segoe MDL2 glyphs used in the WinForms
        // hub layout — close visual equivalents, not exact glyph matches.
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
            // The WinForms version writes Pulse_Results_*.txt under $OutputDir
            // (which defaults to %USERPROFILE%\Documents\PulseReports). Walk a
            // few candidate directories before giving up.
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

            // Read the first 25 lines like the WinForms version.
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
    }
}
