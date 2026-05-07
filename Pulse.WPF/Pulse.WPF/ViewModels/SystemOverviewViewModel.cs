using System;
using System.Collections.ObjectModel;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
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
    /// (Model / OS / Uptime / CPU / RAM / Storage), a System Inventory
    /// list on the left, and a Summary bullet list on the right.
    /// All data sourced from ISystemOverviewService.Collect().
    /// </summary>
    public class SystemOverviewViewModel : ObservableObject
    {
        private readonly ISystemOverviewService _svc;

        public ObservableCollection<SystemOverviewRow> Inventory { get; } =
            new ObservableCollection<SystemOverviewRow>();

        // Summary collection (right-column bullets) was removed in v0.4 along
        // with the right-column Summary card — the bullets were a byte-for-byte
        // restatement of the 6 top tiles. SystemOverviewSummaryItem is kept in
        // the Models layer for now in case anything else binds to it.

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

        // ---- Status pill (top-right, matches Network/Hardware pattern) ------
        private string _statusLabel = "Loading…";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        // Status text shown next to the action buttons — drives the
        // "Copied to clipboard" / error feedback after a Copy-as-text click.
        // Cleared automatically a few seconds later via the dispatcher.
        private string _copyStatus = "";
        public string CopyStatus { get => _copyStatus; set => Set(ref _copyStatus, value); }

        // Action-bar commands.
        public ICommand RefreshCommand { get; }
        public ICommand CopyAsTextCommand { get; }

        public SystemOverviewViewModel(ISystemOverviewService svc)
        {
            _svc = svc;
            RefreshCommand = new AsyncCommand(RefreshAsync);
            CopyAsTextCommand = new RelayCommand(CopyInventoryToClipboard);
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

                    Inventory.Clear();
                    foreach (var r in snap.Inventory) Inventory.Add(r);

                    UpdatePillFromCards(c);
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

        // Roll up the worst card status into the page's Overall Status pill.
        // Matches the Hardware/Network pill semantics so techs see consistent
        // colour cues across panels.
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

        // ---- Copy as text (for support tickets) -------------------------------
        // Renders the entire inventory as a plain-text block ready to paste
        // into a ticket / Slack / email. Sections become headings, label/value
        // pairs become aligned columns, status-pill state shows at the top.
        // Per UX_REVIEW round 2: this is the single most useful Tier-1 action
        // on this page.
        private void CopyInventoryToClipboard()
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

            foreach (var row in Inventory)
            {
                if (!string.IsNullOrEmpty(row.Section))
                {
                    sb.AppendLine();
                    sb.AppendLine($"== {row.Section} ==");
                    continue;
                }
                if (string.IsNullOrEmpty(row.Label)) continue;
                // Pad the label column to 26 chars so values align reading down.
                var label = (row.Label.Length > 26 ? row.Label.Substring(0, 26) : row.Label.PadRight(26));
                sb.AppendLine($"  {label}{row.Value}");
            }

            try
            {
                Clipboard.SetText(sb.ToString());
                CopyStatus = "Copied to clipboard.";
                ScheduleClearStatus();
            }
            catch (Exception ex)
            {
                CopyStatus = $"Copy failed: {ex.Message}";
                ScheduleClearStatus();
            }
        }

        // Wipe the CopyStatus string after a few seconds so the toast
        // doesn't linger. Best-effort — no-op on the design-time / test
        // path where Application.Current is null.
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
