using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// System & Disk Health panel VM. Pulls volume info, Pixellot path sizes,
    /// SMART status, and disk-related event log errors via IDiskHealthService.
    /// </summary>
    public class DiskHealthViewModel : ObservableObject
    {
        private readonly IDiskHealthService _disk;

        public ObservableCollection<VolumeRow> Volumes { get; } = new ObservableCollection<VolumeRow>();
        public ObservableCollection<PixellotPathRow> PixellotPaths { get; } = new ObservableCollection<PixellotPathRow>();
        public ObservableCollection<LogEntry> LogEntries { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding> Findings { get; } = new ObservableCollection<Finding>();
        public bool HasFindings => Findings.Count > 0;

        private string _smartStatus = "Unknown";
        public string SmartStatus { get => _smartStatus; set => Set(ref _smartStatus, value); }

        private int _diskErrorCount;
        public int DiskErrorCount { get => _diskErrorCount; set => Set(ref _diskErrorCount, value); }

        private string _statusLabel = "Ready";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        public ICommand RunTestCommand { get; }

        public DiskHealthViewModel(IDiskHealthService disk)
        {
            _disk = disk;
            RunTestCommand = new AsyncCommand(RefreshAsync);
        }

        public async Task RefreshAsync()
        {
            await Task.Run(() =>
            {
                var vols = _disk.GetVolumes();
                var paths = _disk.GetPixellotPaths();
                var smart = _disk.SmartPredictsFailure();
                int errs = _disk.CountDiskErrorEvents48h();

                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    Volumes.Clear();
                    PixellotPaths.Clear();
                    LogEntries.Clear();
                    Findings.Clear();

                    AddLog("", "Volumes & Space", "Section");
                    foreach (var v in vols)
                    {
                        Volumes.Add(v);
                        var sevLog = v.Severity == "Pass" ? "Pass" : v.Severity == "Warn" ? "Warn" : "Fail";
                        AddLog($"{v.DeviceId}  {v.Label} [{v.Role}]",
                            $"{v.FreeGb:0.#} GB free / {v.TotalGb:0.#} GB total ({v.PercentUsed}% used)",
                            sevLog);
                    }

                    AddLog("", "Pixellot Storage Paths", "Section");
                    foreach (var p in paths)
                    {
                        PixellotPaths.Add(p);
                        var sevLog = p.Severity == "Pass" ? "Pass" : p.Severity == "Warn" ? "Warn" :
                                     p.Severity == "Fail" ? "Fail" : "Gray";
                        AddLog(p.Label, p.SizeFormatted, sevLog);
                    }

                    AddLog("", "SMART & Errors", "Section");
                    if (smart == null) { SmartStatus = "Unavailable"; AddLog("SMART", "Cannot query (admin required)", "Gray"); }
                    else if (smart.Value) { SmartStatus = "Predict Failure"; AddLog("SMART", "Predict Failure", "Fail"); }
                    else { SmartStatus = "Healthy"; AddLog("SMART", "Healthy", "Pass"); }

                    DiskErrorCount = errs;
                    AddLog("Disk events (48h)", errs == 0 ? "No disk-related errors" : $"{errs} error event(s)",
                        errs == 0 ? "Pass" : "Fail");

                    // ---- Findings ------------------------------------------------
                    foreach (var v in vols.Where(v => v.Severity == "Fail"))
                    {
                        AddFinding("Critical",
                            $"{v.DeviceId} is critically low on space ({v.FreeGb:0.#} GB free)",
                            "Free space immediately or VPU may stop recording. Clear old recordings or logs first.");
                    }
                    foreach (var v in vols.Where(v => v.Severity == "Warn" && v.Role != "Inaccessible"))
                    {
                        AddFinding("Warning",
                            $"{v.DeviceId} is getting low on space ({v.FreeGb:0.#} GB free, {v.PercentUsed}% used)",
                            "Review large folders and clear non-essential files before they reach the critical threshold.");
                    }
                    if (smart == true)
                    {
                        AddFinding("Critical",
                            "SMART predicts disk failure",
                            "Back up Pixellot data and replace the affected drive as soon as possible.");
                    }
                    if (errs > 0)
                    {
                        AddFinding("Critical",
                            $"{errs} disk-related error events in the last 48 hours",
                            "Check cables, run chkdsk, or schedule a drive replacement if errors continue.");
                    }

                    UpdateStatusPill();
                    OnPropertyChanged(nameof(HasFindings));
                });
            }).ConfigureAwait(false);
        }

        private void AddLog(string label, string result, string level)
        {
            LogEntries.Add(new LogEntry
            {
                Label = label,
                Result = result,
                Level = level,
                ResultColor = StatusHelpers.BrushForLogLevel(level),
            });
        }

        private void AddFinding(string severity, string title, string recommendation)
        {
            Findings.Add(Finding.Create(severity, title, recommendation));
        }

        private void UpdateStatusPill()
        {
            int crit = Findings.Count(f => f.Severity == "Critical");
            int warn = Findings.Count(f => f.Severity == "Warning");
            var worst = StatusHelpers.WorstSeverity(Findings);
            var pill = StatusHelpers.PillFor(worst, warn, crit);
            StatusLabel = pill.Label;
            StatusColor = pill.Fg;
            StatusBg = pill.Bg;
        }
    }
}
