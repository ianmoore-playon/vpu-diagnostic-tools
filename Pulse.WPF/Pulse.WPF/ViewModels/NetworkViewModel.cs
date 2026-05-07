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

        // Single primary internet-bound adapter — what the new compact card binds to.
        // Adapters collection is kept for legacy / future use but no longer rendered.
        private NetworkAdapterRow _primaryAdapter;
        public NetworkAdapterRow PrimaryAdapter
        {
            get => _primaryAdapter;
            private set
            {
                if (Set(ref _primaryAdapter, value))
                    OnPropertyChanged(nameof(HasPrimaryAdapter));
            }
        }
        public bool HasPrimaryAdapter => _primaryAdapter != null;

        public IpConfigurationViewModel IpConfig { get => _ipConfig; private set => Set(ref _ipConfig, value); }
        private IpConfigurationViewModel _ipConfig = new IpConfigurationViewModel();

        // Derived from IpConfig.Dhcp ("Enabled" -> "DHCP", "Disabled" -> "Static").
        public string IpAssignment
        {
            get
            {
                var d = (IpConfig?.Dhcp ?? "").Trim().ToLowerInvariant();
                if (d == "enabled")  return "DHCP";
                if (d == "disabled") return "Static";
                return "Unknown";
            }
        }

        public ObservableCollection<PortTestResult> PortTests { get; } = new ObservableCollection<PortTestResult>();
        // Protocol-split views of PortTests so the view can render TCP and UDP
        // tiles in two side-by-side columns. Populated in RunTestAsync.
        public ObservableCollection<PortTestResult> TcpPortTests { get; } = new ObservableCollection<PortTestResult>();
        public ObservableCollection<PortTestResult> UdpPortTests { get; } = new ObservableCollection<PortTestResult>();
        public ObservableCollection<DomainTestResult> DomainTests { get; } = new ObservableCollection<DomainTestResult>();
        public ObservableCollection<LogEntry> LogEntries { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding> Findings { get; } = new ObservableCollection<Finding>();
        public ObservableCollection<NetworkRecommendation> Recommendations { get; } = new ObservableCollection<NetworkRecommendation>();
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
                var primary = _net.GetPrimaryInternetAdapter();
                var ipCfg = _net.GetIpConfiguration();
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    Adapters.Clear();
                    foreach (var a in adapters) Adapters.Add(a);
                    PrimaryAdapter = primary;
                    IpConfig = ipCfg;
                    OnPropertyChanged(nameof(IpAssignment));
                    var detected = primary ?? adapters.FirstOrDefault();
                    DetectedNic = detected != null ? $"{detected.Name} — {detected.Ip}" : "No adapters detected";
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
            ClearRecommendations();
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
                p.ResultColor = StatusHelpers.BrushForLogLevel(lvl);
                if (p.Status == "Pass") portPass++;
                else if (p.Status == "Fail") portFail++;
            }
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                PortTests.Clear();
                TcpPortTests.Clear();
                UdpPortTests.Clear();
                foreach (var p in ports)
                {
                    PortTests.Add(p);
                    if (string.Equals(p.Protocol, "TCP", System.StringComparison.OrdinalIgnoreCase))
                        TcpPortTests.Add(p);
                    else if (string.Equals(p.Protocol, "UDP", System.StringComparison.OrdinalIgnoreCase))
                        UdpPortTests.Add(p);
                }
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
                d.ResultColor = StatusHelpers.BrushForLogLevel(lvl);
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

            // Build per-failure recommendations off the captured results.
            BuildRecommendations(internet, ports, doms);

            UpdateStatusPill();
        }

        // Build the actionable per-failure recommendation list. Called at the
        // tail of RunTestAsync. One row per failed port, one per failed domain,
        // plus a top-level row when the box has no internet at all. Falls back
        // to a single "all clear" row when nothing failed.
        private void BuildRecommendations(bool internet, List<PortTestResult> ports, List<DomainTestResult> doms)
        {
            var built = new List<NetworkRecommendation>();

            if (!internet)
            {
                built.Add(NetworkRecommendation.Create(
                    "Critical",
                    "No internet ping",
                    "VPU has no internet connectivity. Verify the uplink cable and the gateway's WAN status before further triage."));
            }

            if (ports != null)
            {
                foreach (var p in ports)
                {
                    if (p == null || p.Status != "Fail") continue;
                    var purpose = string.IsNullOrEmpty(p.Purpose) ? "purpose unknown" : p.Purpose;
                    built.Add(NetworkRecommendation.Create(
                        "Critical",
                        $"{p.Protocol} {p.Port} blocked",
                        $"{p.Protocol}/{p.Port} ({purpose}) is blocked. Ensure outbound {p.Protocol} {p.Port} to {p.Host} is allowed by the venue firewall, content-filter, and VLAN policy."));
                }
            }

            if (doms != null)
            {
                foreach (var d in doms)
                {
                    if (d == null || d.Status != "Fail") continue;
                    built.Add(NetworkRecommendation.Create(
                        "Warning",
                        $"{d.Domain} unreachable",
                        $"Domain `{d.Domain}` is unreachable. Ensure `{d.Domain}` is whitelisted on the venue network (firewall, DNS allow-list, SSL inspection bypass)."));
                }
            }

            // Note: no "all clear" fallback row — when there are no failures
            // the Recommendations panel auto-collapses entirely (Visibility is
            // bound to Recommendations.Count via CountToVis), so the user only
            // sees this card when there's something actionable to do. The
            // page-level status pill already communicates the all-good state.

            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                Recommendations.Clear();
                foreach (var r in built) Recommendations.Add(r);
            });
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

        private void ClearRecommendations()
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() => Recommendations.Clear());
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
                int crit = Findings.Count(f => f.Severity == FindingSeverity.Critical);
                int warn = Findings.Count(f => f.Severity == FindingSeverity.Warning);
                var worst = StatusHelpers.WorstSeverity(Findings);
                var pill = StatusHelpers.PillFor(worst, warn, crit);
                StatusLabel = pill.Label;
                StatusColor = pill.Fg;
                StatusBg = pill.Bg;
            });
        }
    }
}
