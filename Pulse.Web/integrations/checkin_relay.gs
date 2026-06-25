/**
 * Pulse check-in → Slack relay  (PULSEDEV-54)
 * ============================================
 * Google Apps Script bound to the existing Pulse check-in Sheet — the sink the
 * VPUs already POST to (main.py `_CHECKIN_URL`, `_send_checkin`). This turns a
 * *new* FAIL landing in the Sheet into a Slack message, with the alerting logic
 * and the Slack secret living HERE (server-side) — never on the VPUs.
 *
 * ── HOW TO ADOPT ──────────────────────────────────────────────────────────
 * A check-in Apps Script is ALREADY deployed and bound to the Sheet (it upserts
 * the per-unit ledger). Do NOT blind-paste this over it. Instead:
 *   1. Open the bound script (Sheet → Extensions → Apps Script).
 *   2. Reconcile `appendLedger_()` below with the live ledger columns (the
 *      LEDGER_HEADERS list here is the documented shape — match it to reality).
 *   3. Merge the relay half (`routeDelta_`, `notifySlack_`, incident store) into
 *      the existing `doPost` so a single deployment handles ledger + Slack.
 *   4. Run `setup()` once to seed Script Properties + sheets, then redeploy the
 *      web app (Deploy → Manage deployments → edit → new version).
 *
 * ── CONFIG (Project Settings → Script properties) ─────────────────────────
 *   CHECKIN_SECRET      shared secret the VPUs send (matches main.py).
 *   SLACK_WEBHOOK_URL   Slack incoming-webhook URL for the alert channel.
 *   ALERT_MENTION       optional, e.g. "<!here>" — prepended to blocker alerts.
 *
 * The payload shape is the locked contract from main.py `_send_checkin`
 * (`reason`, `readiness`, `delta.opened/resolved/...`). Keep this transport-
 * agnostic: the same body graduates to OneUptime's Incoming Request Monitor —
 * swap `notifySlack_` for an OneUptime POST and the routing logic is unchanged.
 */

// Ledger columns — RECONCILE with the live sheet before deploying (see header).
var LEDGER_HEADERS = [
  'firstSeen', 'lastSeen', 'runCount', 'hostname', 'serialNumber', 'vpuName',
  'venueId', 'model', 'pulseVersion', 'channel', 'reason', 'status',
  'blockers', 'risks'
];
var LEDGER_SHEET = 'checkins';
var INCIDENT_SHEET = 'incidents';
var INCIDENT_HEADERS = ['fingerprint', 'serialNumber', 'code', 'class', 'title',
                        'vpuName', 'openedAt', 'lastNotified'];

