using System;
using System.Collections.Generic;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Dashboard (home) panel data source. Aggregates from the other panel
    /// services (Network / Network adapters / Services / Disk) so the
    /// Dashboard can render a one-page snapshot without each panel having
    /// to be visited first. Hub tiles + last-run summary kept for backward
    /// compatibility with the v0.2.0 layout — the new dashboard primarily
    /// renders DashboardSnapshot.
    /// </summary>
    public interface IDashboardService
    {
        // Hub tiles for the bottom Quick Nav row.
        List<HubTileViewModel> GetHubTiles();

        // Last-run summary; null when no report has been generated yet.
        LastRunSummary GetLastRunSummary();

        // One-shot snapshot covering identity, gauges, NIC ports, network
        // config, services, volumes, and rolled-up findings. Async because
        // the NIC-port poll uses GetCameraPortsAsync(); other reads happen
        // synchronously inside this call. Caller should keep this off the
        // UI thread.
        System.Threading.Tasks.Task<DashboardSnapshot> CollectSnapshotAsync();
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
