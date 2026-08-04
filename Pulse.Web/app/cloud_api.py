"""Cloud-side lookups for the Event Streaming lane.

Chains the box's own identifiers through the NFHS cloud APIs (all public,
read-only GETs — verified 2026-08-04, no credentials required):

  venueId            -> search-api producers  (who am I in the cloud)
  venueId            -> search-api events     (my listed schedule)
  venueId            -> EQS venue             (did recent events actually air)
  pixellot key       -> Unity pixellots/{key} (live health metrics, proxied
                                               from Pixellot Club)
  pixellot event ids -> Unity pixellots/broadcasts/{id}
                        (box-driven: catches unlisted/test streams that the
                         search index never shows)

Every call is timeout-bounded and individually fail-soft: on a locked-down
school network (DPI / blocked domains) the lane degrades to a single
"cloud lookup unavailable" state — a failed lookup is never itself a finding.

All calls run server-side (this module), never from the browser and never
from PowerShell — no CORS, no PS 5.1 TLS landmines.
"""

import json
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from powershell import DEMO_MODE

SEARCH_BASE = "https://search-api.nfhsnetwork.com"
UNITY_BASE = "https://unity.nfhsnetwork.com"
EQS_BASE = "https://eqs.nfhsnetwork.com"

TIMEOUT_S = 6          # per-call; hostile networks hang, so keep this short
MAX_BOX_LOOKUPS = 6    # unity per-event lookups per request, newest first
LISTED_PAST_DAYS = 14  # listed-events window
LISTED_FUTURE_DAYS = 7

_UA = {"User-Agent": "Pulse-VPU-Diagnostics"}


def _get_json(url):
    req = urllib.request.Request(url, headers=_UA)
    with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
        return json.load(resp)


def _try(fn, *args):
    """Run fn, returning (result, None) or (None, short error string)."""
    try:
        return fn(*args), None
    except Exception as exc:  # noqa: BLE001 — fail-soft by design
        return None, f"{type(exc).__name__}: {exc}"


def _parse_iso(ts):
    if not ts:
        return None
    try:
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    except ValueError:
        return None


# ── individual fetches ───────────────────────────────────────────


def _fetch_producer(venue_id):
    data = _get_json(f"{SEARCH_BASE}/v3/search/producers?venue_id={venue_id}")
    items = data.get("items") or []
    if not items:
        return None
    item = items[0]
    px = item.get("pixellot") or {}
    pubs = [
        {
            "name": p.get("publisher_name"),
            "type": p.get("publisher_type"),
            "city": p.get("city"),
            "state": p.get("state"),
        }
        for p in (item.get("related_publishers") or [])
    ]
    return {
        "name": item.get("formatted_name") or item.get("name"),
        "producerKey": item.get("key"),
        "pixellotKey": px.get("key"),
        "pixellotName": px.get("pixellot_name"),
        "internalStatus": px.get("internal_status"),
        "lastStatus": px.get("last_status"),
        "statusChangedAt": px.get("status_changed_at"),
        "broadcastStatusReason": px.get("broadcast_status_reason"),
        "currentSwVersion": px.get("current_sw_version"),
        "targetSwVersion": px.get("target_sw_version"),
        "targetSwVersionSetDate": px.get("target_sw_version_set_date"),
        "state": px.get("state"),
        "activationDate": px.get("activation_date"),
        "publishers": pubs,
        # deliberately NOT surfacing updated_by_user (employee email)
    }


def _fetch_listed_events(venue_id):
    data = _get_json(f"{SEARCH_BASE}/v3/search/events?venue_id={venue_id}&size=100")
    return data.get("items") or []


def _fetch_eqs(venue_id):
    data = _get_json(f"{EQS_BASE}/venue/{venue_id}?include_unlisted=true")
    by_event = {}
    for entry in data.get("included") or []:
        key = entry.get("eventKey")
        if key:
            by_event[key] = entry
    excluded = {
        e.get("eventKey") for e in (data.get("excluded") or []) if e.get("eventKey")
    }
    return {"avgScore": data.get("avgScore"), "byEvent": by_event, "excluded": excluded}


