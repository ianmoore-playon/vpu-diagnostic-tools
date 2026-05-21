using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
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

        // v0.8.16-beta: NIC driver events from the System event log are a
        // strong supplemental fault signal. Intel's e1iexpress (and other
        // NIC drivers) log the exact flap pattern - Event 40 "SmartSpeed
        // downgrade", Event 33 "link established at X Mbps", Event 27
        // "Network link is disconnected" - giving us per-driver telemetry
        // that's more reliable than our debounced polling for "is this
        // port misbehaving". Polled on a separate timer (30 s) because
        // EventLogReader is expensive relative to the 500 ms monitor poll.
        private readonly IEventViewerService _events;
        private System.Windows.Threading.DispatcherTimer _eventPollTimer;
        private bool _eventPollRunning;

        // v0.8.19-beta: positive OCR identification via Dynacolor CGI probe.
        // Replaces the speed-inference heuristic (Layer 2/3 in IsLikelyOcr)
        // with an authoritative answer from the camera itself: a single
        // HTTP GET to the OCR's CGI returns the camera MAC, AND the act
        // of probing populates Windows' ARP table as a side effect so the
        // existing monitor pipeline picks it up on the next 500 ms tick.
        //
        // _confirmedOcrByMac caches the result of a successful probe so
        // IsLikelyOcr can short-circuit the 5 s grace period for ports
        // we've already identified as OCR. Keyed by the camera's MAC (from
        // the probe response) - we cross-check against ARP-resolved
        // RemoteMac on the next tick to determine which port it's on.
        //
        // _lastProbeAt rate-limits probes per IP to once every 10 s so a
        // port stuck in "no ARP" doesn't spam the network with HTTP
        // requests every tick.
        private readonly IOcrProbeService _ocrProbe;
        private readonly Dictionary<string, DateTime> _lastProbeAtByIp =
            new Dictionary<string, DateTime>(StringComparer.OrdinalIgnoreCase);
        private readonly HashSet<string> _confirmedOcrMacs =
            new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private static readonly TimeSpan OcrProbeInterval = TimeSpan.FromSeconds(10);
        private static readonly TimeSpan OcrProbeTimeout  = TimeSpan.FromSeconds(2);

        // Pixellot ships OCR cameras with these two default link-local
        // IPs out of the box. The ocr-tester reference tool uses them as
        // probe targets when the user hasn't supplied a custom IP. Pulse
        // adds them to the cfg-derived list so a brand-new venue (cfg not
        // yet populated) can still positively identify the OCR.
        private static readonly string[] DefaultOcrIps =
        {
            "169.254.16.52",
            "169.254.16.60",
        };

        // v0.8.16-beta: per-port event analysis. Keyed by local MAC so a
        // PortViewModel can be looked up across both the live monitor and
        // the slow event poll. _descriptionByMac is updated by OnMonitorTick
        // (snap.Description is the long adapter name like "Intel(R) 82574L
        // Gigabit Network Connection #15" which Windows events include as
        // the first line of Message - that's the matching key). The other
        // two dictionaries are updated by PollNicDriverEventsAsync and read
        // by BuildRecommendations to surface a Critical row when Intel's
        // SmartSpeed downgrade event fired in the last hour.
        private readonly Dictionary<string, string> _descriptionByMac =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, int> _eventCountByMac =
            new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, bool> _smartSpeedDowngradeByMac =
            new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

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

        /// <summary>
        /// v0.8.6-beta: Ports in physical-jack visual order (Port 4 → 3 → 2 → 1).
        ///
        /// The chassis's RJ45 jacks are laid out right-to-left as Port 4 |
        /// Port 3 | Port 2 | Port 1. The NIC card diagram + the tile strip
        /// underneath bind to this collection so the on-screen layout
        /// mirrors what the tech sees on the physical card. The vertical
        /// LED strip in the diagram also binds to this collection so its
        /// top-to-bottom LEDs read Port 4, Port 3, Port 2, Port 1.
        ///
        /// The same PortViewModel instances appear in both Ports and
        /// PortsByPhysical — only the iteration order differs. Property
        /// changes on a port (LinkLedBrush, StatusLine, etc.) propagate to
        /// both views without extra plumbing.
        ///
        /// Kept in sync with Ports inside <see cref="EnsurePortCount"/>.
        /// </summary>
        public ObservableCollection<PortViewModel> PortsByPhysical { get; } = new ObservableCollection<PortViewModel>();
        // Composed via PanelLogger (v0.5.0) — shared with the four other panels.
        public PanelLogger Logger { get; } = new PanelLogger("Camera");
        // v0.5.5: Camera is a live monitor, so it doesn't auto-write a report
        // per tick (86,400 files/day would be absurd). Instead we expose a
        // user-driven "Save Snapshot" top-bar button that captures the
        // current state. The rolling AppLogFile still catches every live-
        // monitor transition via PanelLogger.
        private readonly ReportWriter _reportWriter = new ReportWriter();
        public string LastReportPath { get; private set; }
        public ObservableCollection<LogEntry> LogEntries => Logger.Entries;
        public ObservableCollection<Finding>                Findings        { get; } = new ObservableCollection<Finding>();
        public ObservableCollection<NetworkRecommendation>  Recommendations { get; } = new ObservableCollection<NetworkRecommendation>();

        /// <summary>
        /// v0.8.22-beta: header text for the merged Findings + Recommended
        /// Actions card. Returns "1 finding needs attention" / "2 findings
        /// need attention" / "" (empty when no recommendations to surface).
        /// Updated whenever Recommendations changes shape via the
        /// CollectionChanged subscription in the constructor.
        /// </summary>
        private string _findingsHeader = "";
        public string FindingsHeader { get => _findingsHeader; private set => Set(ref _findingsHeader, value); }

        private void RebuildFindingsHeader()
        {
            int n = Recommendations.Count;
            FindingsHeader = n == 0 ? ""
                : n == 1 ? "1 finding needs attention"
                : $"{n} findings need attention";
        }

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

        // v0.6.5: inline status toast next to the Save Snapshot button.
        // Cleared by a 4 s DispatcherTimer (see ScheduleClearSnapshotStatus)
        // — matches the SystemOverview "Copy as text" pattern.
        private string _snapshotStatus = "";
        public string SnapshotStatus { get => _snapshotStatus; set => Set(ref _snapshotStatus, value); }

        // ----- Cross-tab + adapter-settings commands -----
        public ICommand OpenAdapterSettingsCommand        { get; }
        public ICommand OpenNetworkAndSharingCenterCommand { get; }
        public ICommand GoToNetworkCommand                { get; }
        public ICommand OpenCamerasCfgCommand             { get; }
        public ICommand SaveSnapshotCommand               { get; }

        // v0.8.0-beta: opens the Fault Isolator (4-phase swap test).
        // v0.8.21-beta: now inline on this same panel rather than a modal
        // Window. The button toggles FaultIsolator on/off; the wizard
        // renders in a new section below the tile strip. Live tile updates
        // continue while the wizard is running so the tech can see the
        // background panel state.
        public ICommand OpenFaultIsolatorCommand          { get; }

        /// <summary>
        /// v0.8.21-beta: inline Fault Isolator VM. Non-null while the
        /// wizard is active; null otherwise. The Camera Connectivity view
        /// renders a Fault Isolator card when this is non-null and binds
        /// directly to the VM.
        /// </summary>
        private FaultIsolatorViewModel _faultIsolator;
        public FaultIsolatorViewModel FaultIsolator
        {
            get => _faultIsolator;
            private set
            {
                if (Set(ref _faultIsolator, value))
                    OnPropertyChanged(nameof(IsFaultIsolatorOpen));
            }
        }
        public bool IsFaultIsolatorOpen => _faultIsolator != null;

        public CameraConnectivityViewModel(
            INetworkAdapterService net,
            IPixellotConfigService cfg,
            IEventViewerService events = null,
            IOcrProbeService ocrProbe = null)
        {
            _net = net;
            _cfg = cfg;
            _events = events;
            _ocrProbe = ocrProbe;

            _statusColor = StatusHelpers.Brush("MutedForegroundBrush");
            _statusBg    = StatusHelpers.Brush("BorderColBrush");

            // v0.8.22-beta: keep the merged Findings + Recommendations card
            // header in lockstep with the row count. ApplyDelta mutates rows
            // in-place + adds/removes the tail, so CollectionChanged fires on
            // every real change. RebuildFindingsHeader is a no-op string set,
            // so this is cheap even on a no-change tick (Set<T> short-circuits
            // when the value is equal).
            Recommendations.CollectionChanged += (_, __) => RebuildFindingsHeader();

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
            // v0.8.6-beta: seed PortsByPhysical in reverse order so the
            // diagram + tile row render correctly even before the first
            // monitor tick.
            for (int i = Ports.Count - 1; i >= 0; i--)
                PortsByPhysical.Add(Ports[i]);

            OpenAdapterSettingsCommand = new RelayCommand(() => SafeStart("ncpa.cpl"));

            // v0.5.2 §5: second outlined button beside "Open Adapter Settings".
            // Launches the Network and Sharing Center via the legacy control
            // panel applet by canonical name.
            OpenNetworkAndSharingCenterCommand = new RelayCommand(() =>
            {
                try
                {
                    var psi = new ProcessStartInfo("control")
                    {
                        Arguments = "/name Microsoft.NetworkAndSharingCenter",
                        UseShellExecute = true,
                    };
                    Process.Start(psi);
                    AddLog("Windows", "Opened Network and Sharing Center", "Info");
                }
                catch (Exception ex)
                {
                    AddLog("Windows", $"Failed to open Network and Sharing Center: {ex.Message}", "Fail");
                    SnapshotStatus = "Could not open Network and Sharing Center.";
                    ScheduleClearSnapshotStatus();
                }
            });

            GoToNetworkCommand = new RelayCommand(() => App.NavigateToTab("Network"));

            OpenCamerasCfgCommand = new RelayCommand(() =>
            {
                // Try the path the service knows about; fall back to the
                // canonical Pixellot install location so the click still does
                // something useful even if the service dir is missing.
                var path = _cfg?.CamerasCfgPath ?? @"C:\Pixellot\Data\configuration\cameras.cfg";
                SafeStart(path);
            });

            // v0.5.5: one-shot per-run report. Camera is live (1 s tick) so
            // there's no automatic per-refresh write — this button captures a
            // snapshot when the tech actually wants to attach the state to a
            // ticket. Rolling AppLogFile is still updated every tick.
            SaveSnapshotCommand = new RelayCommand(() =>
            {
                try
                {
                    var path = _reportWriter.Save("Camera", BuildReportText());
                    if (!string.IsNullOrEmpty(path))
                    {
                        LastReportPath = path;
                        var fileName = System.IO.Path.GetFileName(path);
                        AppLogFile.Instance.WriteLine("Camera", "Info",
                            $"Snapshot saved: {path}");
                        AddLog("Snapshot", $"Saved: {fileName}", "Pass");
                        // v0.6.5: inline status toast — clears after 4 s.
                        SnapshotStatus = $"Snapshot saved: {fileName}";
                        ScheduleClearSnapshotStatus();
                    }
                    else
                    {
                        AddLog("Snapshot", "Failed to save", "Fail");
                        SnapshotStatus = "Snapshot save failed.";
                        ScheduleClearSnapshotStatus();
                    }
                }
                catch { /* never throw from the command path */ }
            });

            // v0.8.0-beta: Fault Isolator entry point. Always enabled so the
            // tech can launch the wizard whether or not the live monitor has
            // flagged a degraded port. The command itself handles the
            // pause / show-modal / resume / report-write lifecycle.
            OpenFaultIsolatorCommand = new RelayCommand(OpenFaultIsolator);

            // 1 s monitor — the prior agent locked this. Auto-start.
            _monitor = new CameraNicMonitor(_net);
            _monitor.Tick += OnMonitorTick;
            _monitor.Start();

            // v0.8.16-beta: secondary 30 s poll for NIC driver events.
            // EventLogReader is expensive (it walks the System log), so
            // we run it on its own slow cadence rather than every monitor
            // tick. Optional - if IEventViewerService isn't wired the
            // tile just doesn't show driver-event counts.
            if (_events != null)
            {
                _eventPollTimer = new System.Windows.Threading.DispatcherTimer
                {
                    Interval = TimeSpan.FromSeconds(30),
                };
                _eventPollTimer.Tick += async (_, __) => await PollNicDriverEventsAsync().ConfigureAwait(true);
                _eventPollTimer.Start();
                // Fire one immediate poll so the tile has data on first paint.
                _ = PollNicDriverEventsAsync();
            }

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
                    // v0.8.13-beta: detection uses the smarter
                    // IsFlappingPattern (committed-transitions >= 3 in 60s
                    // OR noise-flaps >= 8 in 30s) instead of the raw
                    // combined count. False-positive proof against single
                    // yank-replug (2 committed + a few noise events on
                    // plug-in settling). The displayed count below still
                    // uses the combined total so "↯ Flapping ×N/60s"
                    // surfaces everything observed.
                    int flaps = st.FlapCountInWindow(_monitor.FlapWindow, utcNow);
                    bool isFlapping = st.IsFlappingPattern(_monitor.FlapWindow, utcNow);

                    string statusLine; Brush statusBrush; Brush ledBrush;
                    // v0.8.12-beta: status icon kind (Material Design Icon
                    // name) drives the prominent tile-header glyph. Default
                    // to no-link grey; each branch below sets it alongside
                    // statusBrush so colour + shape stay in lockstep.
                    string statusIconKind = "HelpCircleOutline";
                    bool is1G   = snap.LinkSpeedBps >= 1_000_000_000UL;
                    bool is100M = snap.LinkSpeedBps >= 100_000_000UL && snap.LinkSpeedBps < 1_000_000_000UL;

                    string primary; string secondary;
                    string ipShown = "—"; string macShown = "—";

                    if (!snap.IsUp)
                    {
                        // v0.8.6-beta: binary cable state. IsUp is the only
                        // signal that matters. The prior "Cable, no link"
                        // yellow state was triggered by a stale RemoteMac
                        // (ARP entries persist ~30 s after a cable pull) and
                        // was confusing in field testing — a tile would show
                        // "Cable, no link" with a yellow LED on a port the
                        // tech had just unplugged. Drop that branch; treat
                        // IsUp=false as "No cable" regardless of stale ARP.
                        primary = "No cable";
                        secondary = "";
                        statusLine = "No cable";
                        statusBrush = StatusHelpers.Brush("MutedForegroundBrush");
                        ledBrush    = StatusHelpers.Brush("SubtleForegroundBrush");
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
                        //
                        // v0.6.5: when the port's previously-seen role is OCR
                        // / Scoreboard, swap the "Identifying device…"
                        // spinner copy for an explicit "no ARP traffic
                        // expected" label. OCR cameras connect via RTSP-only
                        // and never generate ARP, so the resolver was
                        // permanently stuck waiting for an identification
                        // that will never arrive.
                        bool lastWasOcr =
                            (!string.IsNullOrEmpty(st.LastRemoteLabel)
                             && (st.LastRemoteLabel.IndexOf("OCR", StringComparison.OrdinalIgnoreCase) >= 0
                                 || st.LastRemoteLabel.IndexOf("Scoreboard", StringComparison.OrdinalIgnoreCase) >= 0));

                        if (lastWasOcr)
                        {
                            primary = st.LastRemoteLabel;
                            secondary = "OCR scoreboard (no ARP traffic expected)";
                            ipShown  = !string.IsNullOrEmpty(st.LastRemoteIp)  ? st.LastRemoteIp  : "—";
                            macShown = !string.IsNullOrEmpty(st.LastRemoteMac) ? st.LastRemoteMac : "—";
                        }
                        else if (!string.IsNullOrEmpty(st.LastRemoteLabel))
                        {
                            primary = st.LastRemoteLabel;
                            secondary = !string.IsNullOrEmpty(st.LastRemoteIp) ? st.LastRemoteIp : "";
                            ipShown  = !string.IsNullOrEmpty(st.LastRemoteIp)  ? st.LastRemoteIp  : "—";
                            macShown = !string.IsNullOrEmpty(st.LastRemoteMac) ? st.LastRemoteMac : "—";
                        }
                        else if (is100M && (roles?.Count ?? 0) > 0
                                 && st.LinkUpSince.HasValue
                                 && (utcNow - st.LinkUpSince.Value) >= TimeSpan.FromSeconds(5))
                        {
                            // v0.6.9: link up at 100 Mbps with no ARP yet — on
                            // a Pixellot VPU this is almost certainly the OCR
                            // / Scoreboard camera. Main cameras negotiate 1
                            // Gbps; only the OCR runs at 100 Mbps. Skip the
                            // "Identifying device…" spinner and call it OCR.
                            //
                            // D6 fix: only infer when cameras.cfg has been
                            // loaded with entries — same guard as the
                            // ARP-resolved branch below. Without that guard
                            // a stale-ARP main camera that renegotiated to
                            // 100 Mbps would be silently labeled OCR Green.
                            //
                            // v0.8.9-beta: 5-second grace period guard.
                            // Field tech reported a faulty cable forcing a
                            // Main Camera to negotiate at 100 Mbps - the
                            // tile briefly mis-labeled it as OCR before
                            // ARP resolved. Real OCR cameras never ARP, so
                            // we still want the inference to fire eventually
                            // (otherwise OCRs stay stuck in "Identifying
                            // device..."); we just hold it back until ARP
                            // has had a fair shot first. 5 s comfortably
                            // covers normal ARP resolution (typically 1-3 s
                            // after first traffic).
                            primary   = "OCR / Scoreboard";
                            secondary = "Inferred from 100 Mbps speed";
                            info.IsOcr = true;        // silences degraded-speed warning
                            info.Source = DeviceIdentitySource.PixellotConfig; // IsConfigured is derived from Source; this drives the accent colouring

                            // v0.8.14-beta: OCR cameras don't ARP, so the
                            // tile's IP / MAC rows would stay "—" forever
                            // without help. Look up the configured OCR /
                            // Scoreboard entry from cameras.cfg and use its
                            // IP + MAC as the displayed values. Field tech
                            // ask: "if the tool can see a link, it should
                            // be able to see that data too and populate
                            // that space".
                            string ocrCfgIp = null;
                            if (roles != null)
                            {
                                foreach (var kv in roles)
                                {
                                    if (!string.IsNullOrEmpty(kv.Value) &&
                                        (kv.Value.IndexOf("OCR", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                         kv.Value.IndexOf("Scoreboard", StringComparison.OrdinalIgnoreCase) >= 0))
                                    {
                                        ocrCfgIp = kv.Key;
                                        break;
                                    }
                                }
                            }
                            if (!string.IsNullOrEmpty(ocrCfgIp)) ipShown = ocrCfgIp;

                            string ocrCfgMac = null;
                            if (rolesByMac != null)
                            {
                                foreach (var kv in rolesByMac)
                                {
                                    if (!string.IsNullOrEmpty(kv.Value) &&
                                        (kv.Value.IndexOf("OCR", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                         kv.Value.IndexOf("Scoreboard", StringComparison.OrdinalIgnoreCase) >= 0))
                                    {
                                        ocrCfgMac = kv.Key;
                                        break;
                                    }
                                }
                            }
                            if (!string.IsNullOrEmpty(ocrCfgMac)) macShown = ocrCfgMac;
                        }
                        else
                        {
                            primary   = "Linked";
                            secondary = "Identifying device…";
                        }
                        // Status line + LED:
                        //   1 Gbps         -> green
                        //   100 Mbps + OCR (inferred above) -> green with OCR suffix
                        //   100 Mbps + no OCR signal        -> yellow (degraded)
                        //   anything else  -> yellow
                        if (is1G)
                        {
                            statusLine  = "Linked · 1 Gbps";
                            statusBrush = StatusHelpers.Brush("GreenBrush");
                            ledBrush    = StatusHelpers.Brush("GreenBrush");
                            statusIconKind = "CheckCircle";
                        }
                        else if (is100M && info.IsOcr)
                        {
                            statusLine  = "Linked · 100 Mbps · OCR (inferred)";
                            statusBrush = StatusHelpers.Brush("GreenBrush");
                            ledBrush    = StatusHelpers.Brush("GreenBrush");
                            statusIconKind = "CheckCircle";
                        }
                        else
                        {
                            // v0.8.11-beta: degraded-link branch (no ARP yet,
                            // not 1G, not OCR-inferred). Was rendering green
                            // status text against a yellow LED - inconsistent
                            // and field tech reported it as misleading on a
                            // damaged-pin 10 Mbps fault. Per the new rule:
                            // any non-1G non-OCR-100M link is a fault. Yellow
                            // status text + "(expected 1 Gbps)" suffix so the
                            // tile copy itself says fault.
                            //
                            // v0.8.14-beta: special-case the OCR-inference
                            // grace period. For the first 5 s after a 100 Mbps
                            // link comes up with no ARP, we don't yet know
                            // whether it's OCR (which IS 100 Mbps by design)
                            // or a degraded Main Camera. Falling through to
                            // yellow degraded for those 5 s confused field
                            // techs - a real OCR camera flashed "fault" for
                            // 5 s before correcting to green. New rule:
                            // during the grace window, render a NEUTRAL
                            // "Identifying..." state. After the window,
                            // either OCR inference fires (above) -> green,
                            // or this branch -> yellow as before.
                            bool inOcrGracePeriod = is100M
                                && (roles?.Count ?? 0) > 0
                                && st.LinkUpSince.HasValue
                                && (utcNow - st.LinkUpSince.Value) < TimeSpan.FromSeconds(5);

                            if (inOcrGracePeriod)
                            {
                                statusLine = "Linked · 100 Mbps · Identifying...";
                                statusBrush = StatusHelpers.Brush("MutedForegroundBrush");
                                ledBrush    = StatusHelpers.Brush("MutedForegroundBrush");
                                statusIconKind = "ProgressClock";
                            }
                            else
                            {
                                statusLine = is100M
                                    ? "Linked · 100 Mbps (expected 1 Gbps)"
                                    : "Linked · " + FormatSpeed(snap.LinkSpeedBps) + " (expected 1 Gbps)";
                                statusBrush = StatusHelpers.Brush("YellowBrush");
                                ledBrush    = StatusHelpers.Brush("YellowBrush");
                                statusIconKind = "AlertCircle";
                            }
                        }
                    }
                    else if (is1G)
                    {
                        primary = info.PrimaryLabel; secondary = info.SecondaryLabel;
                        ipShown = snap.RemoteIp; macShown = snap.RemoteMac;
                        statusLine = "Linked · 1 Gbps";
                        statusBrush = StatusHelpers.Brush("GreenBrush");
                        ledBrush    = StatusHelpers.Brush("GreenBrush");
                        statusIconKind = "CheckCircle";
                    }
                    else if (is100M && info.IsOcr)
                    {
                        primary = info.PrimaryLabel; secondary = info.SecondaryLabel;
                        ipShown = snap.RemoteIp; macShown = snap.RemoteMac;
                        statusLine = "Linked · 100 Mbps · OCR (expected)";
                        statusBrush = StatusHelpers.Brush("GreenBrush");
                        ledBrush    = StatusHelpers.Brush("GreenBrush");
                        statusIconKind = "CheckCircle";
                    }
                    else if (is100M
                             && !string.IsNullOrEmpty(snap.RemoteMac)
                             && _confirmedOcrMacs.Contains(snap.RemoteMac))
                    {
                        // v0.8.19-beta: positive CGI probe identified this
                        // MAC as an OCR. Distinct from the OuiVendor
                        // inference branch below - this fires even when
                        // the OUI doesn't match Pixellot (third-party OCR
                        // SKU, or a Pixellot OCR with a non-standard MAC).
                        // The camera itself answered "yes, I'm an OCR" via
                        // the Dynacolor CGI - we trust that over any
                        // heuristic.
                        primary = "OCR / Scoreboard";
                        secondary = "Confirmed via CGI probe";
                        ipShown = snap.RemoteIp; macShown = snap.RemoteMac;
                        statusLine = "Linked · 100 Mbps · OCR (confirmed)";
                        statusBrush = StatusHelpers.Brush("GreenBrush");
                        ledBrush    = StatusHelpers.Brush("GreenBrush");
                        statusIconKind = "CheckCircle";
                        info.IsOcr = true;
                        info.Source = DeviceIdentitySource.PixellotConfig;
                    }
                    else if (is100M && info.Source == DeviceIdentitySource.OuiVendor && (roles?.Count ?? 0) > 0)
                    {
                        // v0.6.9: ARP resolved to a Pixellot-OUI vendor but
                        // no cameras.cfg entry. At 100 Mbps this is almost
                        // certainly the OCR camera (main cameras run at 1
                        // Gbps). Promote the inference rather than rendering
                        // the misleading "Pixellot - Unknown role" yellow
                        // degraded state.
                        //
                        // D6 fix: only infer when cameras.cfg actually has
                        // entries (the IP is in OuiVendor *because* cfg was
                        // loaded and didn't include this IP). If cfg is
                        // empty/missing, the inference is a guess and could
                        // silently re-classify a real main camera that
                        // renegotiated to 100 Mbps as OCR — masking a cable
                        // fault as "Healthy OCR". When cfg is empty we fall
                        // through to the next branch which renders Yellow
                        // "Linked · 100 Mbps (expected 1 Gbps)".
                        primary = "OCR / Scoreboard";
                        secondary = "Inferred from 100 Mbps speed";
                        ipShown = snap.RemoteIp; macShown = snap.RemoteMac;
                        statusLine = "Linked · 100 Mbps · OCR (inferred)";
                        statusBrush = StatusHelpers.Brush("GreenBrush");
                        ledBrush    = StatusHelpers.Brush("GreenBrush");
                        statusIconKind = "CheckCircle";
                        info.IsOcr = true; // so the warning roll-up below doesn't fire
                        info.Source = DeviceIdentitySource.PixellotConfig; // IsConfigured derives from Source — drives the accent colouring
                    }
                    else if (is100M)
                    {
                        primary = info.PrimaryLabel; secondary = info.SecondaryLabel;
                        ipShown = snap.RemoteIp; macShown = snap.RemoteMac;
                        statusLine = "Linked · 100 Mbps (expected 1 Gbps)";
                        statusBrush = StatusHelpers.Brush("YellowBrush");
                        ledBrush    = StatusHelpers.Brush("YellowBrush");
                        statusIconKind = "AlertCircle";
                    }
                    else
                    {
                        // v0.8.11-beta: ARP resolved, link up, but speed is
                        // neither 1G nor 100M (so e.g. 10 Mbps from a damaged
                        // NIC pin). Was rendering AccentBrush (blue) text on
                        // a yellow LED - inconsistent. Any non-1G non-OCR-
                        // 100M link is a fault: yellow text + "(expected
                        // 1 Gbps)" suffix so the tile copy says fault.
                        primary = info.PrimaryLabel; secondary = info.SecondaryLabel;
                        ipShown = snap.RemoteIp; macShown = snap.RemoteMac;
                        statusLine = "Linked · " + FormatSpeed(snap.LinkSpeedBps) + " (expected 1 Gbps)";
                        statusBrush = StatusHelpers.Brush("YellowBrush");
                        ledBrush    = StatusHelpers.Brush("YellowBrush");
                        statusIconKind = "AlertCircle";
                    }

                    if (isFlapping)
                    {
                        // Flap visualisation: solid amber + ↯ glyph in the
                        // status line. We do NOT pulse the LED (UX call).
                        statusLine += $"  ·  ↯ Flapping ×{flaps}/60s";
                        statusBrush = StatusHelpers.Brush("YellowBrush");
                        ledBrush    = StatusHelpers.Brush("YellowBrush");
                        statusIconKind = "AlertCircle";
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
                    // Local MAC is always available from the snapshot; the
                    // Adapter Details dialog uses it to resolve the adapter.
                    port.LocalMac = snap.LocalMac ?? "";
                    // v0.8.16-beta: cache the long adapter description per
                    // MAC for the event-log correlation (events include
                    // the description as the first line of Message).
                    if (!string.IsNullOrEmpty(snap.LocalMac) && !string.IsNullOrEmpty(snap.Description))
                        _descriptionByMac[snap.LocalMac] = snap.Description;
                    // v0.8.0-beta: forward raw snap fields so the Fault
                    // Isolator can read undecorated port state without going
                    // through the OCR-relabelled StatusLine.
                    port.AdapterName  = snap.Name ?? "";
                    port.LinkSpeedBps = snap.LinkSpeedBps;
                    port.IsUp         = snap.IsUp;
                    port.IsOcr        = info?.IsOcr ?? false;
                    port.PrimaryLabel = primary;
                    port.SecondaryLabel = secondary;
                    port.PrimaryColor = info.IsConfigured
                        ? StatusHelpers.Brush(info.IsOcr ? "AccentBrush" : "GreenBrush")
                        : StatusHelpers.Brush("ForegroundBrush");

                    port.StatusLine   = statusLine;
                    port.StatusText   = statusLine; // legacy
                    port.StatusColor  = statusBrush;
                    port.LinkLedBrush = ledBrush;
                    port.StatusIconKind = statusIconKind;
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
                    // Pass the debounced state (st.PreviousIsUp) instead of
                    // the raw snap.IsUp — that way Recent activity entries
                    // only appear for transitions that survived the 2 s
                    // debounce window, not for the I210 NIC's gigabit auto-
                    // negotiation settling noise.
                    AppendHistoryFromTick(port, snap, st.PreviousIsUp ?? snap.IsUp,
                                          errorsRising, isFlapping, flaps);

                    // ---- Severity contributions for the page-level pill ----
                    // v0.6.9: drop the info.IsConfigured guard from the
                    // degraded-speed warning. A non-OCR port at 100 Mbps is
                    // always a real problem regardless of whether
                    // cameras.cfg knows about it — the previous gating
                    // produced a false-"All Clear" on Port 3 of an 82574L
                    // VPU when the port wasn't in cameras.cfg yet. The
                    // OCR-from-speed inference above sets info.IsOcr = true
                    // for Pixellot-OUI ports at 100 Mbps, so OCR cameras
                    // don't trip this.
                    //
                    // v0.8.11-beta: expanded from is100M to "any sub-1G
                    // non-OCR link". Field tech damaged a NIC pin and the
                    // port negotiated at 10 Mbps - the previous is100M-only
                    // condition missed it, producing a false "All Clear"
                    // page-level pill on a clearly faulty port.
                    bool isSubGigDegraded = snap.IsUp
                                            && snap.LinkSpeedBps > 0
                                            && snap.LinkSpeedBps < 1_000_000_000UL
                                            && !info.IsOcr;
                    if (isSubGigDegraded) warnings++;
                    if (errorsRising) warnings++;
                    if (isFlapping)   warnings++;
                    // v0.6.5: only contribute severity for ports the VPU is
                    // actually configured to use. An unused jack going dark
                    // should not turn the page-level pill yellow.
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

                // v0.8.19-beta: schedule positive OCR identification probes
                // when needed. Async, fire-and-forget - results land in
                // ARP for the next tick to pick up via the existing
                // monitor -> resolver pipeline.
                ScheduleOcrProbesIfNeeded(states, roles);

                // v0.8.22-beta: dropdown population lag fix. When the tab
                // opens with the Fault Isolator already active (or the tech
                // opens the wizard before the first monitor poll resolves),
                // the placeholder Ports have empty LocalMac strings and
                // SeedFromPorts skips every row, leaving both dropdowns
                // empty for the first ~500 ms. Re-seed once the Ports
                // collection has real LocalMacs.
                if (FaultIsolator != null
                    && FaultIsolator.SuspectPortChoices.Count == 0
                    && Ports.Any(p => !string.IsNullOrEmpty(p.LocalMac)))
                {
                    var preselect = Ports.FirstOrDefault(p => p.IsDegraded)?.LocalMac;
                    try { FaultIsolator.SeedFromPorts(Ports, preselect); } catch { }
                }
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
                                           bool debouncedIsUp,
                                           bool errorsRising, bool isFlapping, int flaps)
        {
            var key = snap.LocalMac ?? port.Name;

            // -- Link transition (driven by the debounced state, not the
            //    raw snap.IsUp — so micro-toggles during gigabit auto-
            //    negotiation don't pollute the Recent activity feed) --
            _prevUpByMac.TryGetValue(key, out var prevUp);
            if (prevUp != debouncedIsUp)
            {
                if (prevUp.HasValue)
                {
                    if (debouncedIsUp)
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
                _prevUpByMac[key] = debouncedIsUp;
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
            port.StatusIconKind = "HelpCircleOutline";
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

            // v0.8.6-beta: rebuild PortsByPhysical (reverse order). Same
            // instances - just the iteration order differs. Per-port state
            // changes propagate via the PortViewModel's own
            // INotifyPropertyChanged; we only rebuild this collection when
            // Ports' shape changes.
            if (PortsByPhysical.Count != Ports.Count ||
                !ArePhysicalAndLogicalReversed())
            {
                PortsByPhysical.Clear();
                for (int i = Ports.Count - 1; i >= 0; i--)
                    PortsByPhysical.Add(Ports[i]);
            }
        }

        // v0.8.6-beta helper: cheap check that PortsByPhysical is in the
        // expected reverse-of-Ports order before we tear it down. Avoids a
        // Clear+rebuild on every tick.
        private bool ArePhysicalAndLogicalReversed()
        {
            if (PortsByPhysical.Count != Ports.Count) return false;
            for (int i = 0; i < Ports.Count; i++)
            {
                if (!ReferenceEquals(PortsByPhysical[i], Ports[Ports.Count - 1 - i]))
                    return false;
            }
            return true;
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

                // v0.8.16-beta: Intel SmartSpeed downgrade fired in the last
                // hour for this adapter. Event ID 40 from e1iexpress (or
                // sibling drivers) reports that the link couldn't sustain
                // gigabit at the hardware level - stronger evidence than
                // our debounced live polling.
                //
                // v0.8.18-beta: title + body softened. The driver only
                // tells us "the link can't sustain gigabit" - it doesn't
                // know whether the cable, port, or CHU is at fault. So we
                // describe the symptom and direct the tech to Fault
                // Isolator to narrow down.
                //
                // Also demote to Info when the port has no current cable
                // (snap.IsUp == false). Field tech feedback: after moving
                // a faulty cable to a known-good port, the original port's
                // historical events stayed in the log and Pulse kept
                // surfacing a Critical for an empty jack - misleading,
                // since the system was operational without it.
                if (!string.IsNullOrEmpty(snap.LocalMac)
                    && _smartSpeedDowngradeByMac.TryGetValue(snap.LocalMac, out var hadDowngrade)
                    && hadDowngrade)
                {
                    if (snap.IsUp)
                    {
                        rows.Add(NetworkRecommendation.Create(
                            "Critical",
                            $"Link fault detected by driver on Port {portNum}",
                            $"Intel SmartSpeed downgraded the link speed in the last hour (Event 40 in System log). The driver detected the link can't sustain gigabit - the cause could be the cable, the NIC port, or the camera. Run the Fault Isolator from the top bar to narrow it down. See the Event Viewer tab for the full event sequence."));
                    }
                    else
                    {
                        rows.Add(NetworkRecommendation.Create(
                            "Info",
                            $"Historical link fault on Port {portNum}",
                            $"Port {portNum} had link-speed downgrade events in the last hour, but no cable is currently plugged in. If you've moved the cable to another port and the system is operational, no action needed. See the Event Viewer tab for the event sequence."));
                    }
                }

                // Linked-degraded: Main camera at ANY sub-1G speed.
                //
                // v0.8.11-beta: was previously gated on `is100M` only - missed
                // a damaged-pin NIC field-flagged as negotiating 10 Mbps.
                // Expanded to cover the full sub-1G range.
                //
                // v0.8.14-beta: dropped the `info.IsConfigured` gate. Field
                // tech reported the Dashboard saying "All Clear" while the
                // Camera Connectivity tab showed a 10 Mbps damaged-pin port.
                //
                // v0.8.15-beta: now also gated on !IsLikelyOcr. Without this,
                // a port that's correctly identified as OCR via the
                // inference (100 Mbps + cfg loaded + grace passed) gets a
                // false Critical here because BuildRecommendations re-runs
                // Resolve and doesn't know about the local info.IsOcr
                // mutation OnMonitorTick applied. IsLikelyOcr centralizes
                // the same heuristic and both call sites agree.
                bool likelyOcr = IsLikelyOcr(snap, info, st, roles);
                bool isLinkDegraded = snap.IsUp
                                      && snap.LinkSpeedBps > 0
                                      && snap.LinkSpeedBps < 1_000_000_000UL
                                      && !likelyOcr;
                if (isLinkDegraded)
                {
                    string actualSpeed = is100M ? "100 Mbps" : FormatSpeed(snap.LinkSpeedBps);
                    // Use info.PrimaryLabel when we have an identified
                    // device, otherwise reference the port number for
                    // unconfigured ports.
                    string deviceRef = info.IsConfigured && !string.IsNullOrEmpty(info.PrimaryLabel)
                        ? info.PrimaryLabel
                        : $"Port {portNum}";
                    rows.Add(NetworkRecommendation.Create(
                        "Critical",
                        $"Cable or jack fault on Port {portNum}",
                        $"Reseat or replace the cable on Port {portNum}. Expected 1 Gbps for {deviceRef}, currently negotiated {actualSpeed}."));
                }

                // v0.8.15-beta: dropped the legacy "Cabled, no link" Warning
                // row entirely.
                //
                // Field tech feedback: a port with no cable plugged in
                // should NOT generate a Warning. The legacy gate (snap.IsUp
                // == false && snap.RemoteMac != "") relied on stale ARP
                // entries persisting ~30 s after a cable pull to
                // distinguish "cabled but no negotiation" from "no cable
                // at all". The v0.8.6-beta binary cable-state pass already
                // gave up on that distinction at the tile level - keeping
                // it here produced contradictory output (tile said "No
                // cable", Recommendations said "Cabled, no link").
                //
                // The "Configured camera not detected" Warning below still
                // covers the real signal: a port that USED to carry a
                // configured device and now doesn't. For an unconfigured
                // port with no cable, silence is the right answer; the
                // tech can run the Fault Isolator if they expect
                // something there.
                bool portIsConfigured = info.IsConfigured
                    || (!string.IsNullOrEmpty(st.LastRemoteIp)
                        && roles != null && roles.ContainsKey(st.LastRemoteIp));

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
                // v0.8.13-beta: BuildRecommendations also uses the new
                // pattern check (committed >= 3 or noise >= 8) instead of
                // the combined count. Keeps the Warning row honest about
                // a SUSTAINED flap vs a single physical plug cycle.
                int flaps = st.FlapCountInWindow(_monitor.FlapWindow, DateTime.UtcNow);
                if (st.IsFlappingPattern(_monitor.FlapWindow, DateTime.UtcNow))
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

            // Wire the inline action buttons. Only cameras.cfg /
            // missing-config rows get an action button - the cfg file is
            // the actual fix surface for those. Cable / Link / flap / port
            // rows used to get a "Go to Network" or "Start Fault Isolator"
            // button; both have been dropped:
            //   - "Go to Network" was a cross-tab jump that ended up
            //     duplicating diagnostic surfaces.
            //   - "Start Fault Isolator" became redundant when the Fault
            //     Isolator went inline on this same panel (v0.8.21-beta);
            //     the wizard is always one click away in the top bar.
            // Leaving the row to act as pure information; the tech reads
            // the verdict, then either inspects the Fault Isolator card
            // directly above or clicks the top-bar Fault Isolator button
            // to run the swap test.
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
                else
                {
                    r.ActionLabel = null;
                    r.ActionCommand = null;
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

        // v0.8.16-beta: NIC driver source prefixes we look up in the
        // System event log. Intel produces e1iexpress / e1dexpress /
        // e1cexpress for different chipset families (82574L on the
        // 4-port PCIe cards is e1iexpress). Realtek is rt640x64 on
        // x64. NDIS is the vendor-agnostic backstop. Match is a
        // case-insensitive StartsWith over the event Source.
        private static readonly string[] NicEventSources =
        {
            "e1iexpress",
            "e1dexpress",
            "e1cexpress",
            "rt640x64",
            "Microsoft-Windows-NDIS",
        };

        // Information level included alongside Error/Warning so we
        // catch Event 33 "Network link has been established at X
        // Mbps" - it completes the flap cycle the user reported
        // (40 SmartSpeed -> 33 link at 100 Mbps -> 27 disconnected).
        private static readonly string[] NicEventLevels =
        {
            "Error",
            "Warning",
            "Information",
        };

        /// <summary>
        /// v0.8.16-beta: per-port driver-event poll. Queries the System
        /// event log for NIC driver entries in the last hour, matches each
        /// event's Message to a port via the cached long adapter
        /// description, and updates the tile + Recommendations engine
        /// state. Runs on a separate 30 s DispatcherTimer because
        /// EventLogReader is expensive relative to the 500 ms monitor
        /// poll - the trade is acceptable for supplemental signal.
        ///
        /// Surfaces:
        ///   - PortViewModel.RecentDriverEvents (display string on the tile)
        ///   - _eventCountByMac (used by BuildRecommendations)
        ///   - _smartSpeedDowngradeByMac (Event 40 specifically; fires a
        ///     Critical "cable fault confirmed by driver" recommendation)
        /// </summary>
        private async Task PollNicDriverEventsAsync()
        {
            if (_eventPollRunning || _events == null) return;
            _eventPollRunning = true;
            try
            {
                List<WindowsEventEntry> entries;
                try
                {
                    entries = await _events.GetRecentAsync(1, NicEventSources, NicEventLevels)
                                            .ConfigureAwait(true);
                }
                catch
                {
                    return; // never let an event-log read crash the live monitor
                }
                if (entries == null) return;

                // Build a fresh per-MAC count this cycle. Old entries from
                // ports that no longer have events get reset to 0.
                var newCounts   = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                var newDowngrad = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
                var newMostRecent = new Dictionary<string, DateTime>(StringComparer.OrdinalIgnoreCase);

                // Iterate ports + match each event's Message to the port's
                // cached description. Description is the first line of the
                // event message; using IndexOf with OrdinalIgnoreCase keeps
                // this fast on net48 (string.Contains(string, comparison) is
                // .NET Core 2.1+).
                foreach (var kv in _descriptionByMac)
                {
                    var mac  = kv.Key;
                    var desc = kv.Value;
                    if (string.IsNullOrEmpty(desc)) continue;

                    int count = 0;
                    bool sawDowngrade = false;
                    DateTime mostRecent = DateTime.MinValue;

                    foreach (var ev in entries)
                    {
                        if (string.IsNullOrEmpty(ev?.Message)) continue;
                        if (ev.Message.IndexOf(desc, StringComparison.OrdinalIgnoreCase) < 0) continue;
                        count++;
                        if (ev.TimeGenerated > mostRecent) mostRecent = ev.TimeGenerated;
                        // Intel Event 40 = "SmartSpeed has downgraded the
                        // link speed". Driver-level confirmation that the
                        // cable can't sustain gigabit. Strong fault signal.
                        if (ev.EventId == 40) sawDowngrade = true;
                    }

                    newCounts[mac]   = count;
                    newDowngrad[mac] = sawDowngrade;
                    if (count > 0) newMostRecent[mac] = mostRecent;
                }

                // Atomically swap the per-MAC state. Reads happen on the UI
                // thread inside OnMonitorTick / BuildRecommendations so this
                // is safe under the DispatcherTimer model.
                _eventCountByMac.Clear();
                foreach (var kv in newCounts) _eventCountByMac[kv.Key] = kv.Value;
                _smartSpeedDowngradeByMac.Clear();
                foreach (var kv in newDowngrad) _smartSpeedDowngradeByMac[kv.Key] = kv.Value;

                // Push the display string into each port's view-model.
                foreach (var port in Ports)
                {
                    if (string.IsNullOrEmpty(port.LocalMac)) continue;
                    if (!_eventCountByMac.TryGetValue(port.LocalMac, out var count) || count == 0)
                    {
                        port.RecentDriverEvents = "";
                        continue;
                    }
                    // v0.8.18-beta: append "(historical)" when the port has
                    // no current cable. Field tech feedback: after moving a
                    // faulty cable to a known-good port, the original port's
                    // event count stayed at "257 driver events (last hour)"
                    // which read as a current ongoing fault. Now reads as
                    // "257 driver events (historical)" so the tech sees it
                    // as past context, not a fresh problem.
                    string suffix = port.IsUp ? "(last hour)" : "(historical)";
                    port.RecentDriverEvents = count == 1
                        ? $"1 driver event {suffix}"
                        : $"{count} driver events {suffix}";
                }
            }
            finally
            {
                _eventPollRunning = false;
            }
        }

        /// <summary>
        /// v0.8.19-beta: schedule HTTP CGI probes for candidate OCR IPs
        /// when at least one port might be an OCR. Fire-and-forget - the
        /// probes run in background; on success the camera's MAC lands
        /// in <see cref="_confirmedOcrMacs"/> AND Windows' ARP table gets
        /// populated as a side effect (which the next monitor tick picks
        /// up via the existing resolver pipeline).
        ///
        /// "When at least one port might be OCR" = any port currently up
        /// at 100 Mbps with no ARP yet. If every port is either at 1 Gbps
        /// (definitely not OCR), confirmed via ARP, or down, there's
        /// nothing to probe and we skip the whole pass.
        ///
        /// Per-IP rate limit (10 s) keeps us from spamming the camera
        /// CGI on every tick while waiting for ARP to populate.
        /// </summary>
        private void ScheduleOcrProbesIfNeeded(
            List<PortState> states,
            Dictionary<string, string> roles)
        {
            if (_ocrProbe == null) return;

            // Cheap check: do we have any port that might be an OCR right
            // now? If not, no probe scheduling needed this tick.
            bool needsProbe = false;
            foreach (var st in states)
            {
                var snap = st.Snapshot;
                if (snap == null) continue;
                bool is100M = snap.IsUp
                              && snap.LinkSpeedBps >= 100_000_000UL
                              && snap.LinkSpeedBps < 1_000_000_000UL;
                bool noArp = string.IsNullOrEmpty(snap.RemoteMac);
                if (is100M && noArp) { needsProbe = true; break; }
            }
            if (!needsProbe) return;

            // Build the candidate IP list: cameras.cfg OCR/Scoreboard
            // entries first (more likely to match a given venue's actual
            // OCR), then the Pixellot defaults as a fallback for venues
            // where cfg hasn't been populated yet.
            var candidateIps = new List<string>();
            if (roles != null)
            {
                foreach (var kv in roles)
                {
                    if (string.IsNullOrEmpty(kv.Key) || string.IsNullOrEmpty(kv.Value)) continue;
                    if (kv.Value.IndexOf("OCR", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        kv.Value.IndexOf("Scoreboard", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        if (!candidateIps.Contains(kv.Key)) candidateIps.Add(kv.Key);
                    }
                }
            }
            foreach (var def in DefaultOcrIps)
                if (!candidateIps.Contains(def)) candidateIps.Add(def);

            if (candidateIps.Count == 0) return;

            var now = DateTime.UtcNow;
            foreach (var ip in candidateIps)
            {
                if (_lastProbeAtByIp.TryGetValue(ip, out var lastAt)
                    && (now - lastAt) < OcrProbeInterval)
                {
                    continue; // rate-limit
                }
                _lastProbeAtByIp[ip] = now;

                // Fire-and-forget. Captured `ip` is a string, immutable.
                _ = Task.Run(async () =>
                {
                    try
                    {
                        var result = await _ocrProbe.ProbeAsync(ip, OcrProbeTimeout).ConfigureAwait(false);
                        if (result.IsOcr && !string.IsNullOrEmpty(result.Mac))
                        {
                            // Marshal back to the UI thread for the
                            // _confirmedOcrMacs update + the Live Log
                            // entry. Both surfaces are read by the next
                            // OnMonitorTick on the UI thread.
                            var app = Application.Current;
                            if (app != null)
                            {
                                app.Dispatcher.Invoke(() =>
                                {
                                    _confirmedOcrMacs.Add(result.Mac);
                                    AddLog("OcrProbe",
                                        $"Identified OCR at {ip} (MAC {result.Mac}, {(int)result.Elapsed.TotalMilliseconds} ms)",
                                        "Info");
                                });
                            }
                        }
                        // Failures are silent by design - most candidate IPs
                        // won't have an OCR on them, so logging every miss
                        // would flood the Live Log. The successful match
                        // is the signal worth surfacing.
                    }
                    catch { /* never throw from fire-and-forget */ }
                });
            }
        }

        /// <summary>
        /// v0.8.15-beta: centralized "is this port likely an OCR camera"
        /// inference. Two consumers need the same answer:
        ///   - OnMonitorTick (tile rendering): decides whether to paint
        ///     the 100 Mbps state green ("OCR") or yellow (degraded)
        ///   - BuildRecommendations: decides whether to fire the Critical
        ///     "Cable or jack fault" row for a sub-1G link
        ///
        /// Without a shared helper, the two diverged in v0.8.14-beta:
        /// the tile inference mutated a local info.IsOcr=true, but the
        /// recommendations engine re-ran Resolve and got info.IsOcr=false,
        /// firing a false Critical on every inferred-OCR port.
        ///
        /// Rules: any one of these makes the port "likely OCR":
        ///   1. info.IsOcr is already set (resolver matched cfg/role).
        ///   2. Link up at 100 Mbps, no ARP yet, cameras.cfg loaded, AND
        ///      the link has been up for at least 5 s (post-grace).
        ///   3. ARP resolved to a Pixellot OUI vendor (no cfg match)
        ///      AND 100 Mbps + cfg loaded.
        /// </summary>
        private bool IsLikelyOcr(
            CameraNicSnapshot snap,
            RemoteDeviceInfo info,
            PortState st,
            Dictionary<string, string> roles)
        {
            // v0.8.19-beta: positive probe wins. The Dynacolor CGI probe
            // got a parseable MAC back from this IP - the camera told us
            // it's an OCR. No need to consult speed / cfg / grace period
            // when we have a positive ID. Also handles the edge case
            // where an OCR has a non-Pixellot MAC (the OuiVendor branch
            // below would miss it).
            if (snap != null
                && !string.IsNullOrEmpty(snap.RemoteMac)
                && _confirmedOcrMacs.Contains(snap.RemoteMac))
            {
                return true;
            }

            if (info != null && info.IsOcr) return true;

            bool is100M = snap != null
                          && snap.IsUp
                          && snap.LinkSpeedBps >= 100_000_000UL
                          && snap.LinkSpeedBps < 1_000_000_000UL;
            if (!is100M) return false;

            bool cfgLoaded = (roles?.Count ?? 0) > 0;
            if (!cfgLoaded) return false;

            // Branch A: no ARP, link up, past 5 s grace
            bool noArp = string.IsNullOrEmpty(snap.RemoteMac);
            bool gracePassed = st != null
                               && st.LinkUpSince.HasValue
                               && (DateTime.UtcNow - st.LinkUpSince.Value) >= TimeSpan.FromSeconds(5);
            if (noArp && gracePassed) return true;

            // Branch B: ARP resolved to Pixellot OUI but no cfg entry
            if (info != null && info.Source == DeviceIdentitySource.OuiVendor) return true;

            return false;
        }

        private void UpdateSpeedBaseline(CameraNicSnapshot snap)
        {
            if (string.IsNullOrEmpty(snap.LocalMac)) return;
            // Only update the baseline when we have a credible speed reading
            // — a transient 0 from a polling glitch must not erase a valid
            // 1 Gbps history.
            if (snap.LinkSpeedBps > 0)
            {
                _prevSpeedByMac[snap.LocalMac] = snap.LinkSpeedBps;
                return;
            }
            // D8 fix (extended in v0.8.0-beta after the Fault Isolator
            // review): a confirmed physical disconnect (IsUp=false, debounced
            // by the monitor) should clear the speed baseline regardless of
            // whether ARP still has a cached RemoteMac. The original D8 fix
            // only cleared on the no-RemoteMac branch (cable physically out)
            // and missed the "cable plugged in but camera powered off" case
            // — that left a stale 1 Gbps baseline cached, so when an OCR
            // camera at 100 Mbps later attached to the same port,
            // DidSpeedRegress fired a false "Live cable failure" Critical.
            // The IsUp flag is already debounced by CameraNicMonitor's
            // TransitionDebounce window, so it protects against transient
            // polling glitches without needing the RemoteMac gate.
            if (!snap.IsUp)
            {
                _prevSpeedByMac.Remove(snap.LocalMac);
            }
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
                // v0.6.9: pill text used to assert "at 1 Gbps" unconditionally
                // — wrong on a VPU with an OCR camera at 100 Mbps in the mix.
                // Stay accurate without overstating the speed claim.
                StatusLabel = linked == 1
                    ? "All Clear (1 port linked)"
                    : $"All Clear ({linked} ports linked)";
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
            // v0.8.6-beta: when there's no link, return empty. The previous
            // "Last: <device>, X min ago" hint was misleading once cable
            // state went binary — a tile showing "No cable" alongside
            // "Last: 169.254.16.50, just now" reads as ambiguous activity.
            // Field tech feedback: if there's a link, show it. If not, do
            // not show anything.
            return "";
        }

        private void SafeStart(string target)
        {
            try
            {
                var psi = new ProcessStartInfo(target) { UseShellExecute = true };
                Process.Start(psi);
                AddLog("Windows", $"Opened: {target}", "Info");
            }
            catch (Exception ex)
            {
                AddLog("Windows", $"Failed to open {target}: {ex.Message}", "Fail");
                SnapshotStatus = $"Could not open {target}.";
                ScheduleClearSnapshotStatus();
            }
        }

        private void AddLog(string label, string result, string level) => Logger.Add(label, result, level);

        /// <summary>
        /// Compose the Camera Connectivity panel's per-run snapshot body.
        /// Camera doesn't auto-write per tick — this is invoked by the
        /// "Save Snapshot" top-bar button (v0.5.5 option (a)). Captures the
        /// 4 port tiles' state + cameras.cfg / OUI matches + Live Log tail.
        /// </summary>
        public string BuildReportText()
        {
            var sb = new System.Text.StringBuilder();

            sb.AppendLine($"== NIC ==");
            sb.AppendLine($"  {NicCaption}");
            sb.AppendLine($"  Status:        {StatusLabel}");
            if (!string.IsNullOrEmpty(_cfg?.CamerasCfgPath))
                sb.AppendLine($"  cameras.cfg:   {_cfg.CamerasCfgPath}");

            sb.AppendLine();
            sb.AppendLine("== Ports ==");
            foreach (var p in Ports)
            {
                sb.AppendLine($"  {p.Name}  [{p.StatusText}]  {p.StatusLine}");
                sb.AppendLine($"      Primary:   {p.PrimaryLabel}");
                if (!string.IsNullOrEmpty(p.SecondaryLabel))
                    sb.AppendLine($"      Secondary: {p.SecondaryLabel}");
                if (!string.IsNullOrEmpty(p.Ip))     sb.AppendLine($"      Remote IP: {p.Ip}");
                if (!string.IsNullOrEmpty(p.Mac))    sb.AppendLine($"      Remote MAC:{p.Mac}");
                if (!string.IsNullOrEmpty(p.LocalMac)) sb.AppendLine($"      Local MAC: {p.LocalMac}");
                if (!string.IsNullOrEmpty(p.Speed))  sb.AppendLine($"      Speed:     {p.Speed}");
                if (!string.IsNullOrEmpty(p.Device)) sb.AppendLine($"      Device:    {p.Device}");
                if (!string.IsNullOrEmpty(p.Uptime)) sb.AppendLine($"      Uptime:    {p.Uptime}");
                if (!string.IsNullOrEmpty(p.ErrorsText) && p.ErrorsText != "0")
                    sb.AppendLine($"      Errors:    {p.ErrorsText}");
            }

            if (Findings.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== Findings ==");
                foreach (var f in Findings)
                    sb.AppendLine($"  [{f.Severity}] {f.Title}\n      -> {f.Recommendation}");
            }

            if (Recommendations.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("== Recommendations ==");
                foreach (var r in Recommendations)
                    sb.AppendLine($"  [{r.Severity}] {r.Title}\n      -> {r.Body}");
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

        // -------------------------------------------------------------------
        // Adapter Details (v0.5.2 §6)
        // -------------------------------------------------------------------
        /// <summary>
        /// Called from the tile's MouseLeftButtonUp handler. Looks up the
        /// adapter by the port's local MAC, builds an
        /// <see cref="AdapterDetailsViewModel"/> with the live remote info
        /// + recent activity, and shows the modal Adapter Details dialog.
        /// Wrapped in try/catch — a dialog construction failure must never
        /// kill the monitor or the page.
        /// </summary>
        public void OpenAdapterDetails(PortViewModel port)
        {
            if (port == null) return;
            try
            {
                // Resolve the adapter by its *local* MAC. The remote MAC
                // shown on the tile is the camera at the other end of the
                // cable — not the NIC we want to introspect.
                var details = _net?.GetAdapterDetails(port.LocalMac);
                if (details == null)
                {
                    // Fall back to a mostly-empty POCO so the dialog still
                    // opens — we render "—" everywhere we don't have data.
                    details = new AdapterDetails { LocalMac = port.LocalMac ?? "—" };
                }

                // Pull remote info off the tile so the dialog doesn't need
                // to re-walk ARP. Vendor + role come from the helpers.
                if (!string.IsNullOrEmpty(port.Ip) && port.Ip != "—")
                    details.RemoteIp = port.Ip;
                if (!string.IsNullOrEmpty(port.Mac) && port.Mac != "—")
                {
                    details.RemoteMac    = port.Mac;
                    details.RemoteVendor = MacOuiTable.LookupVendor(port.Mac);
                }
                try
                {
                    var roles      = SafeGetRoles();
                    var rolesByMac = SafeGetRolesByMac();
                    var info = RemoteDeviceResolver.Resolve(details.RemoteMac, details.RemoteIp, roles, rolesByMac);
                    if (info != null && info.IsConfigured)
                        details.RemoteRole = info.PrimaryLabel;
                }
                catch { }

                var dialogVm = new AdapterDetailsViewModel(details, port);
                var dialog = new Views.AdapterDetailsDialog(dialogVm);
                // Owner = the active main window so the dialog centers + is
                // modal to the right shell. Application.Current.MainWindow
                // is safe in net48 / WPF; null-check tolerates design-time.
                if (Application.Current?.MainWindow != null
                    && !ReferenceEquals(Application.Current.MainWindow, dialog))
                {
                    dialog.Owner = Application.Current.MainWindow;
                }
                dialog.ShowDialog();
            }
            catch (Exception ex)
            {
                AddLog("AdapterDetails", $"Failed to open adapter details: {ex.Message}", "Warn");
            }
        }

        // ------------------------------------------------------------------
        // v0.8.0-beta: Fault Isolator wizard entry point.
        //
        // Lifecycle (matches FAULT_ISOLATOR_PORT_PLAN.md):
        //   1. Pause the 1Hz live monitor so its 2-s transition debounce +
        //      flap detection + DidSpeedRegress don't fight the wizard's own
        //      per-port poll loop.
        //   2. Seed the dialog VM from the live PortViewModel list. If a
        //      port is already degraded (>= 100 M, < 1 G, IsUp), pre-select it.
        //   3. Show the dialog modal to MainWindow. ShowDialog() blocks here
        //      until the user dismisses (Cancel / Close) the wizard.
        //   4. Resume the monitor.
        //   5. If the wizard concluded with a verdict, fire the existing
        //      SaveSnapshotCommand so the parent panel state is captured
        //      alongside the wizard's own report (written below).
        //   6. Always write the wizard's run as its own report file
        //      (`<host>-FaultIsolator-yyyyMMdd-HHmmss.txt`) so the
        //      verdict + phase history land in the Reports directory even
        //      if the tech bails before a conclusion. Mirrors the legacy
        //      tool's per-run report behaviour.
        // ------------------------------------------------------------------
        // v0.8.21-beta: inline Fault Isolator. The button toggles - first
        // click opens (creates the VM, binds it to FaultIsolator); second
        // click (or the wizard's own Cancel / Concluded -> Run Full
        // Diagnostic) closes (writes the report, fires SaveSnapshot if
        // there's a verdict, clears FaultIsolator).
        //
        // The live CameraNicMonitor keeps running throughout - no more
        // empty tile strip while the wizard is open. The
        // v0.8.13-beta false-positive-proof flap detection absorbs the
        // transitions a tech generates by physically moving cables during
        // the swap test (2 committed transitions per yank-replug, well
        // under the >=3-in-60s threshold).
        private void OpenFaultIsolator()
        {
            try
            {
                // Toggle: clicking when already open closes the wizard
                // (treats it like a Cancel). Lets the same top-bar button
                // serve as the open/close affordance.
                if (FaultIsolator != null)
                {
                    CloseFaultIsolator(); // user-initiated close = no verdict
                    return;
                }

                var preselect = Ports.FirstOrDefault(p => p.IsDegraded)?.LocalMac;

                var vm = new FaultIsolatorViewModel(
                    _net,
                    onConcluded: _ => { /* SaveSnapshot fires in CloseFaultIsolator after the wizard signals close */ },
                    requestRunFullDiagnostic: () =>
                    {
                        // Concluded-phase exit action: close the wizard so
                        // the tech lands back on the live panel.
                    });
                vm.SeedFromPorts(Ports, preselect);
                vm.RequestClose += CloseFaultIsolator;

                AddLog("FaultIsolator",
                    preselect != null
                        ? $"Opened — pre-selected degraded port {preselect}."
                        : "Opened.",
                    "Info");

                FaultIsolator = vm;
            }
            catch (Exception ex)
            {
                AddLog("FaultIsolator", $"Failed to open wizard: {ex.Message}", "Warn");
                try { AppLogFile.Instance.WriteLine("FaultIsolator", "Warn",
                    $"Open-wizard failure:\n{ex}"); } catch { }
            }
        }

        /// <summary>
        /// Tears down the inline Fault Isolator. Captures the conclusion
        /// before clearing, fires SaveSnapshotCommand on a verdict so the
        /// live panel state is bundled with the wizard's own report, and
        /// always writes the per-run report regardless of how the user
        /// exited. Same lifecycle as the legacy modal path - just driven
        /// by the wizard's RequestClose event instead of dialog.ShowDialog
        /// returning.
        /// </summary>
        private void CloseFaultIsolator()
        {
            var vm = FaultIsolator;
            if (vm == null) return;
            try { vm.RequestClose -= CloseFaultIsolator; } catch { }

            bool concluded = vm.Conclusion != FaultConclusion.None;
            string reportText;
            try { reportText = vm.BuildReportText(); }
            catch { reportText = ""; }

            // Drop the binding first so the inline card collapses
            // immediately - users get visual feedback before the
            // SaveSnapshot side effects complete.
            FaultIsolator = null;

            if (concluded)
            {
                AddLog("FaultIsolator",
                    $"Conclusion: {vm.Conclusion}. Capturing snapshot.",
                    "Info");
                try { SaveSnapshotCommand?.Execute(null); } catch { }
            }
            else
            {
                AddLog("FaultIsolator", "Closed without a verdict.", "Info");
            }

            if (!string.IsNullOrEmpty(reportText))
            {
                try
                {
                    var path = _reportWriter.Save("FaultIsolator", reportText);
                    if (!string.IsNullOrEmpty(path))
                    {
                        var fileName = System.IO.Path.GetFileName(path);
                        AppLogFile.Instance.WriteLine("FaultIsolator", "Info",
                            $"Wizard report saved: {path}");
                        AddLog("FaultIsolator", $"Report saved: {fileName}", "Pass");
                        SnapshotStatus = $"Fault Isolator report saved: {fileName}";
                        ScheduleClearSnapshotStatus();
                    }
                }
                catch (Exception ex)
                {
                    AddLog("FaultIsolator", $"Failed to save report: {ex.Message}", "Warn");
                }
            }
        }

        // v0.6.5: mirror of SystemOverviewViewModel.ScheduleClearStatus.
        // Clears the SnapshotStatus toast 4 s after Save Snapshot is clicked.
        // Kept panel-local for now — a shared helper could fold both in once
        // a third caller appears.
        private void ScheduleClearSnapshotStatus()
        {
            var app = Application.Current;
            if (app == null) return;
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
            timer.Tick += (s, e) =>
            {
                SnapshotStatus = "";
                timer.Stop();
            };
            timer.Start();
        }
    }
}
