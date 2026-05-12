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

        // Single primary internet-bound adapter — what the compact card binds to.
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

        // Protocol-split port-test collections — the view renders TCP and UDP
        // tiles in two side-by-side columns. Populated in RunTestAsync.
        public ObservableCollection<PortTestResult> TcpPortTests { get; } = new ObservableCollection<PortTestResult>();
        public ObservableCollection<PortTestResult> UdpPortTests { get; } = new ObservableCollection<PortTestResult>();
        public ObservableCollection<DomainTestResult> DomainTests { get; } = new ObservableCollection<DomainTestResult>();
        // Composed via PanelLogger (v0.5.0) — shared with the four other
        // panels. v0.5.5: PanelName tags every line in the rolling app log.
        public PanelLogger Logger { get; } = new PanelLogger("Network");
        private readonly ReportWriter _reportWriter = new ReportWriter();
        public ObservableCollection<LogEntry> LogEntries => Logger.Entries;
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
                var primary = _net.GetPrimaryInternetAdapter();
                var ipCfg = _net.GetIpConfiguration();
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    PrimaryAdapter = primary;
                    IpConfig = ipCfg;
                    OnPropertyChanged(nameof(IpAssignment));
                    DetectedNic = primary != null ? $"{primary.Name} — {primary.Ip}" : "No adapters detected";
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
            // Track required vs optional fails separately. Optional ports
            // (SportzCast 1402/1935, Zixi UDP/443 fallback) failing isn't a
            // Critical event — only required-port failures bubble up to the
            // page-header pill / Findings banner.
            int reqFail = 0, reqPass = 0, optFail = 0;
            foreach (var p in ports)
            {
                var lvl = p.Status == "Pass" ? "Pass" : (p.Status == "Fail" ? "Fail" : "Gray");
                AddLog($"{p.Protocol} {p.Port}", $"{p.Status} {p.Purpose}", lvl);
                p.ResultColor = StatusHelpers.BrushForLogLevel(lvl);
                if (p.Optional)
                {
                    if (p.Status == "Fail") optFail++;
                }
                else
                {
                    if (p.Status == "Pass") reqPass++;
                    else if (p.Status == "Fail") reqFail++;
                }
            }
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                TcpPortTests.Clear();
                UdpPortTests.Clear();
                foreach (var p in ports)
                {
                    if (string.Equals(p.Protocol, "TCP", System.StringComparison.OrdinalIgnoreCase))
                        TcpPortTests.Add(p);
                    else if (string.Equals(p.Protocol, "UDP", System.StringComparison.OrdinalIgnoreCase))
                        UdpPortTests.Add(p);
                }
            });
            // When the box has no internet at all, every port-blocked / domain-
            // unreachable result is downstream of that one root cause. Don't
            // surface them — they'd just be N copies of "go fix the cable".
            // The "VPU has no internet connection" critical Finding above
            // already covers it.
            if (internet)
            {
                if (reqFail > 0)
                {
                    AddFinding("Critical",
                        $"{reqFail} of {reqFail + reqPass} required ports failed",
                        "Check the firewall, router, or content-filter / VLAN policy.");
                }
                if (optFail > 0)
                {
                    AddFinding("Info",
                        $"{optFail} optional port(s) failed",
                        "Optional ports (SportzCast / Zixi UDP/443 fallback) aren't required at every venue. See Recommended Actions for context.");
                }
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
            if (internet && domFail > 0)
            {
                AddFinding("Warning",
                    $"{domFail} of {domFail + domPass} domains failed DNS resolution",
                    "Check DNS server settings on this adapter.");
            }
            // When !internet, the domain-resolution failures are downstream
            // of the same "no uplink" root cause and are suppressed —
            // see the comment on the required-ports finding above.

            // Build per-failure recommendations off the captured results.
            BuildRecommendations(internet, ports, doms);

            UpdateStatusPill();

            // v0.5.5: per-run report file — composes the same vocabulary as
            // the live log but as a static snapshot the tech can attach to a
            // ticket. AppLogFile already captured every AddLog above; the
            // per-run file is the user-facing artifact.
            try
            {
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    var path = _reportWriter.Save("Network", BuildReportText());
                    if (!string.IsNullOrEmpty(path))
                        AppLogFile.Instance.WriteLine("Network", "Info",
                            $"Report saved: {path}");
                });
            }
            catch { }
        }

        /// <summary>
        /// Compose the Network panel's per-run report body. Mirrors the
        /// vocabulary of System Overview's CopyInventoryToClipboard — section
        /// headers, key/value blocks, tables for port + domain collections,
        /// then a Findings / Recommendations / Live Log tail footer.
        /// </summary>
        public string BuildReportText()
        {
            var sb = new System.Text.StringBuilder();

            sb.AppendLine("== Primary Adapter ==");
            if (PrimaryAdapter == null)
            {
                sb.AppendLine("  (no adapter detected)");
            }
            else
            {
                sb.AppendLine($"  Name:        {PrimaryAdapter.Name}");
                sb.AppendLine($"  IP:          {PrimaryAdapter.Ip}");
                sb.AppendLine($"  MAC:         {PrimaryAdapter.Mac}");
                sb.AppendLine($"  Status:      {PrimaryAdapter.Status}");
                sb.AppendLine($"  Speed:       {PrimaryAdapter.Speed}");
            }

            sb.AppendLine();
            sb.AppendLine("== IP Configuration ==");
            sb.AppendLine($"  Assignment:  {IpAssignment}");
            sb.AppendLine($"  Adapter:     {IpConfig?.AdapterName}");
            sb.AppendLine($"  IPv4:        {IpConfig?.IpAddress}");
            sb.AppendLine($"  Subnet:      {IpConfig?.SubnetMask}");
            sb.AppendLine($"  Gateway:     {IpConfig?.Gateway}");
            sb.AppendLine($"  DNS:         {IpConfig?.DnsServers}");
            sb.AppendLine($"  NTP:         {IpConfig?.NtpServer}");
            sb.AppendLine($"  DHCP:        {IpConfig?.Dhcp}");

            sb.AppendLine();
            sb.AppendLine("== Port Tests ==");
            foreach (var p in TcpPortTests)
                sb.AppendLine($"  [{p.Status,-4}] TCP/{p.Port,-5} {p.Host}  ({p.Purpose})");
            foreach (var p in UdpPortTests)
                sb.AppendLine($"  [{p.Status,-4}] UDP/{p.Port,-5} {p.Host}  ({p.Purpose})");
            if (TcpPortTests.Count == 0 && UdpPortTests.Count == 0)
                sb.AppendLine("  (no port tests recorded — run a test first)");

            sb.AppendLine();
            sb.AppendLine("== Domain Tests ==");
            foreach (var d in DomainTests)
            {
                var detail = d.Status == "Pass" ? $" -> {d.ResolvedTo}" : "";
                sb.AppendLine($"  [{d.Status,-4}] {d.Domain}{detail}");
            }
            if (DomainTests.Count == 0)
                sb.AppendLine("  (no domain tests recorded — run a test first)");

            if (Findings.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== Findings ==");
                foreach (var f in Findings)
                    sb.AppendLine($"  [{f.Severity}] {f.Title}\n      -> {f.Recommendation}");
            }

            if (Recommendations.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== Recommendations ==");
                foreach (var r in Recommendations)
                    sb.AppendLine($"  [{r.Severity}] {r.Title}\n      -> {r.Body}");
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

                // Short-circuit: when the box has no internet, the per-port
                // and per-domain failures are all downstream of that one
                // root cause. Surfacing them as separate recommendations
                // just buries the actual fix ("check the cable") in a wall
                // of redundant "X is blocked" rows. Commit the single
                // upstream recommendation and bail.
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    Recommendations.Clear();
                    foreach (var r in built) Recommendations.Add(r);
                });
                return;
            }

            if (ports != null)
            {
                foreach (var p in ports)
                {
                    if (p == null || p.Status != "Fail") continue;
                    var purpose = string.IsNullOrEmpty(p.Purpose) ? "purpose unknown" : p.Purpose;
                    // NTP probe (UDP/123) failing is a special case — it's
                    // usually surfaced by the System Overview panel as a
                    // clock-skew finding too, so wire a direct cross-tab
                    // navigation action onto the recommendation row.
                    var isNtp = p.Port == 123 &&
                                string.Equals(p.Protocol, "UDP", System.StringComparison.OrdinalIgnoreCase);
                    NetworkRecommendation rec;
                    if (p.Optional)
                    {
                        // Optional ports (SportzCast 1402/1935, Zixi UDP/443
                        // fallback) aren't required at every venue. Soften the
                        // language so support doesn't get pointed at a firewall
                        // change they don't actually need.
                        rec = NetworkRecommendation.Create(
                            "Info",
                            $"{p.Protocol} {p.Port} blocked (optional)",
                            $"{p.Protocol}/{p.Port} ({purpose}) is blocked. This port may not be required at this venue — only act on this if streaming is failing in a way that points at this service. If it's actually required, ensure outbound {p.Protocol} {p.Port} to {p.Host} is allowed by the venue firewall.");
                    }
                    else
                    {
                        rec = NetworkRecommendation.Create(
                            "Critical",
                            isNtp ? "NTP time sync failed"
                                  : $"{p.Protocol} {p.Port} blocked",
                            isNtp
                                ? $"NTP time sync to {p.Host} failed (UDP/123). Without a clock peer the VPU's system time will drift, breaking signed-URL streaming and log-correlation. Check the System Overview panel for the live clock-skew value, and ensure outbound UDP/123 to {p.Host} is allowed."
                                : $"{p.Protocol}/{p.Port} ({purpose}) is blocked. Ensure outbound {p.Protocol} {p.Port} to {p.Host} is allowed by the venue firewall, content-filter, and VLAN policy.");
                    }
                    if (isNtp)
                    {
                        rec.ActionLabel = "Open System Overview";
                        rec.ActionCommand = new RelayCommand(() =>
                        {
                            try { Pulse.WPF.App.NavigateToTab("SystemOverview"); } catch { }
                        });
                    }
                    built.Add(rec);
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

        private void AddLog(string label, string result, string level) => Logger.Add(label, result, level);

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
