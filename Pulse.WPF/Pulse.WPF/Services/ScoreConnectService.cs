using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// HTTP client for the ScoreConnect III ASP.NET Core API. All endpoints
    /// live under <c>api/v1/configuration/...</c> (the V2 controller offers
    /// the same handful at <c>api/v2/configuration/...</c> — V1 is the wider
    /// surface and what this client targets).
    ///
    /// Defensive style throughout:
    ///   - Every HTTP call has a timeout (2 s for reads, 10 s for writes).
    ///   - Every call is wrapped in try/catch — a failure surfaces as an
    ///     empty result, never an unhandled exception.
    ///   - JSON shapes are parsed via <see cref="JsonScrape"/>, which returns
    ///     empty values on any unexpected key / missing field. We DON'T pull
    ///     in Newtonsoft.Json or System.Text.Json (csproj convention — see
    ///     UX_REVIEW notes).
    ///   - <see cref="HttpClient"/> is constructor-injected as a singleton —
    ///     a new instance per call would exhaust sockets on the loopback
    ///     listener under heavy panel refresh churn.
    ///
    /// Endpoint catalog (extracted from <c>strings ScoreConnectIII.dll</c>):
    ///   GET  api/v1/configuration/get-current-configuration
    ///   GET  api/v1/configuration/get-current-configuration-extended
    ///   GET  api/v2/configuration/get-bot-configuration-status
    ///   GET  api/v1/configuration/get-vendor-list
    ///   GET  api/v1/configuration/get-vendor-sports/{vendorId}
    ///   GET  api/v1/configuration/get-vendor-configurations/{vendorSportId}
    ///   GET  api/v1/configuration/get-devices-list
    ///   GET  api/v1/configuration/get-available-ports        (inferred — no route attr observed; method exists)
    ///   POST api/v1/configuration/select-vendor-sport/{id}
    ///   POST api/v1/configuration/select-vendor-configuration/{id}
    ///   POST api/v2/configuration/set-scoreconnect-configuration
    /// </summary>
    public class ScoreConnectService : IScoreConnectService
    {
        private const int ReadTimeoutMs = 2000;     // ProbeAsync
        private const int FetchTimeoutMs = 5000;    // GET reads
        private const int WriteTimeoutMs = 10000;   // POST writes

        // Common endpoint roots. Centralised so a rename ripples through
        // exactly once. Kept as private const strings instead of f-strings so
        // the route catalog is greppable from a single place.
        // v0.6.2: the live VPU log shows every "api/v1/configuration/..." call
        // 404'd — the real swagger.json has no v1 prefix; routes live at
        // /api/configuration/... The constant name is kept (V1Cfg) so the
        // dozen call sites don't churn, but it now resolves to the documented
        // path. The legacy v1Fallback handler in TryGetAsync still tries the
        // old prefix when a probe fails, so an older ScoreConnect III build
        // (if any) still works.
        private const string V1Cfg = "api/configuration";
        private const string LegacyV1Cfg = "api/v1/configuration";
        private const string V2Cfg = "api/v2/configuration";

        private readonly HttpClient _http;
        private readonly string _baseUrl;

        public string BaseUrl => _baseUrl;

        public ScoreConnectService(HttpClient http)
        {
            _http = http ?? throw new ArgumentNullException(nameof(http));
            _baseUrl = (AppSettings.Instance.ScoreConnectUrl ??
                        AppSettings.DefaultScoreConnectUrl).TrimEnd('/');
        }

        // ---------- Probe ----------

        public async Task<ScoreConnectStatus> ProbeAsync()
        {
            var status = new ScoreConnectStatus
            {
                BaseUrl = _baseUrl,
                LastProbedAt = DateTime.Now,
                IsDetected = false,
            };

            // Try the API health route first (cheap, returns config JSON if
            // service is up). Fall back to the root (the MVC homepage)
            // because some ScoreConnect builds 404 the bare /api path.
            string[] probes =
            {
                $"{V1Cfg}/get-current-configuration",
                "",
            };

            foreach (var path in probes)
            {
                var (ok, body, err) = await TryGetAsync(path, ReadTimeoutMs).ConfigureAwait(false);
                if (ok)
                {
                    status.IsDetected = true;
                    status.ProbeError = "";
                    // Most ScoreConnect responses don't carry a version, but
                    // the deps.json lists 3.x — best-effort scrape so the UI
                    // has SOMETHING when the field is present.
                    var v = JsonScrape.String(body ?? "", "version");
                    if (!string.IsNullOrEmpty(v)) status.Version = v;
                    return status;
                }
                status.ProbeError = err ?? "Service not reachable.";
            }

            return status;
        }

        // ---------- Configuration reads ----------

        public async Task<ScoreConnectConfiguration> GetCurrentConfigurationAsync()
        {
            var cfg = new ScoreConnectConfiguration();

            // Try the extended endpoint first — it carries the firmware /
            // event-type / vendor-configuration-id fields too. If extended
            // isn't there we still get the basic fields off the v1 endpoint.
            string[] endpoints =
            {
                $"{V1Cfg}/get-current-configuration-extended",
                $"{V1Cfg}/get-current-configuration",
                // v2 prefix is not used by current ScoreConnect builds (no
                // route registered); the TryGetAsync fallback already retries
                // V1Cfg -> LegacyV1Cfg on 404, so the third entry would only
                // ever fire for an exotic build. Kept for back-compat.
                $"{V2Cfg}/get-current-configuration",
            };

            foreach (var path in endpoints)
            {
                var (ok, body, _) = await TryGetAsync(path, FetchTimeoutMs).ConfigureAwait(false);
                if (!ok || string.IsNullOrWhiteSpace(body)) continue;
                PopulateConfigurationFromJson(cfg, body);
                if (!cfg.IsEmpty) return cfg;
            }

            return cfg;
        }

        // Tolerant field projection — every key has a small alias set because
        // V1 / V2 / extended don't share spellings. Anything else is captured
        // in ExtendedFields so the raw data is at least visible to the
        // operator if the typed mapping ever drifts.
        private static void PopulateConfigurationFromJson(
            ScoreConnectConfiguration cfg, string body)
        {
            var map = JsonScrape.ObjectAsMap(body);
            if (map.Count == 0) return;

            // v0.6.1: field aliases tuned against the real swagger.json
            // + a live VPU report (see /Users/ian.moore/Code/swagger +
            // VPU2-ScoreConnect-...txt). Real keys observed:
            //   vendorName, vendorId, vendorSportName, vendorSportId,
            //   vendorSportCode, vendorConfigurationName,
            //   additionalConfiguration. The legacy alias list is kept as a
            //   fallback so older ScoreConnect builds still parse cleanly.
            cfg.Vendor                  = PickFirst(map, "vendorName", "vendor", "currentVendor", "currentSbvendor");
            cfg.Sport                   = PickFirst(map, "vendorSportName", "sport", "vendorSport", "sportName", "vendorSportCode", "currentSbCode");
            cfg.Device                  = PickFirst(map, "device", "deviceName", "deviceId");
            cfg.SerialPort              = PickFirst(map, "serialPort", "port", "comPort", "portName");
            cfg.Firmware                = PickFirst(map, "firmware", "firmwareVersion", "fwVersion");
            cfg.EventType               = PickFirst(map, "eventType", "eventTypeName", "eventTypeId");
            cfg.VendorConfigurationId   = PickFirst(map, "vendorConfigurationId", "configurationId", "currentConfigurationId");
            cfg.VendorConfigurationName = PickFirst(map, "vendorConfigurationName", "configurationName");
            cfg.VendorId                = PickFirst(map, "vendorId");
            cfg.VendorSportId           = PickFirst(map, "vendorSportId");

            // Stash unrecognised fields so the operator can still see what
            // the service is reporting even when the typed mapping misses.
            cfg.ExtendedFields.Clear();
            foreach (var kv in map)
            {
                if (IsTypedKey(kv.Key)) continue;
                if (string.IsNullOrEmpty(kv.Value)) continue;
                cfg.ExtendedFields[kv.Key] = kv.Value;
            }
        }

        private static bool IsTypedKey(string key)
        {
            if (string.IsNullOrEmpty(key)) return true;
            switch (key.ToLowerInvariant())
            {
                case "vendor":
                case "vendorname":
                case "currentvendor":
                case "currentsbvendor":
                case "vendorid":
                case "sport":
                case "vendorsport":
                case "vendorsportname":
                case "vendorsportcode":
                case "vendorsportid":
                case "sportname":
                case "currentsbcode":
                case "device":
                case "devicename":
                case "deviceid":
                case "serialport":
                case "port":
                case "comport":
                case "portname":
                case "firmware":
                case "firmwareversion":
                case "fwversion":
                case "eventtype":
                case "eventtypename":
                case "eventtypeid":
                case "vendorconfigurationid":
                case "vendorconfigurationname":
                case "configurationid":
                case "configurationname":
                case "currentconfigurationid":
                    return true;
            }
            return false;
        }

        private static string PickFirst(Dictionary<string, string> map, params string[] keys)
        {
            foreach (var k in keys)
            {
                if (map.TryGetValue(k, out var v) && !string.IsNullOrWhiteSpace(v))
                    return v;
            }
            return "";
        }

        // ---------- BOT cloud status ----------

        public async Task<ScoreConnectBotStatus> GetBotStatusAsync()
        {
            var s = new ScoreConnectBotStatus();
            // v0.6.1: the real swagger.json route is /api/configuration/
            // get-bot-number (no v2 prefix, no -configuration-status suffix).
            // We try the documented path first and fall back to the legacy
            // guess so an older ScoreConnect III still resolves cleanly.
            var (ok, body, _) = await TryGetAsync(
                $"{V1Cfg}/get-bot-number", FetchTimeoutMs).ConfigureAwait(false);
            if (!ok || string.IsNullOrWhiteSpace(body))
            {
                (ok, body, _) = await TryGetAsync(
                    $"{V2Cfg}/get-bot-configuration-status", FetchTimeoutMs).ConfigureAwait(false);
            }
            if (!ok || string.IsNullOrWhiteSpace(body)) return s;

            try
            {
                var map = JsonScrape.ObjectAsMap(body);
                if (map.Count == 0) return s;
                var connected = JsonScrape.Bool(body, "botOnline")
                              ?? JsonScrape.Bool(body, "isConnected")
                              ?? JsonScrape.Bool(body, "cloudConnection");
                s.IsConnected = connected ?? false;
                s.ScoreConnectId   = PickFirst(map, "scoreConnectId", "id");
                s.BotServerAddress = PickFirst(map, "botServerAddress", "botAddress", "botServer");
                s.LastErrorMessage = PickFirst(map, "lastErrorMessage", "lastError", "errorMessage");
                var lastConn = PickFirst(map, "lastConnectedAt", "lastConnected", "connectedAt");
                if (DateTime.TryParse(lastConn,
                        System.Globalization.CultureInfo.InvariantCulture,
                        System.Globalization.DateTimeStyles.AssumeUniversal,
                        out var dt))
                {
                    s.LastConnectedAt = dt.ToLocalTime();
                }
            }
            catch { }
            return s;
        }

        // ---------- Serial ports ----------

        public Task<List<ScoreConnectSerialPortInfo>> GetAvailablePortsAsync()
        {
            // v0.6.1: ScoreConnect III does not expose a get-available-ports
            // endpoint (verified against swagger.json — the path is absent).
            // Enumerate COM ports from the OS instead via System.IO.Ports.
            // This is more reliable anyway — the OS always knows what serial
            // ports exist, even when ScoreConnect doesn't.
            var rows = new List<ScoreConnectSerialPortInfo>();
            try
            {
                foreach (var name in System.IO.Ports.SerialPort.GetPortNames())
                {
                    if (string.IsNullOrWhiteSpace(name)) continue;
                    rows.Add(new ScoreConnectSerialPortInfo { Name = name });
                }
            }
            catch { /* on a locked-down box this can throw — swallow. */ }
            return Task.FromResult(rows);
        }

        // Legacy HTTP-based port enumeration — kept dormant in case a future
        // ScoreConnect III build adds the endpoint and we want to prefer the
        // service-side view (which knows which port is currently in use).
        private async Task<List<ScoreConnectSerialPortInfo>> GetAvailablePortsViaHttpAsync()
        {
            var rows = new List<ScoreConnectSerialPortInfo>();
            var (ok, body, _) = await TryGetAsync(
                $"{V1Cfg}/get-available-ports", FetchTimeoutMs).ConfigureAwait(false);
            if (!ok || string.IsNullOrWhiteSpace(body)) return rows;

            // Two shapes seen at runtime in the wild:
            //   1) ["COM3","COM4"]                          (bare string array)
            //   2) [{ "name":"COM3", "isInUse":true, ... }] (object array)
            var trimmed = (body ?? "").TrimStart();
            if (trimmed.StartsWith("[") && trimmed.IndexOf('{') < 0)
            {
                // Bare string array — strip brackets, split on commas,
                // unescape quotes.
                var inner = trimmed.Trim('[', ']', '\r', '\n', ' ');
                foreach (var p in inner.Split(','))
                {
                    var name = p.Trim().Trim('"');
                    if (string.IsNullOrWhiteSpace(name)) continue;
                    rows.Add(new ScoreConnectSerialPortInfo { Name = name });
                }
                return rows;
            }

            foreach (var row in JsonScrape.TopLevelArrayOfObjects(body))
            {
                var name = PickFirst(row, "name", "portName", "port", "id");
                if (string.IsNullOrWhiteSpace(name)) continue;
                var inUseStr = PickFirst(row, "isInUse", "inUse", "busy");
                bool inUse = inUseStr == "true" || inUseStr == "True";
                rows.Add(new ScoreConnectSerialPortInfo
                {
                    Name         = name,
                    IsInUse      = inUse,
                    OwningVendor = PickFirst(row, "owningVendor", "owner", "vendor"),
                });
            }
            return rows;
        }

        // ---------- Vendor / sport / configuration lists ----------

        public async Task<List<ScoreConnectVendorListItem>> GetVendorsAsync()
        {
            var rows = new List<ScoreConnectVendorListItem>();
            var (ok, body, _) = await TryGetAsync(
                $"{V1Cfg}/get-vendor-list", FetchTimeoutMs).ConfigureAwait(false);
            if (!ok || string.IsNullOrWhiteSpace(body)) return rows;
            foreach (var row in JsonScrape.TopLevelArrayOfObjects(body))
            {
                var item = new ScoreConnectVendorListItem
                {
                    Id   = PickFirst(row, "id", "vendorId"),
                    Name = PickFirst(row, "name", "vendorName"),
                };
                if (string.IsNullOrEmpty(item.Name)) item.Name = item.Id;
                if (!string.IsNullOrEmpty(item.Id)) rows.Add(item);
            }
            return rows;
        }

        public async Task<List<ScoreConnectVendorSportListItem>> GetVendorSportsAsync(string vendorId)
        {
            var rows = new List<ScoreConnectVendorSportListItem>();
            if (string.IsNullOrWhiteSpace(vendorId)) return rows;
            var (ok, body, _) = await TryGetAsync(
                $"{V1Cfg}/get-vendor-sports/{Uri.EscapeDataString(vendorId)}",
                FetchTimeoutMs).ConfigureAwait(false);
            if (!ok || string.IsNullOrWhiteSpace(body)) return rows;
            foreach (var row in JsonScrape.TopLevelArrayOfObjects(body))
            {
                var item = new ScoreConnectVendorSportListItem
                {
                    Id   = PickFirst(row, "id", "vendorSportId", "sportId"),
                    Name = PickFirst(row, "name", "sportName", "sport"),
                };
                if (string.IsNullOrEmpty(item.Name)) item.Name = item.Id;
                if (!string.IsNullOrEmpty(item.Id)) rows.Add(item);
            }
            return rows;
        }

        public async Task<List<ScoreConnectVendorConfigurationListItem>>
            GetVendorConfigurationsAsync(string vendorSportId)
        {
            var rows = new List<ScoreConnectVendorConfigurationListItem>();
            if (string.IsNullOrWhiteSpace(vendorSportId)) return rows;
            var (ok, body, _) = await TryGetAsync(
                $"{V1Cfg}/get-vendor-configurations/{Uri.EscapeDataString(vendorSportId)}",
                FetchTimeoutMs).ConfigureAwait(false);
            if (!ok || string.IsNullOrWhiteSpace(body)) return rows;
            foreach (var row in JsonScrape.TopLevelArrayOfObjects(body))
            {
                var item = new ScoreConnectVendorConfigurationListItem
                {
                    Id   = PickFirst(row, "id", "configurationId", "vendorConfigurationId"),
                    Name = PickFirst(row, "name", "configurationName", "description"),
                };
                if (string.IsNullOrEmpty(item.Name)) item.Name = item.Id;
                if (!string.IsNullOrEmpty(item.Id)) rows.Add(item);
            }
            return rows;
        }

        public async Task<List<ScoreConnectDeviceListItem>> GetDevicesAsync()
        {
            var rows = new List<ScoreConnectDeviceListItem>();
            var (ok, body, _) = await TryGetAsync(
                $"{V1Cfg}/get-devices-list", FetchTimeoutMs).ConfigureAwait(false);
            if (!ok || string.IsNullOrWhiteSpace(body)) return rows;
            foreach (var row in JsonScrape.TopLevelArrayOfObjects(body))
            {
                var item = new ScoreConnectDeviceListItem
                {
                    Id     = PickFirst(row, "id", "deviceId"),
                    Name   = PickFirst(row, "name", "deviceName"),
                    Vendor = PickFirst(row, "vendor", "vendorName"),
                    Sport  = PickFirst(row, "sport", "sportName"),
                };
                if (string.IsNullOrEmpty(item.Name)) item.Name = item.Id;
                if (!string.IsNullOrEmpty(item.Id)) rows.Add(item);
            }
            return rows;
        }

        // ---------- Firmware update info ----------

        public Task<string> GetAvailableFirmwareUpdateAsync()
        {
            // v0.6.2: swagger.json on the current ScoreConnect III has no
            // firmware-update endpoint at all (verified — the path is
            // absent). The /Other/CheckForFirmwareUpdates MVC route also
            // doesn't exist in the same version. Returning empty so we
            // stop polluting the rolling AppLogFile with 404s every
            // baseline. If a future build re-exposes the endpoint, wire
            // the call back here.
            return Task.FromResult("");
        }

        // ---------- Writes (Phase 3) ----------

        public Task<bool> SetVendorAsync(string vendorId)
        {
            // The V1 binary maps SetVendorConfigurationId onto a generic write
            // path — there's no dedicated "set vendor only" route in the
            // string dump. Best inferred mapping: POST the id as the body to
            // select-vendor-sport's parent. Fall back to a JSON object POST
            // against set-scoreconnect-configuration if the venue runs a
            // version that doesn't expose a vendor-only route.
            return PostAsync($"{V1Cfg}/select-vendor/{Uri.EscapeDataString(vendorId ?? "")}",
                             body: null);
        }

        public Task<bool> SetVendorSportAsync(string vendorSportId)
        {
            return PostAsync(
                $"{V1Cfg}/select-vendor-sport/{Uri.EscapeDataString(vendorSportId ?? "")}",
                body: null);
        }

        public Task<bool> SetVendorConfigurationAsync(string configId)
        {
            return PostAsync(
                $"{V1Cfg}/select-vendor-configuration/{Uri.EscapeDataString(configId ?? "")}",
                body: null);
        }

        public Task<bool> SetDecoderInfoAsync(string vendorSportId, string serialPort)
        {
            var json = JsonObject(
                ("vendorSportId", vendorSportId ?? ""),
                ("serialPort",    serialPort    ?? ""));
            return PostAsync($"{V1Cfg}/set-decoder-info", json);
        }

        public Task<bool> SetScoreConnectConfigurationAsync(
            string vendorId, string vendorSportId, string configurationId)
        {
            var json = JsonObject(
                ("vendorId",        vendorId        ?? ""),
                ("vendorSportId",   vendorSportId   ?? ""),
                ("configurationId", configurationId ?? ""));
            // v0.6.2: the documented route is /api/configuration/... (no v2).
            return PostAsync($"{V1Cfg}/set-scoreconnect-configuration", json);
        }

        // ---------- Internals: HTTP plumbing ----------

        // Async GET with a per-call timeout (HttpClient.Timeout is per-instance,
        // and we share one instance via DI). Returns (ok, body, errorString).
        //
        // v0.6.2: when a probe targets the documented prefix (api/configuration)
        // and gets a 404, transparently retry against the legacy
        // (api/v1/configuration) prefix. Older ScoreConnect III builds
        // registered both prefixes; the current one drops the v1 alias. This
        // keeps Pulse compatible with both without bloating every call site.
        private async Task<(bool ok, string body, string error)> TryGetAsync(
            string path, int timeoutMs)
        {
            var primary = await TryGetOneAsync(path, timeoutMs).ConfigureAwait(false);
            if (primary.ok) return primary;
            // 404 on the documented path -> try the legacy v1 prefix.
            if ((primary.error ?? "").StartsWith("HTTP 404") &&
                path.StartsWith(V1Cfg + "/", System.StringComparison.OrdinalIgnoreCase))
            {
                var legacyPath = LegacyV1Cfg + path.Substring(V1Cfg.Length);
                var legacy = await TryGetOneAsync(legacyPath, timeoutMs).ConfigureAwait(false);
                if (legacy.ok) return legacy;
            }
            return primary;
        }

        private async Task<(bool ok, string body, string error)> TryGetOneAsync(
            string path, int timeoutMs)
        {
            var url = JoinUrl(_baseUrl, path);
            using (var cts = new CancellationTokenSource(timeoutMs))
            {
                try
                {
                    using (var resp = await _http.GetAsync(url, cts.Token).ConfigureAwait(false))
                    {
                        var body = await resp.Content.ReadAsStringAsync().ConfigureAwait(false);
                        if (!resp.IsSuccessStatusCode)
                        {
                            AppLogFile.Instance.WriteLine("ScoreConnect", "Warn",
                                $"GET {path} -> {(int)resp.StatusCode}");
                            return (false, body, $"HTTP {(int)resp.StatusCode}");
                        }
                        return (true, body, "");
                    }
                }
                catch (OperationCanceledException)
                {
                    return (false, null, "Timeout");
                }
                catch (HttpRequestException ex)
                {
                    return (false, null, ex.Message);
                }
                catch (Exception ex)
                {
                    return (false, null, ex.Message);
                }
            }
        }

        private async Task<bool> PostAsync(string path, string body)
        {
            var url = JoinUrl(_baseUrl, path);
            using (var cts = new CancellationTokenSource(WriteTimeoutMs))
            {
                try
                {
                    HttpContent content = null;
                    if (body != null)
                    {
                        content = new StringContent(body, Encoding.UTF8, "application/json");
                    }
                    using (var req = new HttpRequestMessage(HttpMethod.Post, url) { Content = content })
                    using (var resp = await _http.SendAsync(req, cts.Token).ConfigureAwait(false))
                    {
                        var status = (int)resp.StatusCode;
                        var respBody = "";
                        try
                        {
                            respBody = await resp.Content.ReadAsStringAsync().ConfigureAwait(false);
                        }
                        catch { }
                        AppLogFile.Instance.WriteLine("ScoreConnect",
                            resp.IsSuccessStatusCode ? "Pass" : "Fail",
                            $"POST {path} -> {status} (body={Truncate(respBody, 200)})");
                        return resp.IsSuccessStatusCode;
                    }
                }
                catch (OperationCanceledException)
                {
                    AppLogFile.Instance.WriteLine("ScoreConnect", "Fail",
                        $"POST {path} timed out after {WriteTimeoutMs}ms");
                    return false;
                }
                catch (Exception ex)
                {
                    AppLogFile.Instance.WriteLine("ScoreConnect", "Fail",
                        $"POST {path} failed: {ex.Message}");
                    return false;
                }
            }
        }

        private static string JoinUrl(string baseUrl, string path)
        {
            if (string.IsNullOrEmpty(path)) return baseUrl;
            if (path.StartsWith("http", StringComparison.OrdinalIgnoreCase)) return path;
            return baseUrl + "/" + path.TrimStart('/');
        }

        private static string JsonObject(params (string key, string value)[] kv)
        {
            var sb = new StringBuilder("{");
            for (int i = 0; i < kv.Length; i++)
            {
                if (i > 0) sb.Append(',');
                sb.Append('"').Append(Escape(kv[i].key)).Append("\":\"");
                sb.Append(Escape(kv[i].value)).Append('"');
            }
            sb.Append('}');
            return sb.ToString();
        }

        private static string Escape(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s
                .Replace("\\", "\\\\")
                .Replace("\"", "\\\"")
                .Replace("\r", "\\r")
                .Replace("\n", "\\n");
        }

        private static string Truncate(string s, int max)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Length <= max ? s : s.Substring(0, max) + "...";
        }
    }
}
