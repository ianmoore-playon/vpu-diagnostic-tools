using System;
using System.Collections.Generic;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Source of the device-identity label rendered on a port tile.
    /// </summary>
    public enum DeviceIdentitySource
    {
        None = 0,            // Port has no remote MAC at all (no cable / no link)
        PixellotConfig = 1,  // Resolved via cameras.cfg / pip.cfg role map
        OuiVendor = 2,       // Resolved via the bundled MacOuiTable
        OuiHexOnly = 3,      // OUI string only — vendor unknown
    }

    /// <summary>
    /// Result of resolving a remote device on a port: a primary line + a
    /// muted secondary line for the tile, plus the source so the VM can
    /// pick a colour.
    /// </summary>
    public class RemoteDeviceInfo
    {
        public string PrimaryLabel { get; set; } = "";
        public string SecondaryLabel { get; set; } = "";
        public DeviceIdentitySource Source { get; set; } = DeviceIdentitySource.None;

        /// <summary>True when the role came from cameras.cfg.</summary>
        public bool IsConfigured => Source == DeviceIdentitySource.PixellotConfig;

        /// <summary>True when the cameras.cfg role contains "OCR" or "Scoreboard".</summary>
        public bool IsOcr { get; set; }
    }

    /// <summary>
    /// Resolves the human-readable identity of a port's remote endpoint by
    /// walking the locked fallback ladder:
    ///
    ///   1. cameras.cfg role match (IP or MAC) -> "Main Camera 1" / "OCR /
    ///      Scoreboard" + "Pixellot - OUI 00-30-6C" secondary.
    ///   2. Bundled MAC OUI vendor table       -> "Axis Communications" +
    ///      "Unknown role - OUI AC-CC-8E" secondary.
    ///   3. OUI hex only                       -> "Unknown device" +
    ///      "OUI XX-XX-XX" secondary.
    ///   4. No remote at all                   -> "No cable" + "" secondary.
    ///
    /// Pure helper: no side effects, no I/O. Caller passes the cameras.cfg
    /// snapshot in, so this can be called every poll tick cheaply.
    /// </summary>
    public static class RemoteDeviceResolver
    {
        public static RemoteDeviceInfo Resolve(
            string remoteMac,
            string remoteIp,
            Dictionary<string, string> cfgRolesByIp)
        {
            // ---- 4) No remote at all ----
            if (string.IsNullOrWhiteSpace(remoteMac))
            {
                return new RemoteDeviceInfo
                {
                    PrimaryLabel = "No cable",
                    SecondaryLabel = "",
                    Source = DeviceIdentitySource.None,
                };
            }

            var oui = MacOuiTable.NormaliseOui(remoteMac) ?? "??-??-??";
            var vendor = MacOuiTable.LookupVendor(remoteMac);

            // ---- 1) cameras.cfg role match (by IP) ----
            // The cfg map is keyed by IP today; if a future cfg parser starts
            // recording MACs we can extend the lookup here without touching
            // the rest of the chain.
            if (!string.IsNullOrEmpty(remoteIp)
                && cfgRolesByIp != null
                && cfgRolesByIp.TryGetValue(remoteIp, out var role))
            {
                var sec = vendor != null
                    ? $"{vendor} - OUI {oui}"
                    : $"OUI {oui}";
                return new RemoteDeviceInfo
                {
                    PrimaryLabel = role,
                    SecondaryLabel = sec,
                    Source = DeviceIdentitySource.PixellotConfig,
                    IsOcr = role.IndexOf("OCR", StringComparison.OrdinalIgnoreCase) >= 0
                         || role.IndexOf("Scoreboard", StringComparison.OrdinalIgnoreCase) >= 0,
                };
            }

            // ---- 2) Bundled OUI vendor table ----
            if (vendor != null)
            {
                return new RemoteDeviceInfo
                {
                    PrimaryLabel = vendor,
                    SecondaryLabel = $"Unknown role - OUI {oui}",
                    Source = DeviceIdentitySource.OuiVendor,
                };
            }

            // ---- 3) OUI hex only ----
            return new RemoteDeviceInfo
            {
                PrimaryLabel = "Unknown device",
                SecondaryLabel = $"OUI {oui}",
                Source = DeviceIdentitySource.OuiHexOnly,
            };
        }
    }
}
