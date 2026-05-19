using System;
using System.Collections.Generic;
using Pulse.WPF.Models;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Translates a Sportzcast frame (a string-keyed dictionary handed up by
    /// <see cref="GraphicsManagerSportzcastLogFeed"/>) into one of the
    /// per-sport state objects. Tolerates field-name variation across
    /// decoder versions by checking a small set of common spellings per
    /// scoreboard field.
    ///
    /// "Keep last known" semantics: only non-empty incoming values overwrite
    /// the state. Frames missing a field don't blank that field on screen.
    ///
    /// The hardcoded field-name lists in this file are an *initial* guess
    /// based on the field names visible in Pulse's frame schema capture
    /// from internal test rigs. The always-on capture (see
    /// <see cref="SportzcastFrameCapture"/>) writes every unique field name
    /// seen per sport to disk so we can grow these lists empirically as
    /// real venue data arrives.
    /// </summary>
    public static class SportzcastFrameMapper
    {
        /// <summary>
        /// Mutate <paramref name="state"/> with whatever fields the
        /// <paramref name="frame"/> carries. <paramref name="state"/>
        /// must be a concrete subclass matching the sport — passing the
        /// wrong subclass is a no-op.
        /// </summary>
        public static void Apply(IDictionary<string, object> frame, SportScoreboardState state)
        {
            if (frame == null || state == null) return;

            // Universal fields first (every sport has them).
            ApplyUniversal(frame, state);

            switch (state)
            {
                case BasketballState bb: ApplyBasketball(frame, bb); break;
                case FootballState   ft: ApplyFootball  (frame, ft); break;
                case BaseballState   bs: ApplyBaseball  (frame, bs); break;
                case SoccerState     sc: ApplySoccer    (frame, sc); break;
                case HockeyState     hk: ApplyHockey    (frame, hk); break;
                case VolleyballState vb: ApplyVolleyball(frame, vb); break;
                case GenericScoreboardState g: ApplyGeneric(frame, g); break;
            }

            state.LastFrameAt = DateTime.UtcNow;
        }

        private static void ApplyUniversal(IDictionary<string, object> f, SportScoreboardState s)
        {
            Set(f, v => s.HomeName  = v, "homeTeam", "HomeTeam", "homeName", "home_name", "HomeTeamName");
            Set(f, v => s.AwayName  = v, "awayTeam", "AwayTeam", "awayName", "away_name", "AwayTeamName");
            Set(f, v => s.HomeScore = v, "homeScore","HomeScore","home_score","scoreHome", "Home");
            Set(f, v => s.AwayScore = v, "awayScore","AwayScore","away_score","scoreAway", "Away");
        }

        private static void ApplyGeneric(IDictionary<string, object> f, GenericScoreboardState s)
        {
            Set(f, v => s.Period = v, "period", "Period", "quarter", "half", "inning", "set");
            Set(f, v => s.Clock  = v, "clock",  "Clock",  "gameClock", "game_clock", "time", "Time");
        }

        private static void ApplyBasketball(IDictionary<string, object> f, BasketballState s)
        {
            Set(f, v => s.Period       = v, "period", "Period", "quarter", "Quarter");
            Set(f, v => s.GameClock    = v, "gameClock", "clock", "game_clock", "time", "Clock");
            Set(f, v => s.ShotClock    = v, "shotClock", "shot_clock", "ShotClock", "PossessionClock");
            Set(f, v => s.HomeFouls    = v, "homeFouls", "home_fouls", "HomeFouls", "HomeFoulCount");
            Set(f, v => s.AwayFouls    = v, "awayFouls", "away_fouls", "AwayFouls", "AwayFoulCount");
            Set(f, v => s.Possession   = v, "possession", "possessionArrow", "Possession");
            Set(f, v => s.HomeTimeouts = v, "homeTimeouts", "home_timeouts", "HomeTOL");
            Set(f, v => s.AwayTimeouts = v, "awayTimeouts", "away_timeouts", "AwayTOL");
            SetBool(f, v => s.BonusHome = v, "homeBonus", "home_bonus", "HomeBonus");
            SetBool(f, v => s.BonusAway = v, "awayBonus", "away_bonus", "AwayBonus");
        }

        private static void ApplyFootball(IDictionary<string, object> f, FootballState s)
        {
            Set(f, v => s.Quarter      = v, "quarter", "Quarter", "period", "Period");
            Set(f, v => s.GameClock    = v, "gameClock", "clock", "game_clock", "time", "Clock");
            Set(f, v => s.PlayClock    = v, "playClock", "play_clock", "PlayClock");
            Set(f, v => s.Down         = v, "down", "Down");
            Set(f, v => s.Distance     = v, "distance", "yardsToGo", "yards_to_go", "ToGo", "togo");
            Set(f, v => s.YardLine     = v, "yardLine", "yard_line", "YardLine", "ballOn", "ball_on", "BallOn");
            Set(f, v => s.Possession   = v, "possession", "Possession", "ballPossession");
            Set(f, v => s.HomeTimeouts = v, "homeTimeouts", "home_timeouts", "HomeTOL");
            Set(f, v => s.AwayTimeouts = v, "awayTimeouts", "away_timeouts", "AwayTOL");
            SetBool(f, v => s.PenaltyFlag = v, "penaltyFlag", "penalty", "Flag", "PenaltyFlag");
        }

        private static void ApplyBaseball(IDictionary<string, object> f, BaseballState s)
        {
            Set(f, v => s.Inning      = v, "inning", "Inning");
            Set(f, v => s.Half        = v, "half", "Half", "topBottom", "tb", "InningHalf");
            Set(f, v => s.Balls       = v, "balls", "Balls");
            Set(f, v => s.Strikes     = v, "strikes", "Strikes");
            Set(f, v => s.Outs        = v, "outs", "Outs");
            Set(f, v => s.HomeHits    = v, "homeHits", "home_hits", "HomeHits");
            Set(f, v => s.AwayHits    = v, "awayHits", "away_hits", "AwayHits");
            Set(f, v => s.HomeErrors  = v, "homeErrors", "home_errors", "HomeErrors");
            Set(f, v => s.AwayErrors  = v, "awayErrors", "away_errors", "AwayErrors");
        }

        private static void ApplySoccer(IDictionary<string, object> f, SoccerState s)
        {
            Set(f, v => s.Half             = v, "half", "Half", "period", "Period");
            Set(f, v => s.GameClock        = v, "gameClock", "clock", "time", "Clock");
            Set(f, v => s.StoppageTime     = v, "stoppageTime", "added_time", "AddedTime", "StoppageTime");
            Set(f, v => s.HomeYellowCards  = v, "homeYellow", "homeYellowCards", "HomeYellow");
            Set(f, v => s.AwayYellowCards  = v, "awayYellow", "awayYellowCards", "AwayYellow");
            Set(f, v => s.HomeRedCards     = v, "homeRed", "homeRedCards", "HomeRed");
            Set(f, v => s.AwayRedCards     = v, "awayRed", "awayRedCards", "AwayRed");
        }

        private static void ApplyHockey(IDictionary<string, object> f, HockeyState s)
        {
            Set(f, v => s.Period         = v, "period", "Period");
            Set(f, v => s.GameClock      = v, "gameClock", "clock", "time", "Clock");
            Set(f, v => s.HomeShots      = v, "homeShots", "home_shots", "HomeShots", "HomeShotsOnGoal");
            Set(f, v => s.AwayShots      = v, "awayShots", "away_shots", "AwayShots", "AwayShotsOnGoal");
            Set(f, v => s.PowerPlay      = v, "powerPlay", "power_play", "PowerPlay", "PP");
            Set(f, v => s.PowerPlayClock = v, "powerPlayClock", "pp_clock", "PowerPlayClock", "PenaltyClock");
        }

        private static void ApplyVolleyball(IDictionary<string, object> f, VolleyballState s)
        {
            Set(f, v => s.CurrentSet      = v, "set", "Set", "currentSet", "CurrentSet");
            Set(f, v => s.SetScoreSummary = v, "setScores", "set_scores", "SetScores", "SetSummary");
            Set(f, v => s.Serving         = v, "serving", "Serving", "serve", "Serve");
        }

        // --- helpers -----------------------------------------------------

        private static void Set(IDictionary<string, object> f, Action<string> setter, params string[] keys)
        {
            foreach (var k in keys)
            {
                if (!f.TryGetValue(k, out var v)) continue;
                var s = v?.ToString();
                if (!string.IsNullOrEmpty(s)) { setter(s); return; }
            }
        }

        // Booleans are encoded inconsistently across decoder versions —
        // "true" / "True" / "1" / "yes" / 1 / 1.0 all show up. Normalise.
        private static void SetBool(IDictionary<string, object> f, Action<bool> setter, params string[] keys)
        {
            foreach (var k in keys)
            {
                if (!f.TryGetValue(k, out var v) || v == null) continue;
                if (v is bool b) { setter(b); return; }
                var s = v.ToString().Trim().ToLowerInvariant();
                if (s == "true" || s == "1" || s == "yes" || s == "on")  { setter(true);  return; }
                if (s == "false"|| s == "0" || s == "no"  || s == "off") { setter(false); return; }
            }
        }
    }
}
