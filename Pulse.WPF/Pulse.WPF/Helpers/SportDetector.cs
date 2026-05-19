using System;
using System.Collections.Generic;
using Pulse.WPF.Models;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Resolves a <see cref="ScoreboardSport"/> from whatever signals are
    /// available. Three sources, priority order:
    ///
    /// 1. ScoreConnect III current configuration's sport name — already
    ///    rendered on the Connected Device card. Keyword match against the
    ///    sport title (e.g. "Daktronics 3000 Football" → Football).
    /// 2. SBCODE lookup via <see cref="SportzcastDataDirReader"/> — when the
    ///    API returned only a numeric sport ID, dereference it through the
    ///    local ScoreBOT codes file to get a SCOREBOARD title, then keyword-
    ///    match that.
    /// 3. Live frame inspection — last resort. Looks for sport-identifying
    ///    field names ("down" / "distance" for football, "inning" / "outs"
    ///    for baseball, etc.) in the frame dict.
    ///
    /// Returns <see cref="ScoreboardSport.Unknown"/> when all three signals
    /// fail to identify a known sport — the caller renders the generic
    /// Home/Away/Period/Clock shape in that case.
    /// </summary>
    public static class SportDetector
    {
        public static ScoreboardSport FromConfigurationName(string sportName)
        {
            if (string.IsNullOrWhiteSpace(sportName)) return ScoreboardSport.Unknown;
            return MatchKeyword(sportName);
        }

        public static ScoreboardSport FromSportId(string sportId)
        {
            if (string.IsNullOrWhiteSpace(sportId)) return ScoreboardSport.Unknown;
            var name = SportzcastDataDirReader.GetSportName(sportId);
            if (string.IsNullOrWhiteSpace(name)) return ScoreboardSport.Unknown;
            return MatchKeyword(name);
        }

        public static ScoreboardSport FromFrame(IDictionary<string, object> frame)
        {
            if (frame == null || frame.Count == 0) return ScoreboardSport.Unknown;
            // Field-name signatures per sport. First match wins. Order
            // matters — Baseball's "outs" is more discriminating than
            // Basketball's "fouls" so check the more specific keys first.
            if (Has(frame, "down", "yardLine", "yard_line", "ballOn"))                    return ScoreboardSport.Football;
            if (Has(frame, "balls", "strikes", "outs", "inning"))                         return ScoreboardSport.Baseball;
            if (Has(frame, "shotClock", "shot_clock", "PossessionClock"))                 return ScoreboardSport.Basketball;
            if (Has(frame, "powerPlay", "pp_clock", "PowerPlayClock"))                    return ScoreboardSport.Hockey;
            if (Has(frame, "yellowCard", "homeYellow", "awayYellow", "stoppageTime"))     return ScoreboardSport.Soccer;
            if (Has(frame, "currentSet", "setScores", "SetScores"))                       return ScoreboardSport.Volleyball;
            return ScoreboardSport.Unknown;
        }

        /// <summary>
        /// Convenience composer: tries Sources 1 → 2 → 3, returning the first
        /// non-Unknown answer. Pass null / empty for any source you don't have
        /// available at the call site.
        /// </summary>
        public static ScoreboardSport Detect(
            string configurationSportName,
            string configurationSportId,
            IDictionary<string, object> latestFrame)
        {
            var s = FromConfigurationName(configurationSportName);
            if (s != ScoreboardSport.Unknown) return s;
            s = FromSportId(configurationSportId);
            if (s != ScoreboardSport.Unknown) return s;
            return FromFrame(latestFrame);
        }

        // --- internals -----------------------------------------------------

        private static ScoreboardSport MatchKeyword(string text)
        {
            var t = (text ?? "").ToLowerInvariant();

            // Order: more specific first so e.g. "Lacrosse" doesn't fall
            // through to a "soccer"-substring trap (it wouldn't, but the
            // pattern keeps future additions safe).
            if (Contains(t, "basketball"))                       return ScoreboardSport.Basketball;
            if (Contains(t, "football"))                         return ScoreboardSport.Football;
            if (Contains(t, "baseball", "softball"))             return ScoreboardSport.Baseball;
            if (Contains(t, "soccer", "futbol"))                 return ScoreboardSport.Soccer;
            if (Contains(t, "hockey", "lacrosse"))               return ScoreboardSport.Hockey;
            if (Contains(t, "volleyball"))                       return ScoreboardSport.Volleyball;
            return ScoreboardSport.Unknown;
        }

        private static bool Contains(string text, params string[] needles)
        {
            foreach (var n in needles)
                if (text.IndexOf(n, StringComparison.OrdinalIgnoreCase) >= 0) return true;
            return false;
        }

        private static bool Has(IDictionary<string, object> frame, params string[] keys)
        {
            foreach (var k in keys)
            {
                if (frame.TryGetValue(k, out var v) && v != null && !string.IsNullOrEmpty(v.ToString()))
                    return true;
            }
            return false;
        }
    }
}
