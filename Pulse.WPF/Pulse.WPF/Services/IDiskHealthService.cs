using System.Collections.Generic;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>Disk Health panel data source. Pure C# port of DiskHealth.psm1.</summary>
    public interface IDiskHealthService
    {
        List<VolumeRow> GetVolumes();
        List<PixellotPathRow> GetPixellotPaths();
        // True if SMART predicts failure on any disk. Returns null when SMART
        // can't be queried (root\wmi requires admin on some systems).
        bool? SmartPredictsFailure();
        // Count of disk-related System log error events in the last 48 h.
        int CountDiskErrorEvents48h();
    }
}
