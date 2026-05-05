using System.Collections.Generic;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>Pixellot Services panel data source — process + service health.
    /// Pure C# port of PixellotServices.psm1.</summary>
    public interface IServicesService
    {
        // Returns one row per known process/service (Agent, KeepAgentUp,
        // Coordinator, LogMeIn, VPU, Scoreconnect*).
        List<ServiceStatusRow> GetServiceStatuses();
    }
}
