using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Network panel data source. Pure C# — mirrors the test logic in
    /// Modules/NetworkDiagnostics.psm1 ($PortTests / $DomainTests / Test-Tcp/Udp*).
    /// Side-card data (adapters, IP config) is fast and synchronous; the port
    /// and domain probes are async and run in parallel via Task.WhenAll.
    /// </summary>
    public interface INetworkService
    {
        // Side cards — quick reads, no probes.
        List<NetworkAdapterRow> GetAdapters();
        IpConfigurationViewModel GetIpConfiguration();

        /// <summary>
        /// Single primary internet-bound adapter (the one with a non-zero
        /// default gateway). Returns null if none can be located.
        /// </summary>
        NetworkAdapterRow GetPrimaryInternetAdapter();

        // Active probes — TCP/UDP connect tests against the canonical
        // PortTests / DomainTests sets from NetworkDiagnostics.psm1.
        Task<List<PortTestResult>> RunPortTestsAsync();
        Task<List<DomainTestResult>> RunDomainTestsAsync();
        Task<bool> CheckInternetAsync();

        /// <summary>
        /// Raised when a formerly-silent catch block intercepts an exception.
        /// Mirrors DashboardService.OnSilentError — wired by NetworkViewModel
        /// in its constructor so collection / probe failures surface in the
        /// panel's Live Log and the rolling AppLogFile (v0.6.4).
        /// </summary>
        event Action<string, Exception> OnSilentError;
    }
}
