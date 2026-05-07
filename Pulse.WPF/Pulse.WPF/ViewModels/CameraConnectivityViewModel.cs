using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Camera Connectivity panel — round 1 of the live-diagram rebuild.
    ///
    /// What changed vs. the test-runner skeleton:
    ///   • Auto-starts a 1 s <see cref="CameraNicMonitor"/> in the constructor
    ///     and projects every snapshot through <see cref="RemoteDeviceResolver"/>.
    ///   • Renders 4 fixed port tiles (one per camera-NIC port). Tiles map by
    ///     local MAC ascending so the lowest MAC = Port 1.
    ///   • Builds <see cref="Recommendations"/> dynamically per the state-design
    ///     table (linked-degraded, mid-session regression, no-cable on
    ///     configured port, cable-no-link, flapping, errors rising, unknown
    ///     remote, mostly-dark, configured-but-missing).
    ///   • Maintains a 60-minute per-port history and writes every transition
    ///     into both the tile expander AND the page-level Live Log.
    ///   • Cross-tab buttons are wired: "Go to Network" navigates the sidebar,
    ///     "Open cameras.cfg" launches the cfg path via the OS handler.
    /// </summary>
    public class CameraConnectivityViewModel : ObservableObject
    {
        private readonly INetworkAdapterService _net;
        private readonly IPixellotConfigService _cfg;
        private readonly CameraNicMonitor _monitor;

        // Tracks the previous snapshot speed so we can detect mid-session
        // 1G -> 100M regression. Keyed by local MAC.
        private readonly Dictionary<string, ulong> _prevSpeedByMac =
            new Dictionary<string, ulong>(StringComparer.OrdinalIgnoreCase);

        // Tracks the previous IsUp so we can write the right Live-Log line on
        // a transition. (PortState.PreviousIsUp is consumed by the monitor; we
        // re-track here so log lines fire exactly once per transition.)
        private readonly Dictionary<string, bool?> _prevUpByMac =
            new Dictionary<string, bool?>(StringComparer.OrdinalIgnoreCase);

        // Tracks the previous error count per port so we can log "errors rose".
        private readonly Dictionary<string, long> _prevErrCountByMac =
            new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);

        // History buffer cap. 60 minutes is the spec, but capped at 240 entries
        // per port so a port that flaps every 5 s for an hour can't blow memory.
        private const int MaxHistoryEntriesPerPort = 240;
        private static readonly TimeSpan HistoryRetention = TimeSpan.FromMinutes(60);

        // ----- Public bindings -----
        public ObservableCollection<PortViewModel>          Ports           { get; } = new ObservableCollection<PortViewModel>();
        public ObservableCollection<LogEntry>               LogEntries      { get; } = new ObservableCollection<LogEntry>();
        public ObservableCollection<Finding>                Findings        { get; } = new ObservableCollection<Finding>();
        public ObservableCollection<NetworkRecommendation>  Recommendations { get; } = new ObservableCollection<NetworkRecommendation>();

        // ----- Section header status pill -----
        private string _statusLabel = "Watching ports…";
        public string StatusLabel { get => _statusLabel; set => Set(ref _statusLabel, value); }

        private string _statusSeverity = "neutral";
        public string StatusSeverity { get => _statusSeverity; set => Set(ref _statusSeverity, value); }

        private Brush _statusColor;
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }

        private Brush _statusBg;
        public Brush StatusBg { get => _statusBg; set => Set(ref _statusBg, value); }

        // ----- NIC summary line above the diagram strip -----
        private string _nicCaption = "Camera NIC · 4 ports";
        public string NicCaption { get => _nicCaption; set => Set(ref _nicCaption, value); }

        // ----- Cross-tab + adapter-settings commands -----
        public ICommand OpenAdapterSettingsCommand { get; }
        public ICommand GoToNetworkCommand         { get; }
        public ICommand OpenCamerasCfgCommand      { get; }

        public CameraConnectivityViewModel(INetworkAdapterService net, IPixellotConfigService cfg)
        {
            _net = net;
            _cfg = cfg;

            _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
            _statusBg    = StatusHelpers.Brush("BorderColBrush");

            // Always render 4 placeholder tiles so the diagram strip is full
            // even before the first poll resolves.
            for (int i = 1; i <= 4; i++)
            {
                Ports.Add(new PortViewModel
                {
                    Name = $"Port {i}",
                    PrimaryLabel = "No cable",
                    SecondaryLabel = "",
                    StatusLine = "No cable",
                    StatusColor = StatusHelpers.Brush("MutedForegroundBrush"),
                    ErrorLine = "",
                    ErrorColor = StatusHelpers.Brush("MutedForegroundBrush"),
                });
            }

            OpenAdapterSettingsCommand = new RelayCommand(() => SafeStart("ncpa.cpl"));

            GoToNetworkCommand = new RelayCommand(() => App.NavigateToTab("Network"));

            OpenCamerasCfgCommand = new RelayCommand(() =>
            {
                // Try the path the service knows about; fall back to the
                // canonical Pixellot install location so the click still does
                // something useful even if the service dir is missing.
                var path = _cfg?.CamerasCfgPath ?? @"C:\Pixellot\Data\configuration\cameras.cfg";
                SafeStart(path);
            });

            // 1 s monitor — the prior agent locked this. Auto-start.
            _monitor = new CameraNicMonitor(_net);
            _monitor.Tick += OnMonitorTick;
            _monitor.Start();

            AddLog("Monitor", "Live camera-NIC monitor started (1 s poll).", "Section");
        }

        // -------------------------------------------------------------------
        // Monitor → UI projection
        // -------------------------------------------------------------------
        private void OnMonitorTick(List<PortState> states)
        {
            try
            {
                var roles = SafeGetRoles();

                EnsurePortCount(Math.Max(4, states.Count));

                // Refresh NIC caption from the first known description.
                var firstDesc = states.FirstOrDefault(s => s.Snapshot != null
                                                        && !string.IsNullOrEmpty(s.Snapshot.Description))
                                       ?.Snapshot?.Description;
                NicCaption = !string.IsNullOrWhiteSpace(firstDesc)
                    ? $"{firstDesc} · 4 ports"
                    : "Camera NIC · 4 ports";

                int unpluggedCount = 0;
                int linkedCount    = 0;
                int warnings       = 0;
                int criticals      = 0;

                for (int i = 0; i < Ports.Count; i++)
                {
                    var port = Ports[i];

                    if (i >= states.Count)
                    {
                        ResetTileToEmpty(port, i);
                        unpluggedCount++;
                        continue;
                    }

                    var st   = states[i];
                    var snap = st.Snapshot;
                    if (snap == null) { ResetTileToEmpty(port, i); unpluggedCount++; continue; }

                    var info = RemoteDeviceResolver.Resolve(snap.RemoteMac, snap.RemoteIp, roles);

                    // ---- IP / MAC / errors / labels ----
                    port.Ip = string.IsNullOrEmpty(snap.RemoteIp) ? "—" : snap.RemoteIp;
                    port.Mac = string.IsNullOrEmpty(snap.RemoteMac) ? "—" : snap.RemoteMac;
                    port.PrimaryLabel = info.PrimaryLabel;
                    port.SecondaryLabel = info.SecondaryLabel;
                    port.PrimaryColor = info.IsConfigured
                        ? StatusHelpers.Brush(info.IsOcr ? "AccentBrush" : "GreenBrush")
                        : StatusHelpers.Brush("ForegroundBrush");

                    bool errorsRising = st.ErrorsRising(_monitor.ErrorWindow, DateTime.UtcNow);
                    port.ErrorLine = snap.ErrorCount > 0
                        ? $"{snap.ErrorCount} errors{(errorsRising ? " ↑" : "")}"
                        : "0 errors";
                    port.ErrorColor = (errorsRising || snap.ErrorCount > 0)
                        ? StatusHelpers.Brush(errorsRising ? "YellowBrush" : "ForegroundBrush")
                        : StatusHelpers.Brush("MutedForegroundBrush");
                    // Legacy aliases
                    port.Errors = snap.ErrorCount.ToString();
                    port.ErrorsText  = port.ErrorLine;
                    port.ErrorsColor = port.ErrorColor;

                    // ---- Status line + colour ----
                    int flaps = st.FlapCountInWindow(_monitor.FlapWindow, DateTime.UtcNow);
                    bool isFlapping = flaps >= _monitor.FlapTransitionsThreshold;

                    string statusLine; Brush statusBrush;
                    bool is1G   = snap.LinkSpeedBps >= 1_000_000_000UL;
                    bool is100M = snap.LinkSpeedBps >= 100_000_000UL && snap.LinkSpeedBps < 1_000_000_000UL;

                    if (!snap.IsUp)
                    {
                        if (string.IsNullOrEmpty(snap.RemoteMac))
                        {
                            statusLine = "No cable";
                            statusBrush = StatusHelpers.Brush("MutedForegroundBrush");
                        }
                        else
                        {
                            statusLine = "Cable, no link";
                            statusBrush = StatusHelpers.Brush("YellowBrush");
                        }
                    }
                    else if (is1G)
                    {
                        statusLine = "Linked · 1 Gbps";
                        statusBrush = StatusHelpers.Brush("GreenBrush");
                    }
                    else if (is100M && info.IsOcr)
                    {
                        statusLine = "Linked · 100 Mbps · OCR (expected)";
                        statusBrush = StatusHelpers.Brush("GreenBrush");
                    }
                    else if (is100M)
                    {
                        statusLine = "Linked · 100 Mbps (expected 1 Gbps)";
                        statusBrush = StatusHelpers.Brush("YellowBrush");
                    }
                    else
                    {
                        statusLine = "Linked · " + FormatSpeed(snap.LinkSpeedBps);
                        statusBrush = StatusHelpers.Brush("AccentBrush");
                    }

                    if (isFlapping)
                    {
                        statusLine += $"  ·  Flapping x{flaps}/60s";
                        statusBrush = StatusHelpers.Brush("YellowBrush");
                    }

                    port.StatusLine  = statusLine;
                    port.StatusText  = statusLine; // legacy
                    port.StatusColor = statusBrush;

                    // ---- Duration / Last-seen line ----
                    port.DurationText = ComputeDurationLine(st, snap);
                    port.LastSeenText = port.DurationText;

                    // Legacy fields — keep populated for any old binding paths.
                    port.Speed = FormatSpeed(snap.LinkSpeedBps);
                    port.Device = info.PrimaryLabel;
                    port.DeviceColor = port.PrimaryColor;

                    // ---- Roll-up counters ----
                    if (!snap.IsUp)
                    {
                        if (string.IsNullOrEmpty(snap.RemoteMac)) unpluggedCount++;
                    }
                    else
                    {
                        linkedCount++;
                    }

                    // ---- History updates from transitions ----
                    AppendHistoryFromTick(port, snap, errorsRising, isFlapping, flaps);

                    // ---- Severity contributions for the page-level pill ----
                    if (info.IsConfigured && snap.IsUp && is100M && !info.IsOcr) warnings++;
                    if (errorsRising) warnings++;
                    if (isFlapping)   warnings++;
                    if (info.IsConfigured && !snap.IsUp && !string.IsNullOrEmpty(snap.RemoteMac)) criticals++;
                    if (info.IsConfigured && !snap.IsUp && string.IsNullOrEmpty(snap.RemoteMac)) warnings++;
                    if (DidSpeedRegress(snap)) criticals++;
                }

                // Configured cameras that don't appear on any port at all.
                int missingFromPorts = CountMissingConfiguredCameras(roles, states);

                // ≥3 of 4 dark = critical.
                if (Ports.Count > 0 && unpluggedCount >= 3) criticals++;

                BuildRecommendations(states, roles, unpluggedCount, missingFromPorts);
                ApplyStatusPill(linkedCount, warnings, criticals);
                PruneAllHistory();

                // Bump the speed baseline once at the end so DidSpeedRegress
                // sees a stable "previous tick" value next time around.
                foreach (var st in states)
                    if (st.Snapshot != null) UpdateSpeedBaseline(st.Snapshot);
            }
            catch (Exception ex)
            {
                AddLog("Monitor", $"Tick projection failed: {ex.Message}", "Fail");
            }
        }

        // -------------------------------------------------------------------
        // History, log, and tile-clear helpers
        // -------------------------------------------------------------------
        private void AppendHistoryFromTick(PortViewModel port, CameraNicSnapshot snap,
                                           bool errorsRising, bool isFlapping, int flaps)
        {
            var key = snap.LocalMac ?? port.Name;

            // -- Link transition --
            _prevUpByMac.TryGetValue(key, out var prevUp);
            if (prevUp != snap.IsUp)
            {
                if (prevUp.HasValue)
                {
                    if (snap.IsUp)
                    {
                        AppendHistory(port, "Link up",
                                      $"Negotiated {FormatSpeed(snap.LinkSpeedBps)}",
                                      "GreenBrush");
                        AddLog(port.Name, $"Link up — {FormatSpeed(snap.LinkSpeedBps)}", "Pass");
                    }
                    else
                    {
                        AppendHistory(port, "Link down", "Cable removed or NIC dropped", "RedBrush");
                        AddLog(port.Name, "Link down", "Fail");
                    }
                }
                _prevUpByMac[key] = snap.IsUp;
            }

            // -- Error count rose --
            _prevErrCountByMac.TryGetValue(key, out var prevErr);
            if (snap.ErrorCount > prevErr && errorsRising)
            {
                // Rate-limited via the 30 s window in PortState; we get one
                // entry per "errorsRising" transition, not one per tick.
                AppendHistory(port, "Errors", $"NIC errors rose to {snap.ErrorCount}", "YellowBrush");
                AddLog(port.Name, $"Errors rose to {snap.ErrorCount}", "Warn");
            }
            _prevErrCountByMac[key] = snap.ErrorCount;

            // -- Flapping detected (one entry per minute window) --
            if (isFlapping
                && (port.History.Count == 0
                    || port.History[port.History.Count - 1].State != "Flap"
                    || (DateTime.Now - port.History[port.History.Count - 1].Timestamp) > TimeSpan.FromSeconds(15)))
            {
                AppendHistory(port, "Flap", $"{flaps} transitions in last 60 s", "YellowBrush");
                AddLog(port.Name, $"Flapping — {flaps} transitions in 60 s", "Warn");
            }
        }

        private static void AppendHistory(PortViewModel port, string state, string note, string brushKey)
        {
            port.History.Add(new PortHistoryEntry
            {
                Timestamp = DateTime.Now,
                State = state,
                Note = note,
                StateColor = StatusHelpers.Brush(brushKey),
            });
            // Hard cap so a chronically-flapping port can't exceed the buffer.
            while (port.History.Count > MaxHistoryEntriesPerPort)
                port.History.RemoveAt(0);
        }

        private void PruneAllHistory()
        {
            var threshold = DateTime.Now - HistoryRetention;
            foreach (var p in Ports)
            {
                while (p.History.Count > 0 && p.History[0].Timestamp < threshold)
                    p.History.RemoveAt(0);
            }
        }

        private void ResetTileToEmpty(PortViewModel port, int idx)
        {
            port.PrimaryLabel  = "No cable";
            port.SecondaryLabel = "";
            port.StatusLine    = "No cable";
            port.StatusText    = "No cable";
            port.StatusColor   = StatusHelpers.Brush("MutedForegroundBrush");
            port.Ip = "—"; port.Mac = "—";
            port.ErrorLine = "";
            port.ErrorColor = StatusHelpers.Brush("MutedForegroundBrush");
            port.Errors = "—"; port.ErrorsText = ""; port.ErrorsColor = port.ErrorColor;
            port.Speed = "—"; port.Device = "No cable"; port.DeviceColor = port.StatusColor;
            port.DurationText = ""; port.LastSeenText = "";
        }

        private void EnsurePortCount(int desired)
        {
            // 4 always; never shrink below 4 even if the OS reports fewer.
            // (We map the first 4 by MAC ordering; extras are ignored.)
            while (Ports.Count < 4)
            {
                int n = Ports.Count + 1;
                Ports.Add(new PortViewModel { Name = $"Port {n}" });
            }
            // Re-name in case anything wandered.
            for (int i = 0; i < Ports.Count; i++)
                Ports[i].Name = $"Port {i + 1}";
        }

        // -------------------------------------------------------------------
        // Recommendations engine — one row per failure mode.
        // -------------------------------------------------------------------
        private void BuildRecommendations(List<PortState> states,
                                          Dictionary<string, string> roles,
                                          int unpluggedCount,
                                          int missingFromPorts)
        {
            var rows = new List<NetworkRecommendation>();

            // ≥3 of 4 dark — most-camera-ports-dark critical.
            if (Ports.Count > 0 && unpluggedCount >= 3)
            {
                var r = NetworkRecommendation.Create(
                    "Critical",
                    "Most camera ports dark",
                    $"{unpluggedCount} of {Ports.Count} ports report no link. Check that the camera-NIC card is seated and the breakout cable harness isn't unplugged.");
                rows.Add(r);
            }

            for (int i = 0; i < states.Count && i < Ports.Count; i++)
            {
                var st   = states[i];
                var snap = st.Snapshot;
                if (snap == null) continue;

                var portNum = i + 1;
                var info = RemoteDeviceResolver.Resolve(snap.RemoteMac, snap.RemoteIp, roles);
                bool is1G   = snap.LinkSpeedBps >= 1_000_000_000UL;
                bool is100M = snap.LinkSpeedBps >= 100_000_000UL && snap.LinkSpeedBps < 1_000_000_000UL;

                // Mid-session speed regression (1 Gbps -> 100 Mbps live).
                if (DidSpeedRegress(snap))
                {
                    rows.Add(NetworkRecommendation.Create(
                        "Critical",
                        $"Live cable failure on Port {portNum}",
                        $"Link dropped from 1 Gbps to 100 Mbps mid-session. Replace the cable on Port {portNum}; the previous one is failing under load."));
                }

                // Linked-degraded: configured Main camera at 100 Mbps.
                if (snap.IsUp && is100M && info.IsConfigured && !info.IsOcr)
                {
                    rows.Add(NetworkRecommendation.Create(
                        "Critical",
                        $"Cable or jack fault on Port {portNum}",
                        $"Reseat or replace the cable on Port {portNum}. Expected 1 Gbps for {info.PrimaryLabel}, currently negotiated 100 Mbps."));
                }

                // Cable + no link.
                if (!snap.IsUp && !string.IsNullOrEmpty(snap.RemoteMac))
                {
                    rows.Add(NetworkRecommendation.Create(
                        "Warning",
                        $"Cabled, no link on Port {portNum}",
                        $"Switch sees a cable but no negotiation on Port {portNum}. Try a different cable, then a different jack."));
                }

                // No cable on a configured port.
                // We can only know "configured" via an OS-detected RemoteIp from
                // an earlier tick. A truly absent port surfaces below as
                // "configured camera missing".
                if (!snap.IsUp && string.IsNullOrEmpty(snap.RemoteMac)
                    && !string.IsNullOrEmpty(st.LastRemoteIp)
                    && roles.TryGetValue(st.LastRemoteIp, out var configuredRole))
                {
                    rows.Add(NetworkRecommendation.Create(
                        "Warning",
                        $"Configured camera {configuredRole} not detected on Port {portNum}",
                        $"Plug a cable into Port {portNum} of the VPU."));
                }

                // Flapping.
                int flaps = st.FlapCountInWindow(_monitor.FlapWindow, DateTime.UtcNow);
                if (flaps >= _monitor.FlapTransitionsThreshold)
                {
                    rows.Add(NetworkRecommendation.Create(
                        "Warning",
                        $"Port {portNum} flapping x{flaps} in 60 s",
                        $"Replace the cable on Port {portNum}; if it persists, swap the PoE injector."));
                }

                // Errors rising.
                if (st.ErrorsRising(_monitor.ErrorWindow, DateTime.UtcNow))
                {
                    rows.Add(NetworkRecommendation.Create(
                        "Warning",
                        $"CRC/alignment errors rising on Port {portNum}",
                        $"Likely a damaged cable or EMI near Port {portNum}. Replace the cable; if errors continue, reroute away from power runs."));
                }

                // Unknown remote (linked, no cfg match, not Pixellot OUI).
                if (snap.IsUp
                    && !info.IsConfigured
                    && info.Source != DeviceIdentitySource.None
                    && !MacOuiTable.IsVendor(snap.RemoteMac, "Pixellot"))
                {
                    var label = string.IsNullOrEmpty(info.PrimaryLabel) ? "Unknown" : info.PrimaryLabel;
                    rows.Add(NetworkRecommendation.Create(
                        "Info",
                        $"Unknown {label} device on Port {portNum}",
                        "Verify cameras.cfg or unplug the unintended device."));
                }
            }

            // Configured cameras not visible on any port — Warning.
            if (missingFromPorts > 0)
            {
                rows.Add(NetworkRecommendation.Create(
                    "Warning",
                    "Configured cameras missing",
                    $"cameras.cfg lists {missingFromPorts} camera{(missingFromPorts == 1 ? "" : "s")} not visible on any VPU port. Check cabling and PoE."));
            }

            // Wire the cross-tab buttons. Network is the most useful for any
            // link-degraded / no-link row; cameras.cfg is the right jump for
            // role-mismatch and missing-cfg rows.
            foreach (var r in rows)
            {
                if (r.Title.IndexOf("cameras.cfg", StringComparison.OrdinalIgnoreCase) >= 0
                    || r.Title.IndexOf("missing", StringComparison.OrdinalIgnoreCase) >= 0
                    || r.Title.IndexOf("Configured camera", StringComparison.OrdinalIgnoreCase) >= 0
                    || r.Title.IndexOf("Unknown", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    r.ActionLabel = "Open cameras.cfg";
                    r.ActionCommand = OpenCamerasCfgCommand;
                }
                else if (r.Title.IndexOf("flap", StringComparison.OrdinalIgnoreCase) >= 0
                         || r.Title.IndexOf("Cable", StringComparison.OrdinalIgnoreCase) >= 0
                         || r.Title.IndexOf("dark", StringComparison.OrdinalIgnoreCase) >= 0
                         || r.Title.IndexOf("Live cable", StringComparison.OrdinalIgnoreCase) >= 0
                         || r.Title.IndexOf("errors", StringComparison.OrdinalIgnoreCase) >= 0
                         || r.Title.IndexOf("Cabled", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    r.ActionLabel = "Go to Network";
                    r.ActionCommand = GoToNetworkCommand;
                }
            }

            // Replace the contents (no clear-and-rebuild flicker visible at 1 s).
            Recommendations.Clear();
            foreach (var r in rows) Recommendations.Add(r);

            // Mirror the most severe rows into Findings so the page-header
            // pill + banner stay aligned with what the recs say. Finding.Create
            // accepts the same severity strings, so we re-use them verbatim.
            Findings.Clear();
            foreach (var r in rows)
                Findings.Add(Finding.Create(r.Severity, r.Title, r.Body, "Cameras"));
        }

        private bool DidSpeedRegress(CameraNicSnapshot snap)
        {
            // 1G -> 100M live regression — pure check, no side effects.
            // Baseline is bumped once per tick by UpdateSpeedBaseline at the
            // very end so multiple callers in the same tick agree.
            if (string.IsNullOrEmpty(snap.LocalMac)) return false;
            _prevSpeedByMac.TryGetValue(snap.LocalMac, out var prev);
            return prev >= 1_000_000_000UL
                && snap.LinkSpeedBps >= 100_000_000UL
                && snap.LinkSpeedBps < 1_000_000_000UL
                && snap.IsUp;
        }

        private void UpdateSpeedBaseline(CameraNicSnapshot snap)
        {
            if (string.IsNullOrEmpty(snap.LocalMac)) return;
            // Only update the baseline when we have a credible speed reading
            // — a transient 0 from a polling glitch must not erase a valid
            // 1 Gbps history.
            if (snap.LinkSpeedBps > 0) _prevSpeedByMac[snap.LocalMac] = snap.LinkSpeedBps;
        }

        private static int CountMissingConfiguredCameras(Dictionary<string, string> roles,
                                                         List<PortState> states)
        {
            if (roles == null || roles.Count == 0) return 0;
            var visibleIps = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var st in states)
            {
                var ip = st.Snapshot?.RemoteIp;
                if (!string.IsNullOrEmpty(ip)) visibleIps.Add(ip);
            }
            int n = 0;
            foreach (var ip in roles.Keys)
                if (!visibleIps.Contains(ip)) n++;
            return n;
        }

        // -------------------------------------------------------------------
        // Status-pill aggregator.
        // -------------------------------------------------------------------
        private void ApplyStatusPill(int linked, int warnings, int criticals)
        {
            if (criticals > 0)
            {
                StatusLabel = criticals == 1 ? "1 Critical" : $"{criticals} Critical";
                StatusSeverity = "critical";
                StatusColor = StatusHelpers.Brush("RedBrush");
                StatusBg    = StatusHelpers.Brush("ErrBgBrush");
            }
            else if (warnings > 0)
            {
                StatusLabel = warnings == 1 ? "1 Warning" : $"{warnings} Warnings";
                StatusSeverity = "warn";
                StatusColor = StatusHelpers.Brush("YellowBrush");
                StatusBg    = StatusHelpers.Brush("WarnBgBrush");
            }
            else if (linked > 0)
            {
                StatusLabel = $"All Clear ({linked} linked at 1 Gbps)";
                StatusSeverity = "ok";
                StatusColor = StatusHelpers.Brush("GreenBrush");
                StatusBg    = StatusHelpers.Brush("OkBgBrush");
            }
            else
            {
                StatusLabel = "Watching ports…";
                StatusSeverity = "neutral";
                StatusColor = StatusHelpers.Brush("MutedForegroundBrush");
                StatusBg    = StatusHelpers.Brush("BorderColBrush");
            }
        }

        // -------------------------------------------------------------------
        // Small helpers.
        // -------------------------------------------------------------------
        private Dictionary<string, string> SafeGetRoles()
        {
            try { return _cfg?.GetRoles() ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase); }
            catch { return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase); }
        }

        private static string FormatSpeed(ulong bps)
        {
            if (bps == 0) return "—";
            if (bps >= 1_000_000_000UL) return $"{bps / 1_000_000_000UL} Gbps";
            if (bps >= 1_000_000UL)     return $"{bps / 1_000_000UL} Mbps";
            return $"{bps} bps";
        }

        private static string ComputeDurationLine(PortState st, CameraNicSnapshot snap)
        {
            if (snap.IsUp && st.LinkUpSince.HasValue)
            {
                var d = DateTime.UtcNow - st.LinkUpSince.Value;
                if (d.TotalSeconds < 0) d = TimeSpan.Zero;
                if (d.TotalHours >= 1) return $"Linked {(int)d.TotalHours}h {d.Minutes:00}m";
                if (d.TotalMinutes >= 1) return $"Linked {(int)d.TotalMinutes}m {d.Seconds:00}s";
                return $"Linked {(int)d.TotalSeconds}s";
            }
            // Down — show last-seen if we have one in the retention window.
            if (st.LastRemoteAt.HasValue)
            {
                var ago = DateTime.UtcNow - st.LastRemoteAt.Value;
                var label = !string.IsNullOrEmpty(st.LastRemoteLabel) ? st.LastRemoteLabel
                          : !string.IsNullOrEmpty(st.LastRemoteIp)    ? st.LastRemoteIp
                          : "device";
                if (ago.TotalMinutes < 1) return $"Last: {label}, just now";
                return $"Last: {label}, {(int)ago.TotalMinutes} min ago";
            }
            return "";
        }

        private static void SafeStart(string target)
        {
            try
            {
                var psi = new ProcessStartInfo(target) { UseShellExecute = true };
                Process.Start(psi);
            }
            catch
            {
                // Suppress — the recommendation row is already on screen so
                // the user knows what was supposed to happen. We don't have a
                // reliable toast surface in the WPF pilot yet.
            }
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
            while (LogEntries.Count > 200) LogEntries.RemoveAt(0);
        }
    }
}
