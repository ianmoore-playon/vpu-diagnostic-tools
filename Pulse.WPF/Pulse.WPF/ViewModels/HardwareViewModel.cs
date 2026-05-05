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
    /// <summary>Hardware & Peripherals panel — GPU, monitor, mouse/keyboard,
    /// PoE budget, NIC link uptime. Calls IHardwareService for WMI reads.</summary>
    public class HardwareViewModel : ObservableObject
    {
        private readonly IHardwareService _hw;

        public ObservableCollection<NicUptime> NicUptimes { get; } = new ObservableCollection<NicUptime>();
        public ObservableCollection<PoePortReading> PoePorts { get; } = new ObservableCollection<PoePortReading>();
        public ObservableCollection<LogEntry> LogEntries { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding> Findings { get; } = new ObservableCollection<Finding>();
        public bool HasFindings => Findings.Count > 0;

        private string _gpuName = "—";
        public string GpuName { get => _gpuName; set => Set(ref _gpuName, value); }

        private string _monitorStatus = "—";
        public string MonitorStatus { get => _monitorStatus; set => Set(ref _monitorStatus, value); }

        private string _inputStatus = "—";
        public string InputStatus { get => _inputStatus; set => Set(ref _inputStatus, value); }

        private string _statusLabel = "Ready";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        public ICommand RunTestCommand { get; }

        public HardwareViewModel(IHardwareService hw)
        {
            _hw = hw;
            RunTestCommand = new AsyncCommand(RefreshAsync);
        }

        public async Task RefreshAsync()
        {
            await Task.Run(() =>
            {
                var gpu = _hw.GetGpuName();
                int monCount = _hw.GetMonitorCount();
                bool mouse = _hw.HasMouse();
                bool kbd = _hw.HasKeyboard();
                var uptimes = _hw.GetNicUptimes();
                var poe = _hw.GetPoePortReadings();

                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    LogEntries.Clear();
                    Findings.Clear();

                    GpuName = gpu;
                    MonitorStatus = monCount > 0 ? $"{monCount} connected" : "None detected";
                    InputStatus = $"Mouse: {(mouse ? "OK" : "missing")} / Keyboard: {(kbd ? "OK" : "missing")}";

                    AddLog("", "Graphics", "Section");
                    AddLog("GPU", gpu, "Info");
                    AddLog("", "Peripherals", "Section");
                    AddLog("Monitor", MonitorStatus, monCount > 0 ? "Pass" : "Warn");
                    AddLog("Mouse", mouse ? "Connected" : "None", mouse ? "Pass" : "Warn");
                    AddLog("Keyboard", kbd ? "Connected" : "None", kbd ? "Pass" : "Warn");

                    NicUptimes.Clear();
                    foreach (var u in uptimes) NicUptimes.Add(u);
                    if (uptimes.Count > 0)
                    {
                        AddLog("", "NIC Port Uptime", "Section");
                        foreach (var u in uptimes)
                            AddLog(u.Name, $"Link up: {u.Uptime}", u.Uptime == ">48h" ? "Pass" : "Info");
                    }

                    PoePorts.Clear();
                    foreach (var p in poe) PoePorts.Add(p);
                    if (poe.Count > 0)
                    {
                        AddLog("", "PoE Status", "Section");
                        foreach (var p in poe)
                        {
                            var state = p.PoeOn ? "PoE ON" : "PoE OFF";
                            AddLog(p.Port,
                                $"{p.Voltage:F2} V  {p.Current:F3} A  {p.Watts:F1} W  [{state}]",
                                p.PoeOn ? "Pass" : "Gray");
                        }
                    }

                    // Findings — Warning only when the OS clearly lost a peripheral.
                    if (monCount == 0)
                        AddFinding("Warning", "No monitor detected",
                            "Confirm the display cable is seated; without a monitor the VPU cannot show local diagnostics.");
                    if (!mouse)
                        AddFinding("Warning", "Mouse not detected",
                            "Plug in a USB mouse so on-site techs can interact with the VPU.");
                    if (!kbd)
                        AddFinding("Warning", "Keyboard not detected",
                            "Plug in a USB keyboard for local sign-in.");

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
