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
        // Composed via PanelLogger (v0.5.0) — shared with the four other panels.
        public PanelLogger Logger { get; } = new PanelLogger("DiskHealth");
        private readonly ReportWriter _reportWriter = new ReportWriter();
        public string LastReportPath { get; private set; }
        public ObservableCollection<LogEntry> LogEntries => Logger.Entries;
        public ObservableCollection<Finding> Findings { get; } = new ObservableCollection<Finding>();
        public bool HasFindings => Findings.Count > 0;

        private string _smartStatus = "Unknown";
        public string SmartStatus { get => _smartStatus; set => Set(ref _smartStatus, value); }

        private int _diskErrorCount;
        public int DiskErrorCount { get => _diskErrorCount; set => Set(ref _diskErrorCount, value); }

        // Top-row card severities + summary strings — drive the SeverityChip
        // controls above the Findings banner so the cards read the same
        // vocabulary as the banner below (v0.5.0).
        private string _smartSeverity = "neutral";
        public string SmartSeverity
        {
            get => _smartSeverity;
            set { if (Set(ref _smartSeverity, value)) OnPropertyChanged(nameof(SmartChipText)); }
        }
        public string SmartChipText => ChipLabel(_smartSeverity);
        private string _smartHealthSummary = "—";
        public string SmartHealthSummary { get => _smartHealthSummary; set => Set(ref _smartHealthSummary, value); }

        private string _diskErrorsSeverity = "neutral";
        public string DiskErrorsSeverity
        {
            get => _diskErrorsSeverity;
            set { if (Set(ref _diskErrorsSeverity, value)) OnPropertyChanged(nameof(DiskErrorsChipText)); }
        }
        public string DiskErrorsChipText => ChipLabel(_diskErrorsSeverity);
        private string _diskErrorsSummary = "—";
        public string DiskErrorsSummary { get => _diskErrorsSummary; set => Set(ref _diskErrorsSummary, value); }

        private string _osDriveSeverity = "neutral";
        public string OsDriveSeverity
        {
            get => _osDriveSeverity;
            set { if (Set(ref _osDriveSeverity, value)) OnPropertyChanged(nameof(OsDriveChipText)); }
        }
        public string OsDriveChipText => ChipLabel(_osDriveSeverity);
        private string _osDriveFreeSummary = "—";
        public string OsDriveFreeSummary { get => _osDriveFreeSummary; set => Set(ref _osDriveFreeSummary, value); }

        private static string ChipLabel(string severity)
        {
            switch ((severity ?? "").ToLowerInvariant())
            {
                case "pass": case "ok":   return "PASS";
                case "warn": case "warning": return "WARN";
                case "fail": case "error": return "FAIL";
                case "critical": return "CRIT";
                default: return "—";
            }
        }

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
                    if (smart == null)
                    {
                        SmartStatus = "Unavailable";
                        SmartHealthSummary = "Unavailable";
                        SmartSeverity = "neutral";
                        AddLog("SMART", "Cannot query (admin required)", "Gray");
                    }
                    else if (smart.Value)
                    {
                        SmartStatus = "Predict Failure";
                        SmartHealthSummary = "Predict Failure";
                        SmartSeverity = "fail";
                        AddLog("SMART", "Predict Failure", "Fail");
                    }
                    else
                    {
                        SmartStatus = "Healthy";
                        SmartHealthSummary = "Healthy";
                        SmartSeverity = "pass";
                        AddLog("SMART", "Healthy", "Pass");
                    }

                    DiskErrorCount = errs;
                    DiskErrorsSummary = errs == 0 ? "No disk-related errors" : $"{errs} error event(s)";
                    DiskErrorsSeverity = errs == 0 ? "pass" : "fail";
                    AddLog("Disk events (48h)", errs == 0 ? "No disk-related errors" : $"{errs} error event(s)",
                        errs == 0 ? "Pass" : "Fail");

                    // OS drive — locate it in the volumes list (Role contains
                    // "OS") and surface the free-space band as the chip tier.
                    var os = vols.FirstOrDefault(v => (v.Role ?? "").IndexOf("OS", System.StringComparison.OrdinalIgnoreCase) >= 0)
                             ?? vols.FirstOrDefault(v => (v.DeviceId ?? "").StartsWith("C", System.StringComparison.OrdinalIgnoreCase));
                    if (os == null)
                    {
                        OsDriveFreeSummary = "Not detected";
                        OsDriveSeverity = "neutral";
                    }
                    else
                    {
                        OsDriveFreeSummary = $"{os.FreeGb:0.#} GB free ({os.PercentUsed}% used)";
                        OsDriveSeverity = os.Severity == "Pass" ? "pass"
                                        : os.Severity == "Warn" ? "warn"
                                        : os.Severity == "Fail" ? "fail"
                                        : "neutral";
                    }

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

                    // v0.5.5: per-run report file.
                    try
                    {
                        var path = _reportWriter.Save("DiskHealth", BuildReportText());
                        if (!string.IsNullOrEmpty(path))
                        {
                            LastReportPath = path;
                            AppLogFile.Instance.WriteLine("DiskHealth", "Info",
                                $"Report saved: {path}");
                        }
                    }
                    catch { }
                });
            }).ConfigureAwait(false);
        }

        /// <summary>
        /// Compose the Disk Health panel's per-run report body — SMART
        /// status, disk error count, OS-drive free space, the top three
        /// card values, and the Findings list.
        /// </summary>
        public string BuildReportText()
        {
            var sb = new System.Text.StringBuilder();

            sb.AppendLine("== Top Cards ==");
            sb.AppendLine($"  SMART:          [{SmartChipText}] {SmartHealthSummary}");
            sb.AppendLine($"  Disk Errors:    [{DiskErrorsChipText}] {DiskErrorsSummary}");
            sb.AppendLine($"  OS Drive Free:  [{OsDriveChipText}] {OsDriveFreeSummary}");

            sb.AppendLine();
            sb.AppendLine("== Volumes ==");
            if (Volumes.Count == 0)
            {
                sb.AppendLine("  (no volumes collected)");
            }
            else
            {
                foreach (var v in Volumes)
                {
                    sb.AppendLine($"  [{v.Severity,-4}] {v.DeviceId,-4} {v.Label,-16}  {v.FreeGb,7:0.#} GB free / {v.TotalGb,7:0.#} GB ({v.PercentUsed}% used)  [{v.Role}]");
                }
            }

            if (PixellotPaths.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== Pixellot Storage Paths ==");
                foreach (var p in PixellotPaths)
                    sb.AppendLine($"  [{p.Severity,-4}] {p.Label,-24}  {p.SizeFormatted}");
            }

            if (Findings.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== Findings ==");
                foreach (var f in Findings)
                    sb.AppendLine($"  [{f.Severity}] {f.Title}\n      -> {f.Recommendation}");
            }

            sb.AppendLine();
            sb.AppendLine("## Live Log (last 50 entries)");
            var tail = LogEntries.Count > 50 ? 50 : LogEntries.Count;
            for (int i = LogEntries.Count - tail; i < LogEntries.Count; i++)
            {
                var e = LogEntries[i];
                var label = string.IsNullOrEmpty(e.Label) ? "" : e.Label + "  ";
                sb.AppendLine($"  [{e.Level,-5}] {label}{e.Result}");
            }

            return sb.ToString();
        }

        private void AddLog(string label, string result, string level) => Logger.Add(label, result, level);

        private void AddFinding(string severity, string title, string recommendation)
        {
            Findings.Add(Finding.Create(severity, title, recommendation));
        }

        private void UpdateStatusPill()
        {
            int crit = Findings.Count(f => f.Severity == FindingSeverity.Critical);
            int warn = Findings.Count(f => f.Severity == FindingSeverity.Warning);
            var worst = StatusHelpers.WorstSeverity(Findings);
            var pill = StatusHelpers.PillFor(worst, warn, crit);
            StatusLabel = pill.Label;
            StatusColor = pill.Fg;
            StatusBg = pill.Bg;
        }
    }
}
