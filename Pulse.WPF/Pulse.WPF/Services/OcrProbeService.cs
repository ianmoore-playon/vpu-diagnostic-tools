using System;
using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// HTTP CGI implementation of <see cref="IOcrProbeService"/>. One shared
    /// HttpClient for the lifetime of the service (recommended pattern -
    /// new-per-call exhausts loopback sockets under repeated probes).
    /// Auth credentials are baked in via <see cref="HttpClientHandler"/>;
    /// every request sends Basic auth pre-emptively (PreAuthenticate=true)
    /// so we don't waste a round-trip on the 401 challenge.
    /// </summary>
    public class OcrProbeService : IOcrProbeService, IDisposable
    {
        // Same path / auth as ocr-tester's camera.py get_mac_address. The
        // CGI returns a body of the shape:
        //   root.Network.eth0.MACAddress=00:D0:89:1B:02:DF
        // - one line per requested param. We only ask for one so we expect
        // exactly that single line back.
        private const string CgiPath =
            "/cgi-bin/admin/param.cgi?action=list&group=Network.eth0.MACAddress";

        private const string CgiUser = "Admin";
        private const string CgiPass = "1234";

        private readonly HttpClient _http;

        public OcrProbeService()
        {
            var handler = new HttpClientHandler
            {
                // PreAuthenticate skips the 401 round-trip - we know the
                // CGI always wants Basic auth so just send it on the first
                // request. The Credentials property triggers the standard
                // managed Basic-auth flow.
                Credentials = new NetworkCredential(CgiUser, CgiPass),
                PreAuthenticate = true,
                // The cameras almost certainly speak HTTP/1.1, but be
                // explicit so HttpClient doesn't try HTTP/2 negotiation on
                // a device that doesn't support it.
                AutomaticDecompression = System.Net.DecompressionMethods.None,
            };
            _http = new HttpClient(handler)
            {
                // Per-probe timeout is applied via the per-call CTS below;
                // this just caps any pathological case where the CTS fails
                // to fire (it shouldn't, but defensive).
                Timeout = TimeSpan.FromSeconds(5),
            };
            // Some devices reject requests without an explicit Accept; be
            // generous so we don't fail on a picky CGI.
            _http.DefaultRequestHeaders.Accept.Add(
                new MediaTypeWithQualityHeaderValue("*/*"));
        }

        public async Task<OcrProbeResult> ProbeAsync(string ip, TimeSpan timeout)
        {
            var result = new OcrProbeResult { Ip = ip };
            if (string.IsNullOrWhiteSpace(ip))
            {
                result.Error = "empty IP";
                return result;
            }

            var sw = Stopwatch.StartNew();
            try
            {
                var url = $"http://{ip}{CgiPath}";
                using (var cts = new CancellationTokenSource(timeout))
                using (var resp = await _http.GetAsync(url, cts.Token).ConfigureAwait(false))
                {
                    if (!resp.IsSuccessStatusCode)
                    {
                        result.Error = $"HTTP {(int)resp.StatusCode}";
                        return result;
                    }
                    var bodyBytes = await resp.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
                    var body = Encoding.UTF8.GetString(bodyBytes);
                    // Expected body line:
                    //   root.Network.eth0.MACAddress=00:D0:89:1B:02:DF
                    // Tolerate stray whitespace / blank lines / other
                    // params in case the CGI ever returns extras.
                    foreach (var raw in body.Split('\n'))
                    {
                        var line = raw.Trim();
                        var idx = line.IndexOf("MACAddress=", StringComparison.OrdinalIgnoreCase);
                        if (idx < 0) continue;
                        var rawMac = line.Substring(idx + "MACAddress=".Length).Trim();
                        if (string.IsNullOrEmpty(rawMac)) continue;
                        result.Mac   = NormaliseMac(rawMac);
                        result.IsOcr = true;
                        return result;
                    }
                    result.Error = "MACAddress not in response body";
                }
            }
            catch (TaskCanceledException)
            {
                result.Error = "timeout";
            }
            catch (HttpRequestException ex)
            {
                // Inner exceptions are usually socket-level: connection
                // refused, no route to host, etc. The message is short
                // enough to be useful in the Live Log without dumping a
                // stack trace.
                result.Error = ex.InnerException?.Message ?? ex.Message ?? "connection failed";
            }
            catch (Exception ex)
            {
                result.Error = ex.GetType().Name;
            }
            finally
            {
                sw.Stop();
                result.Elapsed = sw.Elapsed;
            }
            return result;
        }

        /// <summary>
        /// Normalise a MAC string to Pulse's canonical format: uppercase
        /// hex with dash separators (e.g. "00-D0-89-1B-02-DF"). Accepts
        /// the colon-separated form the CGI returns. Pulse's RemoteDevice-
        /// Resolver compares MACs case-insensitively so this is for
        /// display consistency more than correctness.
        /// </summary>
        private static string NormaliseMac(string raw)
        {
            if (string.IsNullOrEmpty(raw)) return raw;
            return raw.Replace(":", "-").ToUpperInvariant().Trim();
        }

        public void Dispose()
        {
            try { _http?.Dispose(); } catch { /* never throw on dispose */ }
        }
    }
}
