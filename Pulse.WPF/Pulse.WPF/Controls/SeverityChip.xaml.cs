using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Pulse.WPF.Controls
{
    /// <summary>
    /// Small inline chip for tables and findings rows. Reuses the same
    /// severity vocabulary as <see cref="StatusPill"/>.
    /// </summary>
    public partial class SeverityChip : UserControl
    {
        public static readonly DependencyProperty SeverityProperty =
            DependencyProperty.Register(nameof(Severity), typeof(string), typeof(SeverityChip),
                new PropertyMetadata("neutral", OnAnyChanged));

        public static readonly DependencyProperty TextProperty =
            DependencyProperty.Register(nameof(Text), typeof(string), typeof(SeverityChip),
                new PropertyMetadata(""));

        public static readonly DependencyProperty ResolvedBgProperty =
            DependencyProperty.Register(nameof(ResolvedBg), typeof(Brush), typeof(SeverityChip),
                new PropertyMetadata(null));

        public static readonly DependencyProperty ResolvedFgProperty =
            DependencyProperty.Register(nameof(ResolvedFg), typeof(Brush), typeof(SeverityChip),
                new PropertyMetadata(null));

        public string Severity
        {
            get => (string)GetValue(SeverityProperty);
            set => SetValue(SeverityProperty, value);
        }

        public string Text
        {
            get => (string)GetValue(TextProperty);
            set => SetValue(TextProperty, value);
        }

        public Brush ResolvedBg
        {
            get => (Brush)GetValue(ResolvedBgProperty);
            private set => SetValue(ResolvedBgProperty, value);
        }

        public Brush ResolvedFg
        {
            get => (Brush)GetValue(ResolvedFgProperty);
            private set => SetValue(ResolvedFgProperty, value);
        }

        public SeverityChip()
        {
            InitializeComponent();
            Loaded += (_, __) => ResolveBrushes();
        }

        private static void OnAnyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
            => ((SeverityChip)d).ResolveBrushes();

        private void ResolveBrushes()
        {
            var res = Application.Current?.Resources;
            if (res == null) return;

            string sev = (Severity ?? "neutral").Trim().ToLowerInvariant();
            switch (sev)
            {
                case "ok":
                case "pass":
                    ResolvedFg = (Brush)res["GreenBrush"];
                    ResolvedBg = (Brush)res["OkBgBrush"];
                    break;
                case "warn":
                case "warning":
                    ResolvedFg = (Brush)res["YellowBrush"];
                    ResolvedBg = (Brush)res["WarnBgBrush"];
                    break;
                case "fail":
                case "error":
                    ResolvedFg = (Brush)res["RedBrush"];
                    ResolvedBg = (Brush)res["ErrBgBrush"];
                    break;
                case "critical":
                    ResolvedFg = (Brush)res["CriticalBrush"];
                    ResolvedBg = (Brush)res["CriticalBgBrush"];
                    break;
                case "info":
                case "running":
                    ResolvedFg = (Brush)res["InfoBrush"];
                    ResolvedBg = (Brush)res["InfoBgBrush"];
                    break;
                default:
                    ResolvedFg = (Brush)res["MutedForegroundBrush"];
                    ResolvedBg = (Brush)res["BorderColBrush"];
                    break;
            }
        }
    }
}
