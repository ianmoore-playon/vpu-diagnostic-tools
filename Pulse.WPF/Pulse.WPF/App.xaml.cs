using System.Windows;
using Pulse.WPF.ViewModels;

namespace Pulse.WPF
{
    public partial class App : Application
    {
        /// <summary>
        /// Cross-tab navigation hook. The Camera Connectivity panel uses this
        /// for its "Go to Network" recommendation button — keeps the wiring
        /// trivial without standing up an INavigationService for one caller.
        ///
        /// Walks up to the active MainWindow's DataContext (which is always a
        /// <see cref="MainViewModel"/>) and sets <c>SelectedNav</c>. No-ops
        /// silently if the window isn't a MainWindow yet (design-time, etc.).
        /// </summary>
        public static void NavigateToTab(string key)
        {
            if (string.IsNullOrWhiteSpace(key)) return;
            var win = Current?.MainWindow;
            if (win?.DataContext is MainViewModel mvm)
            {
                mvm.SelectedNav = key;
            }
        }
    }
}
