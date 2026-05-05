using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Pulse.WPF.Controls
{
    /// <summary>
    /// Two-column "Label: Value" row used inside cards. Set
    /// <see cref="IsMono"/> to render the value in monospace
    /// (Cascadia Mono / Consolas) — useful for IP / MAC values.
    /// </summary>
    public partial class KeyValueRow : UserControl
    {
        public static readonly DependencyProperty LabelProperty =
            DependencyProperty.Register(nameof(Label), typeof(string), typeof(KeyValueRow),
                new PropertyMetadata(""));

        public static readonly DependencyProperty ValueProperty =
            DependencyProperty.Register(nameof(Value), typeof(string), typeof(KeyValueRow),
                new PropertyMetadata(""));

        public static readonly DependencyProperty ValueColorProperty =
            DependencyProperty.Register(nameof(ValueColor), typeof(Brush), typeof(KeyValueRow),
                new PropertyMetadata(null));

        public static readonly DependencyProperty IsMonoProperty =
            DependencyProperty.Register(nameof(IsMono), typeof(bool), typeof(KeyValueRow),
                new PropertyMetadata(false, OnIsMonoChanged));

        public static readonly DependencyProperty LabelWidthProperty =
            DependencyProperty.Register(nameof(LabelWidth), typeof(GridLength), typeof(KeyValueRow),
                new PropertyMetadata(new GridLength(60)));

        public string Label
        {
            get => (string)GetValue(LabelProperty);
            set => SetValue(LabelProperty, value);
        }

        public string Value
        {
            get => (string)GetValue(ValueProperty);
            set => SetValue(ValueProperty, value);
        }

        public Brush ValueColor
        {
            get => (Brush)GetValue(ValueColorProperty);
            set => SetValue(ValueColorProperty, value);
        }

        public bool IsMono
        {
            get => (bool)GetValue(IsMonoProperty);
            set => SetValue(IsMonoProperty, value);
        }

        public GridLength LabelWidth
        {
            get => (GridLength)GetValue(LabelWidthProperty);
            set => SetValue(LabelWidthProperty, value);
        }

        public KeyValueRow()
        {
            InitializeComponent();
            Loaded += (_, __) => ApplyMono();
            // Default value brush — host can override.
            if (ValueColor == null && Application.Current != null)
                ValueColor = (Brush)Application.Current.Resources["ForegroundBrush"];
        }

        private static void OnIsMonoChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
            => ((KeyValueRow)d).ApplyMono();

        private void ApplyMono()
        {
            if (ValueTextBlock == null) return;
            if (IsMono)
            {
                ValueTextBlock.FontFamily = new FontFamily("Cascadia Mono, Consolas");
                ValueTextBlock.FontSize = 11;
            }
            else
            {
                ClearValue(System.Windows.Controls.Control.FontFamilyProperty);
                ValueTextBlock.FontSize = 13;
            }
        }
    }
}
