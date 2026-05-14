using System.Threading.Tasks;
using System.Windows;
using Pulse.WPF.Helpers;
using Pulse.WPF.Services;
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

        // v0.5.5: kick off the daily-log + Reports-folder retention sweep on
        // startup and stamp a "session start" line into the rolling log so a
        // multi-session log tail is greppable.
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            try
            {
                AppLogFile.Instance.WriteLine("App", "Section",
                    $"App start, version {AppVersion.Display}");
            }
            catch { /* AppLogFile already swallows IO failures */ }

            // Retention sweep — push to a background task so the splash isn't
            // blocked by a slow profile / large Reports folder. 90 days for
            // both the rolling log and the per-run report files; the existing
            // 200-file cap stays as a secondary ceiling on Reports.
            Task.Run(() =>
            {
                try { AppLogFile.Instance.CleanupOlderThan(90); } catch { }
                try
                {
                    var reports = new ReportsService();
                    reports.CleanupOlderThan(90);
                }
                catch { }
            });

            // v0.5.6 — kick the startup baseline runner once the main window
            // is fully loaded. MainWindow is constructed by StartupUri after
            // OnStartup returns, so we queue the kick at Background priority:
            // the dispatcher executes it after the window's Loaded event has
            // fired (and after the first frame paints), giving a responsive
            // UI before the orchestrator starts churning panels.
            Dispatcher.BeginInvoke(
                new System.Action(KickStartupBaseline),
                System.Windows.Threading.DispatcherPriority.Background);
        }

        // Resolve the MainViewModel from the live MainWindow and start the
        // baseline orchestrator on a background task. Single-shot — guarded
        // by BaselineRunner.IsRunning if anything else races us. Safe if
        // MainWindow isn't up yet (design-time, very early shutdown): just
        // re-queue once.
        private bool _baselineKicked;
        private void KickStartupBaseline()
        {
            if (_baselineKicked) return;
            var win = Current?.MainWindow;
            if (win == null || !(win.DataContext is ViewModels.MainViewModel mvm) || mvm.Baseline == null)
            {
                // Window not ready yet — re-queue once at Loaded priority.
                Dispatcher.BeginInvoke(new System.Action(KickStartupBaseline),
                    System.Windows.Threading.DispatcherPriority.Loaded);
                return;
            }
            _baselineKicked = true;
            try
            {
                AppLogFile.Instance.WriteLine("Baseline", "Info",
                    "Startup baseline kicked");
            }
            catch { }
            _ = Task.Run(async () =>
            {
                try { await mvm.Baseline.RunAsync(startupNetworkReadinessGuard: true).ConfigureAwait(false); }
                catch (System.Exception ex)
                {
                    try
                    {
                        AppLogFile.Instance.WriteLine("Baseline", "Fail",
                            $"Baseline RunAsync threw: {ex.Message}");
                    }
                    catch { }
                }
            });
        }
    }
}
