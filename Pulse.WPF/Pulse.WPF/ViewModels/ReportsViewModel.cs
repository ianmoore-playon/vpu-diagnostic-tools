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

        // ---- Commands ----------------------------------------------------
        public ICommand RefreshCommand { get; }
        public ICommand OpenFolderCommand { get; }
        public ICommand DeleteCommand { get; }

        public ReportsViewModel(IReportsService svc)
        {
            _svc = svc;
            RefreshCommand    = new AsyncCommand(RefreshAsync);
            OpenFolderCommand = new RelayCommand(OpenFolder);
            DeleteCommand     = new RelayCommand(DeleteSelected, () => _selectedReport != null);

            // Auto-load on construction.
            _ = Task.Run(async () =>
            {
                try { await RefreshAsync(); } catch { }
            });
        }

        public async Task RefreshAsync()
        {
            var list = await _svc.GetAllAsync().ConfigureAwait(false);
            Application.Current?.Dispatcher.Invoke(() =>
            {
                Reports.Clear();
                foreach (var r in list) Reports.Add(r);
                OnPropertyChanged(nameof(HasNoReports));
                UpdatePill();
                TryApplyPreselection();
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
            }
            catch { /* shell could be unavailable on a stripped-down image */ }
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
            }
        }
    }
}
