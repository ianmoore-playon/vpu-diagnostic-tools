using System.Windows;
using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.ViewModels.Stub
{
    /// <summary>
    /// Shared status-pill plumbing for every panel viewmodel. Owns
    /// StatusLabel / StatusColor / StatusBg so the section-header XAML can
    /// bind to the same names on every panel.
    /// Lives under Stub/ alongside the mock viewmodels because Agent B will
    /// promote this to a top-level ViewModelBase when the real services land.
    /// </summary>
    public abstract class StatusViewModelBase : ObservableObject
    {
        private string _statusLabel = "Ready";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }

        private Brush _statusColor;
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }

        private Brush _statusBg;
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        protected StatusViewModelBase()
        {
            // Default to a neutral "Ready" pill until the panel produces a
            // real status. App.Current.Resources is guaranteed populated by
            // the time a VM is constructed because App.xaml merges its
            // dictionaries before MainWindow's DataContext resolves.
            _statusColor = (Brush)Application.Current.Resources["MutedForegroundBrush"];
            _statusBg    = (Brush)Application.Current.Resources["BorderColBrush"];
        }

        /// <summary>
        /// Convenience setter for the three "All Clear / Warning / Critical"
        /// states a panel typically produces. Stub VMs use this to compose a
        /// realistic-looking pill from mock data.
        /// </summary>
        protected void SetStatus(string label, string brushKey, string bgKey)
        {
            StatusLabel = label;
            StatusColor = (Brush)Application.Current.Resources[brushKey];
            StatusBg    = (Brush)Application.Current.Resources[bgKey];
        }
    }
}
