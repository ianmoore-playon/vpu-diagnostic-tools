using System;
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
        private string _statusLabel = "Loading…";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        // ---- Commands -------------------------------------------------------
        public ICommand NavigateCommand { get; }
        public ICommand OpenLastReportCommand { get; }
        public ICommand RefreshCommand { get; }
        public Action<string> RequestNavigate { get; set; }   // wired up by MainViewModel

        // Live-update timer — re-reads only the cheap gauges (CPU / memory /
        // disk / temperature) every 2 seconds. The heavy snapshot (NIC ports,
        // services, internet probe, volumes) refreshes on tab visit + manual
        // Refresh button only.
        private readonly System.Windows.Threading.DispatcherTimer _liveTimer;
        public DashboardViewModel(IDashboardService svc)
        {
            _svc = svc;
            NavigateCommand        = new NavigateCommandImpl(t => RequestNavigate?.Invoke(t as string));
            OpenLastReportCommand  = new RelayCommand(OpenLastReport);
            RefreshCommand         = new AsyncCommand(RefreshAsync);

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
        // for the property assigns.
        private async void OnLiveTick(object sender, EventArgs e)
        {
            GaugeReadings g = null;
            try { g = await Task.Run(() => _svc.ReadGauges()); }
            catch { return; }
            if (g == null) return;
            ApplyGaugeReadings(g);
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
                // Tier the tile colour the same way as the load gauges, but
                // by absolute °C — 70 / 85 °C are the typical CPU-throttle
                // bands. Adjust if specific PXLS hardware has tighter limits.
                TemperatureColor = g.TemperatureC >= 85 ? StatusHelpers.Brush("RedBrush")
                                : g.TemperatureC >= 70 ? StatusHelpers.Brush("YellowBrush")
                                :                          StatusHelpers.Brush("AccentBrush");
            }
            else
            {
                TemperatureVisible = false;
            }
        }

        public async Task RefreshAsync()
        {
            // Tiles + last-run line are cheap registry/file reads — pull them
            // once and let the heavier snapshot fill in the rest.
            var tiles = _svc.GetHubTiles();
            var last  = _svc.GetLastRunSummary();
            DashboardSnapshot snap = null;
            try { snap = await _svc.CollectSnapshotAsync().ConfigureAwait(false); } catch { }

            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                ApplyTilesAndLastRun(tiles, last);
                if (snap != null) ApplySnapshot(snap);
            });
        }

        private void ApplyTilesAndLastRun(System.Collections.Generic.List<HubTileViewModel> tiles,
                                          LastRunSummary last)
        {
            Tiles.Clear();
            foreach (var t in tiles) Tiles.Add(t);

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

            // Network config
            IpAddress     = string.IsNullOrEmpty(s.NetworkConfig?.IpAddress) ? "—" : s.NetworkConfig.IpAddress;
            Gateway       = string.IsNullOrEmpty(s.NetworkConfig?.Gateway)   ? "—" : s.NetworkConfig.Gateway;
            DnsServers    = string.IsNullOrEmpty(s.NetworkConfig?.DnsServers)? "—" : s.NetworkConfig.DnsServers;
            NtpServer     = string.IsNullOrEmpty(s.NetworkConfig?.NtpServer) ? "—" : s.NetworkConfig.NtpServer;
            UplinkAdapter = string.IsNullOrEmpty(s.UplinkAdapterName)        ? "—" : s.UplinkAdapterName;
            InternetText  = s.InternetReachable ? "Reachable" : "Unreachable";
            InternetColor = s.InternetReachable ? StatusHelpers.Brush("GreenBrush") : StatusHelpers.Brush("RedBrush");

            // Services + volumes
            Services.Clear();
            if (s.Services != null) foreach (var svc in s.Services) Services.Add(svc);
            Volumes.Clear();
            if (s.Volumes  != null) foreach (var v   in s.Volumes)  Volumes.Add(v);

            // Findings
            Findings.Clear();
            if (s.Findings != null) foreach (var f in s.Findings) Findings.Add(f);

            // Roll up the worst severity into the page pill.
            UpdatePill();
        }

        private void UpdatePill()
        {
            int rank = 0; string worst = "ok";
            foreach (var f in Findings)
            {
                int r = f.Severity == "fail" ? 3 : f.Severity == "warn" ? 2 : f.Severity == "ok" ? 1 : 0;
                if (r > rank) { rank = r; worst = f.Severity; }
            }
            if (worst == "fail")
            {
                StatusLabel = "Critical"; StatusColor = StatusHelpers.Brush("RedBrush");    StatusBg = StatusHelpers.Brush("ErrBgBrush");
            }
            else if (worst == "warn")
            {
                StatusLabel = "Warning";  StatusColor = StatusHelpers.Brush("YellowBrush"); StatusBg = StatusHelpers.Brush("WarnBgBrush");
            }
            else
            {
                StatusLabel = "Healthy";  StatusColor = StatusHelpers.Brush("GreenBrush");  StatusBg = StatusHelpers.Brush("OkBgBrush");
            }
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

        private void OpenLastReport()
        {
            if (string.IsNullOrEmpty(_lastReportPath)) return;
            try { Process.Start("notepad.exe", _lastReportPath); }
            catch { }
        }

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
