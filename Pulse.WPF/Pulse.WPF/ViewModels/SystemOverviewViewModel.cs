using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// System Overview specs panel — adapted from the legacy WinForms
    /// "System Information" tab. Six summary cards across the top
    /// (Model / OS / Uptime / CPU / RAM / Storage), then a structured
    /// per-card layout (Identity / Pixellot Software / Processor / Memory /
    /// Graphics / Hardware &amp; Peripherals / Storage / OS &amp; Locale /
    /// Network adapters / Software Inventory) per UX_REVIEW round 2 §3.
    /// Inventory data comes from ISystemOverviewService.Collect(); live
    /// peripherals and PoE status are merged from IHardwareService.
    /// </summary>
    public class SystemOverviewViewModel : ObservableObject
    {
        private readonly ISystemOverviewService _svc;
        private readonly IHardwareService _hardware;
        private readonly ReportWriter _reportWriter = new ReportWriter();
        public string LastReportPath { get; private set; }

        // ---- Top-row summary cards ------------------------------------------
        private string _modelTitle = "—";
        public string ModelTitle { get => _modelTitle; set => Set(ref _modelTitle, value); }
        private Brush _modelStatusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush ModelStatusColor { get => _modelStatusColor; set => Set(ref _modelStatusColor, value); }

        private string _osTitle = "—";
        public string OsTitle { get => _osTitle; set => Set(ref _osTitle, value); }
        private Brush _osStatusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush OsStatusColor { get => _osStatusColor; set => Set(ref _osStatusColor, value); }

        private string _uptimeTitle = "—";
        public string UptimeTitle { get => _uptimeTitle; set => Set(ref _uptimeTitle, value); }
        private Brush _uptimeStatusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush UptimeStatusColor { get => _uptimeStatusColor; set => Set(ref _uptimeStatusColor, value); }

        private string _cpuTitle = "—";
        public string CpuTitle { get => _cpuTitle; set => Set(ref _cpuTitle, value); }
        private Brush _cpuStatusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush CpuStatusColor { get => _cpuStatusColor; set => Set(ref _cpuStatusColor, value); }

        private string _ramTitle = "—";
        public string RamTitle { get => _ramTitle; set => Set(ref _ramTitle, value); }
        private Brush _ramStatusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush RamStatusColor { get => _ramStatusColor; set => Set(ref _ramStatusColor, value); }

        private string _storageTitle = "—";
        public string StorageTitle { get => _storageTitle; set => Set(ref _storageTitle, value); }
        private Brush _storageStatusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StorageStatusColor { get => _storageStatusColor; set => Set(ref _storageStatusColor, value); }

        // ---- Per-card typed models (UX_REVIEW round 2 §3) -------------------
        private IdentityCardModel _identity = new IdentityCardModel();
        public IdentityCardModel Identity { get => _identity; set => Set(ref _identity, value); }

        private PixellotSoftwareCardModel _pixellotSoftware = new PixellotSoftwareCardModel();
        public PixellotSoftwareCardModel PixellotSoftware { get => _pixellotSoftware; set => Set(ref _pixellotSoftware, value); }

        private ProcessorCardModel _processor = new ProcessorCardModel();
        public ProcessorCardModel Processor { get => _processor; set => Set(ref _processor, value); }

        private MemoryCardModel _memory = new MemoryCardModel();
        public MemoryCardModel Memory { get => _memory; set => Set(ref _memory, value); }

        private GraphicsCardModel _graphics = new GraphicsCardModel();
        public GraphicsCardModel Graphics { get => _graphics; set => Set(ref _graphics, value); }

        private StorageCardModel _storage = new StorageCardModel();
        public StorageCardModel Storage { get => _storage; set => Set(ref _storage, value); }

        private OsLocaleCardModel _osLocale = new OsLocaleCardModel();
        public OsLocaleCardModel OsLocale { get => _osLocale; set => Set(ref _osLocale, value); }

        public ObservableCollection<NicInventoryRow> NetworkAdapters { get; } =
            new ObservableCollection<NicInventoryRow>();

        // ---- Hardware & Peripherals (merged from former standalone panel) ---
        public ObservableCollection<PoePortReading> PoePorts { get; } =
            new ObservableCollection<PoePortReading>();
        public ObservableCollection<Finding> Findings { get; } =
            new ObservableCollection<Finding>();
        public bool HasFindings => Findings.Count > 0;

        private string _gpuName = "—";
        public string GpuName { get => _gpuName; set => Set(ref _gpuName, value); }

        private string _monitorStatus = "—";
        public string MonitorStatus { get => _monitorStatus; set => Set(ref _monitorStatus, value); }

        private string _inputStatus = "—";
        public string InputStatus { get => _inputStatus; set => Set(ref _inputStatus, value); }

        private bool _poeAvailable;
        public bool PoeAvailable { get => _poeAvailable; set => Set(ref _poeAvailable, value); }

        private string _poeUnavailableReason = "";
        public string PoeUnavailableReason { get => _poeUnavailableReason; set => Set(ref _poeUnavailableReason, value); }

        private string _poeBudgetW = "—";
        public string PoeBudgetW { get => _poeBudgetW; set => Set(ref _poeBudgetW, value); }

        // ---- Software Inventory (collapsible) -------------------------------
        // Default: collapsed; shows total + flagged. Expanded: searchable
        // DataGrid bound to AllAppsView (filtered by SearchTerm).
        private int _softwareTotal;
        public int SoftwareTotal { get => _softwareTotal; set => Set(ref _softwareTotal, value); }
        private int _softwareFlagged;
        public int SoftwareFlagged { get => _softwareFlagged; set => Set(ref _softwareFlagged, value); }

        public ObservableCollection<InstalledApp> AllApps { get; } =
            new ObservableCollection<InstalledApp>();
        public ObservableCollection<InstalledApp> FlaggedApps { get; } =
            new ObservableCollection<InstalledApp>();

        // CollectionView wrapper around AllApps so SearchTerm can filter the
        // visible rows in the expander DataGrid without rebuilding the source.
        public ICollectionView AllAppsView { get; }

        private string _searchTerm = "";
        public string SearchTerm
        {
            get => _searchTerm;
            set
            {
                if (Set(ref _searchTerm, value)) AllAppsView.Refresh();
            }
        }

        // ---- Status pill (top-right) ----------------------------------------
        private string _statusLabel = "Loading…";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        private string _copyStatus = "";
        public string CopyStatus { get => _copyStatus; set => Set(ref _copyStatus, value); }

        public ICommand RefreshCommand { get; }
        public ICommand CopyAsTextCommand { get; }

        public SystemOverviewViewModel(ISystemOverviewService svc, IHardwareService hardware = null)
        {
            _svc = svc;
            _hardware = hardware ?? new HardwareService();
            RefreshCommand = new AsyncCommand(RefreshAsync);
            CopyAsTextCommand = new RelayCommand(CopyInventoryToClipboard);

            AllAppsView = CollectionViewSource.GetDefaultView(AllApps);
            AllAppsView.Filter = obj =>
            {
                if (string.IsNullOrWhiteSpace(_searchTerm)) return true;
                if (!(obj is InstalledApp a)) return false;
                var t = _searchTerm.Trim();
                return (a.DisplayName != null && a.DisplayName.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0)
                    || (a.Publisher   != null && a.Publisher.IndexOf(t,   StringComparison.OrdinalIgnoreCase) >= 0);
            };

            // v0.8.1-beta: surface formerly-silent WMI catches from both
            // services into the rolling AppLogFile. System Overview doesn't
            // have a panel-level Live Log of its own (its inventory list IS
            // the surface) so the rolling daily log is the right sink —
            // matches the route DashboardViewModel and NetworkViewModel use
            // when their services emit OnSilentError.
            if (_hardware != null)
            {
                _hardware.OnSilentError += (section, ex) =>
                {
                    try
                    {
                        AppLogFile.Instance.WriteLine("Hardware", "Warn",
                            $"{section}: {ex?.GetType().Name}: {ex?.Message}");
                    }
                    catch { /* a logger failure must not crash the host */ }
                };
            }
            // SystemOverviewService.OnSilentError is static so it only
            // needs hooking once per process. Subscribing in the VM ctor
            // is safe: the VM lifetime matches the panel which matches
            // the process. The += never adds duplicates because the VM
            // is constructed exactly once in MainViewModel.
            SystemOverviewService.OnSilentError += (section, ex) =>
            {
                try
                {
                    AppLogFile.Instance.WriteLine("SystemOverview", "Warn",
                        $"{section}: {ex?.GetType().Name}: {ex?.Message}");
                }
                catch { /* a logger failure must not crash the host */ }
            };
        }

        public Task RefreshAsync()
        {
            return Task.Run(() =>
            {
                var snap = _svc.Collect();
                var peripherals = CollectPeripheralSnapshot();
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    var c = snap.Cards;
                    ModelTitle         = c.ModelTitle;
                    ModelStatusColor   = StatusForTier(c.ModelStatus);
                    OsTitle            = c.OsTitle;
                    OsStatusColor      = StatusForTier(c.OsStatus);
                    UptimeTitle        = c.UptimeTitle;
                    UptimeStatusColor  = StatusForTier(c.UptimeStatus);
                    CpuTitle           = c.CpuTitle;
                    CpuStatusColor     = StatusForTier(c.CpuStatus);
                    RamTitle           = c.RamTitle;
                    RamStatusColor     = StatusForTier(c.RamStatus);
                    StorageTitle       = c.StorageTitle;
                    StorageStatusColor = StatusForTier(c.StorageStatus);

                    // Replace typed model graphs wholesale — easier than
                    // diffing per field and triggers OneTime/OneWay rebinds.
                    Identity         = snap.Identity;
                    PixellotSoftware = snap.PixellotSoftware;
                    Processor        = snap.Processor;
                    Memory           = snap.Memory;
                    Graphics         = snap.Graphics;
                    Storage          = snap.Storage;
                    OsLocale         = snap.OsLocale;

                    NetworkAdapters.Clear();
                    foreach (var n in snap.NetworkAdapters) NetworkAdapters.Add(n);

                    AllApps.Clear();
                    foreach (var a in snap.SoftwareInventory.AllApps) AllApps.Add(a);
                    FlaggedApps.Clear();
                    foreach (var a in snap.SoftwareInventory.FlaggedApps) FlaggedApps.Add(a);
                    SoftwareTotal   = snap.SoftwareInventory.TotalCount;
                    SoftwareFlagged = snap.SoftwareInventory.FlaggedCount;
                    AllAppsView.Refresh();

                    ApplyPeripheralSnapshot(peripherals);
                    UpdatePillFromCards(c);
                });

                // v0.5.5: auto-write a per-run report once the dispatcher
                // assignments have settled. Read the body off the UI thread —
                // BuildReportText walks the just-assigned typed models so the
                // dispatcher invoke above must complete first.
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    try
                    {
                        var path = _reportWriter.Save("SystemOverview", BuildReportText());
                        if (!string.IsNullOrEmpty(path))
                        {
                            LastReportPath = path;
                            AppLogFile.Instance.WriteLine("SystemOverview", "Info",
                                $"Report saved: {path}");
                        }
                    }
                    catch { }
                });
            });
        }

        private PeripheralSnapshot CollectPeripheralSnapshot()
        {
            var snap = new PeripheralSnapshot();
            if (_hardware == null)
            {
                snap.PoeAvailable = false;
                snap.PoeUnavailableReason = "Hardware service unavailable.";
                return snap;
            }

            try { snap.GpuName = _hardware.GetGpuName(); }
            catch { snap.GpuName = "Query failed"; }

            try { snap.MonitorCount = _hardware.GetMonitorCount(); }
            catch { snap.MonitorCount = 0; }

            try { snap.MousePresent = _hardware.HasMouse(); }
            catch { snap.MousePresent = false; }

            try { snap.KeyboardPresent = _hardware.HasKeyboard(); }
            catch { snap.KeyboardPresent = false; }

            try
            {
                snap.PoeAvailable = _hardware.PoeTelemetryAvailable;
                snap.PoeUnavailableReason = _hardware.PoeTelemetryUnavailableReason ?? "";
            }
            catch
            {
                snap.PoeAvailable = false;
                snap.PoeUnavailableReason = "PoE telemetry query failed.";
            }

            if (snap.PoeAvailable)
            {
                try { snap.PoeBudget = _hardware.GetPoeBudget(); } catch { }
                try { snap.PoePorts = _hardware.GetPoePortReadings() ?? new System.Collections.Generic.List<PoePortReading>(); }
                catch { snap.PoePorts = new System.Collections.Generic.List<PoePortReading>(); }
            }

            return snap;
        }

        private void ApplyPeripheralSnapshot(PeripheralSnapshot snap)
        {
            if (snap == null) snap = new PeripheralSnapshot();

            GpuName = string.IsNullOrWhiteSpace(snap.GpuName) ? "—" : snap.GpuName;
            MonitorStatus = snap.MonitorCount > 0 ? $"{snap.MonitorCount} connected" : "None detected";
            InputStatus = $"Mouse: {(snap.MousePresent ? "OK" : "missing")} / Keyboard: {(snap.KeyboardPresent ? "OK" : "missing")}";

            PoePorts.Clear();
            foreach (var p in snap.PoePorts ?? new System.Collections.Generic.List<PoePortReading>()) PoePorts.Add(p);
            PoeAvailable = snap.PoeAvailable;
            PoeUnavailableReason = snap.PoeUnavailableReason ?? "";
            if (snap.PoeAvailable && snap.PoeBudget != null && snap.PoeBudget.TotalW > 0)
            {
                PoeBudgetW = $"Budget: {snap.PoeBudget.TotalW:F0} W  ({snap.PoeBudget.ConsumedW:F1} W used / {snap.PoeBudget.RemainingW:F1} W free)";
            }
            else
            {
                PoeBudgetW = snap.PoeAvailable ? "Budget: —" : "Budget: unavailable";
            }

            Findings.Clear();
            if (snap.PoeAvailable && snap.PoeBudget != null && snap.PoeBudget.Low)
            {
                Findings.Add(Finding.Create(
                    "Warning",
                    $"PoE budget low: {snap.PoeBudget.TotalW:F0} W",
                    "Total power budget is below the 55 W minimum — the Molex power connector on the PoE NIC may be disconnected.",
                    "PoE"));
            }

            if (snap.MonitorCount == 0)
            {
                Findings.Add(Finding.Create(
                    "Warning",
                    "No monitor detected",
                    "Confirm the display cable is seated; without a monitor the VPU cannot show local diagnostics.",
                    "Peripherals"));
            }
            if (!snap.MousePresent)
            {
                Findings.Add(Finding.Create(
                    "Warning",
                    "Mouse not detected",
                    "Plug in a USB mouse so on-site techs can interact with the VPU.",
                    "Peripherals"));
            }
            if (!snap.KeyboardPresent)
            {
                Findings.Add(Finding.Create(
                    "Warning",
                    "Keyboard not detected",
                    "Plug in a USB keyboard for local sign-in.",
                    "Peripherals"));
            }
            OnPropertyChanged(nameof(HasFindings));
        }

        private static Brush StatusForTier(string tier)
        {
            switch (tier)
            {
                case "ok":   return StatusHelpers.Brush("GreenBrush");
                case "warn": return StatusHelpers.Brush("YellowBrush");
                case "fail": return StatusHelpers.Brush("RedBrush");
                default:      return StatusHelpers.Brush("MutedForegroundBrush");
            }
        }

        private void UpdatePillFromCards(SystemOverviewCards c)
        {
            int crit = Findings.Count(f => f.Severity == FindingSeverity.Critical);
            int warn = Findings.Count(f => f.Severity == FindingSeverity.Warning);
            if (crit > 0 || warn > 0)
            {
                var worstFinding = crit > 0 ? "Critical" : "Warning";
                var pill = StatusHelpers.PillFor(worstFinding, warn, crit);
                StatusLabel = pill.Label;
                StatusColor = pill.Fg;
                StatusBg = pill.Bg;
                return;
            }

            string worst = "ok";
            int rank = 1;
            foreach (var t in new[] { c.ModelStatus, c.OsStatus, c.UptimeStatus, c.CpuStatus, c.RamStatus, c.StorageStatus })
            {
                int r = t == "fail" ? 3 : t == "warn" ? 2 : 1;
                if (r > rank) { rank = r; worst = t; }
            }

            if (worst == "fail")
            {
                StatusLabel = "Critical";
                StatusColor = StatusHelpers.Brush("RedBrush");
                StatusBg    = StatusHelpers.Brush("ErrBgBrush");
            }
            else if (worst == "warn")
            {
                StatusLabel = "Warning";
                StatusColor = StatusHelpers.Brush("YellowBrush");
                StatusBg    = StatusHelpers.Brush("WarnBgBrush");
            }
            else
            {
                StatusLabel = "Healthy";
                StatusColor = StatusHelpers.Brush("GreenBrush");
                StatusBg    = StatusHelpers.Brush("OkBgBrush");
            }
        }

        // ---- Copy as text (for support tickets) -----------------------------
        // Walks the typed per-card models so the pasted transcript mirrors the
        // on-screen card layout (Identity → "== Identity ==" → label/value).
        // Per UX_REVIEW round 2: this is the single most useful Tier-1 action
        // on this page.
        private void CopyInventoryToClipboard()
        {
            try
            {
                Clipboard.SetText(BuildReportText());
                CopyStatus = "Copied to clipboard.";
                ScheduleClearStatus();
            }
            catch (Exception ex)
            {
                CopyStatus = $"Copy failed: {ex.Message}";
                ScheduleClearStatus();
            }
        }

        /// <summary>
        /// Compose the system-overview transcript shared by Copy-as-text AND
        /// the per-run report writer (v0.5.5). Walks the typed per-card models
        /// so the output mirrors the on-screen card layout.
        /// </summary>
        public string BuildReportText()
        {
            var sb = new StringBuilder();
            sb.AppendLine("PULSE — System Overview");
            sb.AppendLine($"Generated:  {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            sb.AppendLine($"Status:     {StatusLabel}");
            sb.AppendLine();
            sb.AppendLine($"Model:    {ModelTitle}");
            sb.AppendLine($"OS:       {OsTitle}");
            sb.AppendLine($"Uptime:   {UptimeTitle}");
            sb.AppendLine($"CPU:      {CpuTitle}");
            sb.AppendLine($"RAM:      {RamTitle}");
            sb.AppendLine($"Storage:  {StorageTitle}");
            sb.AppendLine();
            sb.AppendLine(new string('-', 60));

            // Identity
            sb.AppendLine();
            sb.AppendLine("== Identity ==");
            Kv(sb, "Computer Name", Identity.ComputerName);
            Kv(sb, "Manufacturer",  Identity.Manufacturer);
            Kv(sb, "Model",         Identity.Model);
            Kv(sb, "Serial Number", Identity.SerialNumber);
            Kv(sb, "Asset Tag",     Identity.AssetTag);
            Kv(sb, "Chassis Type",  Identity.ChassisType);
            Kv(sb, "System Type",   Identity.SystemType);
            Kv(sb, "Network",       Identity.Network);
            Kv(sb, "BIOS",          Identity.BiosVersion);

            // Pixellot Software
            sb.AppendLine();
            sb.AppendLine("== Pixellot Software ==");
            Kv(sb, "App Version",          PixellotSoftware.AppVersion);
            Kv(sb, "System Image Version", PixellotSoftware.SystemImageVersion);
            Kv(sb, "Package Dependencies", PixellotSoftware.PackageDependencies);
            Kv(sb, "Install Date",         PixellotSoftware.InstallDate);

            // Processor
            sb.AppendLine();
            sb.AppendLine("== Processor ==");
            Kv(sb, "Name",            Processor.Name);
            Kv(sb, "Manufacturer",    Processor.Manufacturer);
            Kv(sb, "Cores",           Processor.Cores);
            Kv(sb, "Max Speed",       Processor.MaxSpeed);
            Kv(sb, "Socket",          Processor.Socket);
            Kv(sb, "Family",          Processor.Family);
            Kv(sb, "Stepping",        Processor.Stepping);
            Kv(sb, "Processor ID",    Processor.ProcessorId);
            Kv(sb, "Virtualization",  Processor.Virtualization);
            Kv(sb, "L2 Cache",        Processor.L2Cache);
            Kv(sb, "L3 Cache",        Processor.L3Cache);

            // Memory
            sb.AppendLine();
            sb.AppendLine("== Memory ==");
            Kv(sb, "Total RAM",  Memory.TotalRam);
            Kv(sb, "Available",  Memory.Available);
            Kv(sb, "Slots",      $"{Memory.SlotsUsed} used / {Memory.SlotsTotal} total");
            int slotN = 1;
            foreach (var s in Memory.Slots)
            {
                var line = $"{s.Capacity} {s.Type} {s.Speed}".Trim();
                if (!string.IsNullOrEmpty(s.Manufacturer)) line += $"  ({s.Manufacturer})";
                Kv(sb, $"  Slot {slotN} ({s.Locator})", line);
                if (!string.IsNullOrEmpty(s.PartNumber)) Kv(sb, "    Part Number", s.PartNumber);
                slotN++;
            }

            // Graphics
            sb.AppendLine();
            sb.AppendLine("== Graphics ==");
            Kv(sb, "Display Outputs", Graphics.DisplayCount);
            int gpuN = 1;
            foreach (var g in Graphics.Adapters)
            {
                Kv(sb, $"GPU {gpuN}",            g.Name);
                if (!string.IsNullOrEmpty(g.Vram))          Kv(sb, "  VRAM",        g.Vram);
                if (!string.IsNullOrEmpty(g.DriverVersion)) Kv(sb, "  Driver",      g.DriverVersion);
                if (!string.IsNullOrEmpty(g.DriverDate))    Kv(sb, "  Driver Date", g.DriverDate);
                gpuN++;
            }

            // Hardware & Peripherals
            sb.AppendLine();
            sb.AppendLine("== Hardware & Peripherals ==");
            Kv(sb, "Primary GPU", GpuName);
            Kv(sb, "Monitor",     MonitorStatus);
            Kv(sb, "Input",       InputStatus);

            sb.AppendLine();
            sb.AppendLine("== PoE ==");
            Kv(sb, "Available", PoeAvailable ? "yes" : "no");
            if (!PoeAvailable && !string.IsNullOrEmpty(PoeUnavailableReason))
                Kv(sb, "Reason", PoeUnavailableReason);
            Kv(sb, "Budget", PoeBudgetW);
            if (PoeAvailable && PoePorts.Count > 0)
            {
                foreach (var p in PoePorts)
                {
                    var state = p.PoeOn ? "PoE ON" : "PoE OFF";
                    Kv(sb, p.Port, $"{p.Voltage}  {p.Current}  {p.Wattage}  [{state}]");
                }
            }

            if (Findings.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== System Overview Findings ==");
                foreach (var f in Findings)
                    sb.AppendLine($"  [{f.Severity}] {f.Title}\n      -> {f.Recommendation}");
            }

            // Storage
            sb.AppendLine();
            sb.AppendLine("== Storage Devices ==");
            int diskN = 0;
            foreach (var d in Storage.Disks)
            {
                Kv(sb, $"Disk {d.Index}",            d.Model);
                Kv(sb, "  Size",                    d.Size);
                if (!string.IsNullOrEmpty(d.BusType))   Kv(sb, "  Bus",      d.BusType);
                if (!string.IsNullOrEmpty(d.MediaType)) Kv(sb, "  Media",    d.MediaType);
                if (!string.IsNullOrEmpty(d.Firmware))  Kv(sb, "  Firmware", d.Firmware);
                if (!string.IsNullOrEmpty(d.Serial))    Kv(sb, "  Serial",   d.Serial);
                diskN++;
            }
            if (diskN == 0) Kv(sb, "(no disks reported)", "");

            sb.AppendLine();
            sb.AppendLine("== Logical Volumes ==");
            foreach (var v in Storage.Volumes)
            {
                Kv(sb, v.DriveLetter, $"{v.Label}  {v.FileSystem}  {v.Size}  ({v.FreeSpace} free, {v.PercentUsed} used)");
            }

            // Operating System & Locale
            sb.AppendLine();
            sb.AppendLine("== Operating System & Locale ==");
            Kv(sb, "Edition",         OsLocale.Edition);
            Kv(sb, "Version",         OsLocale.Version);
            Kv(sb, "Build",           OsLocale.Build);
            Kv(sb, "Architecture",    OsLocale.Architecture);
            Kv(sb, "Install Date",    OsLocale.InstallDate);
            Kv(sb, "Uptime",          OsLocale.Uptime);
            Kv(sb, "Timezone",        OsLocale.Timezone);
            Kv(sb, "System Time",     OsLocale.SystemTime);
            Kv(sb, "NTP Server",      OsLocale.NtpServer);
            Kv(sb, ".NET Runtimes",   OsLocale.DotNetRuntimes);
            Kv(sb, "Last Update",     OsLocale.LastUpdate);

            // Network adapters
            sb.AppendLine();
            sb.AppendLine("== Network Adapters ==");
            foreach (var n in NetworkAdapters)
            {
                Kv(sb, n.Name, n.Mac);
                if (!string.IsNullOrEmpty(n.Speed))         Kv(sb, "  Speed",       n.Speed);
                if (!string.IsNullOrEmpty(n.Status))        Kv(sb, "  Status",      n.Status);
                if (!string.IsNullOrEmpty(n.DriverVersion)) Kv(sb, "  Driver",      n.DriverVersion);
                if (!string.IsNullOrEmpty(n.DriverDate))    Kv(sb, "  Driver Date", n.DriverDate);
            }

            // Software Inventory — count + flagged only (full list would
            // bloat the clipboard; tier-3 can expand on screen).
            sb.AppendLine();
            sb.AppendLine("== Software Inventory ==");
            Kv(sb, "Total Installed", $"{SoftwareTotal} applications");
            Kv(sb, "Flagged",         SoftwareFlagged == 0
                ? "None — no known-conflicting software detected"
                : $"{SoftwareFlagged} potentially-conflicting applications");
            foreach (var a in FlaggedApps)
            {
                Kv(sb, $"  {a.DisplayName}", $"{a.Publisher} — confirm this is intentional");
            }

            return sb.ToString();
        }

        private static void Kv(StringBuilder sb, string label, string value)
        {
            if (label == null) label = "";
            var l = label.Length > 26 ? label.Substring(0, 26) : label.PadRight(26);
            sb.AppendLine($"  {l}{value}");
        }

        private void ScheduleClearStatus()
        {
            var app = Application.Current;
            if (app == null) return;
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
            timer.Tick += (s, e) =>
            {
                CopyStatus = "";
                timer.Stop();
            };
            timer.Start();
        }

        private class PeripheralSnapshot
        {
            public string GpuName { get; set; } = "—";
            public int MonitorCount { get; set; }
            public bool MousePresent { get; set; }
            public bool KeyboardPresent { get; set; }
            public bool PoeAvailable { get; set; }
            public string PoeUnavailableReason { get; set; } = "";
            public PoeBudgetReading PoeBudget { get; set; }
            public System.Collections.Generic.List<PoePortReading> PoePorts { get; set; } =
                new System.Collections.Generic.List<PoePortReading>();
        }
    }
}
