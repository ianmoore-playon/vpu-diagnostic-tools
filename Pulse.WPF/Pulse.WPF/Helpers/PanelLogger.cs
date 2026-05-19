using System.Collections.ObjectModel;
using Pulse.WPF.Models;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Live-log sink shared by the diagnostic-panel VMs (DiskHealth,
    /// Services, Network, Camera, EventViewer). Each VM used to
    /// carry its own `AddLog` + `LogEntries` + 200-entry cap loop; extracted
    /// here in v0.5.0 so the behaviour stays consistent and adding a new
    /// panel doesn't drag the same boilerplate along.
    ///
    /// v0.5.5: every <see cref="Add"/> call now also write-throughs to
    /// <see cref="AppLogFile"/> so the on-disk rolling daily log captures
    /// every diagnostic line across every panel. Set <see cref="PanelName"/>
    /// at construction time so the AppLogFile entries carry a useful tag.
    /// </summary>
    public class PanelLogger
    {
        /// <summary>Cap matches the original per-VM loops.</summary>
        public const int MaxEntries = 200;

        /// <summary>UI-bound entries. Always written via Add() so the cap holds.</summary>
        public ObservableCollection<LogEntry> Entries { get; } = new ObservableCollection<LogEntry>();

        /// <summary>Source tag for the rolling AppLogFile. e.g. "Network".
        /// Empty means "untagged"; callers should set this in the VM ctor.</summary>
        public string PanelName { get; set; }

        public PanelLogger() { }
        public PanelLogger(string panelName) { PanelName = panelName; }

        /// <summary>
        /// v0.8.6-beta: consecutive-duplicate dedup window. Identical
        /// (Label, Result, Level) entries fired within this window are
        /// collapsed into the previous entry with a "(×N)" suffix on the
        /// Result text. Field tech feedback: clicking a broken button 5
        /// times shouldn't fill the Live Log with 5 identical lines.
        /// </summary>
        private static readonly System.TimeSpan DedupWindow = System.TimeSpan.FromSeconds(5);

        /// <summary>
        /// Append one entry. Marshals to the UI thread when needed so callers
        /// can fire from a Task.Run worker without sprinkling
        /// Application.Current?.Dispatcher.Invoke around the codebase. Also
        /// mirrors the entry into <see cref="AppLogFile"/> so the on-disk
        /// rolling log captures everything the UI sees.
        ///
        /// v0.8.6-beta: consecutive identical entries (same Label + same
        /// bare Result + same Level) within <see cref="DedupWindow"/> are
        /// collapsed in the UI by updating the previous entry with a
        /// "(×N)" suffix. The on-disk AppLogFile is NOT deduped — it
        /// captures every occurrence for forensic analysis.
        /// </summary>
        public void Add(string label, string result, string level)
        {
            var entry = new LogEntry
            {
                Label = label ?? "",
                Result = result ?? "",
                Level = level ?? "Info",
                ResultColor = StatusHelpers.BrushForLogLevel(level ?? "Info"),
            };
            void apply()
            {
                // Dedup: if the most recent entry matches (same Label,
                // same Level, same bare Result without any "(×N)" suffix)
                // AND was added within the dedup window, replace it with
                // an updated entry that bumps the count instead of
                // appending a new row.
                if (Entries.Count > 0)
                {
                    var last = Entries[Entries.Count - 1];
                    var (lastBare, lastCount) = SplitRepeatSuffix(last.Result);
                    if (string.Equals(last.Label, entry.Label, System.StringComparison.Ordinal) &&
                        string.Equals(last.Level, entry.Level, System.StringComparison.Ordinal) &&
                        string.Equals(lastBare, entry.Result, System.StringComparison.Ordinal) &&
                        (System.DateTime.Now - last.Timestamp) < DedupWindow)
                    {
                        int newCount = lastCount + 1;
                        var updated = new LogEntry
                        {
                            Timestamp   = System.DateTime.Now,
                            Label       = entry.Label,
                            Result      = $"{entry.Result} (×{newCount})",
                            Level       = entry.Level,
                            ResultColor = entry.ResultColor,
                        };
                        Entries[Entries.Count - 1] = updated;
                        return; // fall through to AppLogFile mirror below
                    }
                }
                Entries.Add(entry);
                while (Entries.Count > MaxEntries) Entries.RemoveAt(0);
            }
            var app = System.Windows.Application.Current;
            if (app != null && app.Dispatcher.CheckAccess()) apply();
            else if (app != null) app.Dispatcher.Invoke(apply);
            else apply(); // unit-test path — no dispatcher.

            // Write-through to the rolling daily file. Compose the message
            // the same way the live log reads it on screen: "Label  Result"
            // when both are present, otherwise whichever one is non-empty.
            try
            {
                string msg;
                if (!string.IsNullOrEmpty(entry.Label) && !string.IsNullOrEmpty(entry.Result))
                    msg = entry.Label + "  " + entry.Result;
                else if (!string.IsNullOrEmpty(entry.Label))
                    msg = entry.Label;
                else
                    msg = entry.Result;
                AppLogFile.Instance.WriteLine(PanelName ?? "Panel", entry.Level, msg);
            }
            catch { /* AppLogFile already swallows IO failures */ }
        }

        // v0.8.6-beta: split a Result string like "Failed... (×3)" into
        // ("Failed...", 3). When there's no suffix returns (original, 1).
        // Used by the dedup path to compare current vs. previous entries
        // and to bump the counter correctly when collapsing.
        private static (string bare, int count) SplitRepeatSuffix(string result)
        {
            if (string.IsNullOrEmpty(result)) return (result ?? "", 1);
            // Match " (×N)" suffix at the very end of the string.
            var m = System.Text.RegularExpressions.Regex.Match(result, @"^(?<bare>.*?)\s\(×(?<n>\d+)\)$");
            if (!m.Success) return (result, 1);
            if (!int.TryParse(m.Groups["n"].Value, out int n) || n < 1) return (result, 1);
            return (m.Groups["bare"].Value, n);
        }

        /// <summary>Reset the buffer. Used at the top of each refresh.</summary>
        public void Clear()
        {
            void apply() { Entries.Clear(); }
            var app = System.Windows.Application.Current;
            if (app != null && app.Dispatcher.CheckAccess()) apply();
            else if (app != null) app.Dispatcher.Invoke(apply);
            else apply();
        }
    }
}
