using System;
using System.Collections.Generic;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Sport-aware view model for the redesigned Live Scoreboard card.
    ///
    /// Phase A of the v0.7 redesign — backend only, no visible UI change.
    /// This VM exists alongside the existing
    /// <see cref="ScoreConnectViewModel.LiveScoreData"/> so the panel can
    /// adopt it incrementally in Phase B (per-sport <c>DataTemplate</c>s).
    ///
    /// Responsibilities:
    ///   * Resolve the active sport via <see cref="SportDetector"/>
    ///     (configuration name + SBCODE lookup + live-frame inspection).
    ///   * Maintain a typed state object for the active sport
    ///     (<see cref="BasketballState"/> / <see cref="FootballState"/> /
    ///     <see cref="BaseballState"/> / <see cref="SoccerState"/> /
    ///     <see cref="HockeyState"/> / <see cref="VolleyballState"/> /
    ///     <see cref="GenericScoreboardState"/>) and apply incoming
    ///     Sportzcast frames into it via <see cref="SportzcastFrameMapper"/>.
    ///   * Track liveness — IsLive (currently receiving frames) and
    ///     IsStale (last frame &gt; staleness threshold). When the feed
    ///     disconnects mid-game the state is *kept* (per the v0.7
    ///     plan's "show last-known" decision) and rendered with a stale
    ///     banner; only after the feed has been disconnected for &gt; 30 s
    ///     OR the sport changes do we reset the state object.
    ///   * Always-on schema capture to
    ///     <see cref="SportzcastFrameCapture"/> so we grow the
    ///     <see cref="SportzcastFrameMapper"/> field-name lists empirically.
    /// </summary>
    public class LiveScoreboardViewModel : ObservableObject
    {
        private static readonly TimeSpan StalenessThreshold     = TimeSpan.FromSeconds(15);
        private static readonly TimeSpan DisconnectResetTimeout = TimeSpan.FromSeconds(30);

        private readonly SportzcastFrameCapture _capture = new SportzcastFrameCapture();

        public SportzcastFrameCapture Capture => _capture;

        private ScoreboardSport _sport = ScoreboardSport.Unknown;
        public ScoreboardSport Sport
        {
            get => _sport;
            private set
            {
                if (Set(ref _sport, value))
                {
                    OnPropertyChanged(nameof(SportLabel));
                    OnPropertyChanged(nameof(IsBasketball));
                    OnPropertyChanged(nameof(IsFootball));
                    OnPropertyChanged(nameof(IsBaseball));
                    OnPropertyChanged(nameof(IsSoccer));
                    OnPropertyChanged(nameof(IsHockey));
                    OnPropertyChanged(nameof(IsVolleyball));
                    OnPropertyChanged(nameof(IsGeneric));
                }
            }
        }

        public string SportLabel
        {
            get
            {
                switch (Sport)
                {
                    case ScoreboardSport.Basketball: return "Basketball";
                    case ScoreboardSport.Football:   return "Football";
                    case ScoreboardSport.Baseball:   return "Baseball / Softball";
                    case ScoreboardSport.Soccer:     return "Soccer";
                    case ScoreboardSport.Hockey:     return "Hockey / Lacrosse";
                    case ScoreboardSport.Volleyball: return "Volleyball";
                    default:                         return "Scoreboard";
                }
            }
        }

        // Visibility helpers for the per-sport DataTemplate selector — the
        // Phase B XAML will key off these. Cheap derived properties.
        public bool IsBasketball => Sport == ScoreboardSport.Basketball;
        public bool IsFootball   => Sport == ScoreboardSport.Football;
        public bool IsBaseball   => Sport == ScoreboardSport.Baseball;
        public bool IsSoccer     => Sport == ScoreboardSport.Soccer;
        public bool IsHockey     => Sport == ScoreboardSport.Hockey;
        public bool IsVolleyball => Sport == ScoreboardSport.Volleyball;
        public bool IsGeneric    => Sport == ScoreboardSport.Unknown;

        // One backing field per sport so existing bindings can stay live
        // even when the active sport is something else (e.g. a developer
        // page wants to render the football template while the active
        // sport is basketball). The State property below points at the
        // currently-active one.
        public BasketballState         Basketball { get; } = new BasketballState();
        public FootballState           Football   { get; } = new FootballState();
        public BaseballState           Baseball   { get; } = new BaseballState();
        public SoccerState             Soccer     { get; } = new SoccerState();
        public HockeyState             Hockey     { get; } = new HockeyState();
        public VolleyballState         Volleyball { get; } = new VolleyballState();
        public GenericScoreboardState  Generic    { get; } = new GenericScoreboardState();

        public SportScoreboardState ActiveState
        {
            get
            {
                switch (Sport)
                {
                    case ScoreboardSport.Basketball: return Basketball;
                    case ScoreboardSport.Football:   return Football;
                    case ScoreboardSport.Baseball:   return Baseball;
                    case ScoreboardSport.Soccer:     return Soccer;
                    case ScoreboardSport.Hockey:     return Hockey;
                    case ScoreboardSport.Volleyball: return Volleyball;
                    default:                         return Generic;
                }
            }
        }

        private bool _isLive;
        public bool IsLive
        {
            get => _isLive;
            private set
            {
                if (Set(ref _isLive, value))
                    OnPropertyChanged(nameof(LiveStatusLabel));
            }
        }

        private DateTime? _lastFrameAt;
        public DateTime? LastFrameAt
        {
            get => _lastFrameAt;
            private set
            {
                if (Set(ref _lastFrameAt, value))
                {
                    OnPropertyChanged(nameof(IsStale));
                    OnPropertyChanged(nameof(LiveStatusLabel));
                }
            }
        }

        public bool IsStale
        {
            get
            {
                if (!LastFrameAt.HasValue) return false;
                return (DateTime.UtcNow - LastFrameAt.Value) > StalenessThreshold;
            }
        }

        /// <summary>One-line status: "LIVE", "STALE (Nm Ns ago)", or "OFFLINE".</summary>
        public string LiveStatusLabel
        {
            get
            {
                if (!LastFrameAt.HasValue) return "OFFLINE";
                if (IsLive && !IsStale) return "LIVE";
                var age = DateTime.UtcNow - LastFrameAt.Value;
                if (age.TotalSeconds < 60) return $"STALE ({(int)age.TotalSeconds}s ago)";
                if (age.TotalMinutes < 60) return $"STALE ({(int)age.TotalMinutes}m ago)";
                return $"STALE ({(int)age.TotalHours}h ago)";
            }
        }

        /// <summary>
        /// Set the active sport from the configuration. Pass nulls for
        /// signals you don't have. If the sport changes, the per-sport
        /// state is preserved (so a stale Football state stays available
        /// if the operator briefly swaps configurations and comes back).
        /// </summary>
        public void UpdateFromConfiguration(string configurationSportName, string configurationSportId)
        {
            var detected = SportDetector.FromConfigurationName(configurationSportName);
            if (detected == ScoreboardSport.Unknown)
                detected = SportDetector.FromSportId(configurationSportId);
            if (detected != ScoreboardSport.Unknown && detected != Sport)
            {
                Sport = detected;
                OnPropertyChanged(nameof(ActiveState));
            }
        }

        /// <summary>
        /// Apply a live frame. If the sport hasn't been determined yet,
        /// runs Source 3 (frame inspection) — that gives us a hint even on a
        /// fresh boot where the ScoreConnect configuration hasn't been
        /// read yet. Records to the always-on capture regardless of sport.
        /// </summary>
        public void ApplyFrame(IDictionary<string, object> frame)
        {
            if (frame == null) return;
            if (Sport == ScoreboardSport.Unknown)
            {
                var detected = SportDetector.FromFrame(frame);
                if (detected != ScoreboardSport.Unknown)
                {
                    Sport = detected;
                    OnPropertyChanged(nameof(ActiveState));
                }
            }

            // Apply into the active state via the per-sport mapper.
            SportzcastFrameMapper.Apply(frame, ActiveState);
            LastFrameAt = DateTime.UtcNow;
            IsLive = true;

            // Capture the frame's field names for empirical schema growth.
            // Cheap on the hot path — only does work when the frame surfaces
            // a new field name or the sample list isn't full yet.
            try { _capture.Record(Sport, frame); }
            catch { /* capture is best-effort */ }
        }

        /// <summary>
        /// Called when the live feed disconnects. Per the v0.7 plan we keep
        /// the last-known state visible (with the stale banner) until
        /// either the operator switches sport OR the feed has been gone for
        /// &gt; <see cref="DisconnectResetTimeout"/>. This method handles the
        /// "feed went down" transition; <see cref="OnFeedConnected"/>
        /// handles the recovery.
        /// </summary>
        public void OnFeedDisconnected()
        {
            IsLive = false;
            // LastFrameAt is intentionally left set so the panel can render
            // "STALE (Nm ago)". The state object's values stay populated.
        }

        public void OnFeedConnected()
        {
            // Live flag will flip true on the next ApplyFrame.
            // (Don't pre-flip here — we want IsLive to track frame arrival,
            // not connection state, so a connected-but-silent feed still
            // surfaces as stale.)
        }

        /// <summary>
        /// Tick from a 1-Hz UI timer so the stale banner re-evaluates.
        /// </summary>
        public void Tick()
        {
            OnPropertyChanged(nameof(IsStale));
            OnPropertyChanged(nameof(LiveStatusLabel));

            // Hard reset after a long disconnect — protects against a
            // half-day-old stale state lingering on screen.
            if (!IsLive && LastFrameAt.HasValue
                && (DateTime.UtcNow - LastFrameAt.Value) > DisconnectResetTimeout
                && Sport != ScoreboardSport.Unknown)
            {
                // Reset state values but keep the active Sport — the
                // operator hasn't changed the configuration; we just
                // haven't seen frames in a while.
                ResetActiveStateValues();
                LastFrameAt = null;
            }
        }

        private void ResetActiveStateValues()
        {
            var s = ActiveState;
            // Score and live-data fields only — leave HomeName / AwayName
            // untouched so the labels remain after the disconnect reset.
            s.HomeScore = "";
            s.AwayScore = "";
            s.LastFrameAt = null;

            // Per-sport reset — clear the gameplay fields. This is verbose
            // but keeps the type-safe POCO model intact (no reflection on
            // a hot-ish path).
            switch (s)
            {
                case BasketballState bb:
                    bb.Period = bb.GameClock = bb.ShotClock = "";
                    bb.HomeFouls = bb.AwayFouls = "";
                    bb.HomeTimeouts = bb.AwayTimeouts = "";
                    bb.Possession = "";
                    bb.BonusHome = bb.BonusAway = false;
                    break;
                case FootballState ft:
                    ft.Quarter = ft.GameClock = ft.PlayClock = "";
                    ft.Down = ft.Distance = ft.YardLine = ft.Possession = "";
                    ft.HomeTimeouts = ft.AwayTimeouts = "";
                    ft.PenaltyFlag = false;
                    break;
                case BaseballState bs:
                    bs.Inning = bs.Half = bs.Balls = bs.Strikes = bs.Outs = "";
                    bs.HomeHits = bs.AwayHits = bs.HomeErrors = bs.AwayErrors = "";
                    break;
                case SoccerState sc:
                    sc.Half = sc.GameClock = sc.StoppageTime = "";
                    sc.HomeYellowCards = sc.AwayYellowCards = "";
                    sc.HomeRedCards = sc.AwayRedCards = "";
                    break;
                case HockeyState hk:
                    hk.Period = hk.GameClock = "";
                    hk.HomeShots = hk.AwayShots = "";
                    hk.PowerPlay = hk.PowerPlayClock = "";
                    break;
                case VolleyballState vb:
                    vb.CurrentSet = vb.SetScoreSummary = vb.Serving = "";
                    break;
                case GenericScoreboardState gs:
                    gs.Period = gs.Clock = "";
                    break;
            }
        }
    }
}
