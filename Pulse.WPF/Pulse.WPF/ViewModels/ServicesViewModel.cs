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
        public ObservableCollection<LogEntry> LogEntries { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding> Findings { get; } = new ObservableCollection<Finding>();
        public bool HasFindings => Findings.Count > 0;

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
                    CommandManager.InvalidateRequerySuggested();
            }
        }

        public ServicesViewModel(IServicesService svc)
        {
            _svc = svc;
            RunTestCommand = new AsyncCommand(RefreshAsync);
            RestartServiceCommand = new AsyncCommand(
                RestartSelectedServiceAsync,
                () => _selectedService != null);
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
            var name = svc.Name;
            if (string.IsNullOrWhiteSpace(name))
            {
                AppendLog($"Restart aborted — no service name on selected row.", "Warn");
                return;
            }

            // Modal confirmation. Cancel = bail with no side effects.
            var prompt = $"Restart {name}? The service will be unavailable for ~5–15 seconds.";
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

            AppendLog($"Restart requested for {name}", "Section");
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

        // Marshalling wrapper used by the restart path so non-UI threads can
        // append safely. AddLog (above) assumes UI-thread dispatch.
        private void AppendLog(string message, string level)
        {
            void apply()
            {
                LogEntries.Add(new LogEntry
                {
                    Label = "",
                    Result = message,
                    Level = level,
                    ResultColor = StatusHelpers.BrushForLogLevel(level),
                });
                while (LogEntries.Count > 200) LogEntries.RemoveAt(0);
            }
            var app = System.Windows.Application.Current;
            if (app != null && app.Dispatcher.CheckAccess()) apply();
            else app?.Dispatcher.Invoke(apply);
        }

        public async Task RefreshAsync()
        {
            await Task.Run(() =>
            {
                var rows = _svc.GetServiceStatuses();
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    Services.Clear();
                    LogEntries.Clear();
                    Findings.Clear();

                    AddLog("", "Core Pixellot Processes", "Section");
                    foreach (var r in rows)
                    {
                        Services.Add(r);
                        AddLog(r.Name, r.Status + (string.IsNullOrEmpty(r.Detail) ? "" : "  " + r.Detail),
                            r.Severity == "Pass" ? "Pass" :
                            r.Severity == "Fail" ? "Fail" :
                            r.Severity == "Warn" ? "Warn" : "Gray");
                    }

                    foreach (var fail in rows.Where(r => r.Severity == "Fail"))
                    {
                        AddFinding("Critical",
                            $"{fail.Name} is not running",
                            $"Restart {fail.Name} or reboot the VPU. Persistent failures usually mean a missing config or a corrupted install.");
                    }
                    foreach (var warn in rows.Where(r => r.Severity == "Warn"))
                    {
                        AddFinding("Warning",
                            $"{warn.Name}: {warn.Detail}",
                            $"Investigate {warn.Name} — start the service or remove the orphan registration.");
                    }

                    UpdateStatusPill();
                    OnPropertyChanged(nameof(HasFindings));
                });
            }).ConfigureAwait(false);
        }

        private void AddLog(string label, string result, string level)
        {
            LogEntries.Add(new LogEntry
            {
                Label = label,
                Result = result,
                Level = level,
                ResultColor = StatusHelpers.BrushForLogLevel(level),
            });
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
