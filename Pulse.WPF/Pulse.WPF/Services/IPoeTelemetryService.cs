using System.Collections.Generic;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Telemetry from the ADLINK SmartPoE NIC driver shim. The C# port of the
    /// PowerShell-side AdlinkPoE P/Invoke wrappers in Modules/UIHelpers.psm1
    /// (v0.5.0). Lives behind an interface so an unsupported host can be
    /// faked / stubbed without touching the Hardware panel.
    /// </summary>
    public interface IPoeTelemetryService
    {
        /// <summary>
        /// True when SmartPoE.dll loaded and Register_Card succeeded. When
        /// false, the Hardware panel renders the "driver bundle not installed"
        /// empty state instead of an empty DataGrid.
        /// </summary>
        bool IsAvailable { get; }

        /// <summary>
        /// Human-readable explanation for why telemetry is unavailable —
        /// surfaced in the Hardware Findings banner. Empty when IsAvailable.
        /// </summary>
        string UnavailableReason { get; }

        /// <summary>
        /// Total / Consumed / Remaining PoE budget (W). All zero when
        /// IsAvailable is false.
        /// </summary>
        PoeBudgetReading GetBudget();

        /// <summary>
        /// Per-port voltage / current / watts. Returns an empty list when
        /// IsAvailable is false.
        /// </summary>
        List<PoePortReading> GetPortReadings();
    }

    /// <summary>Aggregate PoE budget surfaced by the SmartPoE shim.</summary>
    public class PoeBudgetReading
    {
        public double TotalW     { get; set; }
        public double ConsumedW  { get; set; }
        public double RemainingW { get; set; }
        public double TempC      { get; set; }
        // < 55 W is the WinForms low-budget threshold (Molex disconnected).
        public bool Low => TotalW > 0 && TotalW < 55;
    }
}