# The Unity pixellot record proxies Pixellot Club's live health indicators.
# Field truth (Loma Linda, 2026-08-04): with every camera down, `camera` still
# read Ok — the reliable camera signal is darkCourt + both bandwidths at Error,
# while `connection` distinguishes box-offline from box-online-but-dark.
_METRIC_KEYS = (
    "connection", "status", "status_severity", "health", "cpu", "gpu",
    "cpuTemperature", "darkCourt", "hdBandwidth", "panoBandwidth",
    "hdAudioVolume", "panoAudioVolume", "audioIndication",
    "scoreboardConnection", "scoreboardData", "hardDriveAvailableMB",
)


def _fetch_metrics(pixellot_key):
    data = _get_json(f"{UNITY_BASE}/v2/pixellots/{pixellot_key}")
    return {k: data.get(k) for k in _METRIC_KEYS}


def _fetch_broadcast_by_event_id(pixellot_event_id):
    data = _get_json(f"{UNITY_BASE}/v2/pixellots/broadcasts/{pixellot_event_id}")
    return {
        "broadcastKey": data.get("key"),
        "status": data.get("status"),
        "headline": data.get("headline"),
        "subheadline": data.get("subheadline"),
        "startTime": data.get("start_time"),
        "gameKey": data.get("game_key"),
        "vodKey": data.get("vod_key"),
        "unlisted": data.get("unlisted"),
        "pixellotEventId": data.get("pixellot_event_id"),
        # broadcast can be registered to a different venue than the box that
        # ran it (seen with ops test fixtures) — surface so the UI can flag it
        "pixellotVenueId": data.get("pixellot_id"),
        "producerName": data.get("producer_name"),
    }


# ── verdict engine ───────────────────────────────────────────────

# How long past the scheduled start a broadcast may sit in `scheduled`
# before "never went on air" is the verdict rather than "starting late".
# 30 min: long enough for a genuinely late start, short enough that a tech
# standing at the box during a failed go-live gets a verdict, not "unknown".
# Inside the window the verdict is "late" (started, not on air yet) so the
# in-progress case is visible too.
_STUCK_GRACE = timedelta(minutes=30)


def _verdict_from_eqs(eqs_entry):
    """Verdict for an event EQS actually scored."""
    on_air = eqs_entry.get("onAir")
    duration = eqs_entry.get("eventDuration")
    score = eqs_entry.get("eventScore")
    reasons = []
    if on_air is False:
        return "failed", ["Cloud quality system: stream never went on air"]
    comp_fails = [
        name
        for name in ("exposure", "calibration", "focus", "scoreboard")
        if eqs_entry.get(name) is False
    ]
    if eqs_entry.get("audio") in (0, False):
        comp_fails.append("audio")
    if duration is False and not eqs_entry.get("wasManuallyEnded"):
        # Short streams are common fleet-wide — only call it "died mid-event"
        # when the quality score corroborates something actually went wrong.
        if score is not None and score < 0.6:
            reasons.append("Stream ended well short of the scheduled window")
            if comp_fails:
                reasons.append("Failed checks: " + ", ".join(comp_fails))
            return "partial", reasons
        reasons.append("Ran shorter than scheduled (often benign)")
    if comp_fails:
        reasons.append("Failed quality checks: " + ", ".join(comp_fails))
        return "quality", reasons
    return "streamed", reasons


def _verdict_for(entry, eqs, now):
    """Compute (verdict, reasons) for one timeline entry."""
    start = _parse_iso(entry.get("startTime"))
    status = (entry.get("status") or "").lower()
    game_key = entry.get("gameKey")

    if status == "on_air":
        return "live", ["Broadcast is on air now"]
    if start and start > now:
        return "upcoming", []

    scored = eqs["byEvent"].get(game_key) if game_key else None
    if scored:
        entry["eqs"] = {
            k: scored.get(k)
            for k in (
                "onAir", "eventDuration", "exposure", "calibration", "focus",
                "calibrationZoomSet", "audio", "scoreboard", "wasManuallyEnded",
                "eventScore",
            )
        }
        return _verdict_from_eqs(scored)

    if status == "scheduled" and start and start <= now:
        if now - start > _STUCK_GRACE:
            reasons = [
                "Broadcast never left 'scheduled' — it did not go on air",
            ]
            if game_key and game_key in eqs["excluded"]:
                reasons.append("Cloud quality system never scored it (nothing aired)")
            return "failed", reasons
        return "late", [
            "Scheduled start has passed and the broadcast has not gone on "
            "air yet — if you are at the box now, this is the failure in "
            "progress",
        ]
    if status == "complete":
        return "streamed", ["Marked complete in the cloud (not quality-scored)"]
    return "unknown", []


