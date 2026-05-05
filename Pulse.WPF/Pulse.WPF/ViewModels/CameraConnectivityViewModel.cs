using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Backing viewmodel for CameraConnectivityView. Owns the 4 PortViewModels
    /// the panel binds to, runs the live-monitoring polling timer, and exposes
    /// the Run Test command (currently a stub — diagnostic engine port is
    /// deferred past the pilot).
    /// </summary>
    public class CameraConnectivityViewModel : ObservableObject
    {
        private readonly INetworkAdapterService _net;
        private readonly IPixellotConfigService _cfg;
        private readonly DispatcherTimer _liveTimer;

        public ObservableCollection<PortViewModel> Ports { get; } = new ObservableCollection<PortViewModel>();
        public ObservableCollection<LogEntry>      LogEntries { get; } = new ObservableCollection<LogEntry>();

        public ObservableCollection<string> TestScopes { get; } = new ObservableCollection<string> { "All Ports" };

        private string _selectedScope = "All Ports";
        public string SelectedScope { get => _selectedScope; set => Set(ref _selectedScope, value); }

        // Section header status pill ----------------------------------------
        private string _statusLabel = "Ready";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }

        private Brush _statusColor;
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }

        private Brush _statusBg;
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        // NIC info --------------------------------------------------------
        private string _detectedNic = "Detecting…";
        public string DetectedNic { get => _detectedNic; set => Set(ref _detectedNic, value); }

        // Commands --------------------------------------------------------
        public ICommand RunTestCommand { get; }
        public ICommand OpenFaultIsolatorCommand { get; }
        public ICommand OpenAdapterSettingsCommand { get; }

        public CameraConnectivityViewModel(INetworkAdapterService net, IPixellotConfigService cfg)
        {
            _net = net;
            _cfg = cfg;

            // Initialise resource-backed brushes from the active app instance.
            // We can't use field initializers because Application.Current.Resources
            // hasn't necessarily resolved its merged dictionaries before field
            // init time on some startup paths.
            _statusColor = (Brush)Application.Current.Resources["MutedForegroundBrush"];
            _statusBg    = (Brush)Application.Current.Resources["BorderColBrush"];

            // Pre-populate 4 placeholder ports so the panel doesn't render
            // empty before the first poll completes.
            for (int i = 1; i <= 4; i++)
                Ports.Add(new PortViewModel { Name = $"Port {i}" });

            RunTestCommand = new AsyncCommand(RunDiagnosticAsync);
            OpenFaultIsolatorCommand   = new RelayCommand(() => AddLog("Action", "Fault Isolator wizard not implemented in pilot", "Warn"));
            OpenAdapterSettingsCommand = new RelayCommand(() => System.Diagnostics.Process.Start("ncpa.cpl"));

            // Live monitor every 3 s. Same cadence as the WinForms hwLiveTimer.
            _liveTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
            _liveTimer.Tick += async (_, __) => await RefreshLiveAsync();
            _liveTimer.Start();

            // First refresh as soon as the VM is built — don't make the user
            // wait 3 s to see anything.
            _ = RefreshLiveAsync();
        }

        // ----- live monitoring -----

        private async Task RefreshLiveAsync()
        {
            try
            {
                var snaps   = await _net.GetCameraPortsAsync();
                var roleMap = _cfg.GetRoles();

                // Update the detected-NIC summary line.
                if (snaps.Count == 0)
                {
                    DetectedNic = "No camera NICs detected";
                }
                else
                {
                    DetectedNic = $"{snaps.Count} camera-NIC port{(snaps.Count == 1 ? "" : "s")} detected ({snaps[0].Description})";
                }

                // Refresh Test Scope dropdown to reflect what's actually
                // plugged in. Preserve current selection if still valid.
                var prevScope = SelectedScope;
                TestScopes.Clear();
                TestScopes.Add("All Ports");
                for (int i = 0; i < snaps.Count; i++)
                {
                    var s = snaps[i];
                    var label = ResolveDeviceLabel(s, roleMap);
                    TestScopes.Add($"Port {i + 1} — {s.Name} — {label.Text}");
                }
                SelectedScope = TestScopes.Contains(prevScope) ? prevScope : "All Ports";

                // Update each port card.
                for (int i = 0; i < Ports.Count; i++)
                {
                    var port = Ports[i];
                    if (i < snaps.Count)
                    {
                        var s = snaps[i];
                        var dev = ResolveDeviceLabel(s, roleMap);

                        port.Speed   = FormatSpeed(s.LinkSpeedBps, s.IsUp);
                        port.Ip      = s.RemoteIp ?? "—";
                        port.Mac     = s.RemoteMac ?? "—";
                        port.Errors  = s.ErrorCount.ToString();
                        port.Device  = dev.Text;
                        port.DeviceColor = dev.Color;
                        port.ErrorsColor = s.ErrorCount > 0
                            ? (Brush)App.Current.Resources["YellowBrush"]
                            : (Brush)App.Current.Resources["ForegroundBrush"];

                        // Tier logic — mirrors the v1.0.53 fix on the WinForms side:
                        // 1 Gbps anything = ok; 100 Mbps OCR = ok; 100 Mbps main = warn.
                        var isOcr   = dev.IsOcr;
                        var is1G    = s.LinkSpeedBps >= 1_000_000_000UL;
                        var is100M  = s.LinkSpeedBps >= 100_000_000UL && s.LinkSpeedBps < 1_000_000_000UL;
                        if (!s.IsUp)
                        {
                            port.StatusText  = "No Link";
                            port.StatusColor = (Brush)App.Current.Resources["MutedForegroundBrush"];
                        }
                        else if (is1G)
                        {
                            port.StatusText  = "Linked";
                            port.StatusColor = (Brush)App.Current.Resources["GreenBrush"];
                        }
                        else if (is100M && isOcr)
                        {
                            port.StatusText  = "Linked (OCR)";
                            port.StatusColor = (Brush)App.Current.Resources["GreenBrush"];
                        }
                        else if (is100M)
                        {
                            port.StatusText  = "Degraded";
                            port.StatusColor = (Brush)App.Current.Resources["YellowBrush"];
                        }
                        else
                        {
                            port.StatusText  = "Linked";
                            port.StatusColor = (Brush)App.Current.Resources["AccentBrush"];
                        }
                    }
                    else
                    {
                        port.Speed = "—"; port.Ip = "—"; port.Mac = "—"; port.Errors = "—";
                        port.Device = "No device";
                        port.DeviceColor = (Brush)App.Current.Resources["MutedForegroundBrush"];
                        port.StatusText = "No Link";
                        port.StatusColor = (Brush)App.Current.Resources["MutedForegroundBrush"];
                    }
                }
            }
            catch (Exception ex)
            {
                AddLog("Live monitor", $"Refresh failed: {ex.Message}", "Fail");
            }
        }

        // ----- Run Test command (stub for pilot) -----

        private async Task RunDiagnosticAsync()
        {
            StatusLabel = "Running";
            StatusColor = (Brush)App.Current.Resources["YellowBrush"];
            StatusBg    = (Brush)App.Current.Resources["WarnBgBrush"];
            AddLog("", "Pilot diagnostic", "Section");
            AddLog("Note", "The full diagnostic engine port is deferred past the pilot.", "Warn");
            AddLog("Note", "Live port-status polling is active (refreshes every 3 s).", "Info");

            // Force one immediate refresh so the cards reflect current state right away.
            await RefreshLiveAsync();

            StatusLabel = "All Clear";
            StatusColor = (Brush)App.Current.Resources["GreenBrush"];
            StatusBg    = (Brush)App.Current.Resources["OkBgBrush"];
            AddLog("Pilot", "Refresh complete. See the WinForms Pulse for the full diagnostic.", "Pass");
        }

        // ----- helpers -----

        private struct DeviceLabel { public string Text; public Brush Color; public bool IsOcr; }

        private static DeviceLabel ResolveDeviceLabel(CameraNicSnapshot s, System.Collections.Generic.Dictionary<string, string> roleMap)
        {
            var label = new DeviceLabel { Color = (Brush)App.Current.Resources["MutedForegroundBrush"] };

            if (string.IsNullOrEmpty(s.RemoteMac))
            {
                label.Text = "No device";
                return label;
            }

            // 1) Authoritative role from cameras.cfg / pip.cfg
            if (s.RemoteIp != null && roleMap.TryGetValue(s.RemoteIp, out var role))
            {
                label.Text  = role;
                label.IsOcr = role.IndexOf("OCR", StringComparison.OrdinalIgnoreCase) >= 0
                              || role.IndexOf("Scoreboard", StringComparison.OrdinalIgnoreCase) >= 0;
                label.Color = label.IsOcr
                    ? (Brush)App.Current.Resources["AccentBrush"]
                    : (Brush)App.Current.Resources["GreenBrush"];
                return label;
            }

            // 2) Speed-based fallback for Pixellot OUI devices not in the config
            var isPixOui = s.RemoteMac.StartsWith("00-D0-89", StringComparison.OrdinalIgnoreCase);
            var is100M   = s.LinkSpeedBps >= 100_000_000UL && s.LinkSpeedBps < 1_000_000_000UL;
            var is1G     = s.LinkSpeedBps >= 1_000_000_000UL;

            if (isPixOui && is100M)      { label.Text = "OCR Camera";              label.IsOcr = true;  label.Color = (Brush)App.Current.Resources["AccentBrush"]; }
            else if (isPixOui && is1G)   { label.Text = "Main Camera (probable)";  label.IsOcr = false; label.Color = (Brush)App.Current.Resources["GreenBrush"]; }
            else if (isPixOui)           { label.Text = "Pixellot Camera";         label.IsOcr = false; label.Color = (Brush)App.Current.Resources["YellowBrush"]; }
            else                         { label.Text = "Unknown device";          label.IsOcr = false; label.Color = (Brush)App.Current.Resources["YellowBrush"]; }

            return label;
        }

        private static string FormatSpeed(ulong bps, bool isUp)
        {
            if (!isUp || bps == 0) return "—";
            if (bps >= 1_000_000_000UL) return $"{bps / 1_000_000_000UL} Gbps";
            if (bps >= 1_000_000UL)     return $"{bps / 1_000_000UL} Mbps";
            return $"{bps} bps";
        }

        private void AddLog(string label, string result, string level)
        {
            Brush color = level switch
            {
                "Pass" => (Brush)App.Current.Resources["GreenBrush"],
                "Fail" => (Brush)App.Current.Resources["RedBrush"],
                "Warn" => (Brush)App.Current.Resources["YellowBrush"],
                "Section" => (Brush)App.Current.Resources["AccentBrush"],
                "Gray" => (Brush)App.Current.Resources["MutedForegroundBrush"],
                _ => (Brush)App.Current.Resources["ForegroundBrush"],
            };
            LogEntries.Add(new LogEntry { Label = label, Result = result, Level = level, ResultColor = color });
            // Trim runaway log so memory stays bounded over a long session.
            while (LogEntries.Count > 200) LogEntries.RemoveAt(0);
        }
    }
}
