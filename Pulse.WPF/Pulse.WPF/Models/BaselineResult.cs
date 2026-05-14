using System;
using System.Collections.Generic;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// Terminal result fired by <see cref="Pulse.WPF.Helpers.BaselineRunner"/>
    /// once every phase has completed (or the run was cancelled). Carries
    /// enough state for the Dashboard banner to render the "complete" or
    /// "complete with errors" caption without re-querying the runner.
    /// </summary>
    public class BaselineResult
    {
        /// <summary>Panels that finished their refresh without throwing.</summary>
        public int CompletedCount { get; set; }

        /// <summary>Panels whose RefreshAsync / RunTestAsync threw. The
        /// throw is logged to AppLogFile but does not block the rest of
        /// the orchestrator.</summary>
        public int FailedCount { get; set; }

        /// <summary>Display names of failed panels, in the order they
        /// were attempted. Used by the banner to compose a short list
        /// for tier-1 ("Network, Event Viewer failed").</summary>
        public List<string> FailedPanels { get; set; } = new List<string>();

        /// <summary>End-to-end wall time. Used for the AppLogFile summary
        /// line, not currently rendered in the banner.</summary>
        public TimeSpan Duration { get; set; }

        /// <summary>True when the orchestrator was cancelled via its
        /// CancellationToken before all panels finished. Banner reads this
        /// to swap the "complete" caption to "cancelled".</summary>
        public bool Cancelled { get; set; }

        /// <summary>Persisted baseline snapshot built from the same panel
        /// Findings collections the Dashboard renders after completion.</summary>
        public BaselineSnapshot Snapshot { get; set; }
    }
}
