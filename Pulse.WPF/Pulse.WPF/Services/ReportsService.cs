using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Reads .txt / .json report bundles from %LOCALAPPDATA%\Pulse.WPF\Reports.
    /// Creates the directory on first use; all IO is wrapped in try/catch
    /// so the panel always renders even on a locked-down profile.
    /// </summary>
    public class ReportsService : IReportsService
    {
        // Mirror the legacy WinForms tool's bundle directory shape so a
        // tech moving between the two see the same files.
        public string ReportsDirectory { get; }

        private const int MaxReports = 200;

        public ReportsService()
        {
            try
            {
                var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                ReportsDirectory = Path.Combine(local, "Pulse.WPF", "Reports");
                Directory.CreateDirectory(ReportsDirectory);
            }
            catch
            {
                // Fall back to a tempdir if LOCALAPPDATA is unwritable — the
                // panel still works, just against a different folder.
                ReportsDirectory = Path.Combine(Path.GetTempPath(), "Pulse.WPF", "Reports");
                try { Directory.CreateDirectory(ReportsDirectory); } catch { }
            }
        }

        public Task<List<Report>> GetAllAsync()
        {
            return Task.Run(() =>
            {
                var list = new List<Report>();
                try
                {
                    if (!Directory.Exists(ReportsDirectory)) return list;
                    var files = Directory.EnumerateFiles(ReportsDirectory)
                                          .Where(IsReportFile);
                    foreach (var path in files)
                    {
                        try
                        {
                            var info = new FileInfo(path);
                            list.Add(new Report
                            {
                                FileName  = info.Name,
                                SizeBytes = info.Length,
                                Timestamp = info.LastWriteTime,
                                Notes     = ReadPreview(info.FullName),
                            });
                        }
                        catch { /* skip unreadable file */ }
                    }
                }
                catch { /* directory enumeration failed */ }

                list.Sort((a, b) => b.Timestamp.CompareTo(a.Timestamp));
                if (list.Count > MaxReports) list = list.GetRange(0, MaxReports);
                return list;
            });
        }

        public Task<string> ReadAsync(string fileName)
        {
            return Task.Run(() =>
            {
                if (string.IsNullOrWhiteSpace(fileName)) return "";
                try
                {
                    var path = Path.Combine(ReportsDirectory, fileName);
                    if (!File.Exists(path)) return "(report file no longer exists)";
                    return File.ReadAllText(path);
                }
                catch (Exception ex)
                {
                    return $"(failed to read report: {ex.Message})";
                }
            });
        }

        /// <summary>Surfaces AppLogFile's logs directory so the Reports
        /// panel's "Open Logs Folder" button has a path to shell out to.</summary>
        public string LogsDirectory => AppLogFile.Instance.LogsDirectory;

        /// <summary>Path of today's rolling log file (may not exist yet —
        /// the first log line of the day creates it).</summary>
        public string TodayLogPath => AppLogFile.Instance.TodayPath;

        public IReadOnlyList<string> GetRecentAppLogLines(int count)
        {
            return AppLogFile.Instance.ReadTodayTail(count);
        }

        /// <summary>Prune .txt / .json / .log reports older than the cutoff.
        /// The MaxReports cap stays as a secondary safety net.</summary>
        public void CleanupOlderThan(int days)
        {
            if (days <= 0) return;
            try
            {
                if (!Directory.Exists(ReportsDirectory)) return;
                var cutoff = DateTime.Now.AddDays(-days);
                foreach (var path in Directory.EnumerateFiles(ReportsDirectory))
                {
                    if (!IsReportFile(path)) continue;
                    try
                    {
                        var info = new FileInfo(path);
                        if (info.LastWriteTime < cutoff) File.Delete(path);
                    }
                    catch { /* skip individual stuck file */ }
                }
            }
            catch { /* directory enum failed */ }
        }

        public bool Delete(string fileName)
        {
            if (string.IsNullOrWhiteSpace(fileName)) return false;
            try
            {
                var path = Path.Combine(ReportsDirectory, fileName);
                if (File.Exists(path))
                {
                    File.Delete(path);
                    return true;
                }
            }
            catch { /* swallow */ }
            return false;
        }

        private static bool IsReportFile(string path)
        {
            var ext = (Path.GetExtension(path) ?? "").ToLowerInvariant();
            return ext == ".txt" || ext == ".json" || ext == ".log";
        }

        private static string ReadPreview(string path)
        {
            try
            {
                // Read first ~200 chars without slurping a multi-megabyte file.
                using (var sr = new StreamReader(path))
                {
                    var buf = new char[200];
                    int read = sr.ReadBlock(buf, 0, buf.Length);
                    if (read <= 0) return "";
                    var s = new string(buf, 0, read).Replace("\r", " ").Replace("\n", " ");
                    return s.Trim();
                }
            }
            catch { return ""; }
        }
    }
}
