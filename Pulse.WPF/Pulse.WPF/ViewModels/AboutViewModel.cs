using System;
using System.Diagnostics;
using System.Windows.Input;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// About panel (v0.6.7).
    ///
    /// Plain identity card — app name, version, hostname, and a link to
    /// the public release feed. No diagnostic surface here; this panel
    /// exists so the sidebar entry is no longer dead.
    /// </summary>
    public class AboutViewModel : ObservableObject
    {
        /// <summary>Reads from Helpers/AppVersion which already surfaces the
        /// assembly's InformationalVersion.</summary>
        public string VersionDisplay => AppVersion.Display;

        /// <summary>Tooltip on the version line — full version + commit SHA
        /// when AppVersion.Tooltip is populated.</summary>
        public string VersionTooltip => AppVersion.Tooltip;

        public string MachineName    => Environment.MachineName;
        public string OsDescription  => Environment.OSVersion.ToString();

        public ICommand OpenReleasesCommand { get; }
        public ICommand OpenSourceRepoCommand { get; }

        public AboutViewModel()
        {
            OpenReleasesCommand = new RelayCommand(() => SafeOpenUrl(
                "https://github.com/ianmoore-playon/pulse-releases"));
            OpenSourceRepoCommand = new RelayCommand(() => SafeOpenUrl(
                "https://github.com/ianmoore-playon/vpu-diagnostic-tools"));
        }

        private static void SafeOpenUrl(string url)
        {
            try
            {
                var psi = new ProcessStartInfo(url) { UseShellExecute = true };
                Process.Start(psi);
            }
            catch { /* no toast surface on this panel — swallow */ }
        }
    }
}
