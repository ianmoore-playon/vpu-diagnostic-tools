using System.Windows;
using System.Windows.Controls;

namespace Pulse.WPF.Controls
{
    /// <summary>
    /// Title + subtitle + StatusPill. Used at the top of every panel so
    /// the layout is consistent without copy-pasting the DockPanel each
    /// time.
    /// </summary>
    public partial class SectionHeader : UserControl
    {
        public static readonly DependencyProperty TitleProperty =
            DependencyProperty.Register(nameof(Title), typeof(string), typeof(SectionHeader),
                new PropertyMetadata(""));

        public static readonly DependencyProperty SubtitleProperty =
            DependencyProperty.Register(nameof(Subtitle), typeof(string), typeof(SectionHeader),
                new PropertyMetadata(""));

        public static readonly DependencyProperty StatusLabelProperty =
            DependencyProperty.Register(nameof(StatusLabel), typeof(string), typeof(SectionHeader),
                new PropertyMetadata(""));

        public static readonly DependencyProperty StatusSeverityProperty =
            DependencyProperty.Register(nameof(StatusSeverity), typeof(string), typeof(SectionHeader),
                new PropertyMetadata("neutral"));

        public string Title
        {
            get => (string)GetValue(TitleProperty);
            set => SetValue(TitleProperty, value);
        }

        public string Subtitle
        {
            get => (string)GetValue(SubtitleProperty);
            set => SetValue(SubtitleProperty, value);
        }

        public string StatusLabel
        {
            get => (string)GetValue(StatusLabelProperty);
            set => SetValue(StatusLabelProperty, value);
        }

        public string StatusSeverity
        {
            get => (string)GetValue(StatusSeverityProperty);
            set => SetValue(StatusSeverityProperty, value);
        }

        public SectionHeader()
        {
            InitializeComponent();
        }
    }
}
