using System;
using System.Collections.Generic;
using Pulse.WPF.Services;

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
        /// <summary>
        /// Overload that consults a MAC-keyed role map in addition to the
        /// IP-keyed one. Added v0.5.0 so role attribution survives an IP
        /// being recycled by DHCP — the cfg has both fields, the resolver
        /// just hadn't been keying on MAC.
        /// </summary>
        public static RemoteDeviceInfo Resolve(
            string remoteMac,
            string remoteIp,
            Dictionary<string, string> cfgRolesByIp,
            Dictionary<string, string> cfgRolesByMac)
        {
            return ResolveCore(remoteMac, remoteIp, cfgRolesByIp, cfgRolesByMac);
        }

        public static RemoteDeviceInfo Resolve(
            string remoteMac,
            string remoteIp,
            Dictionary<string, string> cfgRolesByIp)
        {
            return ResolveCore(remoteMac, remoteIp, cfgRolesByIp, null);
        }

        private static RemoteDeviceInfo ResolveCore(
            string remoteMac,
            string remoteIp,
            Dictionary<string, string> cfgRolesByIp,
            Dictionary<string, string> cfgRolesByMac)
        {
            // ---- 4) No remote at all ----
            // Bug #2 / #3 guard: an empty, all-zero, broadcast, or multicast
            // MAC is *not* a real neighbour. Treat it identically to a missing
            // remote so the tile renders the empty-state copy ("Detecting
            // neighbour…" / "No cable") instead of e.g. "Main Camera 1" with
            // OUI 00-00-00.
            if (string.IsNullOrWhiteSpace(remoteMac) || NetworkAdapterService.IsInvalidMac(remoteMac))
            {
                return new RemoteDeviceInfo
                {
                    PrimaryLabel = "",
                    SecondaryLabel = "",
                    Source = DeviceIdentitySource.None,
                };
            }

            var oui = MacOuiTable.NormaliseOui(remoteMac) ?? "??-??-??";
            var vendor = MacOuiTable.LookupVendor(remoteMac);

            // ---- 1a) cameras.cfg role match (by MAC) ----
            // Preferred — survives DHCP recycling the IP. Same gate as the
            // IP-keyed match below.
            if (!NetworkAdapterService.IsInvalidMac(remoteMac)
                && cfgRolesByMac != null && cfgRolesByMac.Count > 0)
            {
                var canonMac = CanonicalMac(remoteMac);
                if (canonMac != null
                    && cfgRolesByMac.TryGetValue(canonMac, out var macRole))
                {
                    var sec = vendor != null ? $"{vendor} - OUI {oui}" : $"OUI {oui}";
                    return new RemoteDeviceInfo
                    {
                        PrimaryLabel = macRole,
                        SecondaryLabel = sec,
                        Source = DeviceIdentitySource.PixellotConfig,
                        IsOcr = macRole.IndexOf("OCR", StringComparison.OrdinalIgnoreCase) >= 0
                             || macRole.IndexOf("Scoreboard", StringComparison.OrdinalIgnoreCase) >= 0,
                    };
                }
            }

            // ---- 1b) cameras.cfg role match (by IP) ----
            //
            // Bug #3: the cfg lookup is *gated* behind a real-MAC + non-empty-IP
            // check. Without this gate, a port whose ARP table only contained
            // the local self-IP (now filtered out at the service layer) was
            // being stamped with the configured camera role.
            if (!string.IsNullOrEmpty(remoteIp)
                && !NetworkAdapterService.IsInvalidMac(remoteMac)
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

        // Normalise a remote MAC into the same canonical
        // "XX-XX-XX-XX-XX-XX" upper-case form PixellotConfigService.GetRolesByMac
        // uses for its keys. Returns null when the input isn't parseable.
        private static string CanonicalMac(string mac)
        {
            if (string.IsNullOrEmpty(mac)) return null;
            var hex = new System.Text.StringBuilder(12);
            foreach (var c in mac)
            {
                if (c == ':' || c == '-' || c == '.' || c == ' ') continue;
                if (!System.Uri.IsHexDigit(c)) return null;
                hex.Append(System.Char.ToUpperInvariant(c));
            }
            if (hex.Length != 12) return null;
            return $"{hex[0]}{hex[1]}-{hex[2]}{hex[3]}-{hex[4]}{hex[5]}-{hex[6]}{hex[7]}-{hex[8]}{hex[9]}-{hex[10]}{hex[11]}";
        }
    }
}
