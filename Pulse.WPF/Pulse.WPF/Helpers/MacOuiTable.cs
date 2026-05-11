using System;
using System.Collections.Generic;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Bundled MAC OUI -> vendor table. Keyed by uppercased "XX-XX-XX".
    ///
    /// TODO: This table is intentionally small and pragmatic — the goal is to
    /// label the gear we routinely see on a Pixellot VPU rig (Pixellot CHU
    /// cameras, common IP-camera vendors, common NIC chipsets). It is expected
    /// to grow over time as field techs surface unknown OUIs in the
    /// "Unknown device" tile state. Add new entries here rather than special-
    /// casing them in the resolver.
    ///
    /// Source rule of thumb: only commit OUIs we are confident about. When in
    /// doubt leave the device as "Unknown" so the OUI hex is shown to the tech
    /// and they can look it up in the IEEE registry.
    /// </summary>
    public static class MacOuiTable
    {
        /// <summary>
        /// Reject MACs that should never be rendered as a real remote:
        ///   • null / empty
        ///   • all-zero (INCOMPLETE neighbour row from Win32 GetIpNetTable)
        ///   • all-FF (broadcast)
        ///   • multicast bit set on the first octet (group address)
        /// Centralised so the ARP loader and the resolver stay in sync.
        /// Lifted from NetworkAdapterService in v0.5.0 to live alongside the
        /// other MAC-handling helpers.
        /// </summary>
        public static bool IsInvalidMac(string mac)
        {
            if (string.IsNullOrEmpty(mac)) return true;

            // Strip separators ("-", ":", whitespace) so the same string
            // covers both "00-00-00-00-00-00" and "000000000000".
            string hex;
            try
            {
                var sb = new System.Text.StringBuilder(mac.Length);
                foreach (var c in mac)
                {
                    if (c == '-' || c == ':' || c == ' ') continue;
                    sb.Append(c);
                }
                hex = sb.ToString();
            }
            catch { return true; }

            if (hex.Length < 12) return true;

            // All-zero MAC — Win32 GetIpNetTable returns this for INCOMPLETE
            // neighbour entries (the OS has an IP from a probe but never got
            // an ARP reply).
            bool allZero = true, allFf = true;
            for (int i = 0; i < 12; i++)
            {
                char c = char.ToUpperInvariant(hex[i]);
                if (c != '0') allZero = false;
                if (c != 'F') allFf = false;
                if (!allZero && !allFf) break;
            }
            if (allZero || allFf) return true;

            // Multicast bit on first octet — group address, never a real host.
            try
            {
                var firstOctet = Convert.ToInt32(hex.Substring(0, 2), 16);
                if ((firstOctet & 1) != 0) return true;
            }
            catch { return true; }

            return false;
        }

        // ---------------------------------------------------------------------
        // OUI string normaliser. Accepts "00306C4B12AB", "00:30:6C:4B:12:AB",
        // "00-30-6C-4B-12-AB". Returns "00-30-6C" (uppercased, dash-separated).
        // Returns null when the input is not parseable as a MAC.
        // ---------------------------------------------------------------------
        public static string NormaliseOui(string mac)
        {
            if (string.IsNullOrWhiteSpace(mac)) return null;
            var hex = new System.Text.StringBuilder(12);
            foreach (var c in mac)
            {
                if (c == '-' || c == ':' || c == ' ') continue;
                hex.Append(char.ToUpperInvariant(c));
                if (hex.Length >= 6) break;
            }
            if (hex.Length < 6) return null;
            return $"{hex[0]}{hex[1]}-{hex[2]}{hex[3]}-{hex[4]}{hex[5]}";
        }

        /// <summary>
        /// Look up the vendor for a given MAC. Returns null if the OUI is not
        /// in the bundled table.
        /// </summary>
        public static string LookupVendor(string mac)
        {
            var oui = NormaliseOui(mac);
            if (oui == null) return null;
            return Table.TryGetValue(oui, out var v) ? v : null;
        }

        /// <summary>
        /// Returns true if the MAC's OUI is in our table for the given vendor
        /// (case-insensitive substring match). Convenience for "is this a
        /// Pixellot camera?" checks.
        /// </summary>
        public static bool IsVendor(string mac, string vendorContains)
        {
            var v = LookupVendor(mac);
            if (v == null) return false;
            return v.IndexOf(vendorContains, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        // ---------------------------------------------------------------------
        // The bundled table. Entries are commented in groups so adding new ones
        // stays easy. All OUI keys MUST be uppercased and dash-separated.
        // ---------------------------------------------------------------------
        private static readonly Dictionary<string, string> Table = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            // ---- Pixellot ----
            // 00-30-6C is the OUI most commonly observed on Pixellot CHU /
            // OCR cameras in our field captures. Add more here as we learn them.
            { "00-30-6C", "Pixellot" },
            { "00-D0-89", "Pixellot" }, // legacy CHU OUI seen on some older units

            // ---- AXIS Communications (PTZ + IP cameras) ----
            { "00-40-8C", "Axis Communications" },
            { "AC-CC-8E", "Axis Communications" },
            { "B8-A4-4F", "Axis Communications" },

            // ---- Hikvision ----
            { "00-0C-43", "Hikvision" },
            { "28-57-BE", "Hikvision" },
            { "44-19-B6", "Hikvision" },
            { "BC-AD-28", "Hikvision" },
            { "C0-51-7E", "Hikvision" },

            // ---- Dahua ----
            { "4C-11-BF", "Dahua" },
            { "90-02-A9", "Dahua" },
            { "BC-32-5F", "Dahua" },

            // ---- Sony ----
            { "00-13-A9", "Sony" },
            { "54-42-49", "Sony" },

            // ---- Bosch ----
            { "00-1C-44", "Bosch" },
            { "00-04-63", "Bosch" },

            // ---- Panasonic ----
            { "00-80-F0", "Panasonic" },

            // ---- Avigilon ----
            { "00-18-85", "Avigilon" },

            // ---- Intel (NIC chipsets we sometimes see on the camera side
            //      of a test rig — e.g. another VPU plugged in) ----
            { "00-15-17", "Intel" },
            { "00-1B-21", "Intel" },
            { "90-E2-BA", "Intel" },

            // ---- Common consumer NIC manufacturers — so a tech testing the
            //      port with a laptop or a Cisco switch sees something better
            //      than "Unknown device". ----
            { "00-1C-B3", "Apple" },
            { "00-1B-D4", "Cisco" },
            { "00-1C-58", "Cisco" },
            { "00-23-AC", "Cisco" },
            { "00-D0-2B", "VMware" },
            { "00-50-56", "VMware" },
            { "B8-27-EB", "Raspberry Pi Foundation" },
            { "DC-A6-32", "Raspberry Pi Foundation" },
        };
    }
}
