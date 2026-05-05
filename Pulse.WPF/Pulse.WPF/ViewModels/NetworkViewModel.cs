using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
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
    /// Backing VM for the Network panel. Calls INetworkService for adapters
    /// + IP config (sync, fast) and port/domain probes (async). Builds Findings
    /// for any failures and sets the section-header pill from the worst severity.
    /// </summary>
    public class NetworkViewModel : ObservableObject
    {
        private readonly INetworkService _net;

        public ObservableCollection<NetworkAdapterRow> Adapters { get; } = new ObservableCollection<NetworkAdapterRow>();
        public IpConfigurationViewModel IpConfig { get => _ipConfig; private set => Set(ref _ipConfig, value); }
        private IpConfigurationViewModel _ipConfig = new IpConfigurationViewModel();
        public ObservableCollection<PortTestResult> PortTests { get; } = new ObservableCollection<PortTestResult>();
        public ObservableCollection<DomainTestResult> DomainTests { get; } = new ObservableCollection<DomainTestResult>();
        public ObservableCollection<LogEntry> LogEntries { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding> Findings { get; } = new ObservableCollection<Finding>();
        public bool HasFindings => Findings.Count > 0;

        private string _statusLabel = "Ready";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        private string _detectedNic = "";
        public string DetectedNic { get => _detectedNic; set => Set(ref _detectedNic, value); }

        public ICommand RunTestCommand { get; }
        public ICommand OpenAdapterSettingsCommand { get; }

        public NetworkViewModel(INetworkService net)
        {
            _net = net;
            RunTestCommand = new AsyncCommand(RunTestAsync);
            OpenAdapterSettingsCommand = new RelayCommand(OpenAdapterSettings);
        }

        // Called when the panel becomes visible. Cheap to call repeatedly —
        // refreshes the side cards without touching the wire.
        public Task RefreshAsync()
        {
            return Task.Run(() =>
            {
                var adapters = _net.GetAdapters();
                var ipCfg = _net.GetIpConfiguration();
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    Adapters.Clear();
                    foreach (var a in adapters) Adapters.Add(a);
                    IpConfig = ipCfg;
                    var first = adapters.FirstOrDefault();
                    DetectedNic = first != null ? $"{first.Name} — {first.Ip}" : "No adapters detected";
                });
            });
        }

        // Run the full network diagnostic — internet check, port tests, domain tests.
        // Mirrors Start-NetDiagnostic in NetworkDiagnostics.psm1.
        public async Task RunTestAsync()
        {
            // Refresh side cards first so the user always sees current adapter state.
            await RefreshAsync().ConfigureAwait(false);

            ClearLogsAndFindings();
            AddLog("", "Connectivity", "Section");
            SetPillRunning();

            var internet = await _net.CheckInternetAsync().ConfigureAwait(false);
            AddLog("Internet", internet ? "Reachable" : "No response - check uplink adapter",
                internet ? "Pass" : "Fail");
            if (!internet)
            {
                AddFinding("Critical",
                    "VPU has no internet connection",
                    "Check the uplink cable and the gateway's WAN status.");
            }

            // Port tests
            AddLog("", "Port Tests", "Section");
            var ports = await _net.RunPortTestsAsync().ConfigureAwait(false);
            int portFail = 0, portPass = 0;
            foreach (var p in ports)
            {
                var lvl = p.Status == "Pass" ? "Pass" : (p.Status == "Fail" ? "Fail" : "Gray");
                AddLog($"{p.Protocol} {p.Port}", $"{p.Status} {p.Purpose}", lvl);
                if (p.Status == "Pass") portPass++;
                else if (p.Status == "Fail") portFail++;
            }
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                PortTests.Clear();
                foreach (var p in ports) PortTests.Add(p);
            });
            if (portFail > 0)
            {
                AddFinding("Critical",
                    $"{portFail} of {portFail + portPass} required ports failed",
                    "Check the firewall, router, or content-filter / VLAN policy.");
            }

            // Domain tests
            AddLog("", "Domain Tests", "Section");
            var doms = await _net.RunDomainTestsAsync().ConfigureAwait(false);
            int domFail = 0, domPass = 0;
            foreach (var d in doms)
            {
                var lvl = d.Status == "Pass" ? "Pass" : (d.Status == "Fail" ? "Fail" : "Gray");
                var detail = d.Status == "Pass" ? $"PASS  ({d.ResolvedTo})" : d.Status.ToUpperInvariant();
                AddLog(d.Domain, detail, lvl);
                if (d.Status == "Pass") domPass++;
                else if (d.Status == "Fail") domFail++;
            }
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                DomainTests.Clear();
                foreach (var d in doms) DomainTests.Add(d);
            });
            if (domFail > 0)
            {
                AddFinding("Warning",
                    $"{domFail} of {domFail + domPass} domains failed DNS resolution",
                    "Check DNS server settings on this adapter.");
            }

            UpdateStatusPill();
        }

        // ----- helpers -----

        private void OpenAdapterSettings()
        {
            try { Process.Start("ncpa.cpl"); } catch { }
        }

        private void ClearLogsAndFindings()
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                LogEntries.Clear();
                Findings.Clear();
                OnPropertyChanged(nameof(HasFindings));
            });
        }

        private void AddLog(string label, string result, string level)
        {
            var entry = new LogEntry
            {
                Label = label,
                Result = result,
                Level = level,
                ResultColor = StatusHelpers.BrushForLogLevel(level),
            };
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                LogEntries.Add(entry);
                while (LogEntries.Count > 200) LogEntries.RemoveAt(0);
            });
        }

        private void AddFinding(string severity, string title, string recommendation)
        {
            var f = Finding.Create(severity, title, recommendation);
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                Findings.Add(f);
                OnPropertyChanged(nameof(HasFindings));
            });
        }

        private void SetPillRunning()
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                StatusLabel = "Running";
                StatusColor = StatusHelpers.Brush("YellowBrush");
                StatusBg = StatusHelpers.Brush("WarnBgBrush");
            });
        }

        private void UpdateStatusPill()
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                int crit = Findings.Count(f => f.Severity == "Critical");
                int warn = Findings.Count(f => f.Severity == "Warning");
                var worst = StatusHelpers.WorstSeverity(Findings);
                var pill = StatusHelpers.PillFor(worst, warn, crit);
                StatusLabel = pill.Label;
                StatusColor = pill.Fg;
                StatusBg = pill.Bg;
            });
        }
    }
}
