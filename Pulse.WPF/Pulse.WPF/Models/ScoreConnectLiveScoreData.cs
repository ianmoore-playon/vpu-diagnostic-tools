using System;
using System.Collections.Generic;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// Real-time scoreboard snapshot pushed over the ScoreConnect III
    /// WebSocket. Populated incrementally — every WS frame mutates whichever
    /// fields it carries, so partial updates don't clobber stale-but-valid
    /// values from the previous frame.
    ///
    /// The exact JSON keys ScoreConnect emits aren't documented; the parser
    /// in <c>ScoreConnectLiveClient</c> tries a small set of common spellings
    /// (homeScore / HomeScore / scoreHome) and dumps anything else into
    /// <see cref="ExtendedFields"/> so we don't lose information on a
    /// version drift.
    /// </summary>
    public class ScoreConnectLiveScoreData : ObservableObject
    {
        private string _homeScore = "";
        public string HomeScore { get => _homeScore; set => Set(ref _homeScore, value); }

        private string _awayScore = "";
        public string AwayScore { get => _awayScore; set => Set(ref _awayScore, value); }

        private string _period = "";
        public string Period { get => _period; set => Set(ref _period, value); }

        private string _clock = "";
        public string Clock { get => _clock; set => Set(ref _clock, value); }

        private string _homeTeam = "";
        public string HomeTeam { get => _homeTeam; set => Set(ref _homeTeam, value); }

        private string _awayTeam = "";
        public string AwayTeam { get => _awayTeam; set => Set(ref _awayTeam, value); }

        private DateTime? _lastUpdatedAt;
        public DateTime? LastUpdatedAt
        {
            get => _lastUpdatedAt;
            set => Set(ref _lastUpdatedAt, value);
        }

        /// <summary>Any keys the typed properties above don't capture — kept
        /// so we can still see / report on the raw fields the feed pushes.</summary>
        public Dictionary<string, string> ExtendedFields { get; }
            = new Dictionary<string, string>();
    }
}
