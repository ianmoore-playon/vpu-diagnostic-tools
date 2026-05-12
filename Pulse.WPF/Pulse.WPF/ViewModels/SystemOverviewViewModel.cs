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
    /// Graphics / Storage / OS &amp; Locale / Network adapters / Software
    /// Inventory) per UX_REVIEW round 2 §3. All data sourced from
    /// ISystemOverviewService.Collect().
    /// </summary>
    public class SystemOverviewViewModel : ObservableObject
    {
        private readonly ISystemOverviewService _svc;
        private readonly ReportWriter _reportWriter = new ReportWriter();

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

        public SystemOverviewViewModel(ISystemOverviewService svc)
        {
            _svc = svc;
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
        }

        public Task RefreshAsync()
        {
            return Task.Run(() =>
            {
                var snap = _svc.Collect();
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
                            AppLogFile.Instance.WriteLine("SystemOverview", "Info",
                                $"Report saved: {path}");
                    }
                    catch { }
                });
            });
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
    }
}
