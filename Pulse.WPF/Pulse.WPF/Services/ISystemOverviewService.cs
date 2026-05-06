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
    }
}
