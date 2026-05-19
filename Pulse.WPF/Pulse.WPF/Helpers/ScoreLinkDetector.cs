using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
using System.Text.RegularExpressions;
using Microsoft.Win32;

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
    /// Hardware identification (per field spec):
    ///   * ScoreLink 1 — bus-reported device description "MCP2221 USB-I2C/UART Combo"
    ///   * ScoreLink 2 — bus-reported device description "ScoreLinkII"
    ///
    /// The **bus-reported** description is set by the USB device itself
    /// (via the USB string descriptor block) and is distinct from the
    /// driver-side `Caption` / `Name` / `Description` exposed by
    /// `Win32_PnPEntity` — those come from the INF and vary by driver
    /// version. The bus-reported value is stable across driver versions
    /// because the device controls it.
    ///
    /// v0.6.22 fix: read the bus-reported description via the registry
    /// (`HKLM\SYSTEM\CurrentControlSet\Enum\<PnpDeviceId>\Properties\
    /// {a45c254e-df1c-4efd-8020-67d146a850e0}\0004` — the
    /// `DEVPKEY_Device_BusReportedDeviceDesc` property). Caption / Name /
    /// Description are kept as a secondary fallback for completeness and
    /// for the diagnostic dump below.
    ///
    /// When no match fires, the detector also publishes a list of every
    /// USB-class PnP device that has a COM port assigned. The UI logs
    /// those to the Live Log so a tech can see what's actually
    /// enumerated and report back if the bus-reported description on
    /// their box uses different wording.
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
            public string MatchedDescription { get; set; } = ""; // the actual string we matched on

            /// <summary>
            /// Every USB-class PnP device with a COM port assignment that
            /// the scan saw. Populated regardless of match outcome so a
            /// caller can dump it to the live log on a miss. Ordered
            /// alphabetically by PortName.
            /// </summary>
            public List<UsbSerialCandidate> AllUsbSerialCandidates { get; } = new List<UsbSerialCandidate>();
        }

        public class UsbSerialCandidate
        {
            public string PortName              { get; set; } = ""; // "COM4"
            public string Caption               { get; set; } = "";
            public string DriverDescription     { get; set; } = ""; // Win32_PnPEntity.Description
            public string BusReportedDescription{ get; set; } = ""; // registry-sourced
            public string PnpDeviceId           { get; set; } = "";
        }

        // Match the bus-reported description verbatim (case-insensitive).
        // Casing in the wild varies; we lower-case both sides before
        // comparison. Newer hardware first so a more-specific match wins
        // if a tech somehow has both attached.
        private static readonly (string Needle, string Model)[] BusDescNeedles =
        {
            ("scorelinkii",                  "ScoreLinkII"),
            ("scorelink ii",                 "ScoreLinkII"),
            ("score link ii",                "ScoreLinkII"),
            ("mcp2221 usb-i2c/uart combo",   "ScoreLink"),
            ("mcp2221",                      "ScoreLink"),
        };

        private static readonly Regex ComPortRx = new Regex(@"\bCOM(\d+)\b",
            RegexOptions.Compiled | RegexOptions.IgnoreCase);

        /// <summary>
        /// Scans Win32_PnPEntity for a currently-connected ScoreLink. Returns
        /// a result with IsConnected = false when nothing matches, but with
        /// AllUsbSerialCandidates populated so the caller can log the visible
        /// pool of USB-serial devices. Never throws.
        /// </summary>
        public static ScoreLinkStatus Detect()
        {
            var result = new ScoreLinkStatus();
            ManagementObjectSearcher searcher = null;
            try
            {
                searcher = new ManagementObjectSearcher(
                    "SELECT Caption, Name, Description, PNPDeviceID FROM Win32_PnPEntity");
                foreach (ManagementObject mo in searcher.Get())
                {
                    string caption     = (mo["Caption"]     as string) ?? "";
                    string name        = (mo["Name"]        as string) ?? "";
                    string description = (mo["Description"] as string) ?? "";
                    string pnpId       = (mo["PNPDeviceID"] as string) ?? "";

                    // A device is a USB-serial candidate when (a) its PnP path
                    // is rooted at USB\ and (b) some text field exposes a COM
                    // port number. We collect every candidate up front so the
                    // miss-path can log them; matching against the bus
                    // description happens in the second loop below.
                    if (!pnpId.StartsWith("USB\\", StringComparison.OrdinalIgnoreCase))
                        continue;

                    var portMatch = ComPortRx.Match(name);
                    if (!portMatch.Success) portMatch = ComPortRx.Match(caption);
                    if (!portMatch.Success) continue;   // not a serial device

                    var candidate = new UsbSerialCandidate
                    {
                        PortName              = "COM" + portMatch.Groups[1].Value,
                        Caption               = caption,
                        DriverDescription     = description,
                        BusReportedDescription = ReadBusReportedDescription(pnpId),
                        PnpDeviceId           = pnpId,
                    };
                    result.AllUsbSerialCandidates.Add(candidate);
                }
            }
            catch
            {
                // WMI unreadable (broken WMI service / Server Core image) —
                // fall through with an empty candidate list.
            }
            finally
            {
                searcher?.Dispose();
            }

            // Sort by port number so the log lines have a stable order.
            result.AllUsbSerialCandidates.Sort((a, b) =>
                string.Compare(a.PortName, b.PortName, StringComparison.OrdinalIgnoreCase));

            // Walk the candidates and pick the best match. Newest model
            // wins on ties.
            foreach (var c in result.AllUsbSerialCandidates)
            {
                var busLower = (c.BusReportedDescription ?? "").ToLowerInvariant();
                var capLower = (c.Caption ?? "").ToLowerInvariant();
                var drvLower = (c.DriverDescription ?? "").ToLowerInvariant();
                string matchedModel = null;
                string matchedText  = "";

                foreach (var (needle, model) in BusDescNeedles)
                {
                    if (busLower.Contains(needle)) { matchedModel = model; matchedText = c.BusReportedDescription; break; }
                    if (capLower.Contains(needle)) { matchedModel = model; matchedText = c.Caption;                 break; }
                    if (drvLower.Contains(needle)) { matchedModel = model; matchedText = c.DriverDescription;       break; }
                }
                if (matchedModel == null) continue;

                // Prefer ScoreLinkII over ScoreLink when both are present.
                if (matchedModel == "ScoreLinkII" || !result.IsConnected)
                {
                    result.IsConnected         = true;
                    result.Model               = matchedModel;
                    result.PortName            = c.PortName;
                    result.MatchedDescription  = matchedText;
                    if (matchedModel == "ScoreLinkII") break;
                }
            }
            return result;
        }

        // DEVPKEY_Device_BusReportedDeviceDesc (the property visible on
        // Device Manager → Details → "Bus reported device description").
        // The PnP property store backs it at the registry path:
        //   HKLM\SYSTEM\CurrentControlSet\Enum\<PNPDeviceID>\Properties\
        //     {a45c254e-df1c-4efd-8020-67d146a850e0}\0004
        // The value type is REG_SZ; the value name is unset (default).
        private const string BusReportedDescGuid = "{a45c254e-df1c-4efd-8020-67d146a850e0}";
        private const string BusReportedDescPid  = "0004";

        private static string ReadBusReportedDescription(string pnpDeviceId)
        {
            if (string.IsNullOrEmpty(pnpDeviceId)) return "";
            try
            {
                var subPath = $@"SYSTEM\CurrentControlSet\Enum\{pnpDeviceId}\Properties\{BusReportedDescGuid}\{BusReportedDescPid}";
                using (var key = Registry.LocalMachine.OpenSubKey(subPath))
                {
                    if (key == null) return "";
                    // The Windows PnP property store writes the value with
                    // the empty-string name (REG_SZ default value); the
                    // older convention used "(Data)". Try both.
                    var v = key.GetValue("") as string;
                    if (string.IsNullOrEmpty(v)) v = key.GetValue("Data") as string;
                    return v ?? "";
                }
            }
            catch { return ""; }
        }
    }
}