def _merge_timeline(listed_items, box_broadcasts, local_events, eqs, now):
    """Combine listed schedule + box-driven broadcasts into one timeline."""
    local_by_id = {e.get("eventId"): e for e in local_events if e.get("eventId")}
    past_cut = now - timedelta(days=LISTED_PAST_DAYS)
    future_cut = now + timedelta(days=LISTED_FUTURE_DAYS)

    timeline = {}

    for item in listed_items:
        start = _parse_iso(item.get("start_time"))
        if not start or start < past_cut or start > future_cut:
            continue
        key = item.get("key")
        timeline[key] = {
            "gameKey": key,
            "headline": item.get("headline") or item.get("sport") or "Event",
            "sport": item.get("sport"),
            "startTime": item.get("start_time"),
            "localStartTime": item.get("local_start_time"),
            "status": item.get("status"),
            "hasVod": item.get("has_vod"),
            "source": "listed",
            "unlisted": False,
            "pixellotEventId": None,
            "local": None,
            "eqs": None,
        }

    for bdc in box_broadcasts:
        if not bdc:
            continue
        key = bdc.get("gameKey") or bdc.get("broadcastKey")
        entry = timeline.get(key)
        if entry is None:
            headline = bdc.get("headline") or "Unlisted / test event"
            if bdc.get("subheadline"):
                headline += f" — {bdc['subheadline']}"
            entry = timeline[key] = {
                "gameKey": bdc.get("gameKey"),
                "headline": headline,
                "sport": None,
                "startTime": bdc.get("startTime"),
                "localStartTime": None,
                "status": bdc.get("status"),
                "hasVod": bool(bdc.get("vodKey")),
                "source": "box",
                "unlisted": bool(bdc.get("unlisted")),
                "local": None,
                "eqs": None,
            }
        else:
            entry["source"] = "listed+box"
        entry["pixellotEventId"] = bdc.get("pixellotEventId")
        entry["broadcastKey"] = bdc.get("broadcastKey")
        entry["registeredVenueId"] = bdc.get("pixellotVenueId")
        loc = local_by_id.get(bdc.get("pixellotEventId"))
        if loc:
            entry["local"] = {
                "recorded": (loc.get("videoBytes") or 0) > 0,
                "videoBytes": loc.get("videoBytes"),
                "uploadedCount": loc.get("uploadedCount"),
                "name": loc.get("name"),
            }

    for entry in timeline.values():
        verdict, reasons = _verdict_for(entry, eqs, now)
        # Local recording evidence sharpens a failed/partial verdict.
        loc = entry.get("local")
        if loc and verdict in ("failed", "partial"):
            if loc["recorded"]:
                reasons.append(
                    "Box DID record video locally — capture worked; look at "
                    "upload/streaming path"
                )
            else:
                reasons.append(
                    "Box never recorded video for this event — capture-side "
                    "failure (cameras / scheduling)"
                )
        entry["verdict"] = verdict
        entry["verdictReasons"] = reasons

    ordered = sorted(
        timeline.values(), key=lambda e: e.get("startTime") or "", reverse=True
    )
    return ordered


