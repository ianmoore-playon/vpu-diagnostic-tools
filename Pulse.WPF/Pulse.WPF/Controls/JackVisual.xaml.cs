using System.Windows;
using System.Windows.Controls;

namespace Pulse.WPF.Controls
{
    /// <summary>
    /// One RJ45 jack rendering for the NIC card diagram. The DataContext is a
    /// <see cref="ViewModels.PortViewModel"/>; the only extra knob is
    /// <see cref="PortNumberLabel"/> which we set from the parent's
    /// AlternationIndex so the badge under the jack reads "1"/"2"/"3"/"4".
    /// </summary>
    public partial class JackVisual : UserControl
    {
        public static readonly DependencyProperty PortNumberLabelProperty =
            DependencyProperty.Register(
                nameof(PortNumberLabel),
                typeof(string),
                typeof(JackVisual),
                new PropertyMetadata("1"));

        public string PortNumberLabel
        {
            get => (string)GetValue(PortNumberLabelProperty);
            set => SetValue(PortNumberLabelProperty, value);
        }

        public JackVisual()
        {
            InitializeComponent();
        }
    }
}
