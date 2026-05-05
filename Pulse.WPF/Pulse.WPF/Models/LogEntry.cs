using System;
using System.Windows.Media;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One row in any panel's Live Log card. Plain DTO — once added to the
    /// ObservableCollection the XAML renders it automatically.
    /// Lives in Models/ (not ViewModels/) so every panel — Camera, Network,
    /// Hardware, Services, Disk — can share the exact same row type.
    /// </summary>
    public class LogEntry
    {
        public DateTime Timestamp { get; set; } = DateTime.Now;
        public string   Label     { get; set; } = "";
        public string   Result    { get; set; } = "";
        public string   Level     { get; set; } = "Info";   // Info, Pass, Warn, Fail, Section, Gray, Cyan

        // Resolved foreground color for the result text — set by the producing
        // VM when entries are added so XAML can bind to it directly without a
        // converter.
        public Brush ResultColor { get; set; } = Brushes.LightGray;
    }
}
