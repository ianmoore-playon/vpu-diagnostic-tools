using System.Collections.Generic;
using Pulse.WPF.Services;   // for CameraNicSnapshot

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One-shot bundle of every field the Dashboard panel renders. Gathered
    /// in DashboardService.CollectSnapshot() so the panel doesn't fan out a
    /// dozen WMI queries on the UI thread.
    /// </summary>
    public class DashboardSnapshot
    {
        // ---- Identity & version ---------------------------------------------
        public string VpuLabel        { get; set; } = "—";   // "PXLS2_5931  Olympia (IL)"  (best-effort)
        public string VpuModel        { get; set; } = "—";   // "Pixellot S2"
        public string Hostname        { get; set; } = "—";
        public string Manufacturer    { get; set; } = "—";
        public string ProductName     { get; set; } = "—";
        public string SerialNumber    { get; set; } = "—";

        public string PixellotApp     { get; set; } = "—";
        public string PixellotImage   { get; set; } = "—";
        public string PixellotDeps    { get; set; } = "—";

        // ---- Last diagnostic run summary ------------------------------------
        public string LastRunWhen     { get; set; } = "Never";   // "May 6, 2:14 PM"
        public string LastRunResult   { get; set; } = "—";       // "Healthy" / "Issues found"
        public string LastRunSeverity { get; set; } = "neutral"; // "ok" / "warn" / "fail" / "neutral"
        public string LastReportPath  { get; set; }              // null when no report exists

        // ---- System status gauges -------------------------------------------
        public double CpuUsagePct     { get; set; }              // 0..100
        public double MemoryUsedPct   { get; set; }              // 0..100
        public string MemoryUsedLabel { get; set; } = "—";       // "22.3 / 64 GB"
        public double DiskUsedPct     { get; set; }              // 0..100 (system drive)
        public string DiskUsedLabel   { get; set; } = "—";       // "94 / 932 GB free"
        public string Uptime          { get; set; } = "—";       // "1d 7h 13m"
        public string CpuName         { get; set; } = "—";       // "Core i9-12900K"
        public int    CpuCores        { get; set; }              // logical core count
        public double TemperatureC    { get; set; } = double.NaN; // NaN = unavailable
        public bool   TemperatureAvailable => !double.IsNaN(TemperatureC);

        // ---- NIC ports / camera links ---------------------------------------
        // Reuse CameraNicSnapshot from INetworkAdapterService — same shape.
        public List<CameraNicSnapshot> NicPorts { get; set; } = new List<CameraNicSnapshot>();

        // ---- Network configuration ------------------------------------------
        public IpConfigurationViewModel NetworkConfig { get; set; } = new IpConfigurationViewModel();
        public bool   InternetReachable      { get; set; }
        public string UplinkAdapterName      { get; set; } = "—";

        // ---- Pixellot services snapshot -------------------------------------
        public List<ServiceStatusRow> Services { get; set; } = new List<ServiceStatusRow>();

        // ---- Volumes (system drive + extras) --------------------------------
        public List<VolumeRow> Volumes { get; set; } = new List<VolumeRow>();

        // ---- Aggregated quick-look findings ---------------------------------
        // Headline issues to surface above the action bar. Populated by
        // DashboardService rolling up the worst items from Services / NIC
        // ports / disk / network. UI shows the top 5; click "Run Full
        // Diagnostic" to see the rest.
        public List<DashboardFinding> Findings { get; set; } = new List<DashboardFinding>();

        // ---- Empty-state flag ------------------------------------------------
        // True when the host has no Pixellot software at all (registry blank
        // and no agent log discovered). Drives the "Pixellot software not
        // detected" empty-state card on the Dashboard so a clean dev box
        // doesn't read as a healthy VPU.
        public bool IsNonVpuHost { get; set; }
    }

    /// <summary>
    /// A short headline issue for the Dashboard's "Active Findings" strip.
    /// Title is the plain-English summary the operator sees first; Detail
    /// is the engineer-facing technical line shown on hover (binds to
    /// ToolTip on the row). Severity drives the dot colour; TargetNav is
    /// the SidebarNav key clicking the row should navigate to ("Network",
    /// "SystemOverview", "Services", "DiskHealth", "Camera"). Source is kept for
    /// telemetry / debugging — not rendered on the row anymore.
    /// </summary>
    public class DashboardFinding
    {
        public string Severity  { get; set; } = "neutral";   // "ok"/"warn"/"fail"/"neutral"
        public string Title     { get; set; } = "";
        public string Detail    { get; set; } = "";
        public string Source    { get; set; } = "";
        public string TargetNav { get; set; } = "";
        // True when DashboardViewModel projected this from a panel's
        // Findings collection after a baseline run. Used to replace the
        // previous baseline merge on re-run instead of stacking duplicates.
        public bool FromBaseline { get; set; }
    }
}
