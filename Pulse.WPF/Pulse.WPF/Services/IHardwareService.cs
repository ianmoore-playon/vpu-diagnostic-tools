using System.Collections.Generic;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Hardware panel data source. Pure C# port of PoeNicHardware.psm1
    /// excluding the PoE telemetry — that requires the Camera Connectivity
    /// runspace's NIC driver shim, which is out of scope for the WPF backend
    /// rewrite. PoE readings stay empty until the Camera Connectivity
    /// integration lands.
    /// </summary>
    public interface IHardwareService
    {
        string GetGpuName();
        int GetMonitorCount();
        bool HasMouse();
        bool HasKeyboard();
        // NIC link uptime — coarse buckets, not precise. Same shape as the
        // $sync.NicLinkUptimes the WinForms version maintains.
        List<NicUptime> GetNicUptimes();
        // PoE — empty list when the PoE NIC isn't present or the driver shim
        // is unavailable. TODO: integrate with the live PoE service.
        List<PoePortReading> GetPoePortReadings();
    }
}
