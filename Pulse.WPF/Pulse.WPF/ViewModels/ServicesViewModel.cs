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
    /// <summary>Pixellot Services panel VM — surfaces process + service health
    /// rows and rolls up Findings for any required process not running.</summary>
    public class ServicesViewModel : ObservableObject
    {
        private readonly IServicesService _svc;

        public ObservableCollection<ServiceStatusRow> Services { get; } = new ObservableCollection<ServiceStatusRow>();
        public ObservableCollection<LogEntry> LogEntries { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding> Findings { get; } = new ObservableCollection<Finding>();
        public bool HasFindings => Findings.Count > 0;

        private string _statusLabel = "Ready";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        public ICommand RunTestCommand { get; }

        public ServicesViewModel(IServicesService svc)
        {
            _svc = svc;
            RunTestCommand = new AsyncCommand(RefreshAsync);
        }

        public async Task RefreshAsync()
        {
            await Task.Run(() =>
            {
                var rows = _svc.GetServiceStatuses();
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    Services.Clear();
                    LogEntries.Clear();
                    Findings.Clear();

                    AddLog("", "Core Pixellot Processes", "Section");
                    foreach (var r in rows)
                    {
                        Services.Add(r);
                        AddLog(r.Name, r.Status + (string.IsNullOrEmpty(r.Detail) ? "" : "  " + r.Detail),
                            r.Severity == "Pass" ? "Pass" :
                            r.Severity == "Fail" ? "Fail" :
                            r.Severity == "Warn" ? "Warn" : "Gray");
                    }

                    foreach (var fail in rows.Where(r => r.Severity == "Fail"))
                    {
                        AddFinding("Critical",
                            $"{fail.Name} is not running",
                            $"Restart {fail.Name} or reboot the VPU. Persistent failures usually mean a missing config or a corrupted install.");
                    }
                    foreach (var warn in rows.Where(r => r.Severity == "Warn"))
                    {
                        AddFinding("Warning",
                            $"{warn.Name}: {warn.Detail}",
                            $"Investigate {warn.Name} — start the service or remove the orphan registration.");
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
