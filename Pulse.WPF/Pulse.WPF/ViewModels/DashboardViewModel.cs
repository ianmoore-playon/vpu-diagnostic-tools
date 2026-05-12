using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Dashboard (home) panel VM. Renders the one-page snapshot returned by
    /// IDashboardService.CollectSnapshotAsync — identity, gauges, NIC ports,
    /// network config, services, volumes, and rolled-up findings — plus the
    /// 8-tile Quick Nav row at the bottom for getting to a specific panel.
    /// </summary>
    public class DashboardViewModel : ObservableObject
    {
        private readonly IDashboardService _svc;
        private readonly ReportWriter _reportWriter = new ReportWriter();

        // ---- Quick Nav tiles + last-run summary (kept from v0.2.0) ----------
        public ObservableCollection<HubTileViewModel> Tiles { get; } =
            new ObservableCollection<HubTileViewModel>();

        private string _lastRunSummary = "Last Run: Never";
        public string LastRunSummary { get => _lastRunSummary; set => Set(ref _lastRunSummary, value); }
        private Brush _lastRunColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush LastRunColor { get => _lastRunColor; set => Set(ref _lastRunColor, value); }

        // ---- Identity card --------------------------------------------------
        private string _vpuLabel = "—";
        public string VpuLabel { get => _vpuLabel; set => Set(ref _vpuLabel, value); }
        private string _vpuModel = "—";
        public string VpuModel { get => _vpuModel; set => Set(ref _vpuModel, value); }
        private string _hostname = "—";
        public string Hostname { get => _hostname; set => Set(ref _hostname, value); }
        private string _manufacturer = "—";
        public string Manufacturer { get => _manufacturer; set => Set(ref _manufacturer, value); }
        private string _productName = "—";
        public string ProductName { get => _productName; set => Set(ref _productName, value); }
        private string _serialNumber = "—";
        public string SerialNumber { get => _serialNumber; set => Set(ref _serialNumber, value); }

        // ---- Pixellot software card -----------------------------------------
        private string _pixellotApp = "—";
        public string PixellotApp { get => _pixellotApp; set => Set(ref _pixellotApp, value); }
        private string _pixellotImage = "—";
        public string PixellotImage { get => _pixellotImage; set => Set(ref _pixellotImage, value); }
        private string _pixellotDeps = "—";
        public string PixellotDeps { get => _pixellotDeps; set => Set(ref _pixellotDeps, value); }

        // ---- Last diagnostic run card ---------------------------------------
        private string _lastRunWhen = "Never";
        public string LastRunWhen { get => _lastRunWhen; set => Set(ref _lastRunWhen, value); }
        private string _lastRunResult = "—";
        public string LastRunResult { get => _lastRunResult; set => Set(ref _lastRunResult, value); }
        private Brush _lastRunResultColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush LastRunResultColor { get => _lastRunResultColor; set => Set(ref _lastRunResultColor, value); }
        private string _lastReportPath;

        // ---- System status gauges -------------------------------------------
        private double _cpuPct;
        public double CpuPct { get => _cpuPct; set => Set(ref _cpuPct, value); }
        private string _cpuPctText = "—";
        public string CpuPctText { get => _cpuPctText; set => Set(ref _cpuPctText, value); }
        private Brush _cpuColor = StatusHelpers.Brush("AccentBrush");
        public Brush CpuColor { get => _cpuColor; set => Set(ref _cpuColor, value); }

        private double _memPct;
        public double MemPct { get => _memPct; set => Set(ref _memPct, value); }
        private string _memPctText = "—";
        public string MemPctText { get => _memPctText; set => Set(ref _memPctText, value); }
        private string _memCaption = "—";
        public string MemCaption { get => _memCaption; set => Set(ref _memCaption, value); }
        private Brush _memColor = StatusHelpers.Brush("AccentBrush");
        public Brush MemColor { get => _memColor; set => Set(ref _memColor, value); }

        private double _diskPct;
        public double DiskPct { get => _diskPct; set => Set(ref _diskPct, value); }
        private string _diskPctText = "—";
        public string DiskPctText { get => _diskPctText; set => Set(ref _diskPctText, value); }
        private string _diskCaption = "—";
        public string DiskCaption { get => _diskCaption; set => Set(ref _diskCaption, value); }
        private Brush _diskColor = StatusHelpers.Brush("AccentBrush");
        public Brush DiskColor { get => _diskColor; set => Set(ref _diskColor, value); }

        private string _uptimeText = "—";
        public string UptimeText { get => _uptimeText; set => Set(ref _uptimeText, value); }
        private string _cpuName = "—";
        public string CpuName { get => _cpuName; set => Set(ref _cpuName, value); }
        private string _cpuCoresText = "—";
        public string CpuCoresText { get => _cpuCoresText; set => Set(ref _cpuCoresText, value); }

        // Temperature tile — hidden when WMI returns no thermal-zone data
        // (typical on consumer / desktop CPUs that don't expose ACPI temp).
        private string _temperatureText = "—";
        public string TemperatureText { get => _temperatureText; set => Set(ref _temperatureText, value); }
        private bool _temperatureVisible;
        public bool TemperatureVisible { get => _temperatureVisible; set => Set(ref _temperatureVisible, value); }
        private Brush _temperatureColor = StatusHelpers.Brush("AccentBrush");
        public Brush TemperatureColor { get => _temperatureColor; set => Set(ref _temperatureColor, value); }

        // ---- NIC ports / volumes / services / findings collections ---------
        public ObservableCollection<NicPortRow> NicPorts { get; } = new ObservableCollection<NicPortRow>();
        public ObservableCollection<VolumeRow> Volumes  { get; } = new ObservableCollection<VolumeRow>();
        public ObservableCollection<ServiceStatusRow> Services { get; } = new ObservableCollection<ServiceStatusRow>();
        public ObservableCollection<DashboardFinding> Findings { get; } = new ObservableCollection<DashboardFinding>();

        // ---- Dashboard log sink -------------------------------------------
        // Lets formerly-silent catches surface low-severity log lines instead
        // of swallowing failures. Capped at 200 entries.
        public ObservableCollection<LogEntry> LogEntries { get; } = new ObservableCollection<LogEntry>();
        internal void AddLog(string message, string level = "Info")
        {
            var entry = new LogEntry
            {
                Label = "",
                Result = message,
                Level = level,
                ResultColor = StatusHelpers.BrushForLogLevel(level),
            };
            void apply()
            {
                LogEntries.Add(entry);
                while (LogEntries.Count > 200) LogEntries.RemoveAt(0);
            }
            var app = System.Windows.Application.Current;
            if (app != null && app.Dispatcher.CheckAccess()) apply();
            else app?.Dispatcher.Invoke(apply);
        }

        // ---- Network config block (read directly from snapshot) ------------
        private string _ipAddress = "—";
        public string IpAddress { get => _ipAddress; set => Set(ref _ipAddress, value); }
        private string _gateway = "—";
        public string Gateway { get => _gateway; set => Set(ref _gateway, value); }
        private string _dns = "—";
        public string DnsServers { get => _dns; set => Set(ref _dns, value); }
        private string _ntp = "—";
        public string NtpServer { get => _ntp; set => Set(ref _ntp, value); }
        private string _uplink = "—";
        public string UplinkAdapter { get => _uplink; set => Set(ref _uplink, value); }
        private string _internetText = "—";
        public string InternetText { get => _internetText; set => Set(ref _internetText, value); }
        private Brush _internetColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush InternetColor { get => _internetColor; set => Set(ref _internetColor, value); }

        // ---- Status pill (overall health) ----------------------------------
        // _hasSnapshot guards the pill against showing "Healthy" before the
        // first snapshot has been applied — that's a false-green that erodes
        // trust in a diagnostic tool. Until then, the pill reads "Checking…"
        // muted.
        private bool _hasSnapshot;
        private string _statusLabel = "Checking…";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        // ---- Empty-state flag (non-VPU host) -------------------------------
        // True when DashboardService can't find Pixellot at all — drives the
        // top-of-page "Pixellot software not detected" empty state so a clean
        // dev box doesn't look like a healthy VPU.
        private bool _isNonVpuHost;
        public bool IsNonVpuHost { get => _isNonVpuHost; set => Set(ref _isNonVpuHost, value); }

        // Status dots beside the Network Configuration values — green when
        // the value is meaningfully populated, muted when it's blank/em-dash.
        private Brush _ipDotColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush IpDotColor { get => _ipDotColor; set => Set(ref _ipDotColor, value); }
        private Brush _gatewayDotColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush GatewayDotColor { get => _gatewayDotColor; set => Set(ref _gatewayDotColor, value); }
        private Brush _dnsDotColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush DnsDotColor { get => _dnsDotColor; set => Set(ref _dnsDotColor, value); }
        private Brush _ntpDotColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush NtpDotColor { get => _ntpDotColor; set => Set(ref _ntpDotColor, value); }

        // ---- Commands -------------------------------------------------------
        public ICommand NavigateCommand { get; }
        public ICommand OpenLastReportCommand { get; }
        public ICommand RefreshCommand { get; }
        public Action<string> RequestNavigate { get; set; }   // wired up by MainViewModel

        // Set by MainViewModel — called when "Open Last Report" fires with the
        // filename of the most recent report so the Reports panel can pre-
        // select it after navigation. Keeps the cross-VM coordination simple.
        public Action<string> RequestOpenReport { get; set; }

        // True when there are no diagnostic reports on disk — drives the
        // "No diagnostic runs yet" muted empty state in the Dashboard's
        // "Last Diagnostic Run" card. Populated from IReportsService when
        // available; otherwise falls back to _lastReportPath being empty.
        private bool _isLastRunEmpty = true;
        public bool IsLastRunEmpty
        {
            get => _isLastRunEmpty;
            set => Set(ref _isLastRunEmpty, value);
        }
        public bool HasLastRun => !_isLastRunEmpty;

        // Live-update timer — re-reads only the cheap gauges (CPU / memory /
        // disk / temperature) every 2 seconds. The heavy snapshot (NIC ports,
        // services, internet probe, volumes) refreshes on tab visit + manual
        // Refresh button only.
        private readonly System.Windows.Threading.DispatcherTimer _liveTimer;
        public DashboardViewModel(IDashboardService svc)
        {
            _svc = svc;
            NavigateCommand        = new NavigateCommandImpl(t => RequestNavigate?.Invoke(t as string));
            // CanExecute disables Open Last Report when no report exists —
            // the button used to silently no-op (rec #11 from the UX review).
            OpenLastReportCommand  = new RelayCommand(OpenLastReport, () => HasLastRun);
            RefreshCommand         = new AsyncCommand(RefreshAsync);

            // Route DashboardService's formerly-silent catches into the VM
            // log sink (v0.5.0) so collection failures finally show up.
            if (_svc is DashboardService concrete)
            {
                concrete.OnSilentError = (section, ex) =>
                    AddLog($"{section} failed: {ex?.Message}", "Warn");
            }

            _liveTimer = new System.Windows.Threading.DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(2),
            };
            _liveTimer.Tick += OnLiveTick;
        }

        // Started by MainViewModel when the Dashboard becomes the current view;
        // stopped when navigating away. Matches what the legacy WinForms tool
        // did with its System.Windows.Forms.Timer.
        public void StartLiveUpdates()
        {
            if (_liveTimer != null && !_liveTimer.IsEnabled) _liveTimer.Start();
        }
        public void StopLiveUpdates()
        {
            if (_liveTimer != null && _liveTimer.IsEnabled) _liveTimer.Stop();
        }

        // ReadGauges does ~250 ms of CPU sampling; run it on a background task
        // so the tick doesn't block the UI thread, then marshal the result back
        // for the property assigns. Body is wrapped in a single try/catch so an
        // async-void exception can never tear down the dispatcher (v0.5.0).
        private async void OnLiveTick(object sender, EventArgs e)
        {
            try
            {
                var g = await Task.Run(() => _svc.ReadGauges()).ConfigureAwait(true);
                if (g != null) ApplyGaugeReadings(g);
            }
            catch (Exception ex)
            {
                AddLog($"Live tick failed: {ex.Message}", "Warn");
            }
        }

        private void ApplyGaugeReadings(GaugeReadings g)
        {
            CpuPct      = g.CpuUsagePct;
            CpuPctText  = $"{(int)g.CpuUsagePct}%";
            CpuColor    = LoadColour(g.CpuUsagePct);

            MemPct      = g.MemoryUsedPct;
            MemPctText  = $"{(int)g.MemoryUsedPct}%";
            MemCaption  = g.MemoryUsedLabel;
            MemColor    = LoadColour(g.MemoryUsedPct);

            DiskPct     = g.DiskUsedPct;
            DiskPctText = $"{(int)g.DiskUsedPct}%";
            DiskCaption = g.DiskUsedLabel;
            DiskColor   = LoadColour(g.DiskUsedPct);

            if (g.TemperatureAvailable)
            {
                TemperatureVisible = true;
                TemperatureText    = $"{g.TemperatureC:F0}°C";
                // Tier the tile colour by absolute °C. 65 / 78 °C bands tuned
                // for the small-form-factor / fanless boards the Pixellot S2
                // typically ships on, which throttle around 80 °C package.
                // (UX review rec #14 — confirm with platform team if tighter
                // limits become known.)
                TemperatureColor = g.TemperatureC >= 78 ? StatusHelpers.Brush("RedBrush")
                                : g.TemperatureC >= 65 ? StatusHelpers.Brush("YellowBrush")
                                :                          StatusHelpers.Brush("AccentBrush");
            }
            else
            {
                TemperatureVisible = false;
            }
        }

        public async Task RefreshAsync()
        {
            // The cheap-reads (GetHubTiles, GetLastRunSummary) and the pre-await
            // body of CollectSnapshotAsync (which still includes the 250 ms
            // Thread.Sleep in ReadGaugesCore) all used to run inline on the UI
            // thread. Push everything that touches the service onto a worker
            // task so the dispatcher stays free until we marshal results back.
            List<HubTileViewModel> tiles = null;
            LastRunSummary last = null;
            DashboardSnapshot snap = null;
            Exception snapErr = null;
            try
            {
                tiles = await Task.Run(() => _svc.GetHubTiles()).ConfigureAwait(false);
            }
            catch (Exception ex) { snapErr = ex; }
            try
            {
                last = await Task.Run(() => _svc.GetLastRunSummary()).ConfigureAwait(false);
            }
            catch (Exception ex) { if (snapErr == null) snapErr = ex; }
            try { snap = await _svc.CollectSnapshotAsync().ConfigureAwait(false); }
            catch (Exception ex) { snapErr = ex; }

            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                ApplyTilesAndLastRun(tiles ?? new List<HubTileViewModel>(), last);
                if (snap != null) ApplySnapshot(snap);
                if (snapErr != null) AddLog($"Snapshot collection failed: {snapErr.Message}", "Warn");

                // v0.5.5: per-run report file.
                try
                {
                    var path = _reportWriter.Save("Dashboard", BuildReportText());
                    if (!string.IsNullOrEmpty(path))
                        AppLogFile.Instance.WriteLine("Dashboard", "Info",
                            $"Report saved: {path}");
                }
                catch { }
            });
        }

        /// <summary>
        /// Compose the Dashboard panel's per-run report body — gauge
        /// readings, hub-tile statuses, the last diagnostic-run summary,
        /// and the Findings list.
        /// </summary>
        public string BuildReportText()
        {
            var sb = new System.Text.StringBuilder();

            sb.AppendLine("== Identity ==");
            sb.AppendLine($"  Hostname:    {Hostname}");
            sb.AppendLine($"  Model:       {VpuModel}");
            sb.AppendLine($"  Mfr/Product: {Manufacturer} / {ProductName}");
            sb.AppendLine($"  Serial:      {SerialNumber}");
            sb.AppendLine($"  App:         {PixellotApp}");
            sb.AppendLine($"  Image:       {PixellotImage}");
            sb.AppendLine($"  Deps:        {PixellotDeps}");

            sb.AppendLine();
            sb.AppendLine("== Gauges ==");
            sb.AppendLine($"  CPU:         {CpuPctText}  ({CpuName}, {CpuCoresText})");
            sb.AppendLine($"  Memory:      {MemPctText}  ({MemCaption})");
            sb.AppendLine($"  Disk:        {DiskPctText}  ({DiskCaption})");
            sb.AppendLine($"  Uptime:      {UptimeText}");
            if (TemperatureVisible)
                sb.AppendLine($"  Temperature: {TemperatureText}");

            sb.AppendLine();
            sb.AppendLine("== Network ==");
            sb.AppendLine($"  Uplink:      {UplinkAdapter}");
            sb.AppendLine($"  IP:          {IpAddress}");
            sb.AppendLine($"  Gateway:     {Gateway}");
            sb.AppendLine($"  DNS:         {DnsServers}");
            sb.AppendLine($"  NTP:         {NtpServer}");
            sb.AppendLine($"  Internet:    {InternetText}");

            if (NicPorts.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== NIC Ports ==");
                foreach (var p in NicPorts)
                    sb.AppendLine($"  Port {p.PortNumber}  {p.Name,-32}  {p.SpeedLabel,-10}  {p.StatusText}");
            }

            if (Tiles.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== Hub Tiles ==");
                foreach (var t in Tiles)
                    sb.AppendLine($"  [{t.StatusText,-10}] {t.Title,-22}  {t.Description}");
            }

            sb.AppendLine();
            sb.AppendLine("== Last Diagnostic Run ==");
            sb.AppendLine($"  {LastRunSummary}");
            sb.AppendLine($"  When:        {LastRunWhen}");
            sb.AppendLine($"  Result:      {LastRunResult}");

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

        private void ApplyTilesAndLastRun(List<HubTileViewModel> tiles,
                                          LastRunSummary last)
        {
            Tiles.Clear();
            if (tiles != null) foreach (var t in tiles) Tiles.Add(t);

            if (last == null)
            {
                LastRunSummary = "Last Run: Never";
                LastRunColor   = StatusHelpers.Brush("MutedForegroundBrush");
                _lastReportPath = null;
            }
            else
            {
                var when  = last.When.ToString("MMM d, h:mm tt");
                var model = string.IsNullOrEmpty(last.VpuModel) ? "" : $" — {last.VpuModel}";
                var res   = string.IsNullOrEmpty(last.Result) ? "" : $"   |   {last.Result}";
                LastRunSummary = $"Last Run: {when}{model}{res}";
                LastRunColor =
                    last.Severity == "Fail" ? StatusHelpers.Brush("RedBrush") :
                    last.Severity == "Warn" ? StatusHelpers.Brush("YellowBrush") :
                    last.Severity == "Pass" ? StatusHelpers.Brush("GreenBrush") :
                                                StatusHelpers.Brush("MutedForegroundBrush");
                _lastReportPath = last.ReportPath;
            }
        }

        private void ApplySnapshot(DashboardSnapshot s)
        {
            // Identity + Pixellot software
            VpuLabel      = s.VpuLabel;
            VpuModel      = s.VpuModel;
            Hostname      = s.Hostname;
            Manufacturer  = s.Manufacturer;
            ProductName   = s.ProductName;
            SerialNumber  = s.SerialNumber;
            PixellotApp   = s.PixellotApp;
            PixellotImage = s.PixellotImage;
            PixellotDeps  = s.PixellotDeps;

            // Last diagnostic
            LastRunWhen        = s.LastRunWhen;
            LastRunResult      = s.LastRunResult;
            LastRunResultColor = SeverityBrush(s.LastRunSeverity);

            // Gauges — funnel through the same code path as the live tick so
            // tier colour rules stay in one place.
            ApplyGaugeReadings(new GaugeReadings
            {
                CpuUsagePct     = s.CpuUsagePct,
                MemoryUsedPct   = s.MemoryUsedPct,
                MemoryUsedLabel = s.MemoryUsedLabel,
                DiskUsedPct     = s.DiskUsedPct,
                DiskUsedLabel   = s.DiskUsedLabel,
                TemperatureC    = s.TemperatureC,
            });

            UptimeText   = s.Uptime;
            CpuName      = s.CpuName;
            CpuCoresText = s.CpuCores > 0 ? $"{s.CpuCores} threads" : "";

            // NIC ports — pad to 4 entries so the table always has 4 rows.
            NicPorts.Clear();
            for (int i = 0; i < Math.Max(4, s.NicPorts?.Count ?? 0); i++)
            {
                if (s.NicPorts != null && i < s.NicPorts.Count)
                {
                    var n = s.NicPorts[i];
                    NicPorts.Add(NicPortRow.From(i + 1, n));
                }
                else
                {
                    NicPorts.Add(NicPortRow.Empty(i + 1));
                }
            }

            // Network config + per-row status dots. A green dot reads at a
            // glance for non-tech users without them having to know what
            // "DNS" or "NTP" means; muted dot says "this hasn't been
            // populated" without sounding alarms.
            var ipPresent  = !string.IsNullOrEmpty(s.NetworkConfig?.IpAddress);
            var gwPresent  = !string.IsNullOrEmpty(s.NetworkConfig?.Gateway);
            var dnsPresent = !string.IsNullOrEmpty(s.NetworkConfig?.DnsServers);
            var ntpPresent = !string.IsNullOrEmpty(s.NetworkConfig?.NtpServer);
            IpAddress       = ipPresent  ? s.NetworkConfig.IpAddress    : "—";
            Gateway         = gwPresent  ? s.NetworkConfig.Gateway      : "—";
            DnsServers      = dnsPresent ? s.NetworkConfig.DnsServers   : "—";
            NtpServer       = ntpPresent ? s.NetworkConfig.NtpServer    : "—";
            UplinkAdapter   = string.IsNullOrEmpty(s.UplinkAdapterName) ? "—" : s.UplinkAdapterName;
            IpDotColor      = ipPresent  ? StatusHelpers.Brush("GreenBrush") : StatusHelpers.Brush("MutedForegroundBrush");
            GatewayDotColor = gwPresent  ? StatusHelpers.Brush("GreenBrush") : StatusHelpers.Brush("MutedForegroundBrush");
            DnsDotColor     = dnsPresent ? StatusHelpers.Brush("GreenBrush") : StatusHelpers.Brush("MutedForegroundBrush");
            NtpDotColor     = ntpPresent ? StatusHelpers.Brush("GreenBrush") : StatusHelpers.Brush("MutedForegroundBrush");

            // Plain-English internet status — the icon already encodes the
            // meaning, so the text reads the same way a non-tech user thinks.
            InternetText  = s.InternetReachable ? "Connected" : "No connection";
            InternetColor = s.InternetReachable ? StatusHelpers.Brush("GreenBrush") : StatusHelpers.Brush("RedBrush");

            IsNonVpuHost = s.IsNonVpuHost;

            // Services + volumes
            Services.Clear();
            if (s.Services != null) foreach (var svc in s.Services) Services.Add(svc);
            Volumes.Clear();
            if (s.Volumes  != null) foreach (var v   in s.Volumes)  Volumes.Add(v);

            // Findings
            Findings.Clear();
            if (s.Findings != null) foreach (var f in s.Findings) Findings.Add(f);

            // Mark the first snapshot as applied so the pill stops reading
            // "Checking…" — UpdatePill respects this flag.
            _hasSnapshot = true;
            UpdatePill();
        }

        // Pill reflects the worst Finding severity. Four states, in order of
        // priority:
        //   - Checking…  (no snapshot yet — first paint, before data lands)
        //   - Critical   (any Findings entry has severity "fail")
        //   - Warning    (any Findings entry has severity "warn")
        //   - Healthy    (no findings, snapshot applied)
        // Note: this rolls up Findings only — not raw card statuses — so the
        // pill cannot disagree with the Active Findings card visible above
        // it. (UX review rec #1, #2.)
        private void UpdatePill()
        {
            if (!_hasSnapshot)
            {
                StatusLabel = "Checking…";
                StatusColor = StatusHelpers.Brush("MutedForegroundBrush");
                StatusBg    = StatusHelpers.Brush("BorderColBrush");
                return;
            }

            // Route through StatusHelpers.PillFor so the Dashboard pill reads
            // the same way as the other four panels' pills (v0.5.0).
            int crit = 0, warn = 0;
            foreach (var f in Findings)
            {
                if (f.Severity == "fail") crit++;
                else if (f.Severity == "warn") warn++;
            }
            string worst = crit > 0 ? "Critical" : (warn > 0 ? "Warning" : "");
            var pill = StatusHelpers.PillFor(worst, warn, crit);
            StatusLabel = pill.Label;
            StatusColor = pill.Fg;
            StatusBg    = pill.Bg;
        }

        // 0–60% green, 60–85% yellow, ≥85% red — same threshold the legacy
        // PowerShell tool used for disk/memory bands.
        private static Brush LoadColour(double pct)
        {
            if (pct >= 85) return StatusHelpers.Brush("RedBrush");
            if (pct >= 60) return StatusHelpers.Brush("YellowBrush");
            return StatusHelpers.Brush("AccentBrush");
        }

        private static Brush SeverityBrush(string sev)
        {
            switch (sev)
            {
                case "ok":   return StatusHelpers.Brush("GreenBrush");
                case "warn": return StatusHelpers.Brush("YellowBrush");
                case "fail": return StatusHelpers.Brush("RedBrush");
                default:      return StatusHelpers.Brush("MutedForegroundBrush");
            }
        }

        // Prefer the in-app Reports panel — pre-select the top entry there so
        // the tech sees the bundle inline instead of being thrown into
        // Notepad. Falls back to shelling out for the legacy
        // Pulse_Results_*.txt path when the Reports service has no top
        // entry but the legacy report path does.
        private void OpenLastReport()
        {
            // Preferred path: hand control to Reports.
            if (RequestOpenReport != null)
            {
                RequestOpenReport.Invoke(_lastReportFileName);
                return;
            }

            if (string.IsNullOrEmpty(_lastReportPath)) return;
            try
            {
                var psi = new ProcessStartInfo(_lastReportPath) { UseShellExecute = true };
                Process.Start(psi);
            }
            catch
            {
                // ShellExecute can fail when no association exists — fall
                // back to Notepad explicitly so the click is never lost.
                try { Process.Start("notepad.exe", _lastReportPath); } catch { }
            }
        }

        // Set by MainViewModel after refreshing the Reports list — populates
        // the "Last Diagnostic Run" card with the most recent on-disk report,
        // and lets the Open Last Report button know which one to pre-select.
        public void ApplyLastReport(string fileName, DateTime? timestamp, string sizeLabel)
        {
            _lastReportFileName = fileName;
            if (string.IsNullOrEmpty(fileName))
            {
                IsLastRunEmpty = true;
                OnPropertyChanged(nameof(HasLastRun));
                return;
            }
            IsLastRunEmpty = false;
            OnPropertyChanged(nameof(HasLastRun));
            if (timestamp.HasValue) LastRunWhen = timestamp.Value.ToString("MMM d, h:mm tt");
            if (string.IsNullOrEmpty(LastRunResult) || LastRunResult == "—") LastRunResult = "Saved report";
            if (!string.IsNullOrEmpty(sizeLabel)) LastRunSummary = $"Bundle: {fileName} ({sizeLabel})";
        }

        // Filename of the on-disk report that the breadcrumb should
        // pre-select in the Reports panel. Lives next to _lastReportPath so
        // both the legacy file-open and the new in-app-navigate paths stay
        // available to the OpenLastReport command.
        private string _lastReportFileName;

        // ICommand wrapper that takes the tile's TargetNav string.
        private class NavigateCommandImpl : ICommand
        {
            private readonly Action<object> _execute;
            public NavigateCommandImpl(Action<object> execute) { _execute = execute; }
            public bool CanExecute(object parameter) => true;
            public void Execute(object parameter) => _execute(parameter);
            public event EventHandler CanExecuteChanged
            {
                add    { System.Windows.Input.CommandManager.RequerySuggested += value; }
                remove { System.Windows.Input.CommandManager.RequerySuggested -= value; }
            }
        }
    }

    /// <summary>Dashboard NIC port row — one per detected camera-NIC port.</summary>
    public class NicPortRow
    {
        public int    PortNumber  { get; set; }
        public string Name        { get; set; }
        public string SpeedLabel  { get; set; }
        public string StatusText  { get; set; }
        public Brush  StatusColor { get; set; }

        public static NicPortRow From(int n, CameraNicSnapshot s)
        {
            var spd = s.LinkSpeedBps >= 1_000_000_000UL
                ? $"{s.LinkSpeedBps / 1_000_000_000UL} Gbps"
                : s.LinkSpeedBps >= 1_000_000UL
                    ? $"{s.LinkSpeedBps / 1_000_000UL} Mbps"
                    : "—";
            string status; Brush colour;
            if (!s.IsUp) { status = "Down"; colour = StatusHelpers.Brush("MutedForegroundBrush"); }
            else if (s.LinkSpeedBps >= 1_000_000_000UL) { status = "Linked"; colour = StatusHelpers.Brush("GreenBrush"); }
            else { status = "Sub-gigabit"; colour = StatusHelpers.Brush("YellowBrush"); }
            return new NicPortRow
            {
                PortNumber = n,
                Name       = s.Name ?? "—",
                SpeedLabel = s.IsUp ? spd : "—",
                StatusText = status,
                StatusColor = colour,
            };
        }

        public static NicPortRow Empty(int n) => new NicPortRow
        {
            PortNumber  = n,
            Name        = "Not detected",
            SpeedLabel  = "—",
            StatusText  = "—",
            StatusColor = StatusHelpers.Brush("MutedForegroundBrush"),
        };
    }
}
