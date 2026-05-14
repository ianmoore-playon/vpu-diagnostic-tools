using System.Collections.Generic;
using System.Threading.Tasks;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Data source for the Score Connect panel. All methods are async; every
    /// HTTP probe is wrapped in try/catch in the implementation so the panel
    /// renders cleanly when ScoreConnect III isn't installed or isn't running.
    ///
    /// Service-layer code never assumes the API response shape is exactly
    /// known — fields are parsed defensively and missing data surfaces as
    /// empty strings / empty lists, not exceptions. Endpoint paths were
    /// extracted from <c>strings</c> dumps of the installed ScoreConnect III
    /// binaries (v0.6.0 ledger).
    /// </summary>
    public interface IScoreConnectService
    {
        // ---- Read-only probes (Phase 1 surface) ----

        /// <summary>Probe the configured base URL with a short timeout. Sets
        /// <see cref="ScoreConnectStatus.IsDetected"/> on a successful 2xx.</summary>
        Task<ScoreConnectStatus> ProbeAsync();

        /// <summary>Pull the active scoreboard configuration. Calls
        /// <c>get-current-configuration-extended</c> first, falls back to
        /// <c>get-current-configuration</c> if extended isn't available.</summary>
        Task<ScoreConnectConfiguration> GetCurrentConfigurationAsync();

        Task<ScoreConnectBotStatus> GetBotStatusAsync();

        Task<List<ScoreConnectSerialPortInfo>> GetAvailablePortsAsync();

        Task<List<ScoreConnectVendorListItem>> GetVendorsAsync();

        Task<List<ScoreConnectVendorSportListItem>> GetVendorSportsAsync(string vendorId);

        Task<List<ScoreConnectVendorConfigurationListItem>>
            GetVendorConfigurationsAsync(string vendorSportId);

        Task<List<ScoreConnectDeviceListItem>> GetDevicesAsync();

        /// <summary>Best-effort firmware update probe. Returns the offered
        /// version when the upstream Sportzcast update API advertises one,
        /// empty when there's nothing available or the endpoint is
        /// unreachable. Used by the panel to surface an Info finding.</summary>
        Task<string> GetAvailableFirmwareUpdateAsync();

        // v0.6.3 — fill in Device / SerialPort / Firmware / EventType
        // from the dedicated "selected vendor sport / configuration"
        // endpoints when get-current-configuration leaves them blank.
        Task FillSelectedVendorSportAsync(ScoreConnectConfiguration cfg);
        Task FillSelectedVendorConfigurationAsync(ScoreConnectConfiguration cfg);

        // ---- Write / configure (Phase 3 surface) ----

        // v0.6.3: SetVendorAsync removed (ScoreConnect has no standalone
        // select-vendor endpoint — vendor changes flow through
        // SetVendorSportAsync). The interface drops the method to make the
        // constraint explicit; VM callers now run a two-step vendor + sport
        // prompt and call SetVendorSportAsync at the end.
        Task<bool> SetVendorSportAsync(string vendorSportId);
        Task<bool> SetVendorConfigurationAsync(string configId);
        Task<bool> SetDecoderInfoAsync(string vendorSportId, string serialPort);
        Task<bool> SetScoreConnectConfigurationAsync(
            string vendorId, string vendorSportId, string configurationId);

        // ---- Settings surface ----

        /// <summary>Current base URL the service is probing. This reflects
        /// the runtime Settings value, so saving a new URL does not require
        /// restarting Pulse.</summary>
        string BaseUrl { get; }
    }
}
