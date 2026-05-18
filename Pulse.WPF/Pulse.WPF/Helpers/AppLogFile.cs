using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Rolling daily app log. Every PanelLogger.AddLog() across the panels —
    /// plus user actions worth tracking (nav switches, dialog opens, button
    /// clicks) and live-monitor events that don't otherwise produce a
    /// per-run report — pours into a single text file at
    /// %LOCALAPPDATA%\Pulse.WPF\Logs\Pulse-YYYYMMDD.log.
    ///
    /// Each line:
    ///     2026-05-12 14:43:02.123  [Network]  Pass  Port TCP/443 reachable
    ///
    /// All IO is wrapped in try/catch — a locked file / read-only profile /
    /// full disk must not crash the diagnostic tool. Singleton-style via
    /// <see cref="Instance"/>; thread-safe via an internal lock around the
    /// append call so the PanelLogger UI thread and Camera-NIC monitor's
    /// background tick can both write without tearing each other's lines.
    /// </summary>
    public sealed class AppLogFile
    {
        private static readonly Lazy<AppLogFile> _instance =
            new Lazy<AppLogFile>(() => new AppLogFile());
        public static AppLogFile Instance => _instance.Value;

        private readonly object _gate = new object();
        public string LogsDirectory { get; }

        private AppLogFile()
        {
            string dir;
            try
            {
                var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                dir = Path.Combine(local, "Pulse.WPF", "Logs");
                Directory.CreateDirectory(dir);
            }
            catch
            {
                // Fall back to a tempdir if LOCALAPPDATA is unwritable — the
                // app keeps working, the log just lives elsewhere.
                try
                {
                    dir = Path.Combine(Path.GetTempPath(), "Pulse.WPF", "Logs");
                    Directory.CreateDirectory(dir);
                }
                catch
                {
                    dir = Path.GetTempPath();
                }
            }
            LogsDirectory = dir;
        }

        /// <summary>Full path to today's log file (computed fresh on each call
        /// so a long-running session naturally rolls over at midnight).</summary>
        public string TodayPath
        {
            get
            {
                var name = "Pulse-" + DateTime.Now.ToString("yyyyMMdd") + ".log";
                return Path.Combine(LogsDirectory, name);
            }
        }

        /// <summary>
        /// Append a single line. Wraps every disk op — never throws.
        /// </summary>
        /// <param name="panel">Source tag, e.g. "Network", "Nav", "Camera".</param>
        /// <param name="level">"Pass" / "Fail" / "Warn" / "Section" / "Info".</param>
        /// <param name="message">Free-text payload.</param>
        public void WriteLine(string panel, string level, string message)
        {
            string line;
            try
            {
                var ts = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");
                var p = string.IsNullOrEmpty(panel) ? "-" : panel;
                var l = string.IsNullOrEmpty(level) ? "Info" : level;
                var m = (message ?? "").Replace('\r', ' ').Replace('\n', ' ');
                line = $"{ts}  [{p}]  {l}  {m}";
            }
            catch
            {
                return;
            }

            lock (_gate)
            {
                try
                {
                    File.AppendAllText(TodayPath, line + Environment.NewLine, Encoding.UTF8);
                }
                catch (Exception ex)
                {
                    // R7 fix: disk full, file locked by AV, profile read-only —
                    // we still can't propagate the failure to the user (the
                    // log is itself how we'd report it). But emit a
                    // Debug.WriteLine so the failure shows up in a debugger
                    // / DebugView trace rather than being completely
                    // invisible. Lost-line accounting is still implicit (no
                    // partial-write protection beyond AppendAllText's
                    // own); a future improvement is a persistent
                    // StreamWriter with FileShare.ReadWrite|Delete, but
                    // that needs window-close disposal wiring that's not
                    // in scope here.
                    System.Diagnostics.Debug.WriteLine(
                        $"AppLogFile: lost line on append - {ex.GetType().Name}: {ex.Message}");
                }
            }
        }

        /// <summary>Read the tail of today's log — used by the Reports panel
        /// App Log sub-card. Returns oldest-first within the tail window.</summary>
        public IReadOnlyList<string> ReadTodayTail(int lineCount)
        {
            if (lineCount <= 0) return Array.Empty<string>();
            try
            {
                var path = TodayPath;
                if (!File.Exists(path)) return Array.Empty<string>();

                // Cheap-and-correct: read the whole file when it's small (the
                // daily file is bounded by tens of MB even on a chatty box),
                // then keep the last N. If the file ever grows pathological
                // we can revisit with a reverse-stream reader.
                lock (_gate)
                {
                    var all = File.ReadAllLines(path);
                    if (all.Length <= lineCount) return all;
                    var tail = new string[lineCount];
                    Array.Copy(all, all.Length - lineCount, tail, 0, lineCount);
                    return tail;
                }
            }
            catch
            {
                return Array.Empty<string>();
            }
        }

        /// <summary>Delete Pulse-YYYYMMDD.log files older than the cutoff.
        /// Called from App startup on a Task.Run so a slow IO doesn't stall
        /// the splash.</summary>
        public void CleanupOlderThan(int days)
        {
            if (days <= 0) return;
            try
            {
                if (!Directory.Exists(LogsDirectory)) return;
                var cutoff = DateTime.Now.AddDays(-days);
                foreach (var path in Directory.EnumerateFiles(LogsDirectory, "Pulse-*.log"))
                {
                    try
                    {
                        var info = new FileInfo(path);
                        if (info.LastWriteTime < cutoff)
                        {
                            File.Delete(path);
                        }
                    }
                    catch { /* skip one stuck file */ }
                }
            }
            catch { /* directory enum failed — nothing to do */ }
        }
    }
}
