using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// Severity for a Finding row in the Findings banner.
    /// Order matters — used for "worst-of" status aggregation.
    /// </summary>
    public enum FindingSeverity
    {
        Info     = 0,
        Warning  = 1,
        Critical = 2
    }

    /// <summary>
    /// One row in the Findings banner. Per the UX review every Warning/Critical
    /// must include a plain-English Title AND a Recommendation that tells the
    /// support agent what to do next.
    /// </summary>
    public class Finding : ObservableObject
    {
        private FindingSeverity _severity = FindingSeverity.Warning;
        public FindingSeverity Severity { get => _severity; set => Set(ref _severity, value); }

        private string _title = "";
        public string Title { get => _title; set => Set(ref _title, value); }

        private string _recommendation = "";
        public string Recommendation { get => _recommendation; set => Set(ref _recommendation, value); }

        /// <summary>
        /// Optional one-word category shown as a chip on the left of the row
        /// (e.g. "Network", "Power", "Disk"). Null hides the chip.
        /// </summary>
        private string _category;
        public string Category { get => _category; set => Set(ref _category, value); }

        // Resolved colors so the XAML can bind without converters. Stub VMs
        // populate these via SetSeverity() so the colors stay in lockstep
        // with the brushes defined in Colors.xaml.
        private Brush _severityColor;
        public Brush SeverityColor { get => _severityColor; set => Set(ref _severityColor, value); }

        private Brush _severityBg;
        public Brush SeverityBg { get => _severityBg; set => Set(ref _severityBg, value); }

        private string _severityLabel = "Warning";
        public string SeverityLabel { get => _severityLabel; set => Set(ref _severityLabel, value); }

        /// <summary>
        /// One-shot helper so the stub VMs (and later the real diagnostics)
        /// can set severity + the matching brushes in one call.
        /// </summary>
        public void Apply(FindingSeverity sev, string title, string recommendation, string category = null)
        {
            Severity = sev;
            Title = title;
            Recommendation = recommendation;
            Category = category;

            switch (sev)
            {
                case FindingSeverity.Critical:
                    SeverityLabel = "Critical";
                    SeverityColor = (Brush)System.Windows.Application.Current.Resources["RedBrush"];
                    SeverityBg    = (Brush)System.Windows.Application.Current.Resources["ErrBgBrush"];
                    break;
                case FindingSeverity.Warning:
                    SeverityLabel = "Warning";
                    SeverityColor = (Brush)System.Windows.Application.Current.Resources["YellowBrush"];
                    SeverityBg    = (Brush)System.Windows.Application.Current.Resources["WarnBgBrush"];
                    break;
                default:
                    SeverityLabel = "Info";
                    SeverityColor = (Brush)System.Windows.Application.Current.Resources["AccentBrush"];
                    SeverityBg    = (Brush)System.Windows.Application.Current.Resources["BorderColBrush"];
                    break;
            }
        }

        /// <summary>
        /// Convenience factory that accepts the severity as a string ("Critical",
        /// "Warning", "Info"). Used by the diagnostic ViewModels (Network,
        /// Hardware, Services, DiskHealth, SystemOverview) which build Findings
        /// from service results where severity is a string.
        /// </summary>
        public static Finding Create(string severity, string title, string recommendation, string category = null)
        {
            FindingSeverity sev;
            switch ((severity ?? "").Trim().ToLowerInvariant())
            {
                case "critical": case "fail":  sev = FindingSeverity.Critical; break;
                case "warning":  case "warn":  sev = FindingSeverity.Warning;  break;
                default:                       sev = FindingSeverity.Info;     break;
            }
            var f = new Finding();
            f.Apply(sev, title, recommendation, category);
            return f;
        }
    }
}
