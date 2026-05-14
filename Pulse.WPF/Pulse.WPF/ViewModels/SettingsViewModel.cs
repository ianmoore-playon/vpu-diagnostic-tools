using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Input;
using System.Windows.Threading;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Settings panel (v0.6.7).
    ///
    /// Minimal surface — three cards:
    ///   • ScoreConnect III API base URL (read/write AppSettings.ScoreConnectUrl,
    ///     persists to %LOCALAPPDATA%\Pulse.WPF\settings.json)
    ///   • Logs &amp; Reports folder shortcuts
    ///   • "Run baseline now" — fires MainViewModel.Baseline.RunAsync()
    ///
    /// The "Run baseline now" command is wired by MainViewModel after
    /// construction since this VM doesn't take a reference to the baseline
    /// runner directly (one-way dependency).
    /// </summary>
    public class SettingsViewModel : ObservableObject
    {
        // ---- ScoreConnect URL editor ----
        private string _scoreConnectUrl;
        public string ScoreConnectUrl
        {
            get => _scoreConnectUrl;
            set => Set(ref _scoreConnectUrl, value);
        }

        public string DefaultScoreConnectUrl => AppSettings.DefaultScoreConnectUrl;

        // ---- Folder paths (read-only, surfaced in the UI for the tech) ----
        public string LogsFolderPath { get; }
        public string ReportsFolderPath { get; }

        // ---- 4 s inline status toast (mirrors SystemOverview Copy / Camera Save patterns) ----
        private string _saveStatus = "";
        public string SaveStatus { get => _saveStatus; set => Set(ref _saveStatus, value); }

        private DispatcherTimer _clearStatusTimer;

        // ---- Commands ----
        public ICommand SaveScoreConnectUrlCommand { get; }
        public ICommand ResetScoreConnectUrlCommand { get; }
        public ICommand OpenLogsFolderCommand     { get; }
        public ICommand OpenReportsFolderCommand  { get; }
        public ICommand RunBaselineCommand        { get; }

        // ---- Externally-injected baseline-run hook ----
        // MainViewModel sets this after composition so the Settings panel
        // doesn't take a direct dependency on BaselineRunner.
        public Func<Task> RunBaselineAsyncHook { get; set; }

        public SettingsViewModel()
        {
            _scoreConnectUrl = AppSettings.Instance.ScoreConnectUrl;

            // Best-effort path resolution matching AppLogFile + ReportsService.
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string pulseRoot   = Path.Combine(localAppData, "Pulse.WPF");
            LogsFolderPath     = Path.Combine(pulseRoot, "Logs");
            ReportsFolderPath  = Path.Combine(pulseRoot, "Reports");

            SaveScoreConnectUrlCommand = new RelayCommand(SaveScoreConnectUrl);
            ResetScoreConnectUrlCommand = new RelayCommand(() =>
            {
                ScoreConnectUrl = AppSettings.DefaultScoreConnectUrl;
                SaveScoreConnectUrl();
                ShowToast("Reset to default");
            });
            OpenLogsFolderCommand    = new RelayCommand(() => SafeOpen(LogsFolderPath));
            OpenReportsFolderCommand = new RelayCommand(() => SafeOpen(ReportsFolderPath));
            RunBaselineCommand       = new RelayCommand(async () =>
            {
                var hook = RunBaselineAsyncHook;
                if (hook == null) { ShowToast("Baseline runner unavailable"); return; }
                ShowToast("Baseline started");
                try { await hook().ConfigureAwait(false); } catch { /* logged in runner */ }
            });
        }

        private void SaveScoreConnectUrl()
        {
            var ok = AppSettings.Instance.SetScoreConnectUrl(ScoreConnectUrl);
            // Mirror the canonical value back into the field so a trailing
            // slash typed by the user is normalised in the textbox.
            ScoreConnectUrl = AppSettings.Instance.ScoreConnectUrl;
            ShowToast(ok ? "Saved - Score Connect uses this URL" : "Saved in-session - Score Connect uses this URL");
        }

        private void SafeOpen(string path)
        {
            try
            {
                if (!Directory.Exists(path))
                {
                    try { Directory.CreateDirectory(path); } catch { }
                }
                var psi = new ProcessStartInfo(path) { UseShellExecute = true };
                Process.Start(psi);
            }
            catch
            {
                ShowToast("Could not open folder");
            }
        }

        private void ShowToast(string text)
        {
            SaveStatus = text;
            _clearStatusTimer?.Stop();
            _clearStatusTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
            _clearStatusTimer.Tick += (_, __) =>
            {
                SaveStatus = "";
                _clearStatusTimer.Stop();
            };
            _clearStatusTimer.Start();
        }
    }
}
