using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;

namespace Pulse.WPF.ViewModels.Stub
{
    /// <summary>
    /// Stub viewmodel for DiskHealthView. Mock data covers SMART status,
    /// disk-error counts, OS-drive free space, a small volume list and the
    /// Pixellot-specific paths the field tools care about.
    /// </summary>
    public class DiskHealthViewModel : StatusViewModelBase
    {
        // ---- Top-row summary cards ----
        private string _smartHealthSummary = "All 2 healthy";
        public string SmartHealthSummary { get => _smartHealthSummary; set => Set(ref _smartHealthSummary, value); }

        private string _diskErrorsSummary = "3 disk / 1 driver / 2 app errors (last 48 h)";
        public string DiskErrorsSummary { get => _diskErrorsSummary; set => Set(ref _diskErrorsSummary, value); }

        private string _osDriveFreeSummary = "C: 220 GB free of 500 GB (44% used)";
        public string OsDriveFreeSummary { get => _osDriveFreeSummary; set => Set(ref _osDriveFreeSummary, value); }

        // ---- Volumes ----
        public ObservableCollection<VolumeRow>      Volumes       { get; } = new ObservableCollection<VolumeRow>();
        public ObservableCollection<PixellotPathRow> PixellotPaths { get; } = new ObservableCollection<PixellotPathRow>();
        public ObservableCollection<LogEntry>       LogEntries     { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding>        Findings       { get; } = new ObservableCollection<Finding>();

        public bool HasFindings => Findings.Count > 0;

        public ICommand RunTestCommand { get; }

        public DiskHealthViewModel()
        {
            SetStatus("1 Warning", "YellowBrush", "WarnBgBrush");

            var green  = (Brush)Application.Current.Resources["GreenBrush"];
            var yellow = (Brush)Application.Current.Resources["YellowBrush"];
            var red    = (Brush)Application.Current.Resources["RedBrush"];

            Volumes.Add(new VolumeRow {
                Drive = "C:", Role = "OS",            Free = "220 GB", Total = "500 GB",
                PercentUsed = "56%", PercentUsedValue = 56,
                Status = "Healthy",  StatusColor = green, BarColor = green });
            Volumes.Add(new VolumeRow {
                Drive = "D:", Role = "Pixellot Data", Free = "180 GB", Total = "1 TB",
                PercentUsed = "82%", PercentUsedValue = 82,
                Status = "Approaching limit", StatusColor = yellow, BarColor = yellow });
            Volumes.Add(new VolumeRow {
                Drive = "E:", Role = "Recovery",      Free = "9.4 GB", Total = "20 GB",
                PercentUsed = "53%", PercentUsedValue = 53,
                Status = "Healthy", StatusColor = green, BarColor = green });

            PixellotPaths.Add(new PixellotPathRow {
                Path = @"C:\Pixellot\Data\Log",     Description = "Log archive",       Size = "4.2 GB",  Threshold = "Warn at 10 GB", Status = "OK", StatusColor = green });
            PixellotPaths.Add(new PixellotPathRow {
                Path = @"C:\Pixellot\Data\Records", Description = "Recording buffer",  Size = "180 GB", Threshold = "Warn at 200 GB", Status = "Approaching limit", StatusColor = yellow });
            PixellotPaths.Add(new PixellotPathRow {
                Path = @"C:\Pixellot\Data\Cache",   Description = "Stream cache",      Size = "1.1 GB",  Threshold = "Warn at 5 GB",   Status = "OK", StatusColor = green });

            Findings.Add(MakeFinding(FindingSeverity.Warning,
                "D: drive (Pixellot Data) is 82% full",
                "Free up space by clearing C:\\Pixellot\\Data\\Records older than 7 days, or extend the volume. Below 100 GB free, recordings start dropping frames.",
                "Disk"));

            AddLog("",            "Disk diagnostic",                              "Section");
            AddLog("SMART",       "Disk 0 (NVMe) — healthy",                       "Pass");
            AddLog("SMART",       "Disk 1 (SSD)  — healthy",                       "Pass");
            AddLog("Volume D:",   "180 GB free of 1 TB (82% used)",                 "Warn");
            AddLog("Records dir", "180 GB — approaching 200 GB threshold",          "Warn");
            AddLog("Disk events", "3 disk / 1 driver / 2 app errors in last 48 h",  "Warn");

            RunTestCommand = new RelayCommand(() => AddLog("Action", "Run Test (stub) — engine arrives in v1.1", "Warn"));
        }

        private static Finding MakeFinding(FindingSeverity sev, string title, string rec, string cat)
        {
            var f = new Finding();
            f.Apply(sev, title, rec, cat);
            return f;
        }

        private void AddLog(string label, string result, string level)
        {
            Brush color = level switch
            {
                "Pass"    => (Brush)Application.Current.Resources["GreenBrush"],
                "Fail"    => (Brush)Application.Current.Resources["RedBrush"],
                "Warn"    => (Brush)Application.Current.Resources["YellowBrush"],
                "Section" => (Brush)Application.Current.Resources["AccentBrush"],
                _         => (Brush)Application.Current.Resources["ForegroundBrush"],
            };
            LogEntries.Add(new LogEntry { Label = label, Result = result, Level = level, ResultColor = color });
        }
    }
}