function doPost(e) {
  // Serialize: concurrent check-ins must not interleave row writes / dedup.
  var lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    var body = JSON.parse(e.postData.contents);
    var props = PropertiesService.getScriptProperties();

    var expected = props.getProperty('CHECKIN_SECRET');
    if (!expected || body.secret !== expected) {
      return jsonOut_({ ok: false, error: 'bad secret' });
    }

    appendLedger_(body);                 // existing behavior — keep it
    var sent = routeDelta_(body, props); // new — Slack on opened/resolved blockers

    return jsonOut_({ ok: true, alertsSent: sent });
  } catch (err) {
    return jsonOut_({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

/**
 * Upsert one row per VPU (keyed by serialNumber): first/last seen + run count
 * + the latest readiness snapshot. Mirrors the documented existing ledger —
 * RECONCILE column names with the live sheet.
 */
function appendLedger_(body) {
  var sh = sheet_(LEDGER_SHEET, LEDGER_HEADERS);
  var data = sh.getDataRange().getValues();
  var header = data[0];
  var col = {};
  header.forEach(function (h, i) { col[h] = i; });

  var serial = body.serialNumber || '';
  var now = new Date();
  var r = body.readiness || {};
  var rowValues = {
    lastSeen: now,
    hostname: body.hostname || '',
    serialNumber: serial,
    vpuName: body.vpuName || '',
    venueId: body.venueId || '',
    model: body.model || '',
    pulseVersion: body.pulseVersion || '',
    channel: body.channel || '',
    reason: body.reason || '',
    status: r.status || '',
    blockers: (r.blockers || []).join(', '),
    risks: (r.risks || []).join(', ')
  };

  // Find an existing row for this serial.
  var rowIdx = -1;
  for (var i = 1; i < data.length; i++) {
    if (String(data[i][col.serialNumber]) === serial && serial) { rowIdx = i; break; }
  }

  if (rowIdx === -1) {
    var fresh = header.map(function (h) {
      if (h === 'firstSeen') return now;
      if (h === 'runCount') return 1;
      return (h in rowValues) ? rowValues[h] : '';
    });
    sh.appendRow(fresh);
  } else {
    var existing = data[rowIdx];
    existing[col.runCount] = (Number(existing[col.runCount]) || 0) + 1;
    Object.keys(rowValues).forEach(function (k) {
      if (k in col) existing[col[k]] = rowValues[k];
    });
    sh.getRange(rowIdx + 1, 1, 1, header.length).setValues([existing]);
  }
}

/**
 * The relay. Walks the delta's opened/resolved events and fires Slack on the
 * gated transitions, deduped against the incident store (so a redelivered
 * delta can't double-alert, and we can send a clean "resolved" note).
 *
 * Severity routing mirrors the readiness class carried on each event:
 *   blocker (route=alert)  → Slack now, with ALERT_MENTION
 *   risk    (route=digest) → Slack now, quiet (no mention)
 *   info    (route=log)    → never messaged
 * Returns the number of Slack messages sent.
 */
function routeDelta_(body, props) {
  var delta = body.delta;
  if (!delta) return 0; // startup/periodic beacons with no transitions

  var webhook = props.getProperty('SLACK_WEBHOOK_URL');
  var mention = props.getProperty('ALERT_MENTION') || '';
  var store = sheet_(INCIDENT_SHEET, INCIDENT_HEADERS);
  var open = readIncidents_(store); // fingerprint -> {rowIdx, ...}
  var sent = 0;

  (delta.opened || []).forEach(function (ev) {
    if (ev.route === 'log') return;                 // info: never alert
    if (open[ev.fingerprint]) return;               // already open: dedup
    var pre = (ev.route === 'alert') ? (mention + ' ') : '';
    if (webhook && notifySlack_(webhook, openedMessage_(body, ev, pre))) sent++;
    addIncident_(store, body, ev);
  });

  (delta.resolved || []).forEach(function (ev) {
    var rec = open[ev.fingerprint];
    if (!rec) return;                               // wasn't tracked: nothing to clear
    if (ev.route !== 'log' && webhook &&
        notifySlack_(webhook, resolvedMessage_(body, ev))) sent++;
    removeIncident_(store, rec.rowIdx);
  });

  return sent;
}

function openedMessage_(body, ev, prefix) {
  var who = body.vpuName || body.hostname || body.serialNumber || 'A VPU';
  var venue = body.venueId ? (' · venue ' + body.venueId) : '';
  var sev = (ev['class'] === 'blocker') ? ':red_circle: *BLOCKER*' : ':large_yellow_circle: *Risk*';
  return prefix + sev + ' — *' + who + '*' + venue + '\n' +
         '> ' + ev.title + '  `' + ev.code + '`\n' +
         (ev.recommendation ? ('> ' + ev.recommendation + '\n') : '') +
         '> Verdict: *' + (body.delta.status || '?') + '* · opened ' + (ev.since || 'now');
}

function resolvedMessage_(body, ev) {
  var who = body.vpuName || body.hostname || body.serialNumber || 'A VPU';
  return ':white_check_mark: *Resolved* — *' + who + '*\n' +
         '> ' + ev.title + '  `' + ev.code + '`  (verdict now *' + (body.delta.status || '?') + '*)';
}

function notifySlack_(webhook, text) {
  try {
    var resp = UrlFetchApp.fetch(webhook, {
      method: 'post',
      contentType: 'application/json',
      payload: JSON.stringify({ text: text }),
      muteHttpExceptions: true
    });
    return resp.getResponseCode() < 300;
  } catch (err) {
    return false;
  }
}

// ── Incident store helpers (dedup across deliveries + restarts) ─────────────
function readIncidents_(sh) {
  var data = sh.getDataRange().getValues();
  var map = {};
  for (var i = 1; i < data.length; i++) {
    var fp = String(data[i][0]);
    if (fp) map[fp] = { rowIdx: i };
  }
  return map;
}

function addIncident_(sh, body, ev) {
  sh.appendRow([ev.fingerprint, body.serialNumber || '', ev.code, ev['class'],
                ev.title, body.vpuName || '', ev.since || new Date(), new Date()]);
}

function removeIncident_(sh, rowIdx) {
  sh.deleteRow(rowIdx + 1); // +1: sheet rows are 1-based and include the header
}

// ── Utilities ───────────────────────────────────────────────────────────────
function sheet_(name, headers) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(name);
  if (!sh) {
    sh = ss.insertSheet(name);
    sh.appendRow(headers);
  }
  return sh;
}

function jsonOut_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

// ── One-time setup + manual test (run from the Apps Script editor) ──────────
function setup() {
  sheet_(LEDGER_SHEET, LEDGER_HEADERS);
  sheet_(INCIDENT_SHEET, INCIDENT_HEADERS);
  var p = PropertiesService.getScriptProperties();
  if (!p.getProperty('CHECKIN_SECRET')) p.setProperty('CHECKIN_SECRET', 'PASTE_SECRET');
  if (!p.getProperty('SLACK_WEBHOOK_URL')) p.setProperty('SLACK_WEBHOOK_URL', 'PASTE_WEBHOOK');
  if (!p.getProperty('ALERT_MENTION')) p.setProperty('ALERT_MENTION', '<!here>');
}

function testSlack() {
  var p = PropertiesService.getScriptProperties();
  notifySlack_(p.getProperty('SLACK_WEBHOOK_URL'),
    ':information_source: Pulse relay test — if you see this, the webhook works.');
}
