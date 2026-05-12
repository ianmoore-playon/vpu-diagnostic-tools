using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Pulse.WPF.ViewModels;

namespace Pulse.WPF.Views
{
    public partial class CameraConnectivityView : UserControl
    {
        public CameraConnectivityView()
        {
            InitializeComponent();
        }

        // v0.5.2 §6: each port tile is clickable. The handler asks the
        // panel VM to construct the AdapterDetailsViewModel and shows the
        // dialog modally (owner = MainWindow). Code-behind kept tiny —
        // all the population logic lives on the VM.
        private void PortTile_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
        {
            if (!(sender is FrameworkElement el)) return;
            if (!(el.DataContext is PortViewModel port)) return;
            if (!(DataContext is CameraConnectivityViewModel vm)) return;

            vm.OpenAdapterDetails(port);
        }
    }
}
