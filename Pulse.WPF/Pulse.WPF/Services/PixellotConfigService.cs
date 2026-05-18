using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// C# port of the Read-PixellotCfg / Get-PixellotCameraRoles helpers
    /// from Pulse.ps1 (v1.0.51 / v1.0.52). Same .cfg format:
    ///     [SECTION]
    ///     KEY, type, value      // optional inline comment
    /// Same files: cameras.cfg holds [CAMERA_N] / [ADDITIONAL_ANGLE_N];
    /// pip.cfg holds [PIP] CAMERA_URL.
    /// </summary>
    public class PixellotConfigService : IPixellotConfigService
    {
        // The agent log line "working directory: <Pixellot>\Data\configuration"
        // is the canonical location. R13 fix: resolve the Pixellot install
        // root at runtime instead of hardcoding C:\ — VPUs with Pixellot on
        // D:\ used to silently get a missing config directory and the Camera
        // panel would render every port as "Unknown device" with no signal
        // that the cfg path was wrong.
        private static string ConfigDir =>
            Pulse.WPF.Helpers.PixellotInstallPath.Combine("Data", "configuration");

        /// <inheritdoc />
        public string CamerasCfgPath => Path.Combine(ConfigDir, "cameras.cfg");

        /// <inheritdoc />
        public bool CamerasCfgExists
        {
            get
            {
                try { return File.Exists(CamerasCfgPath); }
                catch { return false; }
            }
        }

        private static readonly Regex SectionRx = new Regex(@"^\[(.+)\]$", RegexOptions.Compiled);
        private static readonly Regex CommentRx = new Regex(@"\s+//", RegexOptions.Compiled);
        private static readonly Regex CameraSection         = new Regex(@"^CAMERA_(\d+)$",          RegexOptions.Compiled);
        private static readonly Regex AdditionalAngleSection = new Regex(@"^ADDITIONAL_ANGLE_(\d+)$", RegexOptions.Compiled);
        private static readonly Regex RtspIpRx              = new Regex(@"rtsp:/+(\d+\.\d+\.\d+\.\d+)", RegexOptions.Compiled);
        // Match a 12-hex-digit MAC with optional colon / dash separators —
        // covers the three formats cameras.cfg has shipped over the years.
        private static readonly Regex MacRx                  = new Regex(@"\b([0-9A-Fa-f]{2}[:\-]?){5}[0-9A-Fa-f]{2}\b", RegexOptions.Compiled);

        // Field names a cfg section might use to record the camera's MAC.
        // Order matters — first match wins.
        private static readonly string[] MacFieldKeys = { "MAC", "MAC_ADDRESS", "MACADDR", "HW_ADDR" };

        public Dictionary<string, string> GetRoles()
        {
            var roles = new Dictionary<string, string>();
            if (!Directory.Exists(ConfigDir)) return roles;

            // cameras.cfg → main cameras + additional angles
            var camsCfg = ReadCfg(Path.Combine(ConfigDir, "cameras.cfg"));
            foreach (var section in camsCfg.Keys)
            {
                var camMatch = CameraSection.Match(section);
                if (camMatch.Success)
                {
                    var idx = int.Parse(camMatch.Groups[1].Value);
                    var ip  = ExtractIp(GetValue(camsCfg[section], "UID"));
                    if (ip != null) roles[ip] = $"Main Camera {idx + 1}";
                    continue;
                }

                var angleMatch = AdditionalAngleSection.Match(section);
                if (angleMatch.Success)
                {
                    var idx = int.Parse(angleMatch.Groups[1].Value);
                    var ip  = ExtractIp(GetValue(camsCfg[section], "UID"));
                    if (ip != null) roles[ip] = $"Additional Angle {idx + 1}";
                    continue;
                }

                // Some Pixellot installs put the PIP section in cameras.cfg
                if (section == "PIP")
                {
                    var ip = ExtractIp(GetValue(camsCfg[section], "CAMERA_URL"));
                    if (ip != null) roles[ip] = "OCR / Scoreboard";
                }
            }

            // Standard PIP location
            var pipCfg = ReadCfg(Path.Combine(ConfigDir, "pip.cfg"));
            if (pipCfg.TryGetValue("PIP", out var pip))
            {
                var ip = ExtractIp(GetValue(pip, "CAMERA_URL"));
                if (ip != null) roles[ip] = "OCR / Scoreboard";
            }

            return roles;
        }

        /// <inheritdoc />
        public Dictionary<string, string> GetRolesByMac()
        {
            var rolesByMac = new Dictionary<string, string>(System.StringComparer.OrdinalIgnoreCase);
            if (!Directory.Exists(ConfigDir)) return rolesByMac;

            void TryAdd(Dictionary<string, string> section, string role)
            {
                foreach (var key in MacFieldKeys)
                {
                    var raw = GetValue(section, key);
                    var mac = NormaliseMac(raw);
                    if (!string.IsNullOrEmpty(mac))
                    {
                        // Last writer wins — duplicate MAC across sections is
                        // a misconfiguration; we'd rather render the latest
                        // role than throw.
                        rolesByMac[mac] = role;
                        return;
                    }
                }
            }

            var camsCfg = ReadCfg(Path.Combine(ConfigDir, "cameras.cfg"));
            foreach (var section in camsCfg.Keys)
            {
                var camMatch = CameraSection.Match(section);
                if (camMatch.Success)
                {
                    var idx = int.Parse(camMatch.Groups[1].Value);
                    TryAdd(camsCfg[section], $"Main Camera {idx + 1}");
                    continue;
                }
                var angleMatch = AdditionalAngleSection.Match(section);
                if (angleMatch.Success)
                {
                    var idx = int.Parse(angleMatch.Groups[1].Value);
                    TryAdd(camsCfg[section], $"Additional Angle {idx + 1}");
                    continue;
                }
                if (section == "PIP") TryAdd(camsCfg[section], "OCR / Scoreboard");
            }

            var pipCfg = ReadCfg(Path.Combine(ConfigDir, "pip.cfg"));
            if (pipCfg.TryGetValue("PIP", out var pip)) TryAdd(pip, "OCR / Scoreboard");

            return rolesByMac;
        }

        // ----- helpers -----

        private static string GetValue(Dictionary<string, string> section, string key)
            => (section != null && section.TryGetValue(key, out var v)) ? v : null;

        private static string ExtractIp(string rtspUrl)
        {
            if (string.IsNullOrEmpty(rtspUrl)) return null;
            var m = RtspIpRx.Match(rtspUrl);
            return m.Success ? m.Groups[1].Value : null;
        }

        // Normalise a MAC string to canonical "XX-XX-XX-XX-XX-XX" upper-case.
        // Tolerant of colon, dash, dot, or undelimited input. Returns null
        // when nothing parseable is in the string.
        private static string NormaliseMac(string raw)
        {
            if (string.IsNullOrEmpty(raw)) return null;
            var m = MacRx.Match(raw);
            if (!m.Success) return null;
            var hex = new System.Text.StringBuilder(12);
            foreach (var c in m.Value)
            {
                if (c == ':' || c == '-' || c == '.') continue;
                hex.Append(char.ToUpperInvariant(c));
            }
            if (hex.Length != 12) return null;
            return $"{hex[0]}{hex[1]}-{hex[2]}{hex[3]}-{hex[4]}{hex[5]}-{hex[6]}{hex[7]}-{hex[8]}{hex[9]}-{hex[10]}{hex[11]}";
        }

        /// <summary>
        /// Parse a Pixellot .cfg file into a dict-of-dicts keyed by section name.
        /// Returns empty if the file doesn't exist or can't be read.
        /// </summary>
        private static Dictionary<string, Dictionary<string, string>> ReadCfg(string path)
        {
            var result = new Dictionary<string, Dictionary<string, string>>();
            if (!File.Exists(path)) return result;

            string section = null;
            string[] lines;
            try { lines = File.ReadAllLines(path); }
            catch { return result; }

            foreach (var raw in lines)
            {
                var line = raw.Trim();
                if (string.IsNullOrEmpty(line)) continue;

                // Full-line comment
                if (line.StartsWith("//")) continue;

                // Trailing comment — match \s+// so "rtsp:////..." inside values
                // doesn't get mistaken for a comment delimiter.
                var c = CommentRx.Match(line);
                if (c.Success) line = line.Substring(0, c.Index).Trim();
                if (string.IsNullOrEmpty(line)) continue;

                // Section header
                var s = SectionRx.Match(line);
                if (s.Success)
                {
                    section = s.Groups[1].Value.Trim();
                    if (!result.ContainsKey(section))
                        result[section] = new Dictionary<string, string>();
                    continue;
                }
                if (section == null) continue;

                // KEY, type, value  — split into max 3 parts so values containing
                // commas don't get truncated.
                //
                // D10 fix: also accept 2-column rows (KEY,VALUE without the
                // type column). Previously these were silently dropped, which
                // meant a camera section with malformed UID/IP rows could
                // leave roles[ip] unwritten and the Camera VM would render
                // "Unknown device" for the port + fire the unknown-remote
                // recommendation. Now: 3+ cols -> parts[2] as value; exactly
                // 2 cols -> parts[1] as value.
                var parts = line.Split(new[] { ',' }, 3);
                if (parts.Length >= 3)
                {
                    var key = parts[0].Trim();
                    var val = parts[2].Trim().Trim('"');
                    if (!string.IsNullOrEmpty(key))
                        result[section][key] = val;
                }
                else if (parts.Length == 2)
                {
                    var key = parts[0].Trim();
                    var val = parts[1].Trim().Trim('"');
                    if (!string.IsNullOrEmpty(key))
                        result[section][key] = val;
                }
            }
            return result;
        }
    }
}
