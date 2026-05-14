using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>Pixellot Services panel VM — surfaces process + service health
    /// rows and rolls up Findings for any required process not running.</summary>
    public class ServicesViewModel : ObservableObject
    {
        private readonly IServicesService _svc;

        public ObservableCollection<ServiceStatusRow> Services { get; } = new ObservableCollection<ServiceStatusRow>();
        public ObservableCollection<ServiceStatusRow> CoreServices { get; } = new ObservableCollection<ServiceStatusRow>();
        public ObservableCollection<ServiceStatusRow> SystemDependencies { get; } = new ObservableCollection<ServiceStatusRow>();

        // Composed via PanelLogger (v0.5.0) — shared with the four other panels.
        public PanelLogger Logger { get; } = new PanelLogger("Services");
        private readonly ReportWriter _reportWriter = new ReportWriter();
        public ObservableCollection<LogEntry> LogEntries => Logger.Entries;
        public ObservableCollection<Finding> Findings { get; } = new ObservableCollection<Finding>();
        public bool HasFindings => Findings.Count > 0;

        // v0.6.6 — "Services panel is loading…" empty-state placeholder.
        // True until the first RefreshAsync populates Services; flipped
        // off inside the dispatcher block of RefreshAsync so the placeholder
        // disappears the moment any row lands (success or zero-row failure).
        // The View binds Visibility on a single muted TextBlock to this
        // flag so an early-nav (before BaselineRunner Phase 1 completes)
        // doesn't render an empty panel that looks broken.
        private bool _isLoading = true;
        public bool IsLoading
        {
            get => _isLoading;
            set
            {
                if (Set(ref _isLoading, value))
                    OnPropertyChanged(nameof(IsReady));
            }
        }
        public bool IsReady => !_isLoading;

        private string _statusLabel = "Ready";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }
        private Brush _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }
        private Brush _statusBg = StatusHelpers.Brush("BorderColBrush");
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        public ICommand RunTestCommand { get; }
        public ICommand RestartServiceCommand { get; }

        // Selected row in the services list/grid — drives RestartServiceCommand.
        private ServiceStatusRow _selectedService;
        public ServiceStatusRow SelectedService
        {
            get => _selectedService;
            set
            {
                if (Set(ref _selectedService, value))
                {
                    OnPropertyChanged(nameof(SelectedServiceRestartHint));
                    CommandManager.InvalidateRequerySuggested();
                }
            }
        }
        public string SelectedServiceRestartHint
        {
            get
            {
                if (_selectedService == null) return "Select a Windows service row to restart it.";
                if (_selectedService.CanRestart) return $"Restarts Windows service {_selectedService.ServiceName}.";
                return _selectedService.RestartAvailability;
            }
        }

        public ServicesViewModel(IServicesService svc)
        {
            _svc = svc;
            RunTestCommand = new AsyncCommand(RefreshAsync);
            RestartServiceCommand = new AsyncCommand(
                RestartSelectedServiceAsync,
                () => _selectedService != null && _selectedService.CanRestart);
        }

        // Restart the selected Windows service via sc.exe stop / sc.exe start.
        // Requires elevation — sc.exe will return ERROR_ACCESS_DENIED (exit 5)
        // when Pulse isn't running as admin. We surface that as a clear log
        // line rather than silently re-launching the process elevated, so the
        // tech sees what happened.
        private async Task RestartSelectedServiceAsync()
        {
            var svc = _selectedService;
            if (svc == null) return;
            if (!svc.CanRestart)
            {
                AppendLog($"Restart unavailable for {DisplayNameOrName(svc)} — {svc.RestartAvailability}", "Warn");
                return;
            }
            var name = svc.ServiceName;
            var display = DisplayNameOrName(svc);
            if (string.IsNullOrWhiteSpace(name))
            {
                AppendLog($"Restart aborted — no service name on selected row.", "Warn");
                return;
            }

            // Modal confirmation. Cancel = bail with no side effects.
            var prompt = $"Restart {display}? The service will be unavailable for ~5–15 seconds.";
            MessageBoxResult choice;
            try
            {
                choice = MessageBox.Show(prompt, "Restart service",
                    MessageBoxButton.OKCancel, MessageBoxImage.Warning,
                    MessageBoxResult.Cancel);
            }
            catch
            {
                // Headless / test path — assume cancel.
                choice = MessageBoxResult.Cancel;
            }
            if (choice != MessageBoxResult.OK) return;

            AppendLog($"Restart requested for {display} ({name})", "Section");
            await Task.Run(() => RunScRestart(name)).ConfigureAwait(false);

            // Re-poll status so the tile/grid re-paints.
            await RefreshAsync().ConfigureAwait(false);
        }

        // Stop + Start via sc.exe in a background task. Logs at every step.
        private void RunScRestart(string name)
        {
            // Stop. sc.exe returns 0 on success, 5 on ERROR_ACCESS_DENIED,
            // 1062 when the service is already stopped, and a handful of
            // other codes we surface verbatim.
            AppendLog($"{name}: Stopping…", "Info");
            int stopExit;
            string stopOut;
            try
            {
                (stopExit, stopOut) = RunSc("stop " + name);
            }
            catch (Exception ex)
            {
                AppendLog($"{name}: Failed to launch sc.exe — {ex.Message}", "Fail");
                return;
            }

            if (stopExit == 5)
            {
                AppendLog($"{name}: Stop failed — access denied. Run Pulse as Administrator to restart services.", "Fail");
                return;
            }
            else if (stopExit == 0 || stopExit == 1062 /* already stopped */)
            {
                if (!WaitForStopped(name, TimeSpan.FromSeconds(15)))
                {
                    AppendLog($"{name}: Stop wait exceeded 15 s — proceeding with start anyway.", "Warn");
                }
                else
                {
                    AppendLog($"{name}: Stopped", "Pass");
                }
            }
            else
            {
                var detail = (stopOut ?? "").Trim();
                AppendLog($"{name}: Stop returned exit {stopExit}. {detail}", "Warn");
            }

            // Start.
            AppendLog($"{name}: Starting…", "Info");
            int startExit;
            string startOut;
            try
            {
                (startExit, startOut) = RunSc("start " + name);
            }
            catch (Exception ex)
            {
                AppendLog($"{name}: Failed to launch sc.exe — {ex.Message}", "Fail");
                return;
            }

            if (startExit == 5)
            {
                AppendLog($"{name}: Start failed — access denied. Run Pulse as Administrator to restart services.", "Fail");
            }
            else if (startExit == 0 || startExit == 1056 /* already running */)
            {
                AppendLog($"{name}: Started", "Pass");
            }
            else
            {
                var detail = (startOut ?? "").Trim();
                AppendLog($"{name}: Start failed — exit {startExit}. {detail}", "Fail");
            }
        }

        // Run sc.exe synchronously, capture exit + stdout. Capped at 20 s in
        // case the SCM stalls on a wedged service.
        private static (int Exit, string Output) RunSc(string args)
        {
            using (var p = new Process())
            {
                p.StartInfo = new ProcessStartInfo("sc.exe", args)
                {
                    RedirectStandardOutput = true,
                    RedirectStandardError  = true,
                    UseShellExecute        = false,
                    CreateNoWindow         = true,
                };
                p.Start();
                var output = p.StandardOutput.ReadToEnd();
                var err    = p.StandardError.ReadToEnd();
                if (!p.WaitForExit(20_000))
                {
                    try { p.Kill(); } catch { }
                    return (-1, "sc.exe timed out");
                }
                var combined = string.IsNullOrEmpty(err) ? output : output + " " + err;
                return (p.ExitCode, combined);
            }
        }

        // Poll the service status until it transitions to Stopped or we hit
        // the budget. Uses System.ServiceProcess.ServiceController.
        private static bool WaitForStopped(string name, TimeSpan budget)
        {
            try
            {
                using (var ctl = new System.ServiceProcess.ServiceController(name))
                {
                    ctl.WaitForStatus(System.ServiceProcess.ServiceControllerStatus.Stopped, budget);
                    return ctl.Status == System.ServiceProcess.ServiceControllerStatus.Stopped;
                }
            }
            catch
            {
                return false;
            }
        }

        // Restart path runs from a worker thread — Logger.Add marshals to UI.
        private void AppendLog(string message, string level) => Logger.Add("", message, level);

        public async Task RefreshAsync()
        {
            await Task.Run(() =>
            {
                var rows = _svc.GetServiceStatuses() ?? new System.Collections.Generic.List<ServiceStatusRow>();
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    Services.Clear();
                    CoreServices.Clear();
                    SystemDependencies.Clear();
                    LogEntries.Clear();
                    Findings.Clear();
                    SelectedService = null;

                    AddLog("", "VPU Processes", "Section");
                    foreach (var r in rows.Where(r => !r.IsWindowsService))
                    {
                        AddServiceRow(r);
                    }

                    AddLog("", "Windows Services", "Section");
                    foreach (var r in rows.Where(r => r.IsWindowsService))
                    {
                        AddServiceRow(r);
                    }

                    foreach (var fail in rows.Where(r => r.Severity == "Fail"))
                    {
                        AddFinding("Critical",
                            $"{fail.Name} is not running",
                            fail.CanRestart
                                ? $"Select {DisplayNameOrName(fail)} in Windows Services and use Restart Service. Persistent failures usually mean a missing config or a corrupted install."
                                : $"Reboot the VPU or call support. {DisplayNameOrName(fail)} is a process row, not a Windows service that Pulse can restart directly.");
                    }
                    foreach (var warn in rows.Where(r => r.Severity == "Warn"))
                    {
                        AddFinding("Warning",
                            $"{warn.Name}: {warn.Detail}",
                            warn.CanRestart
                                ? $"Select {DisplayNameOrName(warn)} in Windows Services and use Restart Service, then refresh this panel."
                                : $"Investigate {DisplayNameOrName(warn)} — {warn.RestartAvailability}.");
                    }

                    UpdateStatusPill();
                    OnPropertyChanged(nameof(HasFindings));
                    // v0.6.6 — first refresh has landed; flip the loading
                    // placeholder off. Done inside the dispatcher block so
                    // the cards render in the same UI tick as the data.
                    IsLoading = false;

                    // v0.5.5: per-run report file.
                    try
                    {
                        var path = _reportWriter.Save("Services", BuildReportText());
                        if (!string.IsNullOrEmpty(path))
                            AppLogFile.Instance.WriteLine("Services", "Info",
                                $"Report saved: {path}");
                    }
                    catch { }
                });
            }).ConfigureAwait(false);
        }

        /// <summary>
        /// Compose the Services panel's per-run report body — a services
        /// table with name/status/startup plus the Findings list.
        /// </summary>
        public string BuildReportText()
        {
            var sb = new System.Text.StringBuilder();

            sb.AppendLine("== Pixellot Services ==");
            if (Services.Count == 0)
            {
                sb.AppendLine("  (no services collected)");
            }
            else
            {
                sb.AppendLine("  Name                                  Kind             Status         Restart                 Detail");
                sb.AppendLine("  ------------------------------------  ---------------  -------------  ----------------------  -----------------------");
                foreach (var r in Services)
                {
                    var name = (r.DisplayName ?? r.Name ?? "").PadRight(36);
                    if (name.Length > 36) name = name.Substring(0, 36);
                    var kind = (r.RowKind ?? "").PadRight(15);
                    if (kind.Length > 15) kind = kind.Substring(0, 15);
                    var status = (r.Status ?? "").PadRight(13);
                    if (status.Length > 13) status = status.Substring(0, 13);
                    var restart = (r.CanRestart ? r.ServiceName : "Unavailable").PadRight(22);
                    if (restart.Length > 22) restart = restart.Substring(0, 22);
                    sb.AppendLine($"  {name}  {kind}  {status}  {restart}  {r.Detail}");
                }
            }

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

        private void AddLog(string label, string result, string level) => Logger.Add(label, result, level);

        private void AddServiceRow(ServiceStatusRow r)
        {
            if (r == null) return;
            Services.Add(r);
            if (r.IsWindowsService) SystemDependencies.Add(r);
            else CoreServices.Add(r);

            AddLog(r.Name, r.Status + (string.IsNullOrEmpty(r.Detail) ? "" : "  " + r.Detail),
                r.Severity == "Pass" ? "Pass" :
                r.Severity == "Fail" ? "Fail" :
                r.Severity == "Warn" ? "Warn" : "Gray");
        }

        private static string DisplayNameOrName(ServiceStatusRow row)
        {
            if (row == null) return "selected row";
            if (!string.IsNullOrWhiteSpace(row.DisplayName)) return row.DisplayName;
            if (!string.IsNullOrWhiteSpace(row.Name)) return row.Name;
            return "selected row";
        }

        private void AddFinding(string severity, string title, string recommendation)
        {
            Findings.Add(Finding.Create(severity, title, recommendation));
        }

        private void UpdateStatusPill()
        {
            int crit = Findings.Count(f => f.Severity == FindingSeverity.Critical);
            int warn = Findings.Count(f => f.Severity == FindingSeverity.Warning);
            var worst = StatusHelpers.WorstSeverity(Findings);
            var pill = StatusHelpers.PillFor(worst, warn, crit);
            StatusLabel = pill.Label;
            StatusColor = pill.Fg;
            StatusBg = pill.Bg;
        }
    }
}
