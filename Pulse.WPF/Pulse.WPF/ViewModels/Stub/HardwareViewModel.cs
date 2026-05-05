using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;

namespace Pulse.WPF.ViewModels.Stub
{
    /// <summary>
    /// Stub viewmodel for HardwareView (Hardware &amp; Peripherals).
    /// Mock data covers GPU / monitor / input devices, the 4-port PoE
    /// readings from the ADLINK SmartPoE module, and per-NIC link uptime.
    /// </summary>
    public class HardwareViewModel : StatusViewModelBase
    {
        // ---- Top-row cards ----
        private string _gpuName = "NVIDIA RTX A2000 (Driver 552.22)";
        public string GpuName { get => _gpuName; set => Set(ref _gpuName, value); }

        private string _gpuStatus = "Healthy";
        public string GpuStatus { get => _gpuStatus; set => Set(ref _gpuStatus, value); }

        private string _monitorStatus = "1 connected (1920×1080 @ 60 Hz)";
        public string MonitorStatus { get => _monitorStatus; set => Set(ref _monitorStatus, value); }

        private string _mouseStatus = "Logitech USB Receiver — present";
        public string MouseStatus { get => _mouseStatus; set => Set(ref _mouseStatus, value); }

        private string _keyboardStatus = "HID Keyboard — present";
        public string KeyboardStatus { get => _keyboardStatus; set => Set(ref _keyboardStatus, value); }

        // ---- PoE ----
        public ObservableCollection<PoePortReading> PoePorts { get; } = new ObservableCollection<PoePortReading>();

        private string _poeBudgetW = "120 W of 240 W in use (50%)";
        public string PoeBudgetW { get => _poeBudgetW; set => Set(ref _poeBudgetW, value); }

        private string _poeBudgetStatus = "OK";
        public string PoeBudgetStatus { get => _poeBudgetStatus; set => Set(ref _poeBudgetStatus, value); }

        // ---- NIC sidebar ----
        public ObservableCollection<NicUptime> NicUptimes { get; } = new ObservableCollection<NicUptime>();

        // ---- Log + findings ----
        public ObservableCollection<LogEntry> LogEntries { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding>  Findings   { get; } = new ObservableCollection<Finding>();

        public bool HasFindings => Findings.Count > 0;

        public ICommand RunTestCommand { get; }

        public HardwareViewModel()
        {
            SetStatus("All Clear", "GreenBrush", "OkBgBrush");

            var green  = (Brush)Application.Current.Resources["GreenBrush"];
            var yellow = (Brush)Application.Current.Resources["YellowBrush"];
            var muted  = (Brush)Application.Current.Resources["MutedForegroundBrush"];

            // PoE port readings (mock, plausible for a Pixellot CHU + OCR pair)
            PoePorts.Add(new PoePortReading { Port = "Port 1", State = "Powered", Voltage = "53.8 V", Current = "180 mA", Wattage = "9.7 W", StateColor = green });
            PoePorts.Add(new PoePortReading { Port = "Port 2", State = "Powered", Voltage = "53.6 V", Current = "175 mA", Wattage = "9.4 W", StateColor = green });
            PoePorts.Add(new PoePortReading { Port = "Port 3", State = "Powered", Voltage = "53.5 V", Current = "120 mA", Wattage = "6.4 W", StateColor = green });
            PoePorts.Add(new PoePortReading { Port = "Port 4", State = "Off",     Voltage = "—",       Current = "—",      Wattage = "0 W",   StateColor = muted });

            NicUptimes.Add(new NicUptime { Adapter = "Ethernet 1", Speed = "1 Gbps",   Uptime = "3 d 14 h", UptimeColor = green });
            NicUptimes.Add(new NicUptime { Adapter = "Ethernet 2", Speed = "1 Gbps",   Uptime = "3 d 14 h", UptimeColor = green });
            NicUptimes.Add(new NicUptime { Adapter = "Ethernet 3", Speed = "100 Mbps", Uptime = "47 min",   UptimeColor = yellow });
            NicUptimes.Add(new NicUptime { Adapter = "Ethernet 4", Speed = "1 Gbps",   Uptime = "3 d 14 h", UptimeColor = green });

            AddLog("",                 "Hardware diagnostic",                       "Section");
            AddLog("GPU",              "NVIDIA RTX A2000 — driver healthy",         "Pass");
            AddLog("Display",          "1 monitor — 1920×1080 @ 60 Hz",             "Pass");
            AddLog("Input",            "Mouse + keyboard present",                  "Pass");
            AddLog("PoE Port 1",       "9.7 W to Main Camera",                      "Pass");
            AddLog("PoE Port 4",       "Off (no device)",                           "Info");

            RunTestCommand = new RelayCommand(() => AddLog("Action", "Run Test (stub) — engine arrives in v1.1", "Warn"));
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
