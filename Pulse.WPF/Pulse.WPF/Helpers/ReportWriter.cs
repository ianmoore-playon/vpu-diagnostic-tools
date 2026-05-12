using System;
using System.IO;
using System.Text;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Writes per-run diagnostic report files into %LOCALAPPDATA%\Pulse.WPF\
    /// Reports. One file per RefreshAsync / RunTestAsync, named
    /// <c>&lt;HOSTNAME&gt;-&lt;Panel&gt;-&lt;YYYYMMDD&gt;-&lt;HHMMSS&gt;.txt</c>.
    ///
    /// The header is built here so every panel's report carries the same
    /// branding block; each panel's <c>BuildReportText()</c> supplies only the
    /// body. All disk IO is wrapped in try/catch — on failure
    /// <see cref="Save"/> returns null and routes a warning into the rolling
    /// AppLogFile rather than blowing up the caller.
    /// </summary>
    public class ReportWriter
    {
        public string ReportsDirectory { get; }

        public ReportWriter()
        {
            try
            {
                var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                ReportsDirectory = Path.Combine(local, "Pulse.WPF", "Reports");
                Directory.CreateDirectory(ReportsDirectory);
            }
            catch
            {
                try
                {
                    ReportsDirectory = Path.Combine(Path.GetTempPath(), "Pulse.WPF", "Reports");
                    Directory.CreateDirectory(ReportsDirectory);
                }
                catch
                {
                    ReportsDirectory = Path.GetTempPath();
                }
            }
        }

        public ReportWriter(string explicitDirectory)
        {
            ReportsDirectory = explicitDirectory;
            try { Directory.CreateDirectory(ReportsDirectory); } catch { }
        }

        /// <summary>
        /// Compose the header + body and write the file. Returns the full
        /// path on success, or null if anything fails. Never throws.
        /// </summary>
        public string Save(string panelName, string bundleBody)
        {
            string path = null;
            try
            {
                var host = SanitiseToken(SafeHostname());
                var panel = SanitiseToken(panelName ?? "Panel");
                var ts = DateTime.Now;
                var name = $"{host}-{panel}-{ts:yyyyMMdd}-{ts:HHmmss}.txt";
                path = Path.Combine(ReportsDirectory, name);

                var sb = new StringBuilder();
                sb.AppendLine("Pulse — Pixellot Unified Live System Evaluator");
                sb.AppendLine(new string('=', 60));
                sb.AppendLine($"Generated:   {ts:yyyy-MM-dd HH:mm:ss}");
                sb.AppendLine($"Hostname:    {SafeHostname()}");
                sb.AppendLine($"Pulse:       {AppVersion.Display}");
                sb.AppendLine($"Panel:       {panelName}");
                sb.AppendLine(new string('=', 60));
                sb.AppendLine();
                sb.AppendLine(bundleBody ?? "");

                File.WriteAllText(path, sb.ToString(), Encoding.UTF8);
                return path;
            }
            catch (Exception ex)
            {
                try
                {
                    AppLogFile.Instance.WriteLine(
                        "ReportWriter", "Warn",
                        $"Failed to save report for {panelName}: {ex.Message}");
                }
                catch { }
                return null;
            }
        }

        private static string SafeHostname()
        {
            try { return Environment.MachineName ?? "VPU"; }
            catch { return "VPU"; }
        }

        // Filename tokens get sanitised so an odd hostname (with spaces or
        // unicode) can't produce an invalid file name. Alphanumerics + dashes
        // only; everything else collapses to a dash.
        private static string SanitiseToken(string s)
        {
            if (string.IsNullOrEmpty(s)) return "VPU";
            var sb = new StringBuilder(s.Length);
            foreach (var ch in s)
            {
                if (char.IsLetterOrDigit(ch)) sb.Append(ch);
                else if (ch == '-' || ch == '_') sb.Append(ch);
                else sb.Append('-');
            }
            var token = sb.ToString().Trim('-');
            return string.IsNullOrEmpty(token) ? "VPU" : token;
        }
    }
}
