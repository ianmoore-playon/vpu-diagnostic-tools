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
        public string Title { get; set; } = "";
        public string Body { get; set; } = "";
        public string Severity { get; set; } = "Info";   // "Critical" / "Warning" / "Info" / "OK"

        // Resolved colors so the XAML can bind without converters.
        public Brush SeverityColor { get; set; }
        public Brush SeverityBg { get; set; }

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
