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
        /// Append one entry. Marshals to the UI thread when needed so callers
        /// can fire from a Task.Run worker without sprinkling
        /// Application.Current?.Dispatcher.Invoke around the codebase. Also
        /// mirrors the entry into <see cref="AppLogFile"/> so the on-disk
        /// rolling log captures everything the UI sees.
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
