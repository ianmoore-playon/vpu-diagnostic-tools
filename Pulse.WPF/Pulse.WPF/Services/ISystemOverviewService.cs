using System.Collections.Generic;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// System Overview (specs) panel data source. Adapted from the legacy
    /// PowerShell SystemInformation.psm1 — full hardware / OS / time-locale /
    /// Pixellot-software inventory plus the 6 summary cards (Model, OS,
    /// Uptime, CPU, RAM, Storage).
    /// </summary>
    public interface ISystemOverviewService
    {
        SystemOverviewSnapshot Collect();
    }

    /// <summary>
    /// Single snapshot of every value the System Overview panel renders.
    /// One service call returns the cards, the inventory rows, and the
    /// summary bullets so the UI doesn't fan out a dozen WMI queries.
    /// </summary>
    public class SystemOverviewSnapshot
    {
        public SystemOverviewCards Cards { get; set; } = new SystemOverviewCards();
        public List<SystemOverviewRow> Inventory { get; set; } = new List<SystemOverviewRow>();
        public List<SystemOverviewSummaryItem> Summary { get; set; } = new List<SystemOverviewSummaryItem>();

        // Typed per-card models — UX_REVIEW round 2 §3 / §5. The
        // structured cards bind against these; the flat Inventory list
        // above is kept populated only so the legacy Copy-as-text path
        // keeps a fallback transcript while the new per-card renderer
        // takes over.
        public IdentityCardModel           Identity         { get; set; } = new IdentityCardModel();
        public PixellotSoftwareCardModel   PixellotSoftware { get; set; } = new PixellotSoftwareCardModel();
        public ProcessorCardModel          Processor        { get; set; } = new ProcessorCardModel();
        public MemoryCardModel             Memory           { get; set; } = new MemoryCardModel();
        public GraphicsCardModel           Graphics         { get; set; } = new GraphicsCardModel();
        public StorageCardModel            Storage          { get; set; } = new StorageCardModel();
        public OsLocaleCardModel           OsLocale         { get; set; } = new OsLocaleCardModel();
        public List<NicInventoryRow>       NetworkAdapters  { get; set; } = new List<NicInventoryRow>();
        public SoftwareInventoryCardModel  SoftwareInventory { get; set; } = new SoftwareInventoryCardModel();
    }
}
