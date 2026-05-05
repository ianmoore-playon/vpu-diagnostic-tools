using System;
using System.Windows.Media;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One row in the Live Log card. Plain DTO — once added to the
    /// ObservableCollection the XAML renders it automatically.
    /// </summary>
    public class LogEntry
    {
        public DateTime Timestamp { get; set; } = DateTime.Now;
        public string Label { get; set; } = "";
        public string Result { get; set; } = "";
        // "Info" | "Pass" | "Warn" | "Fail" | "Section" | "Gray"
        public string Level { get; set; } = "Info";

        // Resolved foreground color for the result text, set when entries are
        // appended so XAML can bind to it directly without a value converter.
        public Brush ResultColor { get; set; } = Brushes.LightGray;
    }
}
