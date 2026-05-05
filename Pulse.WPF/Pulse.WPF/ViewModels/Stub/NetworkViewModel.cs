using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;

namespace Pulse.WPF.ViewModels.Stub
{
    /// <summary>
    /// Stub viewmodel for NetworkView. Mock data mirrors what
    /// NetworkDiagnostics.psm1 produces: 4 adapters with Purpose labels,
    /// IP / mask / NTP block, a few connectivity probes.
    /// </summary>
    public class NetworkViewModel : StatusViewModelBase
    {
        public ObservableCollection<NetworkAdapterRow> Adapters    { get; } = new ObservableCollection<NetworkAdapterRow>();
        public IpConfigurationViewModel                IpConfig    { get; } = new IpConfigurationViewModel();
        public ObservableCollection<PortTestResult>    PortTests   { get; } = new ObservableCollection<PortTestResult>();
        public ObservableCollection<DomainTestResult>  DomainTests { get; } = new ObservableCollection<DomainTestResult>();
        public ObservableCollection<LogEntry>          LogEntries  { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding>           Findings    { get; } = new ObservableCollection<Finding>();

        public bool HasFindings => Findings.Count > 0;

        public ICommand RunTestCommand              { get; }
        public ICommand OpenAdapterSettingsCommand  { get; }

        public NetworkViewModel()
        {
            SetStatus("1 Warning", "YellowBrush", "WarnBgBrush");

            // ---- Adapters ----
            var green  = (Brush)Application.Current.Resources["GreenBrush"];
            var yellow = (Brush)Application.Current.Resources["YellowBrush"];
            var muted  = (Brush)Application.Current.Resources["MutedForegroundBrush"];
            var accent = (Brush)Application.Current.Resources["AccentBrush"];

            Adapters.Add(new NetworkAdapterRow {
                Name = "Ethernet 1", Description = "Intel I350-T4 #1", Mac = "00-1B-21-AC-32-01",
                Ip = "192.168.0.10", Speed = "1 Gbps", Purpose = "Camera",
                LinkState = "1 Gbps", LinkColor = green, PurposeColor = accent });
            Adapters.Add(new NetworkAdapterRow {
                Name = "Ethernet 2", Description = "Intel I350-T4 #2", Mac = "00-1B-21-AC-32-02",
                Ip = "192.168.0.11", Speed = "1 Gbps", Purpose = "Camera",
                LinkState = "1 Gbps", LinkColor = green, PurposeColor = accent });
            Adapters.Add(new NetworkAdapterRow {
                Name = "Ethernet 3", Description = "Intel I350-T4 #3", Mac = "00-1B-21-AC-32-03",
                Ip = "192.168.0.12", Speed = "100 Mbps", Purpose = "Camera (OCR)",
                LinkState = "100 Mbps (expected 1 Gbps)", LinkColor = yellow, PurposeColor = accent });
            Adapters.Add(new NetworkAdapterRow {
                Name = "Ethernet 4", Description = "Realtek PCIe GbE",  Mac = "B0-7B-25-04-77-A1",
                Ip = "10.30.4.182",  Speed = "1 Gbps", Purpose = "Internet",
                LinkState = "1 Gbps", LinkColor = green, PurposeColor = green });

            // ---- IP / NTP block (the venue NIC) ----
            IpConfig.AdapterName = "Ethernet 4 — Internet";
            IpConfig.IpAddress   = "10.30.4.182";
            IpConfig.SubnetMask  = "255.255.255.0";
            IpConfig.Gateway     = "10.30.4.1";
            IpConfig.DnsServers  = "10.30.4.1, 8.8.8.8";
            IpConfig.NtpServer   = "time.windows.com";
            IpConfig.NtpSource   = "Group Policy (NT5DS)";

            // ---- Connectivity tests ----
            PortTests.Add(new PortTestResult { Target = "update.pixellot.com:443",  Description = "Cloud upload",          Result = "Reachable",  ResultColor = green  });
            PortTests.Add(new PortTestResult { Target = "stream.pixellot.com:1935", Description = "RTMP ingest",           Result = "Reachable",  ResultColor = green  });
            PortTests.Add(new PortTestResult { Target = "telemetry.pixellot.com:443", Description = "Telemetry",           Result = "Reachable",  ResultColor = green  });
            PortTests.Add(new PortTestResult { Target = "time.windows.com:123",     Description = "NTP",                   Result = "Reachable",  ResultColor = green  });
            PortTests.Add(new PortTestResult { Target = "secure.logmein.com:443",   Description = "LogMeIn remote support", Result = "Reachable", ResultColor = green  });

            DomainTests.Add(new DomainTestResult { Domain = "update.pixellot.com",    Resolved = "203.0.113.10",  Description = "Cloud control plane", ResultColor = green });
            DomainTests.Add(new DomainTestResult { Domain = "stream.pixellot.com",    Resolved = "203.0.113.22",  Description = "RTMP ingest",         ResultColor = green });
            DomainTests.Add(new DomainTestResult { Domain = "ntp.pool.org",            Resolved = "Failed",       Description = "Backup time source",  ResultColor = yellow });

            // ---- Findings ----
            Findings.Add(MakeFinding(FindingSeverity.Warning,
                "Ethernet 3 negotiated 100 Mbps to an OCR camera",
                "Confirm the OCR camera is plugged into a switch port that limits to 100 Mbps. If not, replace the cable on Port 3 and re-run this test.",
                "Network"));

            // ---- Log entries (mock) ----
            AddLog("",                   "Network diagnostic",                    "Section");
            AddLog("Adapter detection",  "4 adapters detected",                   "Pass");
            AddLog("IP configuration",   "Ethernet 4 — 10.30.4.182/24",            "Pass");
            AddLog("NTP",                "time.windows.com — synced (offset 12 ms)", "Pass");
            AddLog("DNS",                "ntp.pool.org failed to resolve",         "Warn");
            AddLog("",                   "Connectivity probes",                   "Section");
            AddLog("Cloud upload",       "update.pixellot.com:443 reachable",      "Pass");
            AddLog("RTMP ingest",        "stream.pixellot.com:1935 reachable",     "Pass");

            RunTestCommand              = new RelayCommand(() => AddLog("Action", "Run Test (stub) — engine arrives in v1.1", "Warn"));
            OpenAdapterSettingsCommand  = new RelayCommand(() => Process.Start("ncpa.cpl"));
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
