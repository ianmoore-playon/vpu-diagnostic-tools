using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Pulse.WPF.Controls
{
    /// <summary>
    /// Status pill — used as the section-header indicator on every panel.
    /// Bind <see cref="Label"/> + <see cref="Severity"/>; the control
    /// resolves the matching theme brushes itself so the host doesn't have
    /// to track per-state colors.
    /// </summary>
    public partial class StatusPill : UserControl
    {
        public static readonly DependencyProperty LabelProperty =
            DependencyProperty.Register(nameof(Label), typeof(string), typeof(StatusPill),
                new PropertyMetadata(""));

        public static readonly DependencyProperty SeverityProperty =
            DependencyProperty.Register(nameof(Severity), typeof(string), typeof(StatusPill),
                new PropertyMetadata("neutral", OnSeverityChanged));

        public static readonly DependencyProperty ResolvedBgProperty =
            DependencyProperty.Register(nameof(ResolvedBg), typeof(Brush), typeof(StatusPill),
                new PropertyMetadata(null));

        public static readonly DependencyProperty ResolvedFgProperty =
            DependencyProperty.Register(nameof(ResolvedFg), typeof(Brush), typeof(StatusPill),
                new PropertyMetadata(null));

        public string Label
        {
            get => (string)GetValue(LabelProperty);
            set => SetValue(LabelProperty, value);
        }

        /// <summary>"ok" / "warn" / "fail" / "neutral" / "running".</summary>
        public string Severity
        {
            get => (string)GetValue(SeverityProperty);
            set => SetValue(SeverityProperty, value);
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

        public StatusPill()
        {
            InitializeComponent();
            Loaded += (_, __) => ResolveBrushes();
        }

        private static void OnSeverityChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            ((StatusPill)d).ResolveBrushes();
        }

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
                default: // neutral
                    ResolvedFg = (Brush)res["MutedForegroundBrush"];
                    ResolvedBg = (Brush)res["BorderColBrush"];
                    break;
            }
        }
    }
}
