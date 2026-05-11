using System.Collections.ObjectModel;
using Pulse.WPF.Models;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Live-log sink shared by the five diagnostic-panel VMs (DiskHealth,
    /// Services, Hardware, Network, Camera). Each VM used to carry its own
    /// `AddLog` + `LogEntries` + 200-entry cap loop; extracted here in v0.5.0
    /// so the behaviour stays consistent and adding a new panel doesn't drag
    /// the same boilerplate along.
    ///
    /// Compose, don't inherit — keep VMs simple. Caller writes:
    ///   public PanelLogger Logger { get; } = new PanelLogger();
    /// and binds the view to `Logger.Entries`.
    /// </summary>
    public class PanelLogger
    {
        /// <summary>Cap matches the original per-VM loops.</summary>
        public const int MaxEntries = 200;

        /// <summary>UI-bound entries. Always written via Add() so the cap holds.</summary>
        public ObservableCollection<LogEntry> Entries { get; } = new ObservableCollection<LogEntry>();

        /// <summary>
        /// Append one entry. Marshals to the UI thread when needed so callers
        /// can fire from a Task.Run worker without sprinkling
        /// Application.Current?.Dispatcher.Invoke around the codebase.
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