def _cause_hints(metrics, producer):
    """Unit-level hints from live metrics — current state, labeled as such."""
    hints = []
    if not metrics:
        return hints
    if metrics.get("connection") not in (None, "Ok"):
        hints.append({
            "severity": "critical",
            "text": "Pixellot Cloud cannot reach this VPU (connection "
                    f"{metrics.get('connection')}) — box offline or network blocked",
            "page": "network",
        })
    else:
        dark = metrics.get("darkCourt") == "Error"
        no_bw = (
            metrics.get("hdBandwidth") == "Error"
            and metrics.get("panoBandwidth") == "Error"
        )
        if dark and no_bw:
            hints.append({
                "severity": "critical",
                "text": "Box is online but the cloud sees no camera video "
                        "(dark court, no HD/pano bandwidth) — check camera "
                        "connections",
                "page": "cameras",
            })
        elif dark:
            hints.append({
                "severity": "warning",
                "text": "Cloud reports a dark court — camera may be obstructed, "
                        "powered off, or the room is dark",
                "page": "cameras",
            })
    if metrics.get("scoreboardConnection") == "Error" or metrics.get("scoreboardData") == "Error":
        hints.append({
            "severity": "warning",
            "text": "Cloud reports scoreboard connection/data problems",
            "page": "scoreconnect",
        })
    if metrics.get("audioIndication") == "Error":
        hints.append({
            "severity": "warning",
            "text": "Cloud reports no audio indication",
            "page": "audio",
        })
    if producer:
        cur, tgt = producer.get("currentSwVersion"), producer.get("targetSwVersion")
        if cur and tgt and cur != tgt:
            hints.append({
                "severity": "info",
                "text": f"Pixellot software is behind its target ({cur} installed, "
                        f"{tgt} assigned)",
                "page": None,
            })
        if producer.get("broadcastStatusReason"):
            hints.append({
                "severity": "warning",
                "text": "Cloud broadcast status reason: "
                        + str(producer["broadcastStatusReason"]),
                "page": None,
            })
    return hints


# ── entry point ──────────────────────────────────────────────────


def fetch_cloud(venue_id, local_events):
    """Blocking; call via run_in_executor. Returns the `cloud` payload dict.

    local_events: the `events` list from Get-PixellotEvents.ps1 (may be []).
    """
    if DEMO_MODE:
        import demo_data
        return demo_data.demo_cloud_events(venue_id, local_events)

    now = datetime.now(timezone.utc)
    if not venue_id:
        return {"available": False, "error": "no venue id", "events": []}

    with ThreadPoolExecutor(max_workers=4) as pool:
        f_producer = pool.submit(_try, _fetch_producer, venue_id)
        f_listed = pool.submit(_try, _fetch_listed_events, venue_id)
        f_eqs = pool.submit(_try, _fetch_eqs, venue_id)

        producer, err_producer = f_producer.result()
        listed, err_listed = f_listed.result()
        eqs, err_eqs = f_eqs.result()

        metrics, err_metrics = (None, None)
        if producer and producer.get("pixellotKey"):
            metrics, err_metrics = _try(_fetch_metrics, producer["pixellotKey"])

        # Box-driven lookups: newest local event ids first, capped.
        box_broadcasts = []
        ids = [e.get("eventId") for e in local_events if e.get("eventId")]
        futures = [
            pool.submit(_try, _fetch_broadcast_by_event_id, eid)
            for eid in ids[:MAX_BOX_LOOKUPS]
        ]
        for fut in futures:
            result, _err = fut.result()  # 404s (stale folders) are expected
            if result:
                box_broadcasts.append(result)

    errors = {
        k: v
        for k, v in (
            ("producer", err_producer), ("events", err_listed),
            ("eqs", err_eqs), ("metrics", err_metrics),
        )
        if v
    }

    # All primary calls failed -> the cloud is unreachable from here.
    if producer is None and listed is None and eqs is None:
        return {
            "available": False,
            "error": "Cloud APIs unreachable (network may block or intercept "
                     "outbound HTTPS)",
            "errors": errors,
            "events": [],
        }

    eqs = eqs or {"avgScore": None, "byEvent": {}, "excluded": set()}
    timeline = _merge_timeline(listed or [], box_broadcasts, local_events, eqs, now)

    return {
        "available": True,
        "error": None,
        "errors": errors or None,
        "producer": producer,
        "metrics": metrics,
        "eqsAvgScore": eqs.get("avgScore"),
        "events": timeline,
        "causeHints": _cause_hints(metrics, producer),
        "generatedAt": now.isoformat(),
    }
