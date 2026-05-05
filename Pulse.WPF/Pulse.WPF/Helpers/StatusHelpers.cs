using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using Pulse.WPF.Models;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Cross-VM helpers: severity priority comparison, brush resolution from
    /// the active app resources, and overall-status pill computation. Keeps
    /// every panel ViewModel from re-implementing the same plumbing.
    /// </summary>
    public static class StatusHelpers
    {
        // Worse-than ordering: Critical > Warning > Info. Used to roll up a
        // panel's overall pill from its Findings list.
        public static int SeverityRank(string s)
        {
            if (s == "Critical") return 3;
            if (s == "Warning") return 2;
            if (s == "Info") return 1;
            return 0;
        }

        // Find the worst severity across a list of Findings, "" when empty.
        public static string WorstSeverity(IEnumerable<Finding> findings)
        {
            string worst = "";
            int rank = 0;
            foreach (var f in findings)
            {
                int r = SeverityRank(f.Severity);
                if (r > rank) { rank = r; worst = f.Severity; }
            }
            return worst;
        }

        // Resolve a brush key from Application.Current.Resources, with a fallback.
        // Application.Current can be null in design-time / unit-test paths, so
        // we tolerate that and return Brushes.Gray instead of throwing.
        public static Brush Brush(string key)
        {
            try
            {
                var app = Application.Current;
                if (app != null && app.Resources != null && app.Resources.Contains(key))
                {
                    return app.Resources[key] as Brush ?? Brushes.Gray;
                }
            }
            catch { }
            return Brushes.Gray;
        }

        // Map worst-severity to (label, foreground brush, background brush)
        // for the section-header pill. Uses the resource keys defined in
        // Themes/Colors.xaml.
        public static (string Label, Brush Fg, Brush Bg) PillFor(string worst, int warningCount, int criticalCount)
        {
            if (worst == "Critical")
            {
                var label = criticalCount == 1 ? "Critical" : $"{criticalCount} Critical";
                return (label, Brush("RedBrush"), Brush("ErrBgBrush"));
            }
            if (worst == "Warning")
            {
                var label = warningCount == 1 ? "1 Warning" : $"{warningCount} Warnings";
                return (label, Brush("YellowBrush"), Brush("WarnBgBrush"));
            }
            return ("All Clear", Brush("GreenBrush"), Brush("OkBgBrush"));
        }

        // Resolve a foreground brush for a LogEntry "Level" string.
        public static Brush BrushForLogLevel(string level)
        {
            switch (level)
            {
                case "Pass": return Brush("GreenBrush");
                case "Fail": return Brush("RedBrush");
                case "Warn": return Brush("YellowBrush");
                case "Section": return Brush("AccentBrush");
                case "Gray": return Brush("MutedForegroundBrush");
                default: return Brush("ForegroundBrush");
            }
        }
    }
}
