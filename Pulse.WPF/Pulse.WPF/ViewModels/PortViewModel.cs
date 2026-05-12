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

        // ---- Status line (the speed / link / flap state) ----
        // StatusLine is the new tile binding; StatusText kept for legacy.
        private string _statusLine = "No cable";
        public string StatusLine { get => _statusLine; set => Set(ref _statusLine, value); }

        private string _statusText = "No cable";
        public string StatusText { get => _statusText; set => Set(ref _statusText, value); }

        private Brush _statusColor;
        public Brush StatusColor { get => _statusColor; set => Set(ref _statusColor, value); }

        // ---- Identity rows (mono, copyable in the tile) ----
        private string _ip = "";
        public string Ip { get => _ip; set => Set(ref _ip, value); }

        private string _mac = "";
        public string Mac { get => _mac; set => Set(ref _mac, value); }

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
