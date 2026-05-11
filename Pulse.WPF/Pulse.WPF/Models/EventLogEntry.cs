using System;
using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One row in the Event Viewer panel. Backed by a single Windows event log
    /// record (read via <see cref="System.Diagnostics.EventLog"/>) and pre-
    /// computes the level chip colours so the DataGrid binds without
    /// converters.
    ///
    /// Brushes are resolved lazily via <see cref="StatusHelpers.Brush"/> so
    /// resource lookup happens against the active theme at first paint.
    /// </summary>
    public class EventLogEntry
    {
        public DateTime TimeGenerated { get; set; }
        public string   Source        { get; set; }

        /// <summary>"Error" / "Warning" / "Information".</summary>
        public string   Level         { get; set; }

        public int      EventId       { get; set; }
        public string   Message       { get; set; }

        /// <summary>Display string for the timestamp — pre-formatted so the
        /// DataGrid column can bind directly.</summary>
        public string TimestampLabel => TimeGenerated.ToString("MMM d, HH:mm:ss");

        /// <summary>Foreground colour for the Level chip. Mirrors the
        /// severity palette used by Findings.</summary>
        public Brush LevelColor
        {
            get
            {
                switch (Level)
                {
                    case "Error":       return StatusHelpers.Brush("RedBrush");
                    case "Warning":     return StatusHelpers.Brush("YellowBrush");
                    case "Information": return StatusHelpers.Brush("AccentBrush");
                    default:             return StatusHelpers.Brush("MutedForegroundBrush");
                }
            }
        }

        /// <summary>Background colour for the Level chip.</summary>
        public Brush LevelBgBrush
        {
            get
            {
                switch (Level)
                {
                    case "Error":       return StatusHelpers.Brush("ErrBgBrush");
                    case "Warning":     return StatusHelpers.Brush("WarnBgBrush");
                    case "Information": return StatusHelpers.Brush("BorderColBrush");
                    default:             return StatusHelpers.Brush("BorderColBrush");
                }
            }
        }
    }
}
