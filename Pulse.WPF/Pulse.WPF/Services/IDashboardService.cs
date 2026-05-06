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

        // Cheap "just refresh the gauges" call for the live update timer —
        // only re-reads CPU / memory / disk / temperature. Skips the heavy
        // NIC poll, internet ping, services, and volumes so we can tick at
        // 2-second cadence without burning CPU.
        GaugeReadings ReadGauges();
    }

    /// <summary>Light-weight payload for the Dashboard's live-update tick.</summary>
    public class GaugeReadings
    {
        public double CpuUsagePct      { get; set; }
        public double MemoryUsedPct    { get; set; }
        public string MemoryUsedLabel  { get; set; } = "—";
        public double DiskUsedPct      { get; set; }
        public string DiskUsedLabel    { get; set; } = "—";
        public double TemperatureC     { get; set; } = double.NaN;
        public bool   TemperatureAvailable => !double.IsNaN(TemperatureC);
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
