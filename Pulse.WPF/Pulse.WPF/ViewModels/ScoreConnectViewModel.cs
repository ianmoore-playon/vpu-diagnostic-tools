using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Backing VM for the Score Connect panel. Probes the local ScoreConnect
    /// III HTTP API (default <c>http://localhost:5000</c>, overridable via
    /// <see cref="AppSettings.ScoreConnectUrl"/>), surfaces the current
    /// scoreboard configuration + the cloud BOT connection state, and emits
    /// Findings + Recommendations from any failures.
    ///
    /// Structure mirrors <see cref="NetworkViewModel"/> — PanelLogger,
    /// ReportWriter, Findings, Recommendations, StatusLabel/Color/Bg pill.
    /// The write flows (Edit Vendor / Sport / Configuration / Decoder) ship
    /// in Phase 3; the WebSocket subscribe arrives in Phase 4.
    /// </summary>
    public class ScoreConnectViewModel : ObservableObject
    {
        private readonly IScoreConnectService _svc;

        // ---- Bindings ----

        private ScoreConnectStatus _status = new ScoreConnectStatus();
        public ScoreConnectStatus Status
        {
            get => _status;
            private set
            {
                if (Set(ref _status, value))
                {
                    OnPropertyChanged(nameof(IsDetected));
                    OnPropertyChanged(nameof(HasProbeError));
                    OnPropertyChanged(nameof(LastProbedAtDisplay));
                }
            }
        }

        public bool IsDetected => _status?.IsDetected ?? false;
        public bool HasProbeError => !string.IsNullOrEmpty(_status?.ProbeError);
        public string LastProbedAtDisplay =>
            _status?.LastProbedAt?.ToString("HH:mm:ss") ?? "Never";

        private ScoreConnectConfiguration _configuration = new ScoreConnectConfiguration();
        public ScoreConnectConfiguration Configuration
        {
            get => _configuration;
            private set
            {
                if (Set(ref _configuration, value))
                    OnPropertyChanged(nameof(HasConfiguration));
            }
        }
        public bool HasConfiguration => _configuration != null && !_configuration.IsEmpty;

        private ScoreConnectBotStatus _botStatus = new ScoreConnectBotStatus();
        public ScoreConnectBotStatus BotStatus
        {
            get => _botStatus;
            private set => Set(ref _botStatus, value);
        }

        private ScoreConnectLiveScoreData _liveScoreData = new ScoreConnectLiveScoreData();
        public ScoreConnectLiveScoreData LiveScoreData
        {
            get => _liveScoreData;
            private set => Set(ref _liveScoreData, value);
        }

        private bool _liveConnected;
        public bool LiveConnected
        {
            get => _liveConnected;
            set => Set(ref _liveConnected, value);
        }

        public ObservableCollection<ScoreConnectSerialPortInfo> AvailablePorts { get; }
            = new ObservableCollection<ScoreConnectSerialPortInfo>();

        public ObservableCollection<ScoreConnectVendorListItem> Vendors { get; }
            = new ObservableCollection<ScoreConnectVendorListItem>();

        public ObservableCollection<ScoreConnectVendorSportListItem> VendorSports { get; }
            = new ObservableCollection<ScoreConnectVendorSportListItem>();

        public ObservableCollection<ScoreConnectVendorConfigurationListItem> VendorConfigurations { get; }
            = new ObservableCollection<ScoreConnectVendorConfigurationListItem>();

        public ObservableCollection<ScoreConnectDeviceListItem> Devices { get; }
            = new ObservableCollection<ScoreConnectDeviceListItem>();

        // Renders the raw extended-fields map from the configuration response.
        public ObservableCollection<KeyValueRow> ConfigurationExtraRows { get; }
            = new ObservableCollection<KeyValueRow>();

        public PanelLogger Logger { get; } = new PanelLogger("ScoreConnect");
        private readonly ReportWriter _reportWriter = new ReportWriter();
        public ObservableCollection<LogEntry> LogEntries => Logger.Entries;
        public ObservableCollection<Finding> Findings { get; } = new ObservableCollection<Finding>();
        public ObservableCollection<NetworkRecommendation> Recommendations { get; }
            = new ObservableCollection<NetworkRecommendation>();
        public bool HasFindings => Findings.Count > 0;

        // ---- Pill state ----

        private string _statusLabel = "Idle";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }

        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }

        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        // ---- Commands ----

        public ICommand RefreshCommand { get; }
        public ICommand OpenScoreConnectGuiCommand { get; }

        // Phase 3 wires real edit dialogs onto these — Phase 2 ships stub
        // commands so the View bindings resolve cleanly.
        public ICommand EditVendorCommand { get; protected set; }
        public ICommand EditSportCommand { get; protected set; }
        public ICommand EditConfigurationCommand { get; protected set; }
        public ICommand EditDecoderCommand { get; protected set; }

        public ScoreConnectViewModel(IScoreConnectService svc)
        {
            _svc = svc ?? throw new ArgumentNullException(nameof(svc));
            RefreshCommand = new AsyncCommand(RefreshAsync);
            OpenScoreConnectGuiCommand = new RelayCommand(OpenScoreConnectGui);

            // Phase 2 stubs — replaced by real handlers in Phase 3.
            EditVendorCommand        = new RelayCommand(() => { });
            EditSportCommand         = new RelayCommand(() => { });
            EditConfigurationCommand = new RelayCommand(() => { });
            EditDecoderCommand       = new RelayCommand(() => { });
        }

        // ---------- Refresh ----------

        public async Task RefreshAsync()
        {
            ClearLogsAndFindings();
            ClearRecommendations();
            AddLog("", "Score Connect", "Section");
            SetPillRunning();

            // Phase 1: probe.
            var status = await _svc.ProbeAsync().ConfigureAwait(false);
            ApplyStatus(status);
            AddLog("Service",
                status.IsDetected
                    ? $"Detected at {status.BaseUrl}"
                    : $"Not detected at {status.BaseUrl} ({status.ProbeError})",
                status.IsDetected ? "Pass" : "Fail");

            if (!status.IsDetected)
            {
                AddFinding("Critical",
                    "ScoreConnect III service not detected",
                    "Verify the ScoreConnect III service is running on this VPU. Open the Pixellot Services panel to start it.");
                BuildRecommendations(detected: false);
                UpdateStatusPill();
                WriteReport();
                return;
            }

            // Phase 1: read every endpoint in parallel — they all share one
            // HttpClient but the loopback listener can comfortably handle
            // half-a-dozen overlapping reads.
            var cfgTask     = SafeAsync(_svc.GetCurrentConfigurationAsync, () => new ScoreConnectConfiguration());
            var botTask     = SafeAsync(_svc.GetBotStatusAsync,            () => new ScoreConnectBotStatus());
            var portsTask   = SafeAsync(_svc.GetAvailablePortsAsync,       () => new List<ScoreConnectSerialPortInfo>());
            var vendorsTask = SafeAsync(_svc.GetVendorsAsync,              () => new List<ScoreConnectVendorListItem>());
            var devicesTask = SafeAsync(_svc.GetDevicesAsync,              () => new List<ScoreConnectDeviceListItem>());

            await Task.WhenAll(cfgTask, botTask, portsTask, vendorsTask, devicesTask)
                      .ConfigureAwait(false);

            var cfg     = cfgTask.Result;
            var bot     = botTask.Result;
            var ports   = portsTask.Result;
            var vendors = vendorsTask.Result;
            var devices = devicesTask.Result;

            ApplyConfiguration(cfg);
            ApplyBotStatus(bot);
            ApplyPorts(ports);
            ApplyVendors(vendors);
            ApplyDevices(devices);

            AddLog("Configuration",
                cfg.IsEmpty ? "Not configured" : $"{cfg.Vendor} / {cfg.Sport}",
                cfg.IsEmpty ? "Warn" : "Pass");
            AddLog("Cloud (BOT)",
                bot.IsConnected ? "Connected" : "Disconnected",
                bot.IsConnected ? "Pass" : "Warn");
            AddLog("Serial ports", $"{ports.Count} visible", "Info");
            AddLog("Vendors", $"{vendors.Count} known", "Info");
            AddLog("Devices", $"{devices.Count} known", "Info");

            // Findings + Recommendations.
            BuildFindings(cfg, bot, ports);
            BuildRecommendations(detected: true);

            UpdateStatusPill();
            WriteReport();
        }

        // ---------- Findings + Recommendations ----------

        // Phase 5 fleshes this out further (firmware update + WS disconnect).
        // The Phase 2 surface covers the three failure classes we can detect
        // from the read endpoints alone.
        private void BuildFindings(
            ScoreConnectConfiguration cfg,
            ScoreConnectBotStatus bot,
            List<ScoreConnectSerialPortInfo> ports)
        {
            if (cfg == null || cfg.IsEmpty)
            {
                AddFinding("Warning",
                    "No scoreboard device configured",
                    "Open the ScoreConnect III GUI from this panel to configure a scoreboard.");
            }

            if (bot != null && !bot.IsConnected)
            {
                AddFinding("Warning",
                    "Cloud control unreachable",
                    "Check TCP/1402 + scorebot.sportzcast.net in the Network panel.");
            }

            // Serial-port conflict: ScoreConnect itself sees the port as
            // "in use" by something OTHER than its own decoder. We don't
            // know the owning process identity here — surface the COM port
            // and let the operator close whichever consumer is holding it.
            if (ports != null)
            {
                foreach (var p in ports)
                {
                    if (p.IsInUse && !string.Equals(p.OwningVendor, cfg?.Vendor,
                                                    StringComparison.OrdinalIgnoreCase))
                    {
                        AddFinding("Critical",
                            $"Serial port {p.Name} in use by another process",
                            "Close the other consumer or reassign the port in the ScoreConnect III GUI.");
                    }
                }
            }
        }

        // Mirror NetworkViewModel.BuildRecommendations vocabulary so the
        // Reports panel renders all the panels' recommendations the same way.
        private void BuildRecommendations(bool detected)
        {
            var built = new List<NetworkRecommendation>();

            if (!detected)
            {
                built.Add(NetworkRecommendation.Create(
                    "Critical",
                    "ScoreConnect III not detected",
                    "The local ScoreConnect III HTTP API isn't responding at " +
                    (Status?.BaseUrl ?? AppSettings.DefaultScoreConnectUrl) +
                    ". Open the Pixellot Services panel to start the service, " +
                    "or update the scoreConnectUrl setting if it's bound to a different port."));
            }
            else
            {
                if (Configuration == null || Configuration.IsEmpty)
                {
                    built.Add(NetworkRecommendation.Create(
                        "Warning",
                        "Scoreboard not configured",
                        "Click \"Open ScoreConnect GUI\" above to pick a vendor + sport. Once configured, the live scoreboard feed will populate the Live card."));
                }
                if (BotStatus != null && !BotStatus.IsConnected)
                {
                    var rec = NetworkRecommendation.Create(
                        "Warning",
                        "Cloud (BOT) control disconnected",
                        $"ScoreConnect can't reach {(string.IsNullOrEmpty(BotStatus.BotServerAddress) ? "the BOT server" : BotStatus.BotServerAddress)}. " +
                        "Confirm TCP/1402 is open to scorebot.sportzcast.net on the Network panel.");
                    rec.ActionLabel = "Open Network";
                    rec.ActionCommand = new RelayCommand(() =>
                    {
                        try { Pulse.WPF.App.NavigateToTab("Network"); } catch { }
                    });
                    built.Add(rec);
                }
            }

            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                Recommendations.Clear();
                foreach (var r in built) Recommendations.Add(r);
            });
        }

        // ---------- Apply helpers (dispatcher-marshalled) ----------

        private void ApplyStatus(ScoreConnectStatus s)
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() => Status = s);
        }

        private void ApplyConfiguration(ScoreConnectConfiguration cfg)
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                Configuration = cfg ?? new ScoreConnectConfiguration();
                ConfigurationExtraRows.Clear();
                if (cfg?.ExtendedFields != null)
                {
                    foreach (var kv in cfg.ExtendedFields)
                        ConfigurationExtraRows.Add(new KeyValueRow { Key = kv.Key, Value = kv.Value });
                }
            });
        }

        private void ApplyBotStatus(ScoreConnectBotStatus bot)
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                BotStatus = bot ?? new ScoreConnectBotStatus());
        }

        private void ApplyPorts(List<ScoreConnectSerialPortInfo> ports)
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                AvailablePorts.Clear();
                if (ports == null) return;
                foreach (var p in ports) AvailablePorts.Add(p);
            });
        }

        private void ApplyVendors(List<ScoreConnectVendorListItem> vendors)
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                Vendors.Clear();
                if (vendors == null) return;
                foreach (var v in vendors) Vendors.Add(v);
            });
        }

        private void ApplyDevices(List<ScoreConnectDeviceListItem> devices)
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                Devices.Clear();
                if (devices == null) return;
                foreach (var d in devices) Devices.Add(d);
            });
        }

        // ---------- Helpers ----------

        // Wrap any service call so an exception or null doesn't poison the
        // parallel WhenAll. Returns the fallback on any failure.
        private static async Task<T> SafeAsync<T>(Func<Task<T>> call, Func<T> fallback)
        {
            try
            {
                var v = await call().ConfigureAwait(false);
                return v != null ? v : fallback();
            }
            catch
            {
                return fallback();
            }
        }

        private void OpenScoreConnectGui()
        {
            var url = Status?.BaseUrl ?? AppSettings.Instance.ScoreConnectUrl;
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName        = url,
                    UseShellExecute = true,
                });
                AppLogFile.Instance.WriteLine("ScoreConnect", "Info",
                    $"Opened ScoreConnect GUI at {url}");
            }
            catch (Exception ex)
            {
                AppLogFile.Instance.WriteLine("ScoreConnect", "Fail",
                    $"Failed to open ScoreConnect GUI: {ex.Message}");
            }
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

        private void AddLog(string label, string result, string level) =>
            Logger.Add(label, result, level);

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
                StatusLabel = "Probing";
                StatusColor = StatusHelpers.Brush("YellowBrush");
                StatusBg    = StatusHelpers.Brush("WarnBgBrush");
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
                StatusBg    = pill.Bg;
            });
        }

        // ---------- Report (BuildReportText + write) ----------

        private void WriteReport()
        {
            try
            {
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    var path = _reportWriter.Save("ScoreConnect", BuildReportText());
                    if (!string.IsNullOrEmpty(path))
                        AppLogFile.Instance.WriteLine("ScoreConnect", "Info",
                            $"Report saved: {path}");
                });
            }
            catch { }
        }

        public string BuildReportText()
        {
            var sb = new StringBuilder();
            sb.AppendLine("== Service ==");
            sb.AppendLine($"  Detected:    {(Status?.IsDetected == true ? "Yes" : "No")}");
            sb.AppendLine($"  Base URL:    {Status?.BaseUrl}");
            sb.AppendLine($"  Version:     {(string.IsNullOrEmpty(Status?.Version) ? "—" : Status.Version)}");
            sb.AppendLine($"  Last probe:  {LastProbedAtDisplay}");
            if (!string.IsNullOrEmpty(Status?.ProbeError))
                sb.AppendLine($"  Last error:  {Status.ProbeError}");

            sb.AppendLine();
            sb.AppendLine("== Configuration ==");
            if (Configuration == null || Configuration.IsEmpty)
            {
                sb.AppendLine("  (no scoreboard configured)");
            }
            else
            {
                sb.AppendLine($"  Vendor:      {Configuration.Vendor}");
                sb.AppendLine($"  Sport:       {Configuration.Sport}");
                sb.AppendLine($"  Device:      {Configuration.Device}");
                sb.AppendLine($"  Serial port: {Configuration.SerialPort}");
                sb.AppendLine($"  Firmware:    {Configuration.Firmware}");
                sb.AppendLine($"  Event type:  {Configuration.EventType}");
                if (Configuration.ExtendedFields.Count > 0)
                {
                    sb.AppendLine("  Extended:");
                    foreach (var kv in Configuration.ExtendedFields)
                        sb.AppendLine($"    {kv.Key}: {kv.Value}");
                }
            }

            sb.AppendLine();
            sb.AppendLine("== Cloud (BOT) ==");
            if (BotStatus == null)
            {
                sb.AppendLine("  (not queried)");
            }
            else
            {
                sb.AppendLine($"  Connected:   {(BotStatus.IsConnected ? "Yes" : "No")}");
                sb.AppendLine($"  Server:      {BotStatus.BotServerAddress}");
                sb.AppendLine($"  ScoreConnect ID: {BotStatus.ScoreConnectId}");
                if (BotStatus.LastConnectedAt.HasValue)
                    sb.AppendLine($"  Last conn:   {BotStatus.LastConnectedAt.Value:yyyy-MM-dd HH:mm:ss}");
                if (!string.IsNullOrEmpty(BotStatus.LastErrorMessage))
                    sb.AppendLine($"  Last error:  {BotStatus.LastErrorMessage}");
            }

            sb.AppendLine();
            sb.AppendLine("== Serial Ports ==");
            if (AvailablePorts.Count == 0)
            {
                sb.AppendLine("  (no COM ports reported)");
            }
            else
            {
                foreach (var p in AvailablePorts)
                {
                    var owner = string.IsNullOrEmpty(p.OwningVendor) ? "" : $"  owner={p.OwningVendor}";
                    sb.AppendLine($"  {p.Name}  inUse={p.IsInUse}{owner}");
                }
            }

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
    }

    /// <summary>One row of the "extended fields" table on the configuration
    /// card. Lives in this file to keep the VM file self-contained — it isn't
    /// reused anywhere else.</summary>
    public class KeyValueRow
    {
        public string Key { get; set; } = "";
        public string Value { get; set; } = "";
    }
}
