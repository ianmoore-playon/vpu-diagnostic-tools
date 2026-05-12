using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Pulls entries from the Application + System Windows event logs and
    /// hands the panel a flat list of <see cref="WindowsEventEntry"/> rows.
    ///
    /// Read-time gotchas worth flagging for future maintainers:
    ///   - <see cref="EventLog.Entries"/> enumerates oldest-first and is
    ///     expensive on a busy box; we iterate in reverse and stop as soon
    ///     as we cross the time window.
    ///   - A locked-down VPU image can refuse the read with
    ///     <see cref="System.Security.SecurityException"/> on first access.
    ///     We swallow that here so the panel still renders empty instead of
    ///     crashing the tab.
    ///   - <c>EventLog</c> instances hold an unmanaged handle — caller code
    ///     should use the <c>using</c> we apply here, not store them.
    /// </summary>
    public class EventViewerService : IEventViewerService
    {
        // Hard cap so a noisy log doesn't drag the DataGrid to a crawl.
        private const int MaxEntries = 500;

        // Logs we read. Application catches Pixellot / app crashes / WHEA;
        // System catches disk / NIC / SCM / driver complaints.
        private static readonly string[] LogsToRead = { "Application", "System" };

        public Task<List<WindowsEventEntry>> GetRecentAsync(int hoursBack,
                                                        IEnumerable<string> sources,
                                                        IEnumerable<string> levels)
        {
            return Task.Run(() => Read(hoursBack, sources, levels));
        }

        private static List<WindowsEventEntry> Read(int hoursBack,
                                                 IEnumerable<string> sources,
                                                 IEnumerable<string> levels)
        {
            var results = new List<WindowsEventEntry>();
            var cutoff  = DateTime.Now.AddHours(-Math.Max(1, hoursBack));

            // Case-insensitive prefix list. Empty means "match any".
            var sourcePrefixes = (sources ?? Array.Empty<string>())
                .Where(s => !string.IsNullOrWhiteSpace(s))
                .Select(s => s.Trim())
                .ToArray();
            var levelSet = new HashSet<string>(
                (levels ?? Array.Empty<string>()).Where(l => !string.IsNullOrWhiteSpace(l)),
                StringComparer.OrdinalIgnoreCase);
            if (levelSet.Count == 0)
            {
                // Default = Error + Warning so the panel surfaces signal first.
                levelSet.Add("Error");
                levelSet.Add("Warning");
            }

            foreach (var logName in LogsToRead)
            {
                try
                {
                    using (var log = new EventLog(logName))
                    {
                        // EventLog.Entries is indexed but enumerates oldest-first
                        // when iterated. Walk in reverse so we stop at the
                        // window cutoff as soon as possible.
                        var entries = log.Entries;
                        int total = entries.Count;
                        for (int i = total - 1; i >= 0 && results.Count < MaxEntries; i--)
                        {
                            WindowsEventEntry row;
                            try
                            {
                                var e = entries[i];
                                if (e.TimeGenerated < cutoff) break;

                                var level = MapLevel(e.EntryType);
                                if (!levelSet.Contains(level)) continue;

                                if (!MatchesSource(e.Source, sourcePrefixes)) continue;

                                row = new WindowsEventEntry
                                {
                                    TimeGenerated = e.TimeGenerated,
                                    Source        = e.Source ?? "",
                                    Level         = level,
                                    EventId       = (int)(e.InstanceId & 0xFFFF),
                                    Message       = TrimMessage(e.Message),
                                };
                            }
                            catch
                            {
                                // Individual entries can throw when the message
                                // template DLL is missing — skip them.
                                continue;
                            }
                            results.Add(row);
                        }
                    }
                }
                catch
                {
                    // SecurityException / IO failures — log is unreadable on
                    // this box. Leave the result list as-is and move on.
                    Debug.WriteLine($"EventViewerService: failed to read {logName} log");
                }
            }

            // Newest first across both logs.
            results.Sort((a, b) => b.TimeGenerated.CompareTo(a.TimeGenerated));
            if (results.Count > MaxEntries) results = results.GetRange(0, MaxEntries);
            return results;
        }

        private static string MapLevel(EventLogEntryType t)
        {
            switch (t)
            {
                case EventLogEntryType.Error:           return "Error";
                case EventLogEntryType.FailureAudit:    return "Error";
                case EventLogEntryType.Warning:         return "Warning";
                case EventLogEntryType.Information:     return "Information";
                case EventLogEntryType.SuccessAudit:    return "Information";
                default:                                 return "Information";
            }
        }

        private static bool MatchesSource(string source, string[] prefixes)
        {
            if (prefixes == null || prefixes.Length == 0) return true;
            if (string.IsNullOrEmpty(source)) return false;
            foreach (var p in prefixes)
            {
                if (source.StartsWith(p, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        private static string TrimMessage(string msg)
        {
            if (string.IsNullOrEmpty(msg)) return "";
            // Normalise CRLF so the DataGrid renders single-line ellipsis but
            // expanded view keeps its structure.
            msg = msg.Replace("\r\n", " • ").Replace('\r', ' ').Replace('\n', ' ');
            return msg.Length > 800 ? msg.Substring(0, 800) + "…" : msg;
        }
    }
}
