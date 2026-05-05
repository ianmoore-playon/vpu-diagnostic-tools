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
    /// the Run Test command (currently a stub — full diagnostic engine port is
    /// deferred). Wording / status-aggregation quick-wins per UX_REVIEW Section 8.
    /// </summary>
    public class CameraConnectivityViewModel : ObservableObject
    {
        private readonly INetworkAdapterService _net;
        private readonly IPixellotConfigService _cfg;
        private readonly DispatcherTimer _liveTimer;

        public ObservableCollection<PortViewModel> Ports     { get; } = new ObservableCollection<PortViewModel>();
        public ObservableCollection<LogEntry>      LogEntries { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding>       Findings   { get; } = new ObservableCollection<Finding>();

        public ObservableCollection<string> TestScopes { get; } = new ObservableCollection<string> { "All Ports" };

        private string _selectedScope = "All Ports";
        public string SelectedScope { get => _selectedScope; set => Set(ref _selectedScope, value); }

        // ----- Section header status pill -----
        private string _statusLabel = "Ready";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }

        /// <summary>
        /// String severity for shared StatusPill control: "ok", "warn", "fail",
        /// "running", "neutral".
        /// </summary>
        private string _statusSeverity = "neutral";
        public string StatusSeverity { get => _statusSeverity; set => Set(ref _statusSeverity, value); }

        private Brush _statusColor;
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }

        private Brush _statusBg;
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        // ----- NIC info -----
        private string _detectedNic = "Detecting…";
        public string DetectedNic { get => _detectedNic; set => Set(ref _detectedNic, value); }

        // ----- Has a test ever run? Hides the 5 placeholder probe cards. -----
        private bool _hasTestRun;
        public bool HasTestRun { get => _hasTestRun; set => Set(ref _hasTestRun, value); }

        // ----- Commands -----
        public ICommand RunTestCommand { get; }
        public ICommand OpenFaultIsolatorCommand { get; }
        public ICommand OpenAdapterSettingsCommand { get; }

        public CameraConnectivityViewModel(INetworkAdapterService net, IPixellotConfigService cfg)
        {
            _net = net;
            _cfg = cfg;

            _statusColor = (Brush)Application.Current.Resources["MutedForegroundBrush"];
            _statusBg    = (Brush)Application.Current.Resources["BorderColBrush"];

            for (int i = 1; i <= 4; i++)
                Ports.Add(new PortViewModel { Name = $"Port {i}" });

            RunTestCommand = new AsyncCommand(RunDiagnosticAsync);
            // The real fault isolator wizard ships in v1.1. Until then the
            // button is disabled in the view; the command stays a no-op so
            // existing bindings don't break.
            OpenFaultIsolatorCommand   = new RelayCommand(() => { }, () => false);
            OpenAdapterSettingsCommand = new RelayCommand(() => System.Diagnostics.Process.Start("ncpa.cpl"));

            // Live monitor every 3 s — same cadence as the WinForms hwLiveTimer.
            _liveTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
            _liveTimer.Tick += async (_, __) => await RefreshLiveAsync();
            _liveTimer.Start();

            // First refresh immediately so the cards aren't empty for 3 s.
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

                // Refresh Test Scope dropdown to reflect what's plugged in.
                var prevScope = SelectedScope;
                TestScopes.Clear();
                // Specific count beats generic — UX_REVIEW Section 4.
                TestScopes.Add(snaps.Count > 0 ? $"All {snaps.Count} ports" : "All Ports");
                for (int i = 0; i < snaps.Count; i++)
                {
                    var s = snaps[i];
                    var label = ResolveDeviceLabel(s, roleMap);
                    TestScopes.Add($"Port {i + 1} — {s.Name} — {label.Text}");
                }
                SelectedScope = TestScopes.Contains(prevScope) ? prevScope : TestScopes[0];

                // Update each port card.
                int linkedAt1G = 0;
                int warningPorts = 0;
                int criticalPorts = 0;

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

                        // Tier logic — UX_REVIEW Section 4 wording fixes.
                        var isOcr   = dev.IsOcr;
                        var is1G    = s.LinkSpeedBps >= 1_000_000_000UL;
                        var is100M  = s.LinkSpeedBps >= 100_000_000UL && s.LinkSpeedBps < 1_000_000_000UL;
                        var hasMac  = !string.IsNullOrEmpty(s.RemoteMac);

                        if (!s.IsUp)
                        {
                            if (!hasMac)
                            {
                                // No cable scenario
                                port.StatusText  = "No cable";
                                port.StatusColor = (Brush)App.Current.Resources["MutedForegroundBrush"];
                            }
                            else
                            {
                                port.StatusText  = "No Link";
                                port.StatusColor = (Brush)App.Current.Resources["MutedForegroundBrush"];
                                // Cable but no negotiation on a configured port = critical-ish
                                if (dev.IsConfigured) criticalPorts++;
                            }
                        }
                        else if (is1G)
                        {
                            // Status text encodes the *speed*, not just "Linked".
                            port.StatusText  = "1 Gbps";
                            port.StatusColor = (Brush)App.Current.Resources["GreenBrush"];
                            linkedAt1G++;
                        }
                        else if (is100M && isOcr)
                        {
                            // OCR cameras are spec'd for 100 Mbps — that's expected.
                            port.StatusText  = "100 Mbps — OCR (expected)";
                            port.StatusColor = (Brush)App.Current.Resources["GreenBrush"];
                        }
                        else if (is100M)
                        {
                            // Main camera at 100 Mbps = degraded link.
                            port.StatusText  = "100 Mbps (expected 1 Gbps)";
                            port.StatusColor = (Brush)App.Current.Resources["YellowBrush"];
                            warningPorts++;
                            AddOrUpdateFinding(
                                key: $"port{i + 1}-degraded",
                                sev: FindingSeverity.Warning,
                                title: $"Port {i + 1} — {dev.Text} negotiated 100 Mbps",
                                rec:   $"Reseat the cable on Port {i + 1} or replace it. Expected 1 Gbps for a Main camera.",
                                category: "Network");
                        }
                        else
                        {
                            port.StatusText  = FormatSpeed(s.LinkSpeedBps, s.IsUp);
                            port.StatusColor = (Brush)App.Current.Resources["AccentBrush"];
                        }
                    }
                    else
                    {
                        port.Speed = "—"; port.Ip = "—"; port.Mac = "—"; port.Errors = "—";
                        // "No cable" is more user-friendly than "No device" — UX_REVIEW Section 4.
                        port.Device = "No cable";
                        port.DeviceColor = (Brush)App.Current.Resources["MutedForegroundBrush"];
                        port.StatusText = "No cable";
                        port.StatusColor = (Brush)App.Current.Resources["MutedForegroundBrush"];
                    }
                }

                // Prune findings that are no longer relevant
                PruneStalePortFindings(snaps.Count);

                // Live status aggregation — UX_REVIEW Section 8.
                if (criticalPorts > 0)
                {
                    StatusLabel = criticalPorts == 1 ? "1 Critical" : $"{criticalPorts} Critical";
                    StatusSeverity = "critical";
                    StatusColor = (Brush)App.Current.Resources["RedBrush"];
                    StatusBg    = (Brush)App.Current.Resources["ErrBgBrush"];
                }
                else if (warningPorts > 0)
                {
                    StatusLabel = warningPorts == 1 ? "1 Warning" : $"{warningPorts} Warnings";
                    StatusSeverity = "warn";
                    StatusColor = (Brush)App.Current.Resources["YellowBrush"];
                    StatusBg    = (Brush)App.Current.Resources["WarnBgBrush"];
                }
                else if (linkedAt1G > 0)
                {
                    // Specific count beats vague "All Clear".
                    StatusLabel = $"All Clear ({linkedAt1G} port{(linkedAt1G == 1 ? "" : "s")} linked at 1 Gbps)";
                    StatusSeverity = "ok";
                    StatusColor = (Brush)App.Current.Resources["GreenBrush"];
                    StatusBg    = (Brush)App.Current.Resources["OkBgBrush"];
                }
                else
                {
                    StatusLabel = "Ready";
                    StatusSeverity = "neutral";
                    StatusColor = (Brush)App.Current.Resources["MutedForegroundBrush"];
                    StatusBg    = (Brush)App.Current.Resources["BorderColBrush"];
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
            StatusSeverity = "running";
            StatusColor = (Brush)App.Current.Resources["YellowBrush"];
            StatusBg    = (Brush)App.Current.Resources["WarnBgBrush"];
            AddLog("", "Full diagnostic", "Section");
            AddLog("Note", "Live state refreshed. Full diagnostic engine arrives in v1.1.", "Info");

            // Force one immediate refresh so the cards reflect current state.
            await RefreshLiveAsync();
            HasTestRun = true;
            AddLog("Refresh", "Live port-status polling continues every 3 s.", "Info");
        }

        // ----- helpers -----

        private struct DeviceLabel
        {
            public string Text;
            public Brush  Color;
            public bool   IsOcr;
            public bool   IsConfigured; // Found in cameras.cfg / pip.cfg
        }

        private static DeviceLabel ResolveDeviceLabel(CameraNicSnapshot s, System.Collections.Generic.Dictionary<string, string> roleMap)
        {
            var label = new DeviceLabel { Color = (Brush)App.Current.Resources["MutedForegroundBrush"] };

            if (string.IsNullOrEmpty(s.RemoteMac))
            {
                label.Text = "No cable"; // was "No device" — UX_REVIEW Section 4
                return label;
            }

            // 1) Authoritative role from cameras.cfg / pip.cfg
            if (s.RemoteIp != null && roleMap.TryGetValue(s.RemoteIp, out var role))
            {
                label.Text  = role;
                label.IsOcr = role.IndexOf("OCR", StringComparison.OrdinalIgnoreCase) >= 0
                              || role.IndexOf("Scoreboard", StringComparison.OrdinalIgnoreCase) >= 0;
                label.IsConfigured = true;
                label.Color = label.IsOcr
                    ? (Brush)App.Current.Resources["AccentBrush"]
                    : (Brush)App.Current.Resources["GreenBrush"];
                return label;
            }

            // 2) Speed-based fallback for Pixellot OUI devices not in the config
            var isPixOui = s.RemoteMac.StartsWith("00-D0-89", StringComparison.OrdinalIgnoreCase);
            var is100M   = s.LinkSpeedBps >= 100_000_000UL && s.LinkSpeedBps < 1_000_000_000UL;
            var is1G     = s.LinkSpeedBps >= 1_000_000_000UL;

            if (isPixOui && is100M)      { label.Text = "OCR Camera";     label.IsOcr = true;  label.Color = (Brush)App.Current.Resources["AccentBrush"]; }
            else if (isPixOui && is1G)   { label.Text = "Main Camera";    label.IsOcr = false; label.Color = (Brush)App.Current.Resources["GreenBrush"]; }
            else if (isPixOui)           { label.Text = "Pixellot Camera";label.IsOcr = false; label.Color = (Brush)App.Current.Resources["YellowBrush"]; }
            else                         { label.Text = "Unknown device"; label.IsOcr = false; label.Color = (Brush)App.Current.Resources["YellowBrush"]; }

            return label;
        }

        private static string FormatSpeed(ulong bps, bool isUp)
        {
            if (!isUp || bps == 0) return "—";
            if (bps >= 1_000_000_000UL) return $"{bps / 1_000_000_000UL} Gbps";
            if (bps >= 1_000_000UL)     return $"{bps / 1_000_000UL} Mbps";
            return $"{bps} bps";
        }

        // ----- findings helpers -----

        private void AddOrUpdateFinding(string key, FindingSeverity sev, string title, string rec, string category = null)
        {
            // Attach a stable key via the Title prefix so we can dedupe
            // across polling ticks. Crude but enough for the pilot.
            var existing = Findings.FirstOrDefault(f => f.Title == title);
            if (existing != null)
            {
                existing.Apply(sev, title, rec, category);
                return;
            }
            var f2 = new Finding();
            f2.Apply(sev, title, rec, category);
            Findings.Add(f2);
        }

        private void PruneStalePortFindings(int currentPortCount)
        {
            // Re-evaluate which port findings still apply. Anything we
            // didn't re-add this tick is stale — drop it. We track this
            // by reconciling against the current Ports' StatusColor.
            for (int i = Findings.Count - 1; i >= 0; i--)
            {
                var f = Findings[i];
                if (f.Title.StartsWith("Port ", StringComparison.OrdinalIgnoreCase))
                {
                    // Find the port number in the title.
                    var parts = f.Title.Split(' ');
                    if (parts.Length >= 2 && int.TryParse(parts[1], out int n)
                        && n - 1 < Ports.Count)
                    {
                        var p = Ports[n - 1];
                        // Only keep degraded-port findings if the port still reports degradation.
                        if (p.StatusText != "100 Mbps (expected 1 Gbps)")
                            Findings.RemoveAt(i);
                    }
                }
            }
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
            while (LogEntries.Count > 200) LogEntries.RemoveAt(0);
        }
    }
}
