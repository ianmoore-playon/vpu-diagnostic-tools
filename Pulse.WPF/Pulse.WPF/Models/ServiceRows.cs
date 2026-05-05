using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One row in the Pixellot Services / System Dependencies cards. Mirrors
    /// what PixellotServices.psm1 renders: name, a status pill, last-start
    /// time, and start mode (Automatic / Manual / Disabled).
    /// </summary>
    public class ServiceStatusRow : ObservableObject
    {
        public string Name        { get; set; } = "";
        public string DisplayName { get; set; } = "";
        public string Status      { get; set; } = "";   // "Running", "Stopped", "Stopping"
        public string StartMode   { get; set; } = "";   // "Automatic", "Manual", "Disabled"
        public string LastStarted { get; set; } = "";   // "2h 14m ago"
        public string Note        { get; set; } = "";   // "Restarted 3× in 24h" / etc.

        public Brush  StatusColor { get; set; }
        public Brush  StatusBg    { get; set; }
    }
}
