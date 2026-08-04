# NFHS Unity API — full GET surface

Source of truth: `config/routes.rb` in **github.com/playon/unity-api** (Rails, `master`),
fetched 2026-08-04. The `/v1` namespace is fully commented out — **everything lives under `/v2`**.
Swagger UI (`https://unity.nfhsnetwork.com/api-docs/index.html`) exists but was 404 on
2026-08-04; it has a history of going down (owners: Jahmal Lewis / Milton Camelo, #team-connect)
and was incomplete even when up.

Rails `resources :x` ⇒ `GET /v2/x` (index) and `GET /v2/x/{id}` (show), plus write verbs not listed here.

## Most relevant to the Pulse scenario (VPU > event > why no stream)

| Endpoint | What it gives |
|----------|---------------|
| `GET /v2/game_or_event/{id}` | Core lookup (the one we already use) |
| `GET /v2/pixellots` / `GET /v2/pixellots/{id}` | Unity's own record of each Pixellot unit |
| `GET /v2/pixellots/broadcasts/{pixellot_event_id}` | Broadcast lookup **by Pixellot event id** — direct VPU-side join |
| `GET /v2/pixellots/publisher/{publisher_key}` | Pixellot units for a publisher |
| `GET /v2/pixellot_venues` / `GET /v2/pixellot_venues/{venue_id}` | Venue records Unity keeps |
| `GET /v2/pixellot_auth_token` | **Unity brokers a Pixellot auth token** — likely the clean path to abe.pixellot.tv creds |
| `POST /v2/pixellots/pixellot_monitoring/{pixellot_venue_id}` | Pixellot system monitoring via Unity (POST, but diagnostic) |
| `GET /v2/pixellots/{id}/get-available-versions` / `get-target-version` | Software version state |
| `GET /v2/pixellots/presets/{broadcast_key}` | Event preset for a broadcast |
| `GET /v2/broadcasts/{key}` + `/url` + `/vod` + `/broadcast_api_url` + `/test_stream/url` | Broadcast detail, player URL, VOD link, test stream |
| `GET /v2/games/{key}/on_air|off_air|complete|scheduled` | Status-scoped game views (same nested set on `/v2/events`) |
| `GET /v2/upcoming` · `/upcoming_by_quality` · `/current_by_quality` | Fleet-wide event lists, quality-ranked |
| `GET /v2/vods/{key}/url` · `/editor_details` | VOD playback / details |

## Everything else (GET only, by area)

- **Org data:** `schools` (+`/{id}/lookup`, `missing_required_fields`, `cleaning/disabled`), `recommended_schools`, `seasons`, `conferences` (+`/{id}/teams(/{season_id})`), `conference_divisions`, `state_divisions`, `affiliates` (+`/csv`), `state_associations`, `states` (+`/{code}/conferences`), `sports`, `teams` (+nested `games`), `publishers` (+`/{id}/dvd_publishers`), `producers`, `profiles/{id}`
- **Permissions dumps:** `permissions/schools|state_associations|publishers|affiliates(/{unix_timestamp})`
- **Games/events extras:** `games`/`events` index+show, `/{id}/publisher/{publisher_key}`, `/{id}/highlights`, `/{id}/restore`, `deleted` (collection), `game_has_match`, `games_with_many_broadcasts_or_vods`
- **Broadcast extras:** `broadcasts/dmas`, `broadcast_stats`, `datacasts`, `facebook/unscheduled|upcoming|upcoming/count`, `launch_producer`, `launch_test_broadcast`
- **Content/site:** `highlights`, `highlight_categories`, `video_metadata`, `carousel_images` (+`homepage/{image_type}`), `landing_pages`, `pixellot_overlays`, `tournament_page_cards`, `tournaments`, `tournament_games`, `tournament_teams`, `championships/{season}/{state_or_section}`, `sitemap_helper`, `activities`, `activities_by_popularity/{key}`, `event_tags`, `extensions`
- **Commerce/misc:** `tickets`, `dvds`, `dvd_publishers`, `cdn_location/{id}`, `school_emails` (+`/count`), `partner_schools` (+`/partners`), `partner_games` (+`/totals`), `polyauth_event_urls`, `hudl_credentials`, `foreign_keychains` (+by-type/site_url variants), `external_mappings/by_internal|by_external/...`, `playon/{id}`, `generate_headline`, `generate_default_payment`
- **Health:** `GET /` and `GET /status`

## Auth notes (from Slack archaeology, 2026-08-04)

- Writes observed with a **raw 64-hex token in the `Authorization` header, no `Bearer` prefix**.
- Several read/URL endpoints (`/v2/broadcasts/{key}/url.json`, `/v2/vods/{key}/url.json`) observed
  called with **no auth header** — the signed-URL endpoints may be open.
- `.json` suffix works on routes (Rails); a CloudFront alias **cfunity.nfhsnetwork.com** fronts
  the same API and is what some consumers use for URL fetches.
- Contract stability warning: the `v2/ticket` endpoint changed contract in Aug 2025 and broke a
  downstream consumer — pin to fields we actually use, tolerate additions.
