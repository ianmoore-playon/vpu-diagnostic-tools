using System;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// Shared base for the per-sport scoreboard state objects. The fields
    /// every scoreboard needs (home/away names, scores, last-frame
    /// timestamp) live here; sport-specific fields (down/distance,
    /// shot clock, inning, etc.) hang off the concrete subclasses.
    ///
    /// The state objects deliberately render values as <c>string</c>
    /// rather than typed numbers — Sportzcast frame fields arrive
    /// formatted (e.g. "00:42" for game clock, "H 35" for yard line,
    /// "T1 3-2" for baseball balls/strikes) and the per-sport DataTemplate
    /// is going to bind directly. Re-stringifying typed values only
    /// introduces locale-format drift we don't want.
    ///
    /// "Keep last known" semantics: the <see cref="Pulse.WPF.Helpers.SportzcastFrameMapper"/>
    /// only overwrites a property when the incoming frame supplies a
    /// non-null value for it, so a frame missing the clock field doesn't
    /// blank the clock on screen. The state is fully reset only when the
    /// sport changes or the feed has been disconnected for &gt; 30 s.
    /// </summary>
    public abstract class SportScoreboardState : ObservableObject
    {
        /// <summary>Concrete subclass identifies which sport it represents.</summary>
        public abstract ScoreboardSport Sport { get; }

        private string _homeName = "HOME";
        public string HomeName { get => _homeName; set => Set(ref _homeName, value); }

        private string _awayName = "AWAY";
        public string AwayName { get => _awayName; set => Set(ref _awayName, value); }

        private string _homeScore = "";
        public string HomeScore { get => _homeScore; set => Set(ref _homeScore, value); }

        private string _awayScore = "";
        public string AwayScore { get => _awayScore; set => Set(ref _awayScore, value); }

        private DateTime? _lastFrameAt;
        public DateTime? LastFrameAt
        {
            get => _lastFrameAt;
            set => Set(ref _lastFrameAt, value);
        }
    }

    public class GenericScoreboardState : SportScoreboardState
    {
        public override ScoreboardSport Sport => ScoreboardSport.Unknown;

        private string _period = "";
        public string Period { get => _period; set => Set(ref _period, value); }

        private string _clock = "";
        public string Clock { get => _clock; set => Set(ref _clock, value); }
    }

    public class BasketballState : SportScoreboardState
    {
        public override ScoreboardSport Sport => ScoreboardSport.Basketball;

        // Game period (1-4 for high-school, OT1+ for overtime).
        private string _period = "";
        public string Period { get => _period; set => Set(ref _period, value); }

        private string _gameClock = "";
        public string GameClock { get => _gameClock; set => Set(ref _gameClock, value); }

        private string _shotClock = "";
        public string ShotClock { get => _shotClock; set => Set(ref _shotClock, value); }

        private string _homeFouls = "";
        public string HomeFouls { get => _homeFouls; set => Set(ref _homeFouls, value); }

        private string _awayFouls = "";
        public string AwayFouls { get => _awayFouls; set => Set(ref _awayFouls, value); }

        /// <summary>"H" or "A" — possession arrow indicator. Empty when not reported.</summary>
        private string _possession = "";
        public string Possession { get => _possession; set => Set(ref _possession, value); }

        private string _homeTimeouts = "";
        public string HomeTimeouts { get => _homeTimeouts; set => Set(ref _homeTimeouts, value); }

        private string _awayTimeouts = "";
        public string AwayTimeouts { get => _awayTimeouts; set => Set(ref _awayTimeouts, value); }

        private bool _bonusHome;
        public bool BonusHome { get => _bonusHome; set => Set(ref _bonusHome, value); }

        private bool _bonusAway;
        public bool BonusAway { get => _bonusAway; set => Set(ref _bonusAway, value); }
    }

    public class FootballState : SportScoreboardState
    {
        public override ScoreboardSport Sport => ScoreboardSport.Football;

        private string _quarter = "";
        public string Quarter { get => _quarter; set => Set(ref _quarter, value); }

        private string _gameClock = "";
        public string GameClock { get => _gameClock; set => Set(ref _gameClock, value); }

        private string _playClock = "";
        public string PlayClock { get => _playClock; set => Set(ref _playClock, value); }

        /// <summary>1-4 (or blank when no current down). Renders as "1ST" / "2ND" / etc.</summary>
        private string _down = "";
        public string Down { get => _down; set => Set(ref _down, value); }

        /// <summary>Yards to go for first down.</summary>
        private string _distance = "";
        public string Distance { get => _distance; set => Set(ref _distance, value); }

        /// <summary>Ball spot — e.g. "H 35" (home side of field, 35 yard line) or "A 22".</summary>
        private string _yardLine = "";
        public string YardLine { get => _yardLine; set => Set(ref _yardLine, value); }

        /// <summary>"H" / "A" — possession indicator.</summary>
        private string _possession = "";
        public string Possession { get => _possession; set => Set(ref _possession, value); }

        private string _homeTimeouts = "";
        public string HomeTimeouts { get => _homeTimeouts; set => Set(ref _homeTimeouts, value); }

        private string _awayTimeouts = "";
        public string AwayTimeouts { get => _awayTimeouts; set => Set(ref _awayTimeouts, value); }

        private bool _penaltyFlag;
        public bool PenaltyFlag { get => _penaltyFlag; set => Set(ref _penaltyFlag, value); }
    }

    public class BaseballState : SportScoreboardState
    {
        public override ScoreboardSport Sport => ScoreboardSport.Baseball;

        private string _inning = "";
        public string Inning { get => _inning; set => Set(ref _inning, value); }

        /// <summary>"Top" or "Bottom" — half-inning indicator.</summary>
        private string _half = "";
        public string Half { get => _half; set => Set(ref _half, value); }

        private string _balls = "";
        public string Balls { get => _balls; set => Set(ref _balls, value); }

        private string _strikes = "";
        public string Strikes { get => _strikes; set => Set(ref _strikes, value); }

        private string _outs = "";
        public string Outs { get => _outs; set => Set(ref _outs, value); }

        private string _homeHits = "";
        public string HomeHits { get => _homeHits; set => Set(ref _homeHits, value); }

        private string _awayHits = "";
        public string AwayHits { get => _awayHits; set => Set(ref _awayHits, value); }

        private string _homeErrors = "";
        public string HomeErrors { get => _homeErrors; set => Set(ref _homeErrors, value); }

        private string _awayErrors = "";
        public string AwayErrors { get => _awayErrors; set => Set(ref _awayErrors, value); }
    }

    public class SoccerState : SportScoreboardState
    {
        public override ScoreboardSport Sport => ScoreboardSport.Soccer;

        /// <summary>"1" / "2" / "ET1" / "ET2" / "PK".</summary>
        private string _half = "";
        public string Half { get => _half; set => Set(ref _half, value); }

        private string _gameClock = "";
        public string GameClock { get => _gameClock; set => Set(ref _gameClock, value); }

        private string _stoppageTime = "";
        public string StoppageTime { get => _stoppageTime; set => Set(ref _stoppageTime, value); }

        private string _homeYellowCards = "";
        public string HomeYellowCards { get => _homeYellowCards; set => Set(ref _homeYellowCards, value); }

        private string _awayYellowCards = "";
        public string AwayYellowCards { get => _awayYellowCards; set => Set(ref _awayYellowCards, value); }

        private string _homeRedCards = "";
        public string HomeRedCards { get => _homeRedCards; set => Set(ref _homeRedCards, value); }

        private string _awayRedCards = "";
        public string AwayRedCards { get => _awayRedCards; set => Set(ref _awayRedCards, value); }
    }

    public class HockeyState : SportScoreboardState
    {
        public override ScoreboardSport Sport => ScoreboardSport.Hockey;

        private string _period = "";
        public string Period { get => _period; set => Set(ref _period, value); }

        private string _gameClock = "";
        public string GameClock { get => _gameClock; set => Set(ref _gameClock, value); }

        private string _homeShots = "";
        public string HomeShots { get => _homeShots; set => Set(ref _homeShots, value); }

        private string _awayShots = "";
        public string AwayShots { get => _awayShots; set => Set(ref _awayShots, value); }

        /// <summary>Power-play indicator: "" / "H" / "A".</summary>
        private string _powerPlay = "";
        public string PowerPlay { get => _powerPlay; set => Set(ref _powerPlay, value); }

        private string _powerPlayClock = "";
        public string PowerPlayClock { get => _powerPlayClock; set => Set(ref _powerPlayClock, value); }
    }

    public class VolleyballState : SportScoreboardState
    {
        public override ScoreboardSport Sport => ScoreboardSport.Volleyball;

        /// <summary>"1" / "2" / "3" / "4" / "5".</summary>
        private string _currentSet = "";
        public string CurrentSet { get => _currentSet; set => Set(ref _currentSet, value); }

        // Per-set scores. The format is one big concatenated string ("25-23, 18-25, 25-19")
        // so the DataTemplate can render it without us needing a child collection.
        private string _setScoreSummary = "";
        public string SetScoreSummary { get => _setScoreSummary; set => Set(ref _setScoreSummary, value); }

        /// <summary>"H" / "A" — serve indicator.</summary>
        private string _serving = "";
        public string Serving { get => _serving; set => Set(ref _serving, value); }
    }
}
