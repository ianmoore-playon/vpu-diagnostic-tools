using System;
using System.Collections.Generic;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>Dashboard (home) panel data source. Returns the static
    /// hub-tile definitions and the last-run summary read from the report
    /// directory if available. (Renamed from ISystemOverviewService — the
    /// hub tab is now called "Dashboard" and a new "System Overview" tab
    /// hosts full hardware specs.)</summary>
    public interface IDashboardService
    {
        List<HubTileViewModel> GetHubTiles();
        // Last-run summary; null when no report has been generated yet.
        LastRunSummary GetLastRunSummary();
    }

    /// <summary>Tiny DTO for the "Last Run: Apr 30, 2:14 PM — Healthy" line.</summary>
    public class LastRunSummary
    {
        public DateTime When { get; set; }
        public string VpuModel { get; set; }
        public string Result { get; set; }   // "Healthy" / "Issues found" / etc.
        public string Severity { get; set; } // "Pass" / "Warn" / "Fail" / "Gray"
        public string ReportPath { get; set; }
    }
}
