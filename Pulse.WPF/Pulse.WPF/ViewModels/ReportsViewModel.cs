using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Lists past diagnostic-run snapshots from %LOCALAPPDATA%\Pulse.WPF\Reports.
    /// Left ListBox is the catalogue; right TextBox shows the selected
    /// report body. The Dashboard's "Open Last Report" breadcrumb pre-
    /// selects the top report via <see cref="PreselectFileName"/>.
    /// </summary>
    public class ReportsViewModel : ObservableObject
    {
        private readonly IReportsService _svc;

        public ObservableCollection<Report> Reports { get; } = new ObservableCollection<Report>();

        // True when there are no reports — drives the muted "No diagnostic
        // runs yet" empty state in the left list (and the Dashboard
        // breadcrumb's empty state).
        public bool HasNoReports => Reports.Count == 0;

        // ---- Selection ---------------------------------------------------
        private Report _selectedReport;
        public Report SelectedReport
        {
            get => _selectedReport;
            set
            {
                if (Set(ref _selectedReport, value))
                {
                    _ = LoadSelectedAsync();
                }
            }
        }

        private string _selectedReportContent = "";
        public string SelectedReportContent
        {
            get => _selectedReportContent;
            set => Set(ref _selectedReportContent, value);
        }

        private string _actionStatus = "";
        public string ActionStatus
        {
            get => _actionStatus;
            set => Set(ref _actionStatus, value);
        }

        // Used by the Dashboard's "Open Last Report" command to pre-select
        // a specific bundle once Reports finishes loading. Cleared after
        // use so a subsequent visit doesn't fight the user's selection.
        private string _preselectFileName;
        public string PreselectFileName
        {
            get => _preselectFileName;
            set { if (Set(ref _preselectFileName, value)) TryApplyPreselection(); }
        }

        // ---- Status pill -------------------------------------------------
        // Reports is informational — pill states are Info / All Clear, never
        // Critical. Count of reports in the last 7 days drives the label.
        private string _statusLabel = "No reports";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        // ---- App Log sub-card (v0.5.5) -----------------------------------
        // Tail of today's rolling Pulse-YYYYMMDD.log. The Reports panel adds
        // an "App Log" sub-card below the main 2-column body that shows the
        // most recent lines plus two folder-shortcut buttons.
        public ObservableCollection<string> RecentAppLogLines { get; } =
            new ObservableCollection<string>();

        // ---- Commands ----------------------------------------------------
        public ICommand RefreshCommand { get; }
        public ICommand GenerateSupportBundleCommand { get; }
        public ICommand OpenFolderCommand { get; }
        public ICommand DeleteCommand { get; }
        public ICommand OpenLogsFolderCommand { get; }
        public ICommand OpenTodayLogCommand { get; }
        public Func<Task<string>> GenerateSupportBundleAsyncHook { get; set; }

        public ReportsViewModel(IReportsService svc)
        {
            _svc = svc;
            RefreshCommand        = new AsyncCommand(RefreshAsync);
            GenerateSupportBundleCommand = new AsyncCommand(GenerateSupportBundleAsync,
                                                           () => GenerateSupportBundleAsyncHook != null);
            OpenFolderCommand     = new RelayCommand(OpenFolder);
            DeleteCommand         = new RelayCommand(DeleteSelected, () => _selectedReport != null);
            OpenLogsFolderCommand = new RelayCommand(OpenLogsFolder);
            OpenTodayLogCommand   = new RelayCommand(OpenTodayLog);

            // Auto-load on construction.
            _ = Task.Run(async () =>
            {
                try { await RefreshAsync(); } catch { }
            });
        }

        public async Task RefreshAsync()
        {
            var list = await _svc.GetAllAsync().ConfigureAwait(false);

            // Tail of the rolling daily log. Read off the UI thread —
            // ReadAllLines on a 5-10 MB file shouldn't be done in the
            // dispatcher invoke below.
            System.Collections.Generic.IReadOnlyList<string> tail;
            try { tail = _svc.GetRecentAppLogLines(10); }
            catch { tail = System.Array.Empty<string>(); }

            Application.Current?.Dispatcher.Invoke(() =>
            {
                Reports.Clear();
                foreach (var r in list) Reports.Add(r);

                RecentAppLogLines.Clear();
                foreach (var line in tail) RecentAppLogLines.Add(line);

                OnPropertyChanged(nameof(HasNoReports));
                UpdatePill();
                TryApplyPreselection();

                // Auto-select the newest report so the viewer pre-populates
                // on panel open (v0.5.5 — Reports UX). Preselection from the
                // Dashboard breadcrumb still wins because TryApplyPreselection
                // ran first.
                if (_selectedReport == null && Reports.Count > 0)
                {
                    SelectedReport = Reports[0];
                }
            });
        }

        private void TryApplyPreselection()
        {
            if (string.IsNullOrEmpty(_preselectFileName)) return;
            var match = Reports.FirstOrDefault(r =>
                string.Equals(r.FileName, _preselectFileName, StringComparison.OrdinalIgnoreCase));
            if (match != null)
            {
                SelectedReport = match;
                _preselectFileName = null;
                OnPropertyChanged(nameof(PreselectFileName));
            }
        }

        private async Task LoadSelectedAsync()
        {
            if (_selectedReport == null) { SelectedReportContent = ""; return; }
            var fileName = _selectedReport.FileName;
            string text;
            try { text = await _svc.ReadAsync(fileName).ConfigureAwait(false); }
            catch { text = ""; }
            Application.Current?.Dispatcher.Invoke(() =>
            {
                SelectedReportContent = text ?? "";
            });
        }

        private void UpdatePill()
        {
            if (Reports.Count == 0)
            {
                StatusLabel = "No reports";
                StatusColor = StatusHelpers.Brush("MutedForegroundBrush");
                StatusBg    = StatusHelpers.Brush("BorderColBrush");
                return;
            }
            var since = DateTime.Now.AddDays(-7);
            int recent = Reports.Count(r => r.Timestamp >= since);
            if (recent > 0)
            {
                StatusLabel = recent == 1 ? "1 in last 7 days" : $"{recent} in last 7 days";
                StatusColor = StatusHelpers.Brush("AccentBrush");
                StatusBg    = StatusHelpers.Brush("BorderColBrush");
            }
            else
            {
                StatusLabel = $"{Reports.Count} archived";
                StatusColor = StatusHelpers.Brush("MutedForegroundBrush");
                StatusBg    = StatusHelpers.Brush("BorderColBrush");
            }
        }

        private void OpenFolder()
        {
            try
            {
                if (!Directory.Exists(_svc.ReportsDirectory)) Directory.CreateDirectory(_svc.ReportsDirectory);
                var psi = new ProcessStartInfo(_svc.ReportsDirectory) { UseShellExecute = true };
                Process.Start(psi);
                SetActionStatus($"Opened reports folder: {_svc.ReportsDirectory}");
            }
            catch (Exception ex)
            {
                SetActionStatus($"Couldn't open reports folder: {ex.Message}");
            }
        }

        private void OpenLogsFolder()
        {
            try
            {
                var dir = _svc.LogsDirectory;
                if (string.IsNullOrEmpty(dir))
                {
                    SetActionStatus("Log folder is not available.");
                    return;
                }
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                var psi = new ProcessStartInfo(dir) { UseShellExecute = true };
                Process.Start(psi);
                SetActionStatus($"Opened logs folder: {dir}");
            }
            catch (Exception ex)
            {
                SetActionStatus($"Couldn't open logs folder: {ex.Message}");
            }
        }

        private void OpenTodayLog()
        {
            try
            {
                var path = _svc.TodayLogPath;
                if (string.IsNullOrEmpty(path))
                {
                    SetActionStatus("Today's log path is not available.");
                    return;
                }
                // The file may not exist yet if no log lines have been written
                // today — create an empty stub so Notepad has something to
                // open rather than throwing a "file not found" dialog.
                if (!File.Exists(path))
                {
                    try { File.WriteAllText(path, ""); }
                    catch (Exception ex)
                    {
                        SetActionStatus($"Couldn't create today's log file: {ex.Message}");
                        return;
                    }
                }
                var psi = new ProcessStartInfo(path) { UseShellExecute = true };
                Process.Start(psi);
                SetActionStatus($"Opened today's log: {Path.GetFileName(path)}");
            }
            catch
            {
                // ShellExecute can fail for .log files when no association
                // exists — explicit Notepad fallback so the click is never lost.
                try
                {
                    Process.Start("notepad.exe", _svc.TodayLogPath);
                    SetActionStatus($"Opened today's log: {Path.GetFileName(_svc.TodayLogPath)}");
                }
                catch (Exception ex)
                {
                    SetActionStatus($"Couldn't open today's log: {ex.Message}");
                }
            }
        }

        private void DeleteSelected()
        {
            var sel = _selectedReport;
            if (sel == null) return;
            var result = MessageBox.Show(
                $"Delete report \"{sel.FileName}\"? This can't be undone.",
                "Confirm delete",
                MessageBoxButton.OKCancel,
                MessageBoxImage.Warning,
                MessageBoxResult.Cancel);
            if (result != MessageBoxResult.OK) return;

            if (_svc.Delete(sel.FileName))
            {
                Reports.Remove(sel);
                SelectedReport = null;
                SelectedReportContent = "";
                OnPropertyChanged(nameof(HasNoReports));
                UpdatePill();
                SetActionStatus($"Deleted report: {sel.FileName}");
            }
            else
            {
                SetActionStatus($"Couldn't delete report: {sel.FileName}");
            }
        }

        private async Task GenerateSupportBundleAsync()
        {
            if (GenerateSupportBundleAsyncHook == null)
            {
                SetActionStatus("Support bundle generator is not ready.");
                return;
            }

            SetActionStatus("Generating support bundle…");
            try
            {
                var path = await GenerateSupportBundleAsyncHook();
                var fileName = string.IsNullOrEmpty(path) ? "" : Path.GetFileName(path);
                SetActionStatus(string.IsNullOrEmpty(fileName)
                    ? "Support bundle created."
                    : $"Support bundle created: {fileName}");
                await RefreshAsync();
                if (!string.IsNullOrEmpty(fileName)) PreselectFileName = fileName;
            }
            catch (Exception ex)
            {
                SetActionStatus($"Support bundle failed: {ex.Message}");
            }
        }

        private void SetActionStatus(string message)
        {
            ActionStatus = message ?? "";
            try
            {
                AppLogFile.Instance.WriteLine("Reports", "Info", ActionStatus);
            }
            catch { }
        }
    }
}
