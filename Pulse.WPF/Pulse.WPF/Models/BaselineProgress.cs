namespace Pulse.WPF.Models
{
    /// <summary>
    /// Snapshot of <see cref="Pulse.WPF.Helpers.BaselineRunner"/> progress.
    /// Fired by the runner after each panel transitions (started / finished)
    /// so the Dashboard banner can render a "(N/M done — Network probing…)"
    /// caption without polling. Plain DTO; no INotifyPropertyChanged here —
    /// the consumer (DashboardViewModel) maps the values onto its own
    /// observable fields on the UI thread.
    /// </summary>
    public class BaselineProgress
    {
        /// <summary>Human-readable name of the panel currently running
        /// (e.g. "Network", "Disk Health"). Empty when the runner is between
        /// phases or finished.</summary>
        public string CurrentPanel { get; set; } = "";

        /// <summary>Panels finished so far (success + failure).</summary>
        public int Completed { get; set; }

        /// <summary>Total panels the orchestrator plans to run this pass.</summary>
        public int Total { get; set; }

        /// <summary>Short phase tag — "Running", "Phase 1 done",
        /// "Cancelled", "Completed". Used by the Dashboard banner as a
        /// secondary caption.</summary>
        public string Status { get; set; } = "";
    }
}
