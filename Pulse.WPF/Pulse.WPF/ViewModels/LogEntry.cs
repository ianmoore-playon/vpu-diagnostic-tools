using System;
using System.Windows.Media;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// One row in the Live Log card. Plain DTO — once added to the
    /// ObservableCollection the XAML renders it automatically.
    /// </summary>
    public class LogEntry
    {
        public DateTime Timestamp { get; set; } = DateTime.Now;
        public string   Label     { get; set; } = "";
        public string   Result    { get; set; } = "";
        public string   Level     { get; set; } = "Info";   // Info, Pass, Warn, Fail, Section, Gray, Cyan

        // Resolved foreground color for the result text — set in CameraConnectivityViewModel
        // when entries are added so XAML can bind to it directly.
        public Brush ResultColor { get; set; } = Brushes.LightGray;
    }
}
