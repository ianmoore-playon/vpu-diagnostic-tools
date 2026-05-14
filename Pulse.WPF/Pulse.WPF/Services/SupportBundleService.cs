using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    public class SupportBundleSection
    {
        public string Title { get; set; } = "";
        public string FileName { get; set; } = "";
        public string Content { get; set; } = "";
    }

    /// <summary>
    /// Creates a single attachable support package from the same findings
    /// snapshot that drives the Dashboard baseline summary.
    /// </summary>
    public class SupportBundleService
    {
        public string ReportsDirectory { get; }

        public SupportBundleService(string reportsDirectory)
        {
            ReportsDirectory = string.IsNullOrWhiteSpace(reportsDirectory)
                ? Path.Combine(Path.GetTempPath(), "Pulse.WPF", "Reports")
                : reportsDirectory;
        }

        public string Create(
            BaselineSnapshot snapshot,
            IEnumerable<SupportBundleSection> sections,
            IEnumerable<string> recentLogLines)
        {
            Directory.CreateDirectory(ReportsDirectory);

            var stamp = DateTime.Now;
            var host = SafeName(snapshot?.Hostname ?? Environment.MachineName);
            var zipPath = Path.Combine(
                ReportsDirectory,
                $"PulseSupport-{host}-{stamp:yyyyMMdd-HHmmss}.zip");

            var staging = Path.Combine(
                ReportsDirectory,
                "_bundle-work-" + Guid.NewGuid().ToString("N"));

            Directory.CreateDirectory(staging);
            try
            {
                File.WriteAllText(
                    Path.Combine(staging, "Pulse-Support-Summary.txt"),
                    BuildSummary(snapshot),
                    Encoding.UTF8);

                var panelsDir = Path.Combine(staging, "Panels");
                Directory.CreateDirectory(panelsDir);
                foreach (var section in sections ?? Enumerable.Empty<SupportBundleSection>())
                {
                    if (section == null) continue;
                    var fileName = SafePanelFileName(section.FileName, section.Title);
                    var body = new StringBuilder();
                    body.AppendLine(section.Title ?? "");
                    body.AppendLine(new string('=', Math.Max(3, (section.Title ?? "").Length)));
                    body.AppendLine();
                    body.AppendLine(section.Content ?? "");
                    File.WriteAllText(Path.Combine(panelsDir, fileName), body.ToString(), Encoding.UTF8);
                }

                var logsDir = Path.Combine(staging, "Logs");
                Directory.CreateDirectory(logsDir);
                File.WriteAllLines(
                    Path.Combine(logsDir, "Pulse-log-tail.txt"),
                    recentLogLines ?? Enumerable.Empty<string>(),
                    Encoding.UTF8);

                TryCopyTodayLog(logsDir);

                if (File.Exists(zipPath)) File.Delete(zipPath);
                ZipFile.CreateFromDirectory(staging, zipPath, CompressionLevel.Optimal, false);
                return zipPath;
            }
            finally
            {
                try { if (Directory.Exists(staging)) Directory.Delete(staging, true); } catch { }
            }
        }

        private static string BuildSummary(BaselineSnapshot snapshot)
        {
            var sb = new StringBuilder();
            sb.AppendLine("Pulse Support Bundle");
            sb.AppendLine("====================");
            sb.AppendLine();
            sb.AppendLine($"Generated:     {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            sb.AppendLine($"Hostname:      {snapshot?.Hostname ?? Environment.MachineName}");
            sb.AppendLine($"Pulse version: {snapshot?.PulseVersion ?? AppVersion.Display}");

            if (snapshot == null)
            {
                sb.AppendLine();
                sb.AppendLine("No baseline snapshot was available when this bundle was generated.");
                return sb.ToString();
            }

            sb.AppendLine($"Baseline time: {snapshot.CompletedAtLocal:yyyy-MM-dd HH:mm:ss}");
            sb.AppendLine($"Status:        {BaselineStatus(snapshot)}");
            sb.AppendLine($"Panels:        {snapshot.CompletedCount}/{snapshot.PanelsTotal} completed, {snapshot.FailedCount} failed");
            sb.AppendLine($"Duration:      {snapshot.DurationSeconds:F1}s");
            sb.AppendLine($"Findings:      {snapshot.FindingCount} total ({snapshot.CriticalFindingCount} critical, {snapshot.WarningFindingCount} warning)");

            if (snapshot.FailedPanels != null && snapshot.FailedPanels.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("Failed panels");
                sb.AppendLine("-------------");
                foreach (var panel in snapshot.FailedPanels)
                    sb.AppendLine($"- {panel}");
            }

            sb.AppendLine();
            sb.AppendLine("Findings");
            sb.AppendLine("--------");
            var findings = (snapshot.Findings ?? new List<BaselineFindingSnapshot>())
                .OrderByDescending(f => SeverityRank(f?.Severity))
                .ThenBy(f => f?.Panel ?? "")
                .ToList();
            if (findings.Count == 0)
            {
                sb.AppendLine("No active findings captured.");
            }
            else
            {
                foreach (var f in findings)
                {
                    if (f == null) continue;
                    sb.AppendLine($"[{f.Severity}] {f.Panel}: {f.Title}");
                    if (!string.IsNullOrWhiteSpace(f.Category))
                        sb.AppendLine($"  Category: {f.Category}");
                    if (!string.IsNullOrWhiteSpace(f.Recommendation))
                        sb.AppendLine($"  Next: {f.Recommendation}");
                }
            }

            sb.AppendLine();
            sb.AppendLine("Panel status");
            sb.AppendLine("------------");
            foreach (var panel in snapshot.Panels ?? new List<BaselinePanelSnapshot>())
            {
                if (panel == null) continue;
                sb.AppendLine(
                    $"[{panel.Status}] {panel.Name}: {panel.FindingCount} finding(s), {panel.CriticalCount} critical, {panel.WarningCount} warning");
                if (!string.IsNullOrWhiteSpace(panel.ReportPath))
                    sb.AppendLine($"  Last report: {panel.ReportPath}");
            }

            sb.AppendLine();
            sb.AppendLine("Bundle contents");
            sb.AppendLine("---------------");
            sb.AppendLine("- Pulse-Support-Summary.txt");
            sb.AppendLine("- Panels/*.txt");
            sb.AppendLine("- Logs/Pulse-log-tail.txt");
            sb.AppendLine("- Logs/Pulse-YYYYMMDD.log when available");

            return sb.ToString();
        }

        private static string BaselineStatus(BaselineSnapshot snapshot)
        {
            if (snapshot.Cancelled) return "Cancelled";
            if (snapshot.FailedCount > 0) return "Completed with panel errors";
            if (snapshot.CriticalFindingCount > 0) return "Critical findings";
            if (snapshot.WarningFindingCount > 0) return "Warnings";
            return "Pass";
        }

        private static int SeverityRank(string severity)
        {
            switch ((severity ?? "").Trim().ToLowerInvariant())
            {
                case "critical": return 3;
                case "warning":  return 2;
                case "info":     return 1;
                default:         return 0;
            }
        }

        private static void TryCopyTodayLog(string logsDir)
        {
            try
            {
                var path = AppLogFile.Instance.TodayPath;
                if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return;
                File.Copy(path, Path.Combine(logsDir, Path.GetFileName(path)), true);
            }
            catch { }
        }

        private static string SafePanelFileName(string fileName, string title)
        {
            var raw = string.IsNullOrWhiteSpace(fileName) ? title : fileName;
            raw = string.IsNullOrWhiteSpace(raw) ? "Panel.txt" : raw;
            if (!raw.EndsWith(".txt", StringComparison.OrdinalIgnoreCase)) raw += ".txt";
            return SafeName(raw);
        }

        private static string SafeName(string value)
        {
            var text = string.IsNullOrWhiteSpace(value) ? "Unknown" : value.Trim();
            foreach (var c in Path.GetInvalidFileNameChars())
                text = text.Replace(c, '_');
            return text.Replace(' ', '-');
        }
    }
}
