# Score Connect — Scoreboard Redesign Plan

**Status:** draft for review. No code changes from this plan yet.
**Target:** v0.7 (post-v0.6.x field-test cycle).
**Author note:** captured against v0.6.21 of the WPF tool.

## Goal

Re-organise the Score Connect tab so the **Live Scoreboard becomes the
visual centerpiece** — styled to look like a real scoreboard *for the
sport currently in play*. The remaining panels (Service Status, Connected
Device, Cloud BOT, ScoreLink) compress to a supporting context strip
above the scoreboard. The scoreboard pulls live data from the GraphicsManager
Sportzcast log frames Pulse already tails.

Today the Live Scoreboard is a small column-2 card showing a fixed shape
(Home / Away / Period / Clock / Updated). That's fine for basketball; it's
useless for football (no quarter / down / distance / yard line) and
baseball (no inning / outs / balls / strikes). The redesign makes the
scoreboard *match what the sport actually shows on the venue's display*.

## Scope of this plan

In scope:
- Layout reflow of the existing Score Connect tab
- Per-sport scoreboard rendering (top sports first)
- Sport detection pipeline (ScoreConnect configuration → SBCODE lookup → frame inspection)
- Expanded `LiveScoreData` model + Sportzcast frame field-mapping
- Phased rollout so each phase is independently testable

