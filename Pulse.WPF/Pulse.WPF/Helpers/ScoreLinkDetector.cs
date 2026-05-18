using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
using System.Text.RegularExpressions;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Detects whether a Sportzcast ScoreLink device is currently plugged into
    /// the VPU. The diagnostic surface that used to read "Available Serial
    /// Ports" was misleading — it showed every COM port Windows enumerated
    /// (including stale entries left over from previous Bluetooth/IR pairings
    /// and unrelated USB serial adapters). What support actually cares about
    /// is a one-bit answer: "is the ScoreLink box connected, and on which
    /// COM port?"
    ///
    /// Hardware identification (from field telemetry):
    ///   * ScoreLink 1 — USB-to-UART chip with PnP description
    ///     "MCP2221 USB-I2C/UART Combo"
    ///   * ScoreLink 2 — PnP description "ScoreLinkII"
    ///
    /// We enumerate Win32_PnPEntity (live USB device tree, no stale rows)
    /// and match on the Caption / Name / Description fields. The COM port
    /// is extracted from the device's Name string — Windows renders ports
    /// as e.g. "USB Serial Port (COM4)".
    /// </summary>
    public static class ScoreLinkDetector
    {
        /// <summary>
        /// Result of a single enumeration. PortName is the resolved COM
        /// port (e.g. "COM4"); empty when the device exists but no COM
        /// alias was found. Model is one of "ScoreLink", "ScoreLinkII",
        /// or "" when nothing was detected.
        /// </summary>
        public class ScoreLinkStatus
        {
            public bool   IsConnected      { get; set; }
            public string PortName         { get; set; } = "";
            public string Model            { get; set; } = "";   // "ScoreLink" | "ScoreLinkII"
            public string PnpDescription   { get; set; } = "";   // raw description for the live-log row
        }

        // Match the live Windows PnP description verbatim. Casing in the
        // wild varies; we lower-case both sides before comparison.
        private static readonly (string Needle, string Model)[] DeviceHints =
        {
            // Newer hardware first so the more-specific match wins if a tech
            // somehow has both attached.
            ("scorelinkii",                  "ScoreLinkII"),
            ("scorelink ii",                 "ScoreLinkII"),
            ("score link ii",                "ScoreLinkII"),
            ("mcp2221 usb-i2c/uart combo",   "ScoreLink"),
            ("mcp2221",                      "ScoreLink"),   // fallback for shorter caption variants
        };

        private static readonly Regex ComPortRx = new Regex(@"\bCOM(\d+)\b",
            RegexOptions.Compiled | RegexOptions.IgnoreCase);

        /// <summary>
        /// Scans Win32_PnPEntity for a currently-connected ScoreLink. Returns
        /// a result with IsConnected = false (and empty PortName/Model) when
        /// nothing matches. Never throws; WMI failures return the empty
        /// result. Sync — runs in ~50 ms on a healthy box.
        /// </summary>
        public static ScoreLinkStatus Detect()
        {
            var result = new ScoreLinkStatus();
            ManagementObjectSearcher searcher = null;
            try
            {
                // Limit columns to the three we need so WMI doesn't materialise
                // every device's metadata. Filtering on PNPClass / Service via
                // a WQL `WHERE` would also work but is fragile across Windows
                // editions; iterating all rows is fine for a one-shot lookup.
                searcher = new ManagementObjectSearcher(
                    "SELECT Caption, Name, Description, PNPDeviceID FROM Win32_PnPEntity");
                foreach (ManagementObject mo in searcher.Get())
                {
                    string caption     = (mo["Caption"]     as string) ?? "";
                    string name        = (mo["Name"]        as string) ?? "";
                    string description = (mo["Description"] as string) ?? "";
                    string combinedLower = $"{caption}|{name}|{description}".ToLowerInvariant();

                    string model = null;
                    foreach (var (needle, m) in DeviceHints)
                    {
                        if (combinedLower.Contains(needle)) { model = m; break; }
                    }
                    if (model == null) continue;

                    result.IsConnected    = true;
                    result.Model          = model;
                    result.PnpDescription = !string.IsNullOrWhiteSpace(description) ? description :
                                            !string.IsNullOrWhiteSpace(caption)     ? caption     :
                                                                                       name;

                    // The COM port number lives in the device's Name string,
                    // e.g. "USB Serial Port (COM4)". Caption sometimes carries
                    // it too on newer Windows builds.
                    var portMatch = ComPortRx.Match(name);
                    if (!portMatch.Success) portMatch = ComPortRx.Match(caption);
                    if (portMatch.Success) result.PortName = "COM" + portMatch.Groups[1].Value;

                    // Newest-match-wins — keep scanning so a ScoreLinkII
                    // attached alongside an older ScoreLink wins.
                    if (model == "ScoreLinkII") break;
                }
            }
            catch
            {
                // WMI unreadable (broken WMI service / Server Core image) —
                // return the empty result. The UI will render "Not detected"
                // and the tech can fall back to the launcher log.
            }
            finally
            {
                searcher?.Dispose();
            }
            return result;
        }
    }
}
