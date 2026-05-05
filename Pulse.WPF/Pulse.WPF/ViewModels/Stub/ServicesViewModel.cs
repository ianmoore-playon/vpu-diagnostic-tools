using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;

namespace Pulse.WPF.ViewModels.Stub
{
    /// <summary>
    /// Stub viewmodel for ServicesView (Pixellot Services).
    /// Mock data covers the six core Pixellot services + five Windows
    /// dependencies, with one Stopped service driving a Finding row.
    /// </summary>
    public class ServicesViewModel : StatusViewModelBase
    {
        public ObservableCollection<ServiceStatusRow> CoreServices       { get; } = new ObservableCollection<ServiceStatusRow>();
        public ObservableCollection<ServiceStatusRow> SystemDependencies { get; } = new ObservableCollection<ServiceStatusRow>();
        public ObservableCollection<LogEntry>         LogEntries         { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding>          Findings           { get; } = new ObservableCollection<Finding>();

        public bool HasFindings => Findings.Count > 0;

        public ICommand RunTestCommand        { get; }
        public ICommand RestartServiceCommand { get; }

        public ServicesViewModel()
        {
            SetStatus("1 Critical", "RedBrush", "ErrBgBrush");

            // ---- 6 core Pixellot services ----
            AddCore("PixellotAgent",       "Pixellot Agent",       "Running", "Automatic", "3 d 14 h ago",  "");
            AddCore("KeepAgentUp",         "Keep Agent Up",        "Running", "Automatic", "3 d 14 h ago",  "");
            AddCore("PixellotCoordinator", "Pixellot Coordinator", "Running", "Automatic", "3 d 14 h ago",  "");
            AddCore("LMIGuardianSvc",      "LogMeIn Guardian",     "Running", "Automatic", "3 d 14 h ago",  "");
            AddCore("PixellotVPU",         "Pixellot VPU",         "Stopped", "Automatic", "—",             "Stopped 12 min ago — was crash-looping");
            AddCore("PixellotScoreconnect","Pixellot Scoreconnect","Running", "Automatic", "1 h 22 m ago",  "Restarted 3× in last 24 h");

            // ---- 5 system dependencies ----
            AddDep("W32Time",     "Windows Time",      "Running", "Automatic");
            AddDep("Dnscache",    "DNS Client",        "Running", "Automatic");
            AddDep("Dhcp",        "DHCP Client",       "Running", "Automatic");
            AddDep("EventLog",    "Windows Event Log", "Running", "Automatic");
            AddDep("wuauserv",    "Windows Update",    "Stopped", "Manual");

            // ---- Findings ----
            Findings.Add(MakeFinding(FindingSeverity.Critical,
                "Pixellot VPU service is stopped",
                "Click Restart Service. If it stops again within 5 minutes, capture the latest log under C:\\Pixellot\\Data\\Log and contact Tier 2.",
                "Pixellot"));
            Findings.Add(MakeFinding(FindingSeverity.Warning,
                "Pixellot Scoreconnect restarted 3× in the last 24 h",
                "Check the venue's scoreboard network — repeated restarts usually mean the scoreboard data feed is dropping. Re-run after the next event.",
                "Pixellot"));

            // ---- Log ----
            AddLog("",                "Services diagnostic",                            "Section");
            AddLog("Pixellot Agent",  "Running (3 d 14 h)",                             "Pass");
            AddLog("Pixellot VPU",    "Stopped — last exit code 0xC0000005",             "Fail");
            AddLog("Scoreconnect",    "Running but flapped 3× in 24 h",                  "Warn");
            AddLog("W32Time",         "Synced — offset 12 ms",                          "Pass");

            RunTestCommand        = new RelayCommand(() => AddLog("Action", "Run Test (stub) — engine arrives in v1.1", "Warn"));
            RestartServiceCommand = new RelayCommand(() => AddLog("Action", "Restart Pixellot VPU (stub)",              "Warn"));
        }

        private void AddCore(string name, string display, string status, string startMode, string lastStarted, string note)
        {
            var (color, bg) = StatusBrushes(status);
            CoreServices.Add(new ServiceStatusRow {
                Name = name, DisplayName = display, Status = status, StartMode = startMode,
                LastStarted = lastStarted, Note = note,
                StatusColor = color, StatusBg = bg,
            });
        }

        private void AddDep(string name, string display, string status, string startMode)
        {
            var (color, bg) = StatusBrushes(status);
            SystemDependencies.Add(new ServiceStatusRow {
                Name = name, DisplayName = display, Status = status, StartMode = startMode,
                LastStarted = "", Note = "",
                StatusColor = color, StatusBg = bg,
            });
        }

        private static (Brush color, Brush bg) StatusBrushes(string status)
        {
            switch (status)
            {
                case "Running":
                    return ((Brush)Application.Current.Resources["GreenBrush"],
                            (Brush)Application.Current.Resources["OkBgBrush"]);
                case "Stopped":
                    return ((Brush)Application.Current.Resources["RedBrush"],
                            (Brush)Application.Current.Resources["ErrBgBrush"]);
                default:
                    return ((Brush)Application.Current.Resources["YellowBrush"],
                            (Brush)Application.Current.Resources["WarnBgBrush"]);
            }
        }

        private static Finding MakeFinding(FindingSeverity sev, string title, string rec, string cat)
        {
            var f = new Finding();
            f.Apply(sev, title, rec, cat);
            return f;
        }

        private void AddLog(string label, string result, string level)
        {
            Brush color = level switch
            {
                "Pass"    => (Brush)Application.Current.Resources["GreenBrush"],
                "Fail"    => (Brush)Application.Current.Resources["RedBrush"],
                "Warn"    => (Brush)Application.Current.Resources["YellowBrush"],
                "Section" => (Brush)Application.Current.Resources["AccentBrush"],
                _         => (Brush)Application.Current.Resources["ForegroundBrush"],
            };
            LogEntries.Add(new LogEntry { Label = label, Result = result, Level = level, ResultColor = color });
        }
    }
}
