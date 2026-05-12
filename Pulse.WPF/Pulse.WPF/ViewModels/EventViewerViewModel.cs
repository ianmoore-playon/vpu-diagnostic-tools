using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Surfaces filtered Windows event-log entries so a Tier-1 support agent
    /// can triage a VPU over LogMeIn without opening the Windows Event Viewer
    /// GUI. Defaults filter to the disk / NIC / Pixellot / SCM sources that
    /// matter for VPU operation and a 48-hour window — broad enough to catch
    /// the previous night's incident, narrow enough to render fast.
    /// </summary>
    public class EventViewerViewModel : ObservableObject
    {
        private readonly IEventViewerService _svc;
        private readonly ReportWriter _reportWriter = new ReportWriter();

        // ---- Findings + recommendations banner --------------------------
        public ObservableCollection<Finding> Findings { get; } = new ObservableCollection<Finding>();

        // ---- Entries collection + filtered view ------------------------
        public ObservableCollection<WindowsEventEntry> Entries { get; } = new ObservableCollection<WindowsEventEntry>();
        public ICollectionView EntriesView { get; }

        // ---- Filter state -----------------------------------------------
        // Window options are simple strings so the XAML ComboBox doesn't
        // need a converter. Default is 48h per the Pulse panel vocabulary.
        public string[] WindowOptions { get; } = { "1 hour", "24 hours", "48 hours", "7 days" };

        private string _selectedWindow = "48 hours";
        public string SelectedWindow
        {
            get => _selectedWindow;
            set { if (Set(ref _selectedWindow, value)) _ = RefreshAsync(); }
        }

        private bool _showErrors = true;
        public bool ShowErrors
        {
            get => _showErrors;
            set { if (Set(ref _showErrors, value)) RefreshView(); }
        }

        private bool _showWarnings = true;
        public bool ShowWarnings
        {
            get => _showWarnings;
            set { if (Set(ref _showWarnings, value)) RefreshView(); }
        }

        // Information is off by default — too noisy on a busy VPU.
        private bool _showInformation;
        public bool ShowInformation
        {
            get => _showInformation;
            set { if (Set(ref _showInformation, value)) { _ = RefreshAsync(); } }
        }

        // Free-text source filter — applied on top of the default prefix
        // list. Empty string keeps the default list active.
        private string _sourceFilter = "";
        public string SourceFilter
        {
            get => _sourceFilter;
            set { if (Set(ref _sourceFilter, value)) RefreshView(); }
        }

        // ---- Status pill ------------------------------------------------
        private string _statusLabel = "Checking…";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        // ---- Commands ---------------------------------------------------
        public ICommand RefreshCommand { get; }
        public ICommand OpenEventViewerCommand { get; }

        // Default sources — chosen against a working VPU pcap+evtx pair.
        // Each entry is a prefix; the service does case-insensitive
        // StartsWith. Keep this list short so the result set stays useful.
        private static readonly string[] DefaultSources =
        {
            "disk",
            "nvme",
            "iaStorAC",
            "Pixellot",
            "Service Control Manager",
            "Application Error",
            "WHEA-Logger",
            "NETLOGON",
            "Tcpip",
            "e1iexpress",
            "e1dexpress",
            "Dhcp-Client",
        };

        public EventViewerViewModel(IEventViewerService svc)
        {
            _svc = svc;
            RefreshCommand         = new AsyncCommand(RefreshAsync);
            OpenEventViewerCommand = new RelayCommand(OpenWindowsEventViewer);

            EntriesView = CollectionViewSource.GetDefaultView(Entries);
            EntriesView.Filter = FilterEntry;

            // Auto-load on construction — Task.Run so we don't block the
            // composition root.
            _ = Task.Run(async () =>
            {
                try { await RefreshAsync(); } catch { /* logged inside */ }
            });
        }

        private int HoursForWindow()
        {
            switch (_selectedWindow)
            {
                case "1 hour":   return 1;
                case "24 hours": return 24;
                case "7 days":   return 24 * 7;
                default:          return 48;
            }
        }

        public async Task RefreshAsync()
        {
            var hours = HoursForWindow();
            var levels = new List<string>();
            if (_showErrors)      levels.Add("Error");
            if (_showWarnings)    levels.Add("Warning");
            if (_showInformation) levels.Add("Information");
            if (levels.Count == 0) { levels.Add("Error"); levels.Add("Warning"); }

            List<WindowsEventEntry> rows;
            try { rows = await _svc.GetRecentAsync(hours, DefaultSources, levels); }
            catch { rows = new List<WindowsEventEntry>(); }

            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                Entries.Clear();
                foreach (var r in rows) Entries.Add(r);
                RefreshView();
                RecomputeFindings();
                UpdatePill();

                // v0.5.5: per-run report file.
                try
                {
                    var path = _reportWriter.Save("EventViewer", BuildReportText());
                    if (!string.IsNullOrEmpty(path))
                        AppLogFile.Instance.WriteLine("EventViewer", "Info",
                            $"Report saved: {path}");
                }
                catch { }
            });
        }

        /// <summary>
        /// Compose the Event Viewer panel's per-run report body — current
        /// filter state + the entries currently in the grid (cap at 100 rows).
        /// </summary>
        public string BuildReportText()
        {
            var sb = new System.Text.StringBuilder();

            sb.AppendLine("== Filter ==");
            sb.AppendLine($"  Window:        {SelectedWindow}");
            sb.AppendLine($"  Errors:        {(ShowErrors ? "on" : "off")}");
            sb.AppendLine($"  Warnings:      {(ShowWarnings ? "on" : "off")}");
            sb.AppendLine($"  Information:   {(ShowInformation ? "on" : "off")}");
            if (!string.IsNullOrWhiteSpace(SourceFilter))
                sb.AppendLine($"  Source filter: {SourceFilter}");

            if (Findings.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== Findings ==");
                foreach (var f in Findings)
                    sb.AppendLine($"  [{f.Severity}] {f.Title}\n      -> {f.Recommendation}");
            }

            sb.AppendLine();
            sb.AppendLine("== Entries ==");
            sb.AppendLine($"  (capped at 100 rows; total in panel: {Entries.Count})");
            int cap = System.Math.Min(100, Entries.Count);
            for (int i = 0; i < cap; i++)
            {
                var e = Entries[i];
                var msg = (e.Message ?? "").Replace('\r', ' ').Replace('\n', ' ');
                if (msg.Length > 240) msg = msg.Substring(0, 240) + "…";
                sb.AppendLine($"  {e.TimestampLabel}  [{e.Level,-11}] {e.Source}  ({e.EventId})");
                sb.AppendLine($"      {msg}");
            }

            return sb.ToString();
        }

        private bool FilterEntry(object o)
        {
            if (!(o is WindowsEventEntry e)) return false;

            // Level toggles.
            if (e.Level == "Error"       && !_showErrors)      return false;
            if (e.Level == "Warning"     && !_showWarnings)    return false;
            if (e.Level == "Information" && !_showInformation) return false;

            // Source free-text filter — case-insensitive contains over
            // Source + Message so a tech can type "disk" or part of an
            // error string and the grid narrows.
            if (!string.IsNullOrWhiteSpace(_sourceFilter))
            {
                var needle = _sourceFilter.Trim();
                bool inSource  = (e.Source  ?? "").IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0;
                bool inMessage = (e.Message ?? "").IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0;
                if (!inSource && !inMessage) return false;
            }
            return true;
        }

        private void RefreshView() => EntriesView?.Refresh();

        // Findings banner fires when there are ≥ 5 errors in the last 24h
        // from disk / nvme / Pixellot sources — the "this VPU is sick"
        // threshold worth surfacing without burying the tech in detail.
        private void RecomputeFindings()
        {
            Findings.Clear();
            var since = DateTime.Now.AddHours(-24);
            int diskErrors = Entries.Count(e =>
                e.Level == "Error" &&
                e.TimeGenerated >= since &&
                (StartsWithAny(e.Source, "disk", "nvme", "iaStorAC")));
            int pxErrors = Entries.Count(e =>
                e.Level == "Error" &&
                e.TimeGenerated >= since &&
                StartsWithAny(e.Source, "Pixellot"));

            if (diskErrors >= 5)
            {
                Findings.Add(Finding.Create(
                    "Critical",
                    $"{diskErrors} disk / storage errors in the last 24 hours",
                    "Open System Overview → Storage and check disk SMART status. Consider opening a ticket if the disk is showing pre-failure.",
                    "Disk"));
            }
            if (pxErrors >= 5)
            {
                Findings.Add(Finding.Create(
                    "Warning",
                    $"{pxErrors} Pixellot application errors in the last 24 hours",
                    "Open Pixellot Services to confirm services are running and restart any that have stopped repeatedly.",
                    "Services"));
            }
        }

        private void UpdatePill()
        {
            int errorCount = Entries.Count(e => e.Level == "Error");
            int warnCount  = Entries.Count(e => e.Level == "Warning");

            string worst = "";
            int crit = 0, warn = 0;
            foreach (var f in Findings)
            {
                if (f.Severity == FindingSeverity.Critical) { crit++; worst = "Critical"; }
                else if (f.Severity == FindingSeverity.Warning && worst != "Critical") { warn++; worst = "Warning"; }
            }
            // If no Finding fired but raw error count is non-trivial we still
            // colour the pill — a panel chip stuck on "All Clear" while the
            // grid shows red rows reads as a lying status indicator.
            if (worst == "" && errorCount > 0) { worst = "Warning"; warn = 1; }

            var (label, fg, bg) = StatusHelpers.PillFor(worst, warn, crit);
            // Override the "Warning" label with the raw error count so the
            // pill actually says something useful to the tech.
            if (worst == "Warning" && Findings.Count == 0)
                label = errorCount == 1 ? "1 Error" : $"{errorCount} Errors";
            StatusLabel = label;
            StatusColor = fg;
            StatusBg    = bg;
        }

        private static bool StartsWithAny(string source, params string[] prefixes)
        {
            if (string.IsNullOrEmpty(source)) return false;
            foreach (var p in prefixes)
                if (source.StartsWith(p, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        private static void OpenWindowsEventViewer()
        {
            try
            {
                var psi = new ProcessStartInfo("eventvwr.msc") { UseShellExecute = true };
                Process.Start(psi);
            }
            catch { /* Locked-down boxes may not allow MMC snap-ins. */ }
        }
    }
}
