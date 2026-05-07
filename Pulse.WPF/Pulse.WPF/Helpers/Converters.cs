using System;
using System.Collections;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Bool -> Visibility converter. Pass "Invert" as ConverterParameter
    /// to flip the result (true => Collapsed, false => Visible).
    /// </summary>
    public class BoolToVisibilityConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            bool b = value is bool v && v;
            if (parameter is string p && p.Equals("Invert", StringComparison.OrdinalIgnoreCase))
                b = !b;
            return b ? Visibility.Visible : Visibility.Collapsed;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
            => value is Visibility v && v == Visibility.Visible;
    }

    /// <summary>
    /// Hides a control when the bound collection is empty (or null).
    /// Used by FindingsBanner so it disappears entirely when there's
    /// nothing to show.
    /// </summary>
    public class CountToVisibilityConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            int count = value switch
            {
                null => 0,
                int i => i,
                ICollection c => c.Count,
                _ => 0
            };
            return count > 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
            => Binding.DoNothing;
    }

    /// <summary>
    /// Halve a numeric value (with a 16 px gap subtracted) so a WrapPanel
    /// row of two cards lays out as 2-up at wide widths and 1-up at narrow
    /// widths. Returns at least 320 to avoid a card collapsing to nothing.
    /// </summary>
    public class HalfWidthConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            double w = 0;
            try { w = System.Convert.ToDouble(value); } catch { }
            // Subtract one inter-card gap (16) and a small safety margin (4) so
            // two cards plus the gap exactly fit the available width.
            double half = (w - 20) / 2.0;
            if (half < 320) return w > 320 ? w - 4 : 320; // collapse to one column
            return half;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
            => Binding.DoNothing;
    }

    /// <summary>
    /// Convert <see cref="System.Windows.Controls.ItemsControl.AlternationIndex"/>
    /// (0-based) into a 1-based ordinal string for the NIC card diagram's
    /// per-jack port-number badge.
    /// </summary>
    public class AlternationIndexToOrdinalConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            int idx = 0;
            try { idx = System.Convert.ToInt32(value); } catch { }
            return (idx + 1).ToString(CultureInfo.InvariantCulture);
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
            => Binding.DoNothing;
    }

    /// <summary>
    /// Null/empty string -> Collapsed, otherwise Visible. Used by the
    /// SectionHeader subtitle and StatusPill so an empty value hides
    /// the element instead of leaving a gap.
    /// </summary>
    public class StringToVisibilityConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            var s = value as string;
            return string.IsNullOrWhiteSpace(s) ? Visibility.Collapsed : Visibility.Visible;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
            => Binding.DoNothing;
    }
}
