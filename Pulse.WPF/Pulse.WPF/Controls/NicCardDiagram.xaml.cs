using System.Collections;
using System.Windows;
using System.Windows.Controls;

namespace Pulse.WPF.Controls
{
    /// <summary>
    /// Schematic of the camera-NIC card body — four RJ45 jacks across the top
    /// + connector lines stubbing down to the tile row underneath. Pure
    /// presentation: bind <see cref="Ports"/> to the same
    /// <c>ObservableCollection&lt;PortViewModel&gt;</c> the tile UniformGrid
    /// uses, and set this UserControl directly above that grid inside the
    /// same Card so the four columns align.
    /// </summary>
    public partial class NicCardDiagram : UserControl
    {
        public static readonly DependencyProperty PortsProperty =
            DependencyProperty.Register(
                nameof(Ports),
                typeof(IEnumerable),
                typeof(NicCardDiagram),
                new PropertyMetadata(null));

        public IEnumerable Ports
        {
            get => (IEnumerable)GetValue(PortsProperty);
            set => SetValue(PortsProperty, value);
        }

        public NicCardDiagram()
        {
            InitializeComponent();
        }
    }
}
