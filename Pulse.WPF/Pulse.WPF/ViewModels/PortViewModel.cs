using System;
using System.Collections.ObjectModel;
using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// One row in <see cref="PortViewModel.History"/> — a single transition
    /// observed on the port (link up, link down, flap detected, errors rose).
    /// Cap is enforced by <see cref="CameraConnectivityViewModel"/> so the
    /// buffer reflects roughly the last 60 minutes of activity per port.
    /// </summary>
    public class PortHistoryEntry
    {
        public DateTime Timestamp { get; set; } = DateTime.Now;
        public string   State     { get; set; } = "";   // "Link up", "Link down", "Flap", "Errors"
        public string   Note      { get; set; } = "";
        public Brush    StateColor { get; set; }

        // Pre-formatted "HH:MM:SS" for the expander row — saves a converter.
        public string TimestampLabel => Timestamp.ToString("HH:mm:ss");
    }

    /// <summary>
    /// One port tile binding model in the Camera Connectivity diagram strip.
    /// All UI updates flow through Set() so XAML auto-refreshes when a value
    /// changes — no manual Invalidate / Refresh calls anywhere.
    /// </summary>
    public class PortViewModel : ObservableObject
    {
        public PortViewModel()
        {
            // Pre-seed the brushes so bindings (Foreground / Fill on the
            // tile, the LED, etc.) have a real Brush even before the first
            // monitor tick. Without this, null Brush bindings render
            // invisible text on the just-loaded tab. The CameraConnectivity
            // VM overwrites these with the proper severity brush on every
            // tick.
            _primaryColor = StatusHelpers.Brush("ForegroundBrush");
            _statusColor  = StatusHelpers.Brush("MutedForegroundBrush");
            _errorColor   = StatusHelpers.Brush("MutedForegroundBrush");
            _linkLedBrush = StatusHelpers.Brush("SubtleForegroundBrush");
        }

        // ---- Identity ----
        private string _name = "Port 1";
        public string Name { get => _name; set => Set(ref _name, value); }

        // ---- Primary / secondary device labels ----
        // Primary = "Main Camera 1" | "Axis Communications" | "Unknown device" | "No cable"
        // Secondary = "Pixellot - OUI 00-30-6C" or "" when there's nothing extra to say
        private string _primaryLabel = "No cable";
        public string PrimaryLabel { get => _primaryLabel; set => Set(ref _primaryLabel, value); }

        private string _secondaryLabel = "";
        public string SecondaryLabel { get => _secondaryLabel; set => Set(ref _secondaryLabel, value); }

        private Brush _primaryColor;
        public Brush PrimaryColor { get => _primaryColor; set => Set(ref _primaryColor, value); }

        // ---- Status icon kind (v0.8.12-beta) ----
        // Material Design Icon name driving the prominent at-a-glance
        // status glyph in the tile header. Set by the host VM alongside
        // StatusColor in OnMonitorTick. Three values map to three states:
        //   * "CheckCircle"        — good (1 Gbps or OCR-100 Mbps expected)
        //   * "AlertCircle"        — degraded / fault / flapping / errors
        //   * "HelpCircleOutline"  — no link / no cable
        // The icon's Foreground binds to StatusColor so colour and shape
        // stay in lockstep. Field tech ask: a clear glyph is more
        // scannable than a small coloured dot.
        private string _statusIconKind = "HelpCircleOutline";
        public string StatusIconKind { get => _statusIconKind; set => Set(ref _statusIconKind, value); }

        // ---- Recent driver events from System log (v0.8.16-beta) ----
        // Pre-formatted line like "3 driver events in last hour" when the
        // Intel / Realtek / NDIS driver has logged link-state events for
        // this port's adapter description recently. Empty string suppresses
        // the line in the tile. Updated by CameraConnectivityViewModel on a
        // separate 30 s timer (event-log queries are expensive relative to
        // the 500 ms monitor poll cadence).
        private string _recentDriverEvents = "";
        public string RecentDriverEvents { get => _recentDriverEvents; set => Set(ref _recentDriverEvents, value); }

        // ---- Status line (the speed / link / flap state) ----
        // StatusLine is the new tile binding; StatusText kept for legacy.
        private string _statusLine = "No cable";
        public string StatusLine { get => _statusLine; set => Set(ref _statusLine, value); }

        private string _statusText = "No cable";
        public string StatusText { get => _statusText; set => Set(ref _statusText, value); }

        private Brush _statusColor;
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }

        // ---- Identity rows (mono, copyable in the tile) ----
        // Ip / Mac are the *remote* values shown on the tile when linked.
        // LocalMac is the adapter's own MAC — needed by the Adapter Details
        // dialog (v0.5.2 §6) to look the NetworkInterface back up.
        private string _ip = "";
        public string Ip { get => _ip; set => Set(ref _ip, value); }

        private string _mac = "";
        public string Mac { get => _mac; set => Set(ref _mac, value); }

        private string _localMac = "";
        public string LocalMac { get => _localMac; set => Set(ref _localMac, value); }

        // v0.8.0-beta — added for the Fault Isolator wizard's port-selection
        // logic. AdapterName mirrors the Windows adapter name from the live
        // snapshot (e.g. "Ethernet 3") so the wizard can populate dropdowns
        // with a stable display label; LocalMac stays the keying primitive.
        // LinkSpeedBps + IsUp + IsOcr give the wizard a raw signal for
        // "first degraded port" pre-selection, bypassing the StatusLine
        // label which the OCR-from-speed inference re-paints Green.
        private string _adapterName = "";
        public string AdapterName { get => _adapterName; set => Set(ref _adapterName, value); }

        private ulong _linkSpeedBps;
        public ulong LinkSpeedBps { get => _linkSpeedBps; set => Set(ref _linkSpeedBps, value); }

        private bool _isUp;
        public bool IsUp { get => _isUp; set => Set(ref _isUp, value); }

        private bool _isOcr;
        public bool IsOcr { get => _isOcr; set => Set(ref _isOcr, value); }

        // v0.8.25-beta: per-port LocalIp + IsDhcpEnabled forwarded from
        // CameraNicSnapshot so the recommendations engine can assert the
        // Pixellot deployment convention (static IP, Port N -> .10(N-1)
        // NIC IP / .50+(N-1) CHU IP). Not bound by the tile XAML - these
        // are diagnostic-only fields read by BuildRecommendations.
        private string _localIp = "";
        public string LocalIp { get => _localIp; set => Set(ref _localIp, value); }

        private bool _isDhcpEnabled;
        public bool IsDhcpEnabled { get => _isDhcpEnabled; set => Set(ref _isDhcpEnabled, value); }

        /// <summary>
        /// Raw "this port is below gigabit while it's actually carrying a
        /// link" signal — bypasses the OCR-from-speed inference. Used by
        /// the Fault Isolator's entry-button pre-selection.
        /// </summary>
        public bool IsDegraded => IsUp && LinkSpeedBps > 0 && LinkSpeedBps < 1_000_000_000UL;

        // ---- Errors row ----
        // ErrorLine is the new tile binding (e.g. "0 errors" / "12 errors ↑").
        // ErrorColor flips to YellowBrush when errors are rising.
        private string _errorLine = "0 errors";
        public string ErrorLine { get => _errorLine; set => Set(ref _errorLine, value); }

        private Brush _errorColor;
        public Brush ErrorColor { get => _errorColor; set => Set(ref _errorColor, value); }

        // Legacy aliases (kept so old bindings don't break).
        private string _errorsText = "0 errors";
        public string ErrorsText { get => _errorsText; set => Set(ref _errorsText, value); }

        private Brush _errorsColor;
        public Brush ErrorsColor { get => _errorsColor; set => Set(ref _errorsColor, value); }

        // ---- "Linked HH:MM:SS" / "Last: <device>, N min ago" ----
        // DurationText is the displayed value, populated every tick by the VM.
        private string _durationText = "";
        public string DurationText { get => _durationText; set => Set(ref _durationText, value); }

        // ---- Total uptime since first-seen-up ----
        // Moved here from the Hardware panel (v0.5.0). DurationText resets
        // on every link flap; Uptime is "how long this port has been up
        // *continuously*" which, today, is exactly the same value since
        // CameraNicMonitor doesn't preserve LinkUpSince across flaps. When a
        // future revision starts tracking a first-seen-up timestamp this
        // surface stays — only the VM source needs to change.
        private string _uptime = "";
        public string Uptime { get => _uptime; set => Set(ref _uptime, value); }

        // ---- Last-seen hint (kept for back-compat; new tile uses DurationText) ----
        private string _lastSeenText = "";
        public string LastSeenText { get => _lastSeenText; set => Set(ref _lastSeenText, value); }

        // ---- Per-port history (60-minute rolling buffer) ----
        // Capped by the VM's tick handler.
        public ObservableCollection<PortHistoryEntry> History { get; } = new ObservableCollection<PortHistoryEntry>();

        // ---- Legacy fields kept so existing bindings still resolve. ----
        private string _device = "—";
        public string Device { get => _device; set => Set(ref _device, value); }

        private Brush _deviceColor = Brushes.Gray;
        public Brush DeviceColor { get => _deviceColor; set => Set(ref _deviceColor, value); }

        private string _speed = "—";
        public string Speed { get => _speed; set => Set(ref _speed, value); }

        private string _errors = "—";
        public string Errors { get => _errors; set => Set(ref _errors, value); }

        // Pulsing flag — kept so any future "running" animation can re-bind to it.
        // Per the round-2 UX call we explicitly do NOT pulse the LED on flap
        // (it was distracting); flap state surfaces via the ↯ glyph in
        // StatusLine instead. The property stays here so a future revision
        // can wire pulsing without a model change.
        private bool _isPulsing;
        public bool IsPulsing { get => _isPulsing; set => Set(ref _isPulsing, value); }

        // ---- LED brush for the NIC card diagram jacks ----
        // Computed by CameraConnectivityViewModel in the same pass that
        // composes StatusLine, so the diagram dot and the tile chip are
        // always in sync (a green LED never co-exists with a yellow status
        // line, etc.).
        //   • Linked at 1 Gbps                         -> GreenBrush
        //   • Linked at 100 Mbps for OCR/Scoreboard    -> GreenBrush
        //   • Linked-degraded / cabled-no-link / flap  -> YellowBrush
        //   • Unplugged                                -> SubtleForegroundBrush
        private Brush _linkLedBrush;
        public Brush LinkLedBrush { get => _linkLedBrush; set => Set(ref _linkLedBrush, value); }

        // Legacy "stale" flag — v0.5.2 retired the stale-window dimming per
        // field-tech feedback (binary state only: linked / no cable / cabled-
        // no-link). Property retained so any external bindings don't break;
        // the VM now always writes false.
        private bool _isStale;
        public bool IsStale { get => _isStale; set => Set(ref _isStale, value); }

        private double _tileOpacity = 1.0;
        public double TileOpacity { get => _tileOpacity; set => Set(ref _tileOpacity, value); }
    }
}
