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
        // The agent log line "working directory: C:\Pixellot\Data\configuration"
        // is the canonical location across all VPUs we've checked.
        private const string ConfigDir = @"C:\Pixellot\Data\configuration";

        private static readonly Regex SectionRx = new Regex(@"^\[(.+)\]$", RegexOptions.Compiled);
        private static readonly Regex CommentRx = new Regex(@"\s+//", RegexOptions.Compiled);
        private static readonly Regex CameraSection         = new Regex(@"^CAMERA_(\d+)$",          RegexOptions.Compiled);
        private static readonly Regex AdditionalAngleSection = new Regex(@"^ADDITIONAL_ANGLE_(\d+)$", RegexOptions.Compiled);
        private static readonly Regex RtspIpRx              = new Regex(@"rtsp:/+(\d+\.\d+\.\d+\.\d+)", RegexOptions.Compiled);

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

        // ----- helpers -----

        private static string GetValue(Dictionary<string, string> section, string key)
            => (section != null && section.TryGetValue(key, out var v)) ? v : null;

        private static string ExtractIp(string rtspUrl)
        {
            if (string.IsNullOrEmpty(rtspUrl)) return null;
            var m = RtspIpRx.Match(rtspUrl);
            return m.Success ? m.Groups[1].Value : null;
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
                var parts = line.Split(new[] { ',' }, 3);
                if (parts.Length >= 3)
                {
                    var key = parts[0].Trim();
                    var val = parts[2].Trim().Trim('"');
                    if (!string.IsNullOrEmpty(key))
                        result[section][key] = val;
                }
            }
            return result;
        }
    }
}
