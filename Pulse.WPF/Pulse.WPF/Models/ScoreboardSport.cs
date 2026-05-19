namespace Pulse.WPF.Models
{
    /// <summary>
    /// Canonical sport identity for the per-sport Live Scoreboard rendering.
    /// Phase A of the v0.7 redesign — keep narrow on purpose. The 7-sport
    /// list (6 distinct templates + Generic fallback) was decided in
    /// SCOREBOARD_REDESIGN_PLAN.md:
    ///
    ///   * Phase 1 — Basketball, Football, Baseball (covers softball too)
    ///   * Phase 2 — Soccer, Hockey (covers lacrosse), Volleyball
    ///   * Generic — Unknown / not-yet-detected; renders the legacy
    ///     Home / Away / Period / Clock shape so the panel stays useful
    ///     on a brand-new install and for sports outside the priority list
    ///     (wrestling, track &amp; field, cricket, etc.).
    ///
    /// Detection priority lives in <see cref="Pulse.WPF.Helpers.SportDetector"/>.
    /// </summary>
    public enum ScoreboardSport
    {
        Unknown    = 0,
        Basketball = 1,
        Football   = 2,
        Baseball   = 3,   // includes Softball
        Soccer     = 4,
        Hockey     = 5,   // includes Lacrosse
        Volleyball = 6,
    }
}