Out of scope (separate efforts):
- Live broadcast quality grading (no quality data is exposed locally)
- Historical scoreboard playback (the live log doesn't retain frames long enough)
- A web / mobile mirror of the scoreboard

---

## Sports we support (priority order)

Ordered by usage at NFHS venues. Phase numbers indicate the rollout
batch — Phase 1 covers ~80% of field events; later phases close the
long tail.

| Phase | Sport | Required fields (per real scoreboard) | Optional fields |
|---|---|---|---|
| 1 | **Basketball** | Home, Away, Period, Game clock, Shot clock | Fouls (H/A), Possession arrow, Bonus, Timeouts (H/A) |
| 1 | **Football** | Home, Away, Quarter, Game clock, Down, Distance, Yard line, Possession | Timeouts (H/A), Play clock, Penalty flag |
| 1 | **Baseball / Softball** | Home, Away, Inning, T/B (top/bottom arrow), Outs, Balls, Strikes | Hits (H/A), Errors (H/A), Pitch count |
| 2 | **Soccer** | Home, Away, Half, Game clock | Yellow / Red cards (H/A), Stoppage time |
| 2 | **Hockey / Lacrosse** | Home, Away, Period, Game clock, Shots (H/A) | Power play indicator + countdown, Penalties remaining |
| 2 | **Volleyball** | Home, Away, Set scores (best of 3 or 5), Current set | Serve indicator |
| 3 | **Wrestling, Track & Field** | Sport-specific, defer until field-tested by a real venue | — |

**Unknown / generic** — when the sport can't be detected, fall back to
the current Home / Away / Period / Clock layout (the existing v0.6.x
shape). This keeps the panel useful on a brand-new install before
ScoreConnect has been configured.

---

## Sport detection pipeline

Three signal sources, evaluated in order. First non-empty wins.

### Source 1 — ScoreConnect III current configuration

The API endpoint `api/configuration/get-current-configuration` (already
called by `ScoreConnectService.GetCurrentConfigurationAsync`) returns
the active vendor / sport / configuration. The sport name is rendered
on the Connected Device card today (e.g. "Daktronics 3000 Football").

Parse the sport name to a `ScoreboardSport` enum by keyword match:

| Keyword in sport name | Maps to |
|---|---|
| Football | `Football` |
| Basketball | `Basketball` |
| Baseball, Softball | `Baseball` |
| Soccer | `Soccer` |
| Hockey, Lacrosse | `Hockey` |
| Volleyball | `Volleyball` |
| (anything else) | `Unknown` |

This is the cheapest source — already on hand.

### Source 2 — ScoreBOT codes file lookup

When Source 1 returns Unknown (e.g. the API returned only a numeric sport
ID), `SportzcastDataDirReader.GetSportName(id)` resolves it to the
canonical SCOREBOARD string ("All American Football (Model 3000)"),
which the same keyword matcher then bins.

### Source 3 — Sportzcast frame inspection

Most fragile — used only when Sources 1 & 2 both come back Unknown.
Inspect the live frame for sport-identifying fields. Examples:
- `down`, `distance`, `yardLine` → Football
- `inning`, `outs`, `balls`, `strikes` → Baseball
- `shotClock`, `fouls` → Basketball

Build the keyword set from real captured frames during Phase 1
field test (see "Frame schema capture mode" below).

### Detection-source priority on conflict

Source 1 (config) wins over Source 3 (frame inspection) — if the
operator configured Daktronics 3000 Football, render Football even
if the frame currently has empty football fields. This avoids
flickering when frames are sparse.

---

## Architecture

### New types

```csharp
public enum ScoreboardSport { Unknown, Basketball, Football, Baseball, Soccer, Hockey, Volleyball }

public class LiveScoreboardViewModel : ObservableObject
{
    public ScoreboardSport Sport { get; }
    public BasketballState  Basketball { get; }   // null when Sport != Basketball
    public FootballState    Football   { get; }
    public BaseballState    Baseball   { get; }
    public SoccerState      Soccer     { get; }
    public HockeyState      Hockey     { get; }
    public VolleyballState  Volleyball { get; }
    public GenericState     Generic    { get; }   // fallback for Unknown

    public bool IsLive { get; }                   // mirrors LiveConnected today
    public DateTime?  LastFrameAt { get; }
    public string     SportLabel  { get; }         // "Basketball", "Football", ...
}

public class BasketballState : ObservableObject
{
    public string Home { get; set; }
    public string Away { get; set; }
    public string HomeScore { get; set; }
    public string AwayScore { get; set; }
    public string Period { get; set; }
    public string GameClock { get; set; }
    public string ShotClock { get; set; }
    public string HomeFouls { get; set; }
    public string AwayFouls { get; set; }
    public string Possession { get; set; }   // "H" | "A" | ""
    // ... etc per sport
}
```

The per-sport state objects are tiny POCOs — easier to bind and easier
to add fields to without touching everything else.

### XAML layout — proposed

```
+-------------------------------------------------------------------+
| Status strip  (compact row, ~80 px tall)                          |
| Service:Connected v1.4.0  |  Cloud BOT:Connected #54025  | Open SC |
+-------------------------------------------------------------------+
| LIVE SCOREBOARD  (per-sport template, ~280 px tall)               |
|                                                                   |
|  [HOME 23]  [Q3 4:35]  [A&A]  [AWAY 25]   (basketball shape)      |
|                                                                   |
|  ⟨Configuration: Daktronics 3000 Football · Wired⟩                |
+-------------------------------------------------------------------+
| Connected Device   |  ScoreLink Device   |  Recommended Actions   |
| (compressed)       |  (existing card)    |  (existing if any)     |
+-------------------------------------------------------------------+
| Live Log  (existing)                                              |
+-------------------------------------------------------------------+
```

The page Findings banner stays at the top above the Status strip.

### Per-sport `DataTemplate`s

```xml
<DataTemplate DataType="{x:Type vm:BasketballState}">
  <!-- Basketball-specific scoreboard layout -->
</DataTemplate>

<DataTemplate DataType="{x:Type vm:FootballState}">
  <!-- Football-specific scoreboard layout -->
</DataTemplate>
```

The Live Scoreboard card binds `ContentControl.Content` to a
`SportState` property (the non-null state object). WPF's implicit
template selection by DataType resolves the right layout per sport.

### Visual style

- **Backboard look** — dark border + amber LED-style digits for scores,
  monospace seven-segment-ish font for clock. Material Design's
  `FontFamily="Segoe UI Black"` at large size approximates this without
  shipping a custom font.
- **Sport identity** — small icon in the top-left of the scoreboard
  (basketball / football / baseball SVG from Material Design).
- **Status accent** — green border when live, amber on stale, red on
  disconnected. Mirrors today's LIVE / OFFLINE pill.
- **Aspect target** — fits at 1366 × 768 LogMeIn without scrolling.

---

## Sportzcast frame field-mapping

The GraphicsManager Sportzcast log frame's exact shape varies by
sport and decoder firmware. `GraphicsManagerSportzcastLogFeed.cs`
already emits each frame as `(string raw, Dictionary<string, object> parsed)`
via the `MessageReceived` event — Pulse just doesn't introspect it
beyond a few well-known fields today.

We need empirical schemas. Approach:

### Phase 1 — Frame schema capture mode

A Settings toggle (off by default) that, when enabled, writes every
**unique field name** seen in Sportzcast frames to a daily file at
`%LOCALAPPDATA%\Pulse.WPF\State\sportzcast-frame-schema-YYYYMMDD.json`:

```json
{
  "sport": "football",
  "vendor": "Daktronics 3000 Football",
  "first_seen": "2026-05-18T15:14:12Z",
  "last_seen":  "2026-05-18T16:42:51Z",
  "fields": {
    "homeScore":   { "type": "number", "samples": ["0","7","14","21"] },
    "awayScore":   { "type": "number", "samples": ["0","3","10"] },
    "quarter":     { "type": "number", "samples": ["1","2","3","4"] },
    "gameClock":   { "type": "string", "samples": ["15:00","12:34","00:42"] },
    "down":        { "type": "number", "samples": ["1","2","3","4"] },
    "distance":    { "type": "number", "samples": ["10","7","3","1"] },
    "yardLine":    { "type": "string", "samples": ["H 35","A 22"] }
  }
}
```

Field user enables capture during a real event; export the file; we
import it back into the Pulse.WPF source tree as the canonical
per-sport mapping. Field-data-driven, not vendor-doc-driven (which
doesn't exist consistently).

Capture is a single file ~20 KB; no PII, no scoreboard data values
beyond a handful of samples per field for type inference.

### Phase 2 — Mapping spec

For each Phase-1 sport, ship a hardcoded mapping like:

```csharp
public static class FootballFrameMap
{
    public static FootballState Apply(IDictionary<string, object> frame, FootballState prev)
    {
        var s = prev ?? new FootballState();
        s.HomeScore = PickFirst(frame, "homeScore", "home_score", "HomeScore");
        s.AwayScore = PickFirst(frame, "awayScore", "away_score", "AwayScore");
        s.Quarter   = PickFirst(frame, "quarter",   "period",     "Quarter");
        s.GameClock = PickFirst(frame, "gameClock", "clock",      "GameClock");
        s.Down      = PickFirst(frame, "down",      "Down");
        s.Distance  = PickFirst(frame, "distance",  "yards_to_go","ToGo");
        s.YardLine  = PickFirst(frame, "yardLine",  "ballOn",     "BallOn");
        s.Possession= PickFirst(frame, "possession","ball_on",    "PossessionFlag");
        // ... etc
        return s;
    }
}
```

Tolerates name variation (`camelCase` / `snake_case` / `PascalCase`)
without requiring a single canonical schema across decoder versions.

### Phase 3 — Fallback for missing fields

When a frame is missing a field that previously had a value, **keep
the prior value** (the on-screen scoreboard doesn't blank fields mid-
game). Pulse's scoreboard mirrors that behaviour by treating frames
as deltas. The state is reset to empty only when:
- The sport changes (operator switched configuration)
- The live feed is disconnected for > 30 s

---

## Phased rollout

Each phase ships independently and is field-testable on its own.

### Phase A — Foundation (1 ship)
- New `ScoreboardSport` enum + per-sport state classes
- `LiveScoreboardViewModel` with sport detection (Sources 1 + 2)
- **No new XAML** — existing scoreboard card keeps current shape
- New "Frame schema capture" Settings toggle, writing to disk
- Result: backend is ready; visible UI unchanged

### Phase B — Per-sport rendering (1 ship per sport)
- One sport at a time: Basketball → Football → Baseball
- Each ships:
  - Frame-mapping for that sport (informed by Phase A capture data)
  - DataTemplate for the per-sport scoreboard layout
  - Settings toggle to fall back to the generic layout for that sport (escape hatch)
- Result: incrementally better scoreboard, sport by sport

### Phase C — Layout reflow (1 ship)
- Live Scoreboard moves to centerpiece (Grid.Row 1, full-width)
- Status strip compresses the three header cards
- Connected Device + ScoreLink + Recommended Actions move to a row 3
- Result: the visual "feels like a scoreboard"

### Phase D — Long-tail sports
- Soccer, Hockey, Volleyball when a venue field-tests them

### Phase E — Polish
- Sport-icon assets
- Optional seven-segment font for scores / clock
- Per-sport accent colours

---

## Open questions — decided 2026-05-19

1. **Visual style: ESPN-ticker data look.** Scores / clock as bold
   sans-serif, not faux-LED. The panel reads as a diagnostic surface,
   not a venue display.
2. **Stale-frame handling: keep last-known.** When the feed
   disconnects mid-game, the scoreboard stays populated with the
   last-known state plus a "Stale — last frame N min ago" banner.
   Frames reset only on (a) sport change, (b) > 30 s without any
   frame after the staleness banner has been showing for > 10 min.
3. **Non-VPU hosts: render but inactive.** The scoreboard card
   stays visible on a dev machine / support laptop, in an inactive
   state (greyed labels, dashes for values, "Live feed offline"
   pill). No hiding — the panel is a known landmark.
4. **Frame-capture mode: always on.** Writes the unique-field-names
   summary to disk continuously. Small daily file (~20 KB),
   single-process file lock, no per-frame fsync. Field data
   collection happens passively without an opt-in step.
5. **Sport list freeze for v0.7: open.** Confirm with the
   product owner which sports actually matter at the NFHS venues
   in scope. My proposal: Basketball / Football / Baseball /
   Softball / Soccer / Hockey / Volleyball / Lacrosse (8 sports
   covering ~95% of NFHS broadcast events). Wrestling, Track &
   Field, and the rest fall to the generic Home / Away / Period /
   Clock layout until a venue requests them.

The Phase A foundation is unblocked by these answers.

---

## Risk + rollback

- **Per-sport rendering ships behind a fallback toggle** so a bad
  per-sport mapping doesn't break the panel — Settings → "Use
  generic scoreboard for [Sport]" rolls a single sport back to the
  current shape.
- **Frame-capture mode is off by default** so a buggy capture
  writer can't flood disk.
- **The existing Live Scoreboard card stays the layout until Phase
  C** so Phases A and B can land without disrupting techs who are
  already used to the current shape.

---

## Next decision

If the plan reads right, the first concrete step is Phase A —
foundation + frame-capture. That's ~400 LOC of model + VM + one
Settings toggle, no visible UI change. It'd land as v0.7.0-beta.

If you want to adjust scope before Phase A — fewer sports, different
visual style, change the detection priority, anything — say so here
and I'll revise the plan before any code lands.
