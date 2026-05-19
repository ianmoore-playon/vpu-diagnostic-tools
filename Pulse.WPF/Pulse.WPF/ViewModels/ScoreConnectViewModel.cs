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
    /// Live scoreboard data is scraped from GraphicsManager's Sportzcast log
    /// so the panel reflects the feed Pixellot's graphics pipeline receives.
    /// </summary>
    public class ScoreConnectViewModel : ObservableObject
    {
        private readonly IScoreConnectService _svc;
        // The live scoreboard card is fed from GraphicsManager's own log.
        // That log contains the Sportzcast data after GraphicsManager parses
        // it and before it enters Pixellot's graphics pipeline, which makes
        // it a better field signal than the older best-guess WebSocket path.
        private readonly GraphicsManagerSportzcastLogFeed _graphicsManagerLogFeed =
            new GraphicsManagerSportzcastLogFeed();
        private bool _liveFeedStarted;

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

        private string _liveFeedDetail = "Waiting for GraphicsManager log";
        public string LiveFeedDetail
        {
            get => _liveFeedDetail;
            set => Set(ref _liveFeedDetail, value);
        }

        private string _liveFeedLogPath = "";
        public string LiveFeedLogPath
        {
            get => _liveFeedLogPath;
            set => Set(ref _liveFeedLogPath, value);
        }

        public string LiveFeedSourceLabel => "GraphicsManager log";

        public ObservableCollection<ScoreConnectSerialPortInfo> AvailablePorts { get; }
            = new ObservableCollection<ScoreConnectSerialPortInfo>();

        // v0.6.21: replaces the noisy "Available Serial Ports" list with a
        // one-bit answer. Bound by the Score Connect view's ScoreLink card.
        // Status is recomputed inside BaselineAsync (and on tab refresh) by
        // calling Pulse.WPF.Helpers.ScoreLinkDetector.Detect(), which reads
        // Win32_PnPEntity for currently-attached USB devices only — stale
        // entries from previous pairings don't appear.
        private bool _scoreLinkConnected;
        public bool ScoreLinkConnected
        {
            get => _scoreLinkConnected;
            set
            {
                if (Set(ref _scoreLinkConnected, value))
                    OnPropertyChanged(nameof(ScoreLinkStatusLabel));
            }
        }

        private string _scoreLinkPort = "";
        public string ScoreLinkPort
        {
            get => _scoreLinkPort;
            set
            {
                if (Set(ref _scoreLinkPort, value))
                    OnPropertyChanged(nameof(ScoreLinkStatusLabel));
            }
        }

        private string _scoreLinkModel = "";
        public string ScoreLinkModel
        {
            get => _scoreLinkModel;
            set
            {
                if (Set(ref _scoreLinkModel, value))
                    OnPropertyChanged(nameof(ScoreLinkStatusLabel));
            }
        }

        /// <summary>Composed one-line label for the ScoreLink card.</summary>
        public string ScoreLinkStatusLabel
        {
            get
            {
                if (!ScoreLinkConnected) return "ScoreLink not connected";
                var model = string.IsNullOrEmpty(ScoreLinkModel) ? "ScoreLink" : ScoreLinkModel;
                if (string.IsNullOrEmpty(ScoreLinkPort))
                    return $"{model} device connected";
                return $"{model} device connected ({ScoreLinkPort})";
            }
        }

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
        public string LastReportPath { get; private set; }
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

        // Edit commands open guarded picker dialogs and require a second
        // confirmation before writing to ScoreConnect III.
        public ICommand EditVendorCommand { get; protected set; }
        public ICommand EditSportCommand { get; protected set; }
        public ICommand EditConfigurationCommand { get; protected set; }
        public ICommand EditDecoderCommand { get; protected set; }

        public ScoreConnectViewModel(IScoreConnectService svc)
        {
            _svc = svc ?? throw new ArgumentNullException(nameof(svc));
            _graphicsManagerLogFeed.MessageReceived += OnLiveMessageReceived;
            _graphicsManagerLogFeed.ConnectionStateChanged += OnLiveConnectionStateChanged;
            _graphicsManagerLogFeed.StatusChanged += OnLiveFeedStatusChanged;
            AppSettings.Instance.ScoreConnectUrlChanged += OnScoreConnectUrlChanged;

            RefreshCommand = new AsyncCommand(RefreshAsync);
            OpenScoreConnectGuiCommand = new RelayCommand(OpenScoreConnectGui);

            // v0.6.0 Phase 3 — Edit commands open a picker dialog populated
            // from the read endpoints, then a second confirm before invoking
            // the corresponding Set* service method.
            EditVendorCommand        = new AsyncCommand(EditVendorAsync);
            EditSportCommand         = new AsyncCommand(EditSportAsync);
            EditConfigurationCommand = new AsyncCommand(EditConfigurationAsync);
            EditDecoderCommand       = new AsyncCommand(EditDecoderAsync);
        }

        private void OnScoreConnectUrlChanged(string url)
        {
            AppLogFile.Instance.WriteLine("ScoreConnect", "Info",
                $"ScoreConnect URL changed -> {url}");
            _ = RefreshAsync();
        }

        // ---------- Phase 3: write flows ----------

        // Shared two-stage confirm. Returns the chosen id when the user
        // commits, null when they bail at either prompt. <paramref name="loadItems"/>
        // is called from the dispatcher thread so it can block on a service
        // read — callers should keep it cheap (10s is the write-timeout
        // ceiling, but we don't bound the read here; the service does).
        private async Task<string> PromptAsync(
            string title,
            string description,
            Func<Task<List<ScoreConnectListItem>>> loadItems,
            string currentSelectionId)
        {
            if (!IsDetected) return null;

            List<ScoreConnectListItem> items;
            try
            {
                items = await loadItems().ConfigureAwait(false);
            }
            catch
            {
                items = new List<ScoreConnectListItem>();
            }
            if (items == null || items.Count == 0)
            {
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    System.Windows.MessageBox.Show(
                        $"ScoreConnect III didn't return any options for \"{title}\". " +
                        "Try Refresh, or open the ScoreConnect GUI to verify the service is configured.",
                        title,
                        System.Windows.MessageBoxButton.OK,
                        System.Windows.MessageBoxImage.Information);
                });
                return null;
            }

            string chosenId = null;
            string chosenName = null;
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                var owner = System.Windows.Application.Current?.MainWindow;
                var dlg = new Views.ScoreConnectPickerDialog(title, description, items, currentSelectionId)
                {
                    Owner = owner,
                };
                var ok = dlg.ShowDialog();
                if (ok == true)
                {
                    chosenId = dlg.SelectedId;
                    chosenName = dlg.SelectedName;
                }
            });
            if (string.IsNullOrEmpty(chosenId)) return null;

            // Second-stage confirm — every write to ScoreConnect III may
            // interrupt a live feed, so make the user re-affirm.
            bool confirmed = false;
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                var resp = System.Windows.MessageBox.Show(
                    $"Set {title.ToLowerInvariant()} to \"{chosenName}\"?\n\n" +
                    "This will reconfigure ScoreConnect III and may interrupt live data. Continue?",
                    "Confirm ScoreConnect change",
                    System.Windows.MessageBoxButton.OKCancel,
                    System.Windows.MessageBoxImage.Warning,
                    System.Windows.MessageBoxResult.Cancel);
                confirmed = resp == System.Windows.MessageBoxResult.OK;
            });
            if (!confirmed) return null;

            AppLogFile.Instance.WriteLine("ScoreConnect", "Info",
                $"Operator confirmed change: {title} -> {chosenName} ({chosenId})");
            return chosenId;
        }

        private async Task EditVendorAsync()
        {
            // v0.6.3: ScoreConnect III has no standalone select-vendor
            // endpoint (verified against swagger.json — only select-vendor-
            // sport and select-vendor-configuration exist). Vendor selection
            // happens implicitly through picking a vendor-sport. So Edit
            // Vendor is now a two-step flow: pick vendor -> pick one of
            // that vendor's sports -> PUT select-vendor-sport. The
            // confirmed-change audit log line records both legs.
            var vendor = await PromptAsync(
                "Vendor",
                "Choose the scoreboard vendor. ScoreConnect requires a sport to be picked alongside the vendor — you'll pick one in the next step.",
                async () =>
                {
                    var list = await _svc.GetVendorsAsync().ConfigureAwait(false);
                    return list.Cast<ScoreConnectListItem>().ToList();
                },
                Configuration?.Vendor).ConfigureAwait(false);
            if (vendor == null) return;

            var sport = await PromptAsync(
                "Sport",
                $"Choose a sport for {vendor}. ScoreConnect will switch to the new vendor and sport in one operation.",
                async () =>
                {
                    var list = await _svc.GetVendorSportsAsync(vendor).ConfigureAwait(false);
                    return list.Cast<ScoreConnectListItem>().ToList();
                },
                null).ConfigureAwait(false);
            if (sport == null) return;

            var ok = await _svc.SetVendorSportAsync(sport).ConfigureAwait(false);
            await ReportWriteResultAsync("Vendor", $"{vendor} / sport {sport}", ok).ConfigureAwait(false);
        }

        private async Task EditSportAsync()
        {
            // Sports are scoped by the currently-configured vendor's id —
            // we only have the vendor *name* on the typed configuration
            // model, so resolve the id from the vendor list first.
            var vendorId = await ResolveCurrentVendorIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(vendorId))
            {
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    System.Windows.MessageBox.Show(
                        "Pick a vendor first — the sport list is scoped to the chosen vendor.",
                        "Sport",
                        System.Windows.MessageBoxButton.OK,
                        System.Windows.MessageBoxImage.Information);
                });
                return;
            }

            var chosen = await PromptAsync(
                "Sport",
                "Choose the sport. Changing sport typically resets the active scoreboard data layout.",
                async () =>
                {
                    var list = await _svc.GetVendorSportsAsync(vendorId).ConfigureAwait(false);
                    return list.Cast<ScoreConnectListItem>().ToList();
                },
                Configuration?.Sport).ConfigureAwait(false);
            if (chosen == null) return;

            var ok = await _svc.SetVendorSportAsync(chosen).ConfigureAwait(false);
            await ReportWriteResultAsync("Sport", chosen, ok).ConfigureAwait(false);
        }

        private async Task EditConfigurationAsync()
        {
            // Configurations are scoped by the current vendor-sport. We have
            // the sport NAME, not id — resolve through the vendor's sport list.
            var vendorId = await ResolveCurrentVendorIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(vendorId))
            {
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    System.Windows.MessageBox.Show(
                        "Pick a vendor and sport first — vendor configurations are scoped to a specific sport.",
                        "Vendor configuration",
                        System.Windows.MessageBoxButton.OK,
                        System.Windows.MessageBoxImage.Information);
                });
                return;
            }
            var sportId = await ResolveCurrentVendorSportIdAsync(vendorId).ConfigureAwait(false);
            if (string.IsNullOrEmpty(sportId))
            {
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    System.Windows.MessageBox.Show(
                        "Couldn't resolve the current vendor-sport id from the configuration. Try Refresh and retry.",
                        "Vendor configuration",
                        System.Windows.MessageBoxButton.OK,
                        System.Windows.MessageBoxImage.Information);
                });
                return;
            }

            var chosen = await PromptAsync(
                "Vendor configuration",
                "Choose a vendor configuration. Configurations bundle device + protocol + scoreboard layout.",
                async () =>
                {
                    var list = await _svc.GetVendorConfigurationsAsync(sportId).ConfigureAwait(false);
                    return list.Cast<ScoreConnectListItem>().ToList();
                },
                Configuration?.VendorConfigurationId).ConfigureAwait(false);
            if (chosen == null) return;

            var ok = await _svc.SetVendorConfigurationAsync(chosen).ConfigureAwait(false);
            await ReportWriteResultAsync("Vendor configuration", chosen, ok).ConfigureAwait(false);
        }

        private async Task EditDecoderAsync()
        {
            // The decoder write needs a vendorSportId + serialPort. Reuse
            // the available-ports list as the picker; we don't expose serial
            // port discovery as its own endpoint here.
            var vendorId = await ResolveCurrentVendorIdAsync().ConfigureAwait(false);
            var sportId  = string.IsNullOrEmpty(vendorId)
                ? null
                : await ResolveCurrentVendorSportIdAsync(vendorId).ConfigureAwait(false);
            if (string.IsNullOrEmpty(sportId))
            {
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    System.Windows.MessageBox.Show(
                        "Pick a vendor and sport first — the decoder is bound to a vendor-sport.",
                        "Decoder",
                        System.Windows.MessageBoxButton.OK,
                        System.Windows.MessageBoxImage.Information);
                });
                return;
            }

            var chosen = await PromptAsync(
                "Serial port",
                "Choose the COM port the scoreboard decoder should listen on. Make sure no other process is currently holding the port open.",
                () => Task.FromResult(AvailablePorts
                    .Select(p => (ScoreConnectListItem)new ScoreConnectVendorListItem
                    {
                        Id   = p.Name,
                        Name = p.IsInUse ? $"{p.Name}  (in use)" : p.Name,
                    })
                    .ToList()),
                Configuration?.SerialPort).ConfigureAwait(false);
            if (chosen == null) return;

            var ok = await _svc.SetDecoderInfoAsync(sportId, chosen).ConfigureAwait(false);
            await ReportWriteResultAsync("Decoder serial port", chosen, ok).ConfigureAwait(false);
        }

        // Cross-reference the typed Configuration.Vendor name back to its
        // list-item id. ScoreConnect returns the name on the configuration
        // response but the Set* writes expect ids.
        private async Task<string> ResolveCurrentVendorIdAsync()
        {
            if (Vendors.Count == 0)
            {
                try
                {
                    var list = await _svc.GetVendorsAsync().ConfigureAwait(false);
                    ApplyVendors(list);
                }
                catch { }
            }
            var name = Configuration?.Vendor;
            if (string.IsNullOrEmpty(name)) return null;
            var match = Vendors.FirstOrDefault(v =>
                string.Equals(v.Name, name, StringComparison.OrdinalIgnoreCase));
            return match?.Id;
        }

        private async Task<string> ResolveCurrentVendorSportIdAsync(string vendorId)
        {
            if (string.IsNullOrEmpty(vendorId)) return null;
            try
            {
                var list = await _svc.GetVendorSportsAsync(vendorId).ConfigureAwait(false);
                if (list == null) return null;
                var name = Configuration?.Sport;
                if (string.IsNullOrEmpty(name)) return null;
                var match = list.FirstOrDefault(v =>
                    string.Equals(v.Name, name, StringComparison.OrdinalIgnoreCase));
                return match?.Id;
            }
            catch { return null; }
        }

        private async Task ReportWriteResultAsync(string what, string value, bool ok)
        {
            if (ok)
            {
                AppLogFile.Instance.WriteLine("ScoreConnect", "Pass",
                    $"{what} updated -> {value}");
                AddLog(what, $"Updated -> {value}", "Pass");
                // Refresh so the panel shows the new state.
                await RefreshAsync().ConfigureAwait(false);
            }
            else
            {
                AppLogFile.Instance.WriteLine("ScoreConnect", "Fail",
                    $"{what} update failed (value={value})");
                AddLog(what, $"Update failed", "Fail");
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    var rec = NetworkRecommendation.Create(
                        "Critical",
                        $"{what} change failed",
                        $"ScoreConnect III rejected the {what.ToLowerInvariant()} update. " +
                        "Check the rolling app log for the HTTP status, then verify the value is still valid in the ScoreConnect GUI.");
                    Recommendations.Insert(0, rec);
                });
            }
        }

        // ---------- Refresh ----------

        public async Task RefreshAsync()
        {
            ClearLogsAndFindings();
            ClearRecommendations();
            AddLog("", "Score Connect", "Section");
            SetPillRunning();
            await EnsureLiveFeedStartedAsync().ConfigureAwait(false);

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

            // v0.6.3: backfill Device / SerialPort / Firmware / EventType
            // from get-selected-vendor-sport and get-selected-vendor-
            // configuration. The main get-current-configuration response
            // doesn't always carry these even when ScoreConnect knows them.
            try { await _svc.FillSelectedVendorSportAsync(cfg).ConfigureAwait(false); } catch { }
            try { await _svc.FillSelectedVendorConfigurationAsync(cfg).ConfigureAwait(false); } catch { }

            ApplyConfiguration(cfg);
            ApplyBotStatus(bot);
            ApplyPorts(ports);
            ApplyVendors(vendors);
            ApplyDevices(devices);

            AddLog("Configuration",
                cfg.IsEmpty ? "Not configured" : $"{cfg.Vendor} / {cfg.Sport}",
                cfg.IsEmpty ? "Warn" : "Pass");
            // v0.6.3: BOT discovery is unreliable on ScoreConnect III itself
            // (known upstream limitation — even the native GUI often fails
            // to identify the BOT over USB). "Disconnected" is Info, not
            // Warn — it's not actionable from Pulse and the user can't fix
            // it without restarting ScoreConnect.
            AddLog("Cloud (BOT)",
                bot.IsConnected ? $"BOT identified (#{bot.ScoreConnectId})" : "BOT not identified (upstream limitation)",
                bot.IsConnected ? "Pass" : "Info");
            AddLog("Serial ports", $"{ports.Count} visible", "Info");
            AddLog("Vendors", $"{vendors.Count} known", "Info");
            AddLog("Devices", $"{devices.Count} known", "Info");

            // v0.6.21 / v0.6.22: detect a currently-plugged ScoreLink box.
            // Matches the bus-reported device description ("MCP2221 USB-I2C/
            // UART Combo" or "ScoreLinkII") via the registry-backed PnP
            // property store — Win32_PnPEntity's Caption/Name/Description
            // carry the driver friendly name, not the bus-reported value.
            // On a miss, the candidate pool of USB-serial devices is dumped
            // to the live log so the tech can see what's actually visible
            // and report back the correct description string if a real
            // ScoreLink isn't being recognised.
            try
            {
                var sl = await Task.Run(Pulse.WPF.Helpers.ScoreLinkDetector.Detect).ConfigureAwait(false);
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    ScoreLinkConnected = sl.IsConnected;
                    ScoreLinkPort      = sl.PortName ?? "";
                    ScoreLinkModel     = sl.Model ?? "";
                });
                if (sl.IsConnected)
                {
                    var pStr = string.IsNullOrEmpty(sl.PortName) ? "no COM port" : sl.PortName;
                    var matched = string.IsNullOrEmpty(sl.MatchedDescription)
                        ? sl.Model
                        : $"{sl.Model} - matched on \"{sl.MatchedDescription}\"";
                    AddLog("ScoreLink", $"{matched} connected ({pStr})", "Pass");
                }
                else if (sl.AllUsbSerialCandidates.Count == 0)
                {
                    AddLog("ScoreLink", "Not connected (no USB-serial devices visible)", "Info");
                }
                else
                {
                    AddLog("ScoreLink",
                        $"No match - {sl.AllUsbSerialCandidates.Count} USB-serial device(s) visible:",
                        "Info");
                    foreach (var c in sl.AllUsbSerialCandidates)
                    {
                        // One log line per device with everything we know,
                        // so the tech can spot the actual string we should
                        // be matching on.
                        var bus = string.IsNullOrEmpty(c.BusReportedDescription) ? "(no bus desc)" : c.BusReportedDescription;
                        var cap = string.IsNullOrEmpty(c.Caption)                ? "(no caption)" : c.Caption;
                        AddLog($"ScoreLink {c.PortName}",
                            $"bus=\"{bus}\"  caption=\"{cap}\"",
                            "Info");
                    }
                }
            }
            catch (Exception ex)
            {
                AddLog("ScoreLink", $"Detection failed: {ex.Message}", "Warn");
            }

            // Firmware update — Info finding when one's advertised. The
            // call is deliberately not parallelised with the main read fan
            // because the Sportzcast update API can be slow / 404; we
            // don't want it gating the rest of the panel.
            try
            {
                var fwUpdate = await _svc.GetAvailableFirmwareUpdateAsync().ConfigureAwait(false);
                if (!string.IsNullOrEmpty(fwUpdate))
                {
                    AddFinding("Info",
                        $"Firmware update {fwUpdate} available",
                        "Open the ScoreConnect III GUI to install the available scoreboard firmware update.");
                    AddLog("Firmware", $"Update available: {fwUpdate}", "Info");
                }
            }
            catch { }

            // Findings + Recommendations.
            BuildFindings(cfg, bot, ports);
            BuildRecommendations(detected: true);

            UpdateStatusPill();
            WriteReport();
        }

        private async Task EnsureLiveFeedStartedAsync()
        {
            if (_liveFeedStarted) return;
            _liveFeedStarted = true;
            try
            {
                await _graphicsManagerLogFeed.StartAsync().ConfigureAwait(false);
                AppLogFile.Instance.WriteLine("ScoreConnect", "Info",
                    "GraphicsManager Sportzcast log feed started.");
            }
            catch (Exception ex)
            {
                _liveFeedStarted = false;
                AppLogFile.Instance.WriteLine("ScoreConnect", "Warn",
                    $"Failed to start GraphicsManager log feed: {ex.Message}");
            }
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

            // v0.6.3: BOT identity is unreliable upstream — even the native
            // ScoreConnect III GUI often fails to identify a BOT over USB.
            // Don't false-alarm. The Recommended Actions card surfaces an
            // Info-level row instead so the user has context without a
            // Critical/Warning pill on the page header.

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
                    // v0.6.3: BOT identification is an upstream limitation —
                    // ScoreConnect III itself often can't see a USB-connected
                    // BOT. Downgrade to Info, change copy to reflect that
                    // this isn't actionable from Pulse, and keep the
                    // "Open Network" jump for the case where the user wants
                    // to verify TCP/1402 anyway.
                    var rec = NetworkRecommendation.Create(
                        "Info",
                        "BOT not identified",
                        "ScoreConnect III hasn't identified a BOT. This is a known upstream limitation — even the native ScoreConnect GUI often fails to see a USB-connected BOT. Try unplug/replug the BOT or restart ScoreConnect III. If you also want to confirm cloud reachability, the Network panel tests TCP/1402 + scorebot.sportzcast.net.");
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
            var url = _svc.BaseUrl;
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

        // ---------- Live GraphicsManager / Sportzcast data ----------

        // Best-effort projection of an inbound live frame onto LiveScoreData.
        // The GraphicsManager tailer emits the same typed key names as the
        // older WebSocket path, so this parser can remain tolerant of both.
        // Mutation is partial — a frame that only carries a clock update
        // doesn't clobber the home/away scores.
        private void OnLiveMessageReceived(string raw, Dictionary<string, object> parsed)
        {
            if (string.IsNullOrEmpty(raw)) return;

            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                var data = LiveScoreData ?? new ScoreConnectLiveScoreData();
                if (parsed != null)
                {
                    ApplyIfPresent(parsed, "homeScore",  "HomeScore", "scoreHome",
                                   v => data.HomeScore = v);
                    ApplyIfPresent(parsed, "awayScore",  "AwayScore", "scoreAway",
                                   v => data.AwayScore = v);
                    ApplyIfPresent(parsed, "homeTeam",   "HomeTeam",  "teamHome",
                                   v => data.HomeTeam = v);
                    ApplyIfPresent(parsed, "awayTeam",   "AwayTeam",  "teamAway",
                                   v => data.AwayTeam = v);
                    ApplyIfPresent(parsed, "period",     "Period",    "quarter", "inning",
                                   v => data.Period = v);
                    ApplyIfPresent(parsed, "clock",      "Clock",     "gameClock",
                                   v => data.Clock = v);

                    // Anything we didn't typed-bind goes into ExtendedFields
                    // — these are visible in the report so we never silently
                    // lose data on a schema drift.
                    foreach (var kv in parsed)
                    {
                        if (IsTypedLiveKey(kv.Key)) continue;
                        var s = kv.Value?.ToString() ?? "";
                        if (s.Length > 0 && s.Length < 200)
                            data.ExtendedFields[kv.Key] = s;
                    }
                }
                else
                {
                    // Non-JSON frame — surface the raw text in ExtendedFields
                    // and log a single Info line so the operator can see
                    // something arrived.
                    data.ExtendedFields["__raw"] = raw.Length > 300 ? raw.Substring(0, 300) + "..." : raw;
                }
                data.LastUpdatedAt = ParsedLogTimestampLocal(parsed) ?? DateTime.Now;
                LiveScoreData = data;
            });
        }

        private static DateTime? ParsedLogTimestampLocal(Dictionary<string, object> parsed)
        {
            try
            {
                if (parsed == null || !parsed.TryGetValue("logTimestampUtc", out var value) || value == null)
                    return null;
                if (DateTimeOffset.TryParse(Convert.ToString(value), out var dto))
                    return dto.ToLocalTime().DateTime;
            }
            catch { }
            return null;
        }

        private void OnLiveFeedStatusChanged(string status, string path)
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                LiveFeedDetail = string.IsNullOrWhiteSpace(status)
                    ? "Waiting for GraphicsManager log"
                    : status;
                LiveFeedLogPath = path ?? "";
            });
        }

        private static void ApplyIfPresent(
            Dictionary<string, object> map, string a, string b, string c,
            Action<string> setter)
        {
            ApplyIfPresent(map, new[] { a, b, c }, setter);
        }
        private static void ApplyIfPresent(
            Dictionary<string, object> map, string a, string b, string c, string d,
            Action<string> setter)
        {
            ApplyIfPresent(map, new[] { a, b, c, d }, setter);
        }
        private static void ApplyIfPresent(
            Dictionary<string, object> map, string[] keys, Action<string> setter)
        {
            foreach (var k in keys)
            {
                if (map.TryGetValue(k, out var v) && v != null)
                {
                    var s = v.ToString();
                    if (!string.IsNullOrEmpty(s)) { setter(s); return; }
                }
            }
        }

        private static bool IsTypedLiveKey(string key)
        {
            if (string.IsNullOrEmpty(key)) return true;
            switch (key.ToLowerInvariant())
            {
                case "homescore": case "scorehome":
                case "awayscore": case "scoreaway":
                case "hometeam":  case "teamhome":
                case "awayteam":  case "teamaway":
                case "period":    case "quarter": case "inning":
                case "clock":     case "gameclock":
                    return true;
            }
            return false;
        }

        // -- Live-feed flap detection (v0.6.20) ---------------------------
        // Track recent disconnect timestamps so we can:
        //   * Clear the stale "Live data feed disconnected" Warning when the
        //     feed reconnects (otherwise the finding persisted across a
        //     successful reconnect — field tech had to navigate away+back to
        //     dismiss it).
        //   * Escalate the wording to "Live data feed flapping" when we see
        //     more than 2 disconnects within the flap window (5 min).
        private const string LiveFeedDisconnectTitle = "Live data feed disconnected";
        private const string LiveFeedFlappingTitle   = "Live data feed flapping";
        private static readonly TimeSpan FlapWindow  = TimeSpan.FromMinutes(5);
        private const int FlapCountThreshold         = 2;   // 3rd disconnect inside the window -> flapping
        private readonly System.Collections.Generic.List<DateTime> _liveDisconnectTimes
            = new System.Collections.Generic.List<DateTime>();
        private readonly object _liveFeedFindingGate = new object();

        // Toggle the LIVE / OFFLINE pill in the Live Scoreboard card. When
        // the GraphicsManager log feed goes stale mid-session, also surface
        // a Warning finding + recommendation so the operator notices. On
        // reconnect, the matching Warning is removed and a one-shot Info
        // line is written to the live log so the tech has a paper trail.
        private void OnLiveConnectionStateChanged(bool connected)
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                bool wasConnected = LiveConnected;
                LiveConnected = connected;

                if (wasConnected && !connected)
                {
                    // Disconnect transition. Record timestamp and decide
                    // whether this counts as flapping. Older entries outside
                    // the flap window are pruned first so the count reflects
                    // recent history only.
                    DateTime now = DateTime.UtcNow;
                    int recentCount;
                    lock (_liveFeedFindingGate)
                    {
                        _liveDisconnectTimes.RemoveAll(t => (now - t) > FlapWindow);
                        _liveDisconnectTimes.Add(now);
                        recentCount = _liveDisconnectTimes.Count;
                    }
                    if (recentCount > FlapCountThreshold)
                    {
                        ReplaceLiveFeedFinding(
                            LiveFeedFlappingTitle,
                            $"Pulse has seen the Sportzcast log feed disconnect {recentCount} times in the last {FlapWindow.TotalMinutes:F0} minutes. Check the GraphicsManager process, the Sportzcast device's serial cable, and the venue's power for the scoreboard hardware.");
                        AddLog("LiveFeed", $"Flapping: {recentCount} disconnects in {FlapWindow.TotalMinutes:F0} min", "Warn");
                    }
                    else
                    {
                        ReplaceLiveFeedFinding(
                            LiveFeedDisconnectTitle,
                            "Pulse stopped seeing fresh Sportzcast frames in the GraphicsManager log. Confirm GraphicsManager is running and receiving data from the Sportzcast device.");
                        AddLog("LiveFeed", "Disconnected", "Warn");
                    }
                    UpdateStatusPill();
                }
                else if (!wasConnected && connected)
                {
                    // Reconnect. Clear any of our live-feed warnings; the
                    // tech doesn't need to see the stale "disconnected"
                    // chip after the feed has actually come back. Log a
                    // one-shot Info line so the recovery is recorded.
                    bool removedAny = RemoveLiveFeedFindings();
                    if (removedAny)
                    {
                        AddLog("LiveFeed", "Reconnected — clearing prior warning", "Pass");
                    }
                    else
                    {
                        AddLog("LiveFeed", "Connected", "Pass");
                    }
                    UpdateStatusPill();
                }
            });
        }

        // Replace any prior live-feed finding (disconnect OR flapping) with a
        // fresh one. Keeps the Findings list from accumulating duplicates
        // when the feed flaps; the most-recent message wins.
        private void ReplaceLiveFeedFinding(string title, string recommendation)
        {
            // Must run on the UI thread because Findings is bound to an
            // ItemsControl. Callers already dispatcher-invoke into here.
            RemoveLiveFeedFindings();
            var f = Pulse.WPF.Models.Finding.Create("Warning", title, recommendation);
            Findings.Add(f);
            OnPropertyChanged(nameof(HasFindings));
        }

        // Returns true if any existing live-feed finding was removed.
        private bool RemoveLiveFeedFindings()
        {
            bool removed = false;
            for (int i = Findings.Count - 1; i >= 0; i--)
            {
                var t = Findings[i]?.Title ?? "";
                if (t == LiveFeedDisconnectTitle || t == LiveFeedFlappingTitle)
                {
                    Findings.RemoveAt(i);
                    removed = true;
                }
            }
            if (removed) OnPropertyChanged(nameof(HasFindings));
            return removed;
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
                    {
                        LastReportPath = path;
                        AppLogFile.Instance.WriteLine("ScoreConnect", "Info",
                            $"Report saved: {path}");
                    }
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
                sb.AppendLine($"  Vendor:        {Configuration.Vendor}");
                sb.AppendLine($"  Sport:         {Configuration.Sport}");
                sb.AppendLine($"  Configuration: {Configuration.VendorConfigurationName}");
                sb.AppendLine($"  Device:        {Configuration.Device}");
                sb.AppendLine($"  Serial port:   {Configuration.SerialPort}");
                sb.AppendLine($"  Firmware:      {Configuration.Firmware}");
                sb.AppendLine($"  Event type:    {Configuration.EventType}");
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
            sb.AppendLine("== Live Scoreboard Feed ==");
            sb.AppendLine($"  Source:      {LiveFeedSourceLabel}");
            sb.AppendLine($"  Status:      {(LiveConnected ? "Live" : "Offline")}");
            sb.AppendLine($"  Detail:      {LiveFeedDetail}");
            if (!string.IsNullOrWhiteSpace(LiveFeedLogPath))
                sb.AppendLine($"  Log path:    {LiveFeedLogPath}");
            if (LiveScoreData != null)
            {
                sb.AppendLine($"  Home score:  {LiveScoreData.HomeScore}");
                sb.AppendLine($"  Away score:  {LiveScoreData.AwayScore}");
                sb.AppendLine($"  Period:      {LiveScoreData.Period}");
                sb.AppendLine($"  Clock:       {LiveScoreData.Clock}");
                if (LiveScoreData.LastUpdatedAt.HasValue)
                    sb.AppendLine($"  Updated:     {LiveScoreData.LastUpdatedAt.Value:yyyy-MM-dd HH:mm:ss}");
                if (LiveScoreData.ExtendedFields.Count > 0)
                {
                    sb.AppendLine("  Extended:");
                    foreach (var kv in LiveScoreData.ExtendedFields)
                        sb.AppendLine($"    {kv.Key}: {kv.Value}");
                }
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
