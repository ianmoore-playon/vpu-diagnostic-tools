using System.Collections.Generic;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// System Overview hardware/peripherals data source. Pure C# port of PoeNicHardware.psm1
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
        // PoE — empty list when the PoE NIC isn't present or the driver shim
        // is unavailable. Inspect PoeTelemetryAvailable / Reason first to
        // distinguish "no PoE card" from "driver bundle missing".
        List<PoePortReading> GetPoePortReadings();
        bool PoeTelemetryAvailable { get; }
        string PoeTelemetryUnavailableReason { get; }
        PoeBudgetReading GetPoeBudget();
    }
}
