using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One tile in the System Overview hub grid. Each tile describes a panel
    /// the user can navigate to, plus a one-word status (Healthy / Warnings /
    /// Critical / Unknown) populated from the last full diagnostic run.
    /// </summary>
    public class HubTileViewModel : ObservableObject
    {
        public string Title        { get; set; } = "";
        public string Description  { get; set; } = "";
        public string IconKind     { get; set; } = "Help";   // MaterialDesignThemes PackIcon kind
        public string NavKey       { get; set; } = "";       // "Home", "Network", "Camera", etc.

        // Aliases used by SystemOverviewService — IconKey ↔ IconKind, TargetNav ↔ NavKey.
        // Both the Agent A models and Agent B services were built against my spec
        // but with different field names; adding aliases keeps everyone honest.
        public string IconKey   { get => IconKind; set => IconKind = value; }
        public string TargetNav { get => NavKey;   set => NavKey   = value; }

        private string _statusText = "Not run";
        public string StatusText { get => _statusText; set => Set(ref _statusText, value); }

        private Brush _statusColor;
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }

        private Brush _statusBg;
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        public ICommand NavigateCommand { get; set; }
    }
}
