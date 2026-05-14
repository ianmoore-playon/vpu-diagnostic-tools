using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One row in the Pixellot process / Windows service cards. Process rows
    /// are observational only; restart actions are only available when
    /// ServiceName is populated with a real SCM service name.
    /// </summary>
    public class ServiceStatusRow : ObservableObject
    {
        public string Name        { get; set; } = "";
        public string DisplayName { get; set; } = "";
        public string Status      { get; set; } = "";   // "Running", "Stopped", "Stopping"
        public string StartMode   { get; set; } = "";   // "Automatic", "Manual", "Disabled"
        public string LastStarted { get; set; } = "";   // "2h 14m ago"
        public string Note        { get; set; } = "";   // "Restarted 3× in 24h" / etc.
        public string RowKind     { get; set; } = "";   // "Process" / "Windows service"
        public string ServiceName { get; set; } = "";   // SCM name used by sc.exe restart
        public string RestartUnavailableReason { get; set; } = "";

        public Brush  StatusColor { get; set; }
        public Brush  StatusBg    { get; set; }

        // Aliases used by ServicesService / ServicesViewModel which were built
        // against a slightly different field-name spec. Detail ↔ Note, plus a
        // free-form Severity string ("Pass" / "Warn" / "Fail" / "Gray") for
        // VM-side aggregation. Severity is a string here so the existing
        // service code that does `Severity = "Pass"` keeps compiling.
        public string Detail   { get => Note; set => Note = value; }
        public string Severity { get; set; } = "";

        public bool IsWindowsService =>
            string.Equals(RowKind, "Windows service", System.StringComparison.OrdinalIgnoreCase);

        public bool CanRestart => !string.IsNullOrWhiteSpace(ServiceName);

        public string RestartAvailability
        {
            get
            {
                if (CanRestart) return $"Available ({ServiceName})";
                if (!string.IsNullOrWhiteSpace(RestartUnavailableReason)) return RestartUnavailableReason;
                return IsWindowsService ? "Service name unavailable" : "Process only";
            }
        }
    }
}
