using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
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

        // v0.8.0-beta: launches the Fault Isolator modal wizard (4-phase
        // swap test). Always visible regardless of Recommendation state so
        // the tech can run it on demand without waiting for the live
        // monitor to confirm a degraded port. The command pauses the
        // monitor for the duration of the wizard (see OpenFaultIsolator).
        public ICommand OpenFaultIsolatorCommand          { get; }

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
                        else if (is100M && (roles?.Count ?? 0) > 0)
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
                            primary   = "OCR / Scoreboard";
                            secondary = "Inferred from 100 Mbps speed";
                            info.IsOcr = true;        // silences degraded-speed warning
                            info.Source = DeviceIdentitySource.PixellotConfig; // IsConfigured is derived from Source; this drives the accent colouring
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
                        }
                        else if (is100M && info.IsOcr)
                        {
                            statusLine  = "Linked · 100 Mbps · OCR (inferred)";
                            statusBrush = StatusHelpers.Brush("GreenBrush");
                            ledBrush    = StatusHelpers.Brush("GreenBrush");
                        }
                        else
                        {
                            statusLine  = is100M ? "Linked · 100 Mbps"
                                                 : "Linked · " + FormatSpeed(snap.LinkSpeedBps);
                            statusBrush = StatusHelpers.Brush("GreenBrush");
                            ledBrush    = StatusHelpers.Brush("YellowBrush");
                        }
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
                    // Local MAC is always available from the snapshot; the
                    // Adapter Details dialog uses it to resolve the adapter.
                    port.LocalMac = snap.LocalMac ?? "";
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
                    if (snap.IsUp && is100M && !info.IsOcr) warnings++;
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
                //
                // v0.6.5: also gate on the port having a *configured* role.
                // A dark port whose cameras.cfg entry doesn't exist is not a
                // problem — only flag jacks the VPU expects something on. The
                // role lookup uses st.LastRemoteIp (captured on a prior tick
                // when the device was online) so the gate survives a current
                // ARP loss. Same signal the no-cable-on-configured-port row
                // below uses.
                bool portIsConfigured = info.IsConfigured
                    || (!string.IsNullOrEmpty(st.LastRemoteIp)
                        && roles != null && roles.ContainsKey(st.LastRemoteIp));

                if (!snap.IsUp
                    && !string.IsNullOrEmpty(snap.RemoteMac)
                    && portIsConfigured
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
        private void OpenFaultIsolator()
        {
            try
            {
                _monitor?.Pause();

                var preselect = Ports.FirstOrDefault(p => p.IsDegraded)?.LocalMac;

                var dialogVm = new FaultIsolatorViewModel(
                    _net,
                    onConcluded: _ => { /* SaveSnapshot fires below after the dialog returns */ },
                    requestRunFullDiagnostic: () =>
                    {
                        // Exit action on the Concluded screen — just close
                        // the modal so the tech is back on the live panel.
                        // (No "run all panels" command exists yet; once it
                        // does, swap this for a panel-VM invocation.)
                    });
                dialogVm.SeedFromPorts(Ports, preselect);

                var dialog = new Views.FaultIsolatorDialog(dialogVm);
                if (Application.Current?.MainWindow != null
                    && !ReferenceEquals(Application.Current.MainWindow, dialog))
                {
                    dialog.Owner = Application.Current.MainWindow;
                }

                AddLog("FaultIsolator",
                    preselect != null
                        ? $"Opening wizard — pre-selected degraded port {preselect}."
                        : "Opening wizard.",
                    "Info");

                dialog.ShowDialog();

                // ---- After the modal closes ----
                _monitor?.Resume();

                bool concluded = dialogVm.Conclusion != FaultConclusion.None;
                if (concluded)
                {
                    AddLog("FaultIsolator",
                        $"Conclusion: {dialogVm.Conclusion}. Capturing snapshot.",
                        "Info");
                    // Fire the existing SaveSnapshot command so the live
                    // panel state is bundled alongside the wizard report.
                    try { SaveSnapshotCommand?.Execute(null); } catch { }
                }
                else
                {
                    AddLog("FaultIsolator", "Wizard closed without a verdict.", "Info");
                }

                // Always write the wizard's own per-run report — verdict or
                // not — so the tech has the phase history to attach to a
                // ticket regardless of how they exited.
                try
                {
                    var path = _reportWriter.Save("FaultIsolator", dialogVm.BuildReportText());
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
            catch (Exception ex)
            {
                // Defensive: any failure must still resume the monitor or the
                // live panel will sit frozen.
                try { _monitor?.Resume(); } catch { }
                AddLog("FaultIsolator", $"Failed to open wizard: {ex.Message}", "Warn");
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
