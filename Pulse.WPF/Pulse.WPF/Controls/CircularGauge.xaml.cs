using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Pulse.WPF.Controls
{
    /// <summary>
    /// Circular percentage gauge for the Dashboard system-status row.
    /// Bind Percent (0..100), Caption (small text below the percentage),
    /// optional ValueBrush (foreground arc + percentage text colour) +
    /// TrackBrush (background ring colour). Default sizes match the
    /// Pixellot reference dashboard (78px diameter, 6px stroke).
    /// </summary>
    public partial class CircularGauge : UserControl
    {
        public CircularGauge()
        {
            InitializeComponent();
            // Defaults: diameter, thickness, colours.
            Diameter      = 78;
            Thickness     = 6;
            ValueFontSize = 16;
            TrackBrush    = (Brush)(TryFindResource("BorderColBrush") ?? Brushes.Gray);
            ValueBrush    = (Brush)(TryFindResource("AccentBrush")   ?? Brushes.DodgerBlue);
            CaptionBrush  = (Brush)(TryFindResource("MutedForegroundBrush") ?? Brushes.Gray);
            // Initial render so the control isn't blank in the designer.
            Loaded += (_, __) => Redraw();
        }

        // ---- Dependency properties ----
        public static readonly DependencyProperty PercentProperty = DependencyProperty.Register(
            nameof(Percent), typeof(double), typeof(CircularGauge),
            new PropertyMetadata(0.0, OnPercentChanged));
        public double Percent
        {
            get => (double)GetValue(PercentProperty);
            set => SetValue(PercentProperty, value);
        }

        public static readonly DependencyProperty DiameterProperty = DependencyProperty.Register(
            nameof(Diameter), typeof(double), typeof(CircularGauge),
            new PropertyMetadata(78.0, (d, _) => ((CircularGauge)d).Redraw()));
        public double Diameter
        {
            get => (double)GetValue(DiameterProperty);
            set => SetValue(DiameterProperty, value);
        }

        public static readonly DependencyProperty ThicknessProperty = DependencyProperty.Register(
            nameof(Thickness), typeof(double), typeof(CircularGauge),
            new PropertyMetadata(6.0, (d, _) => ((CircularGauge)d).Redraw()));
        public double Thickness
        {
            get => (double)GetValue(ThicknessProperty);
            set => SetValue(ThicknessProperty, value);
        }

        public static readonly DependencyProperty CaptionProperty = DependencyProperty.Register(
            nameof(Caption), typeof(string), typeof(CircularGauge),
            new PropertyMetadata(""));
        public string Caption
        {
            get => (string)GetValue(CaptionProperty);
            set => SetValue(CaptionProperty, value);
        }

        public static readonly DependencyProperty ValueTextProperty = DependencyProperty.Register(
            nameof(ValueText), typeof(string), typeof(CircularGauge),
            new PropertyMetadata(""));
        public string ValueText
        {
            get => (string)GetValue(ValueTextProperty);
            set => SetValue(ValueTextProperty, value);
        }

        public static readonly DependencyProperty ValueBrushProperty = DependencyProperty.Register(
            nameof(ValueBrush), typeof(Brush), typeof(CircularGauge),
            new PropertyMetadata(Brushes.DodgerBlue));
        public Brush ValueBrush
        {
            get => (Brush)GetValue(ValueBrushProperty);
            set => SetValue(ValueBrushProperty, value);
        }

        public static readonly DependencyProperty TrackBrushProperty = DependencyProperty.Register(
            nameof(TrackBrush), typeof(Brush), typeof(CircularGauge),
            new PropertyMetadata(Brushes.LightGray));
        public Brush TrackBrush
        {
            get => (Brush)GetValue(TrackBrushProperty);
            set => SetValue(TrackBrushProperty, value);
        }

        public static readonly DependencyProperty CaptionBrushProperty = DependencyProperty.Register(
            nameof(CaptionBrush), typeof(Brush), typeof(CircularGauge),
            new PropertyMetadata(Brushes.Gray));
        public Brush CaptionBrush
        {
            get => (Brush)GetValue(CaptionBrushProperty);
            set => SetValue(CaptionBrushProperty, value);
        }

        public static readonly DependencyProperty ValueFontSizeProperty = DependencyProperty.Register(
            nameof(ValueFontSize), typeof(double), typeof(CircularGauge),
            new PropertyMetadata(16.0));
        public double ValueFontSize
        {
            get => (double)GetValue(ValueFontSizeProperty);
            set => SetValue(ValueFontSizeProperty, value);
        }

        // ---- Geometry ----
        private static void OnPercentChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
            => ((CircularGauge)d).Redraw();

        private void Redraw()
        {
            if (ValueArc == null) return;
            var pct  = Math.Max(0, Math.Min(100, Percent));
            var diam = Math.Max(4, Diameter);
            var th   = Math.Max(1, Thickness);
            var r    = (diam - th) / 2;
            var cx   = diam / 2;
            var cy   = diam / 2;

            if (pct <= 0)
            {
                ValueArc.Data = null;
                return;
            }

            // Sweep starts at 12 o'clock (-90°) and goes clockwise pct/100 of 360°.
            var startAngle = -90.0;
            var sweep      = (pct / 100.0) * 360.0;
            var endAngle   = startAngle + sweep;

            // For a near-full circle, ArcSegment with IsLargeArc + a single
            // segment renders fine. For >= 360° we have to split into two
            // semicircle segments because ArcSegment can't span ≥360°.
            var fig = new PathFigure
            {
                StartPoint = PointOnCircle(cx, cy, r, startAngle),
                IsClosed   = false,
            };
            if (sweep >= 359.99)
            {
                // Two halves so the arc renders as a full ring.
                fig.Segments.Add(new ArcSegment(
                    PointOnCircle(cx, cy, r, startAngle + 180), new Size(r, r), 0,
                    false, SweepDirection.Clockwise, true));
                fig.Segments.Add(new ArcSegment(
                    PointOnCircle(cx, cy, r, startAngle + 359.9), new Size(r, r), 0,
                    false, SweepDirection.Clockwise, true));
            }
            else
            {
                fig.Segments.Add(new ArcSegment(
                    PointOnCircle(cx, cy, r, endAngle), new Size(r, r), 0,
                    sweep > 180, SweepDirection.Clockwise, true));
            }
            var geom = new PathGeometry();
            geom.Figures.Add(fig);
            ValueArc.Data = geom;
        }

        private static Point PointOnCircle(double cx, double cy, double r, double angleDeg)
        {
            var rad = angleDeg * Math.PI / 180.0;
            return new Point(cx + r * Math.Cos(rad), cy + r * Math.Sin(rad));
        }
    }
}
