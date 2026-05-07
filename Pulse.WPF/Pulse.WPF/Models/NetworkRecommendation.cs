using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One actionable recommendation rendered in the Network panel's
    /// "Recommended Actions" card. Built fresh after every RunTestAsync —
    /// one row per failure (no internet ping, blocked port, unreachable
    /// domain) plus an all-good row when nothing failed.
    ///
    /// Distinct from <see cref="Finding"/>: Findings drive the page-header
    /// pill and the top-of-page banner (aggregate severity), while
    /// Recommendations are per-failure, prescriptive copy that tells the
    /// support agent exactly what to ask the venue to whitelist or unblock.
    /// </summary>
    public class NetworkRecommendation : ObservableObject
    {
        // Properties are observable so the in-place delta-update path in
        // CameraConnectivityViewModel.BuildRecommendations() can mutate
        // existing rows on a tick instead of clearing-and-rebuilding the
        // whole ObservableCollection (the source of the v0.4.5 flicker).
        private string _title = "";
        public string Title { get => _title; set => Set(ref _title, value); }

        private string _body = "";
        public string Body { get => _body; set => Set(ref _body, value); }

        private string _severity = "Info";   // "Critical" / "Warning" / "Info" / "OK"
        public string Severity { get => _severity; set => Set(ref _severity, value); }

        // Resolved colors so the XAML can bind without converters.
        private Brush _severityColor;
        public Brush SeverityColor { get => _severityColor; set => Set(ref _severityColor, value); }

        private Brush _severityBg;
        public Brush SeverityBg { get => _severityBg; set => Set(ref _severityBg, value); }

        // Optional inline button — when set, the Recommendations template renders
        // an outlined button with this label and command. Camera Connectivity uses
        // these for "Go to Network" / "Open cameras.cfg" cross-tab jumps.
        private string _actionLabel;
        public string ActionLabel { get => _actionLabel; set => Set(ref _actionLabel, value); }

        private ICommand _actionCommand;
        public ICommand ActionCommand { get => _actionCommand; set => Set(ref _actionCommand, value); }

        /// <summary>
        /// Stable identity hash used by the VM's equality short-circuit when
        /// deciding whether to skip the whole rebuild.
        /// </summary>
        public int RowHash()
        {
            unchecked
            {
                int h = 17;
                h = h * 31 + (Severity?.GetHashCode() ?? 0);
                h = h * 31 + (Title?.GetHashCode() ?? 0);
                h = h * 31 + (Body?.GetHashCode() ?? 0);
                return h;
            }
        }

        /// <summary>
        /// In-place mutate from a freshly-built sibling. Severity, brushes,
        /// title, body, action — but the action callback is preserved across
        /// re-applies because RelayCommand instances are stable on the VM.
        /// </summary>
        public void ApplyFrom(NetworkRecommendation other)
        {
            if (other == null) return;
            Title         = other.Title;
            Body          = other.Body;
            Severity      = other.Severity;
            SeverityColor = other.SeverityColor;
            SeverityBg    = other.SeverityBg;
            ActionLabel   = other.ActionLabel;
            ActionCommand = other.ActionCommand;
        }

        public static NetworkRecommendation Create(string severity, string title, string body)
        {
            var r = new NetworkRecommendation { Title = title, Body = body };
            switch ((severity ?? "").Trim().ToLowerInvariant())
            {
                case "critical":
                case "fail":
                    r.Severity = "Critical";
                    r.SeverityColor = StatusHelpers.Brush("RedBrush");
                    r.SeverityBg    = StatusHelpers.Brush("ErrBgBrush");
                    break;
                case "warning":
                case "warn":
                    r.Severity = "Warning";
                    r.SeverityColor = StatusHelpers.Brush("YellowBrush");
                    r.SeverityBg    = StatusHelpers.Brush("WarnBgBrush");
                    break;
                case "ok":
                case "pass":
                case "success":
                    r.Severity = "OK";
                    r.SeverityColor = StatusHelpers.Brush("GreenBrush");
                    r.SeverityBg    = StatusHelpers.Brush("OkBgBrush");
                    break;
                default:
                    r.Severity = "Info";
                    r.SeverityColor = StatusHelpers.Brush("AccentBrush");
                    r.SeverityBg    = StatusHelpers.Brush("BorderColBrush");
                    break;
            }
            return r;
        }
    }
}
