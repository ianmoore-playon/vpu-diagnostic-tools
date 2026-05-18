using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Diagnostics.Eventing.Reader;
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
    ///     We report that back through LastReadFailures so the panel can show
    ///     an honest warning instead of a false-green empty state.
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

        private readonly object _failureLock = new object();
        private List<string> _lastReadFailures = new List<string>();

        public IReadOnlyList<string> LastReadFailures
        {
            get
            {
                lock (_failureLock) return _lastReadFailures.ToArray();
            }
        }

        public Task<List<WindowsEventEntry>> GetRecentAsync(int hoursBack,
                                                        IEnumerable<string> sources,
                                                        IEnumerable<string> levels)
        {
            return Task.Run(() => Read(hoursBack, sources, levels));
        }

        private List<WindowsEventEntry> Read(int hoursBack,
                                             IEnumerable<string> sources,
                                             IEnumerable<string> levels)
        {
            var results = new List<WindowsEventEntry>();
            var failures = new List<string>();
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

            // R11 fix: switch from EventLog.Entries (random-access indexer that
            // becomes O(N) per call on large logs — Server 2019 boxes with
            // long uptimes routinely hit 50k+ rows) to EventLogReader with
            // ReverseDirection=true. DiskHealthService.CountDiskErrorEvents48h
            // already uses this pattern. Builds the same time/level XPath
            // filter so the reader prunes server-side instead of walking
            // every entry. The level filter uses XPath levels 2 (Error),
            // 3 (Warning); the time filter uses timediff against the cutoff.
            long timeDiffMs = (long)Math.Round((DateTime.Now - cutoff).TotalMilliseconds);
            if (timeDiffMs < 0) timeDiffMs = 0;
            var wantError   = levelSet.Contains("Error");
            var wantWarning = levelSet.Contains("Warning");
            var wantInfo    = levelSet.Contains("Information");
            var lvlClauses = new List<string>();
            if (wantError)   lvlClauses.Add("Level=1 or Level=2");
            if (wantWarning) lvlClauses.Add("Level=3");
            if (wantInfo)    lvlClauses.Add("Level=4");
            if (lvlClauses.Count == 0) lvlClauses.Add("Level=1 or Level=2 or Level=3");
            var lvlExpr = string.Join(" or ", lvlClauses.Select(x => $"({x})"));
            var xpath = $"*[System[({lvlExpr}) and TimeCreated[timediff(@SystemTime) <= {timeDiffMs}]]]";

            foreach (var logName in LogsToRead)
            {
                EventLogReader reader = null;
                try
                {
                    var q = new EventLogQuery(logName, PathType.LogName, xpath) { ReverseDirection = true };
                    reader = new EventLogReader(q);
                    EventRecord rec;
                    while ((rec = reader.ReadEvent()) != null && results.Count < MaxEntries)
                    {
                        WindowsEventEntry row = null;
                        try
                        {
                            var time  = rec.TimeCreated ?? DateTime.MinValue;
                            if (time != DateTime.MinValue && time < cutoff)
                            {
                                rec.Dispose();
                                break;
                            }
                            var level = MapEventLogReaderLevel(rec.Level);
                            if (!levelSet.Contains(level)) { rec.Dispose(); continue; }

                            var source = rec.ProviderName ?? "";
                            if (!MatchesSource(source, sourcePrefixes)) { rec.Dispose(); continue; }

                            string formatted = "";
                            try { formatted = rec.FormatDescription() ?? ""; }
                            catch { /* missing message DLL — leave blank */ }

                            row = new WindowsEventEntry
                            {
                                TimeGenerated = time,
                                Source        = source,
                                Level         = level,
                                EventId       = rec.Id,
                                Message       = TrimMessage(formatted),
                            };
                        }
                        catch
                        {
                            // Individual entries can throw when the message
                            // template DLL is missing — skip them.
                        }
                        finally { rec?.Dispose(); }
                        if (row != null) results.Add(row);
                    }
                }
                catch (Exception ex)
                {
                    // SecurityException / IO failures — log is unreadable on
                    // this box. Leave the result list as-is and move on, but
                    // keep the failure so the panel can warn the operator.
                    failures.Add($"{logName}: {ex.Message}");
                    Debug.WriteLine($"EventViewerService: failed to read {logName} log");
                }
                finally
                {
                    reader?.Dispose();
                }
            }

            lock (_failureLock) _lastReadFailures = failures;

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

        // EventLogReader uses a numeric Level field (per Windows Event schema:
        // 1=Critical, 2=Error, 3=Warning, 4=Information, 5=Verbose). Map to
        // the string vocabulary the rest of this service uses.
        private static string MapEventLogReaderLevel(byte? level)
        {
            switch (level)
            {
                case 1: return "Error";       // Critical
                case 2: return "Error";
                case 3: return "Warning";
                case 4: return "Information";
                default: return "Information";
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
