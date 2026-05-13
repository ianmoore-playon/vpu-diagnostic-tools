using System.Windows.Controls;

namespace Pulse.WPF.Views
{
    /// <summary>
    /// Settings panel (v0.6.7). Code-behind is intentionally empty —
    /// every interaction is bound to commands on <see cref="ViewModels.SettingsViewModel"/>.
    /// </summary>
    public partial class SettingsView : UserControl
    {
        public SettingsView()
        {
            InitializeComponent();
        }
    }
}
