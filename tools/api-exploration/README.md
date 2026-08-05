# API Exploration — NFHS Unity + Pixellot Club

Postman collection + environment for prototyping the Pulse cloud lookup feature:
**"I am this VPU > I have this event > I was not able to stream because of X."**

## Import

1. Postman > **Import** > drop both JSON files from this folder.
2. Select the **NFHS + Pixellot (fill in auth)** environment (top-right picker).
3. Fill in the two secret vars:
   - `nfhs_auth` — full `Authorization` header value for unity.nfhsnetwork.com (e.g. `Bearer <token>`)
   - `club_auth` — same for abe.pixellot.tv
   - If either API wants a different header name (e.g. `x-api-key`), edit the header on the requests; the variables still hold the value.
4. Set `event_id` to a real game/event id.

## Run the scenario chain

Run requests 1 → 5 in order. Each request's test script captures the IDs the
next one needs into the environment (watch the Postman Console for what it
grabbed):

| # | Request | Seeds |
|---|---------|-------|
| 1 | Unity `GET /v2/game_or_event/{id}` | `broadcast_key`, `game_key`, `pixellot_id`, `pixellot_key` |
| 2 | Unity `GET /v2/broadcasts/{key}` | `vod_key`; shows `status` (on_air / complete / scheduled) |
| 3 | Unity `GET /v2/broadcasts/{key}/url` | live `.m3u8` (on_air only) |
| 4 | Unity `GET /v2/vods/{vodKey}/url` | VOD `.m3u8` (complete only) |
| 5 | Club `GET /api/v3/venues/{pixellotId}` | hardware profile; console logs every non-Ok `metrics.values` entry |

The chaining scripts probe both snake_case and camelCase field names (and a
`data` wrapper) since the exact response shapes are unconfirmed — if a capture
misses, check the raw response and adjust the field list in the request's
Scripts tab, then note the real shape here.

## What to record while exploring

This folder is the scratchpad for turning exploration into the Pulse feature.
As responses come back, capture:

- Real auth mechanism per API (header name, token lifetime, how a VPU would get one)
- Exact response JSON shapes (drop samples in `samples/`, one file per endpoint — **redact tokens/signed URLs first**)
- Which `metrics.values` severities map to which "could not stream because X" verdicts
- Rate limits / error shapes (401 vs 403 vs 404 bodies)

Key join: `pixellot_id` links Unity events to the Club venue profile. A VPU
knows its own pixellot_id locally, so Pulse on-box can pull its venue's
cloud-side view directly.
