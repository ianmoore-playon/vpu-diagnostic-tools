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

        // v0.5.2 §2: the stale-tile dimming + "· stale Ns" suffix were field-
        // tech confusing. Removed entirely — when ARP is lost the tile flips
        // immediately to the next clean binary state (linked / no cable /
        // cable-no-link). Recent activity expander still preserves the audit
        // trail.

        // v0.4.6 §5 flicker fix — track the last-rendered multiset hash for
        // Recommendations and Findings so a no-change tick is a no-op.
        private int _lastRecommendationsHash;
        private int _lastFindingsHash;

        // ----- Public bindings -----
        public ObservableCollection<PortViewModel>          Ports           { get; } = new ObservableCollection<PortViewModel>();
        // Composed via PanelLogger (v0.5.0) — shared with the four other panels.
        public PanelLogger Logger { get; } = new PanelLogger();
        public ObservableCollection<LogEntry> LogEntries => Logger.Entries;
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
                    LinkLedBrush = StatusHelpers.Brush("SubtleForegroundBrush"),
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
                var rolesByMac = SafeGetRolesByMac();

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

                    // RemoteMac is null/empty whenever the candidate ARP entry
                    // failed the IsInvalidMac filter or matched the local
                    // self-IP. Resolver returns Source=None in that case so
                    // we render the empty-state row.
                    var info = RemoteDeviceResolver.Resolve(snap.RemoteMac, snap.RemoteIp, roles, rolesByMac);
                    bool hasRealRemote = info.Source != DeviceIdentitySource.None
                                         && !string.IsNullOrEmpty(snap.RemoteMac)
                                         && !string.IsNullOrEmpty(snap.RemoteIp);

                    // v0.5.2 §2: stale-window dimming removed. State is now
                    // strictly binary — linked / no cable / cable-no-link.
                    DateTime utcNow = DateTime.UtcNow;

                    bool errorsRising = st.ErrorsRising(_monitor.ErrorWindow, utcNow);
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

                    // ---- Status line + colour + LED brush ----
                    int flaps = st.FlapCountInWindow(_monitor.FlapWindow, utcNow);
                    bool isFlapping = flaps >= _monitor.FlapTransitionsThreshold;

                    string statusLine; Brush statusBrush; Brush ledBrush;
                    bool is1G   = snap.LinkSpeedBps >= 1_000_000_000UL;
                    bool is100M = snap.LinkSpeedBps >= 100_000_000UL && snap.LinkSpeedBps < 1_000_000_000UL;

                    string primary; string secondary;
                    string ipShown = "—"; string macShown = "—";

                    if (!snap.IsUp && string.IsNullOrEmpty(snap.RemoteMac))
                    {
                        // Row 1: No cable.
                        primary = "No cable";
                        secondary = "";
                        statusLine = "No cable";
                        statusBrush = StatusHelpers.Brush("MutedForegroundBrush");
                        ledBrush    = StatusHelpers.Brush("SubtleForegroundBrush");
                    }
                    else if (!snap.IsUp)
                    {
                        // Row 2: cabled, no link.
                        primary = "Waiting for link";
                        secondary = "";
                        statusLine = "Cable, no link";
                        statusBrush = StatusHelpers.Brush("YellowBrush");
                        ledBrush    = StatusHelpers.Brush("YellowBrush");
                    }
                    else if (!hasRealRemote)
                    {
                        // v0.5.2 §1: link is up but ARP hasn't cached the
                        // neighbour yet. Field techs don't care about ARP
                        // state — render plain "Linked" with a tiny side
                        // note. Tile colour stays green (linked is green;
                        // don't muddy with a "still figuring it out" hue).
                        // If we had a previous remote in the resolve window,
                        // keep that label for visual continuity.
                        if (!string.IsNullOrEmpty(st.LastRemoteLabel))
                        {
                            primary = st.LastRemoteLabel;
                            secondary = !string.IsNullOrEmpty(st.LastRemoteIp) ? st.LastRemoteIp : "";
                            ipShown  = !string.IsNullOrEmpty(st.LastRemoteIp)  ? st.LastRemoteIp  : "—";
                            macShown = !string.IsNullOrEmpty(st.LastRemoteMac) ? st.LastRemoteMac : "—";
                        }
                        else
                        {
                            primary   = "Linked";
                            secondary = "Identifying device…";
                        }
                        statusLine = is1G   ? "Linked · 1 Gbps"
                                   : is100M ? "Linked · 100 Mbps"
                                            : "Linked · " + FormatSpeed(snap.LinkSpeedBps);
                        statusBrush = StatusHelpers.Brush("GreenBrush");
                        ledBrush    = is1G ? StatusHelpers.Brush("GreenBrush")
                                           : StatusHelpers.Brush("YellowBrush");
                    }
                    else if (is1G)
                    {
                        primary = info.PrimaryLabel; secondary = info.SecondaryLabel;
                        ipShown = snap.RemoteIp; macShown = snap.RemoteMac;
                        statusLine = "Linked · 1 Gbps";
                        statusBrush = StatusHelpers.Brush("GreenBrush");
                        ledBrush    = StatusHelpers.Brush("GreenBrush");
                    }
                    else if (is100M && info.IsOcr)
                    {
                        primary = info.PrimaryLabel; secondary = info.SecondaryLabel;
                        ipShown = snap.RemoteIp; macShown = snap.RemoteMac;
                        statusLine = "Linked · 100 Mbps · OCR (expected)";
                        statusBrush = StatusHelpers.Brush("GreenBrush");
                        ledBrush    = StatusHelpers.Brush("GreenBrush");
                    }
                    else if (is100M)
                    {
                        primary = info.PrimaryLabel; secondary = info.SecondaryLabel;
                        ipShown = snap.RemoteIp; macShown = snap.RemoteMac;
                        statusLine = "Linked · 100 Mbps (expected 1 Gbps)";
                        statusBrush = StatusHelpers.Brush("YellowBrush");
                        ledBrush    = StatusHelpers.Brush("YellowBrush");
                    }
                    else
                    {
                        primary = info.PrimaryLabel; secondary = info.SecondaryLabel;
                        ipShown = snap.RemoteIp; macShown = snap.RemoteMac;
                        statusLine = "Linked · " + FormatSpeed(snap.LinkSpeedBps);
                        statusBrush = StatusHelpers.Brush("AccentBrush");
                        ledBrush    = StatusHelpers.Brush("YellowBrush");
                    }

                    if (isFlapping)
                    {
                        // Flap visualisation: solid amber + ↯ glyph in the
                        // status line. We do NOT pulse the LED (UX call).
                        statusLine += $"  ·  ↯ Flapping ×{flaps}/60s";
                        statusBrush = StatusHelpers.Brush("YellowBrush");
                        ledBrush    = StatusHelpers.Brush("YellowBrush");
                        port.IsPulsing = true;
                    }
                    else
                    {
                        port.IsPulsing = false;
                    }

                    // ---- Apply identity / labels / colors. ----
                    // Critical guard from the v0.4.6 spec: never render the
                    // literal "00-00-00-00-00-00" as a remote MAC, and never
                    // render the local self-IP (already filtered upstream).
                    port.Ip  = string.IsNullOrEmpty(ipShown)  ? "—" : ipShown;
                    port.Mac = string.IsNullOrEmpty(macShown) ? "—" : macShown;
                    port.PrimaryLabel = primary;
                    port.SecondaryLabel = secondary;
                    port.PrimaryColor = info.IsConfigured
                        ? StatusHelpers.Brush(info.IsOcr ? "AccentBrush" : "GreenBrush")
                        : StatusHelpers.Brush("ForegroundBrush");

                    port.StatusLine   = statusLine;
                    port.StatusText   = statusLine; // legacy
                    port.StatusColor  = statusBrush;
                    port.LinkLedBrush = ledBrush;
                    // v0.5.2 §2: stale-tile dimming dropped.
                    port.IsStale      = false;
                    port.TileOpacity  = 1.0;

                    // ---- Duration / Last-seen line ----
                    port.DurationText = ComputeDurationLine(st, snap);
                    port.LastSeenText = port.DurationText;
                    port.Uptime       = ComputeUptimeLine(st, snap);

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

                BuildRecommendations(states, roles, rolesByMac, unpluggedCount, missingFromPorts);
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
            port.LinkLedBrush  = StatusHelpers.Brush("SubtleForegroundBrush");
            port.Ip = "—"; port.Mac = "—";
            port.ErrorLine = "";
            port.ErrorColor = StatusHelpers.Brush("MutedForegroundBrush");
            port.Errors = "—"; port.ErrorsText = ""; port.ErrorsColor = port.ErrorColor;
            port.Speed = "—"; port.Device = "No cable"; port.DeviceColor = port.StatusColor;
            port.DurationText = ""; port.LastSeenText = ""; port.Uptime = "";
            port.IsStale = false; port.TileOpacity = 1.0; port.IsPulsing = false;
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
                                          Dictionary<string, string> rolesByMac,
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
                var info = RemoteDeviceResolver.Resolve(snap.RemoteMac, snap.RemoteIp, roles, rolesByMac);
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

                // Cable + no link — v0.5.2 §3 hold-off.
                // The *tile* StatusLine shows "Cable, no link" immediately
                // (that's just state display). The *recommendation* waits 30
                // s before firing, because Windows often reports cabled-no-
                // link transiently when a cable is being yanked — we don't
                // want to advise a cable swap for a normal unplug event.
                if (!snap.IsUp
                    && !string.IsNullOrEmpty(snap.RemoteMac)
                    && st.CabledNoLinkSince.HasValue
                    && (DateTime.UtcNow - st.CabledNoLinkSince.Value) >= TimeSpan.FromSeconds(30))
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

                // Flapping. v0.5.2 §3 re-check: the threshold is 3
                // transitions in 60 s, so a single up→down→up sequence (2
                // transitions) during a cable-yank does NOT trigger this —
                // genuine flapping needs at least one further toggle inside
                // the window. No hold-off needed.
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

            // v0.5.2 §4: the "Configured cameras missing" recommendation +
            // Finding were dropped. cameras.cfg vs. port-list comparison is
            // too noisy in the field (cameras.cfg often lists cameras for
            // other VPU models or dev environments). The role lookup itself
            // is still used to drive the tile primary label when a real
            // match exists — we just don't alert on the mismatch.
            _ = missingFromPorts; // intentionally unused now; signature kept

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

            // v0.4.6 §5 flicker fix — three layers:
            //   1. Equality short-circuit: hash the row multiset and bail out
            //      on a no-change tick (no CollectionChanged event fires).
            //   2. In-place delta: walk old/new in order; mutate existing
            //      rows via NetworkRecommendation.ApplyFrom (Set(ref ...));
            //      Add/RemoveAt only the trailing diff. At most a couple of
            //      CollectionChanged events per real change.
            //   3. Findings stays in lockstep with the same logic.
            int newRecHash = MultisetHash(rows.ConvertAll(r => r.RowHash()));
            if (newRecHash != _lastRecommendationsHash)
            {
                ApplyDelta(Recommendations, rows);
                _lastRecommendationsHash = newRecHash;
            }

            // Build the Findings projection separately so the multiset hash
            // is computed against the actual Finding rows we'd mirror.
            var findings = new List<Finding>(rows.Count);
            foreach (var r in rows)
                findings.Add(Finding.Create(r.Severity, r.Title, r.Body, "Cameras"));

            int newFindingsHash = MultisetHash(findings.ConvertAll(FindingRowHash));
            if (newFindingsHash != _lastFindingsHash)
            {
                ApplyFindingsDelta(Findings, findings);
                _lastFindingsHash = newFindingsHash;
            }
        }

        // ---- Multiset hash: order-insensitive, cheap, collision-tolerant. ----
        // We sum the per-row hashes; two lists with the same row hashes (in
        // any order) collide to the same multiset hash. Title+Severity+Body
        // are unique enough in practice that this is fine for "did the rec
        // set change" detection.
        private static int MultisetHash(IList<int> rowHashes)
        {
            unchecked
            {
                int sum = 0;
                int xor = 0;
                int count = rowHashes?.Count ?? 0;
                if (rowHashes != null)
                {
                    for (int i = 0; i < rowHashes.Count; i++)
                    {
                        sum += rowHashes[i];
                        xor ^= rowHashes[i];
                    }
                }
                int h = 17;
                h = h * 31 + count;
                h = h * 31 + sum;
                h = h * 31 + xor;
                return h;
            }
        }

        private static int FindingRowHash(Finding f)
        {
            unchecked
            {
                int h = 17;
                h = h * 31 + (int)f.Severity;
                h = h * 31 + (f.Title?.GetHashCode() ?? 0);
                h = h * 31 + (f.Recommendation?.GetHashCode() ?? 0);
                return h;
            }
        }

        private static void ApplyDelta(ObservableCollection<NetworkRecommendation> live,
                                        List<NetworkRecommendation> next)
        {
            // Walk old/new in order. For each index that exists in both,
            // mutate the existing row's properties; this fires
            // PropertyChanged on the affected fields but keeps the
            // collection slot itself stable, which is what kills the
            // visible flicker.
            int common = Math.Min(live.Count, next.Count);
            for (int i = 0; i < common; i++)
            {
                live[i].ApplyFrom(next[i]);
            }
            // Append any new trailing rows.
            for (int i = common; i < next.Count; i++)
            {
                live.Add(next[i]);
            }
            // Trim removed trailing rows.
            for (int i = live.Count - 1; i >= next.Count; i--)
            {
                live.RemoveAt(i);
            }
        }

        private static void ApplyFindingsDelta(ObservableCollection<Finding> live,
                                                List<Finding> next)
        {
            int common = Math.Min(live.Count, next.Count);
            for (int i = 0; i < common; i++)
            {
                // Re-apply via the existing helper so brushes track too.
                var dst = live[i];
                var src = next[i];
                dst.Apply(src.Severity, src.Title, src.Recommendation, src.Category);
            }
            for (int i = common; i < next.Count; i++)
            {
                live.Add(next[i]);
            }
            for (int i = live.Count - 1; i >= next.Count; i--)
            {
                live.RemoveAt(i);
            }
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

        private Dictionary<string, string> SafeGetRolesByMac()
        {
            try { return _cfg?.GetRolesByMac() ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase); }
            catch { return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase); }
        }

        private static string FormatSpeed(ulong bps)
        {
            if (bps == 0) return "—";
            if (bps >= 1_000_000_000UL) return $"{bps / 1_000_000_000UL} Gbps";
            if (bps >= 1_000_000UL)     return $"{bps / 1_000_000UL} Mbps";
            return $"{bps} bps";
        }

        // Total link uptime — coarser, day-scale render of the same source
        // CameraNicMonitor tracks. Moved here from the Hardware panel in
        // v0.5.0 so link-state data lives on the link-state tab. Returns
        // "" when the port is not currently up.
        private static string ComputeUptimeLine(PortState st, CameraNicSnapshot snap)
        {
            if (!snap.IsUp || !st.LinkUpSince.HasValue) return "";
            var d = DateTime.UtcNow - st.LinkUpSince.Value;
            if (d.TotalSeconds < 0) d = TimeSpan.Zero;
            if (d.TotalDays >= 2)     return $"Uptime: {(int)d.TotalDays}d {d.Hours}h";
            if (d.TotalHours >= 2)    return $"Uptime: {(int)d.TotalHours}h {d.Minutes}m";
            if (d.TotalMinutes >= 1)  return $"Uptime: {(int)d.TotalMinutes}m";
            return $"Uptime: {(int)d.TotalSeconds}s";
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

        private void AddLog(string label, string result, string level) => Logger.Add(label, result, level);
    }
}
