using System;
using System.Threading.Tasks;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// v0.8.19-beta: positive OCR identification via Dynacolor CGI.
    ///
    /// Pixellot OCR / scoreboard cameras (Dynacolor internally) expose an
    /// HTTP admin interface at port 80 with HTTP Basic auth Admin:1234.
    /// A single GET to /cgi-bin/admin/param.cgi?action=list&amp;group=
    /// Network.eth0.MACAddress returns a body containing the camera's MAC
    /// address. The act of probing also forces Windows' ARP table to
    /// populate for the destination IP, which the existing
    /// CameraNicMonitor + RemoteDeviceResolver pipeline picks up on the
    /// next tick.
    ///
    /// Authoritative replacement for the OCR-from-speed inference at
    /// Layer 2 / Layer 3 (see <see cref="ViewModels.CameraConnectivityViewModel.IsLikelyOcr"/>).
    /// Whereas the inference is a probability bet ("100 Mbps + no ARP ≈
    /// OCR"), this is a positive answer from the camera itself.
    ///
    /// Pattern borrowed from Logan Teffertiller's <c>ocr-tester</c> tool
    /// (Python FastAPI bench-test app) — same URL, same auth, same parse.
    /// </summary>
    public interface IOcrProbeService
    {
        /// <summary>
        /// Issue a single HTTP CGI probe to the given IP and return the
        /// camera's identification on success. Returns a result with
        /// <see cref="OcrProbeResult.IsOcr"/> = false on any failure
        /// (timeout, refused, non-OCR device responding on port 80, etc).
        /// </summary>
        /// <param name="ip">Target IP — usually link-local 169.254.x.x.</param>
        /// <param name="timeout">Hard timeout. Default 2 s is enough on
        /// a healthy LAN; tighter so the live-monitor tick isn't blocked
        /// for long.</param>
        Task<OcrProbeResult> ProbeAsync(string ip, TimeSpan timeout);
    }

    /// <summary>One probe outcome — never throws, never null.</summary>
    public class OcrProbeResult
    {
        /// <summary>True only when the CGI returned a parseable MAC.</summary>
        public bool IsOcr { get; set; }

        /// <summary>Camera MAC from the CGI response, normalised to
        /// uppercase with dash separators (matches the format Pulse uses
        /// elsewhere). Null on failure.</summary>
        public string Mac { get; set; }

        /// <summary>The IP we probed; copied through for caller bookkeeping.</summary>
        public string Ip { get; set; }

        /// <summary>How long the probe took. Used by callers for rate-
        /// limit accounting + Live Log telemetry.</summary>
        public TimeSpan Elapsed { get; set; }

        /// <summary>Short error string when IsOcr is false. Helpful for
        /// the Live Log when triaging "why didn't this resolve". Empty
        /// when IsOcr is true.</summary>
        public string Error { get; set; } = "";
    }
}
