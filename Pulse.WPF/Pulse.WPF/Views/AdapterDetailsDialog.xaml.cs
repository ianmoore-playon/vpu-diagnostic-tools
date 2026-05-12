using System.Windows;
using Pulse.WPF.ViewModels;

namespace Pulse.WPF.Views
{
    /// <summary>
    /// Modal dialog for the per-port "Adapter details" sheet (v0.5.2 §6).
    /// First modal in the project — establishes the reusable
    /// <c>PulseDialogWindow</c> style pattern. Owner is set by the caller
    /// (MainWindow) so the dialog centers correctly.
    /// </summary>
    public partial class AdapterDetailsDialog : Window
    {
        public AdapterDetailsDialog(AdapterDetailsViewModel vm)
        {
            InitializeComponent();
            DataContext = vm;
            // Let the VM's CloseCommand dismiss this Window without the VM
            // having to know about Window.
            vm.CloseAction = () => { try { Close(); } catch { } };
        }
    }
}
