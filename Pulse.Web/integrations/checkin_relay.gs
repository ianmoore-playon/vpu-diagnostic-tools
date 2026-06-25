/**
 * Pulse check-in relay — Apps Script bound to the "Pulse VPU Run Log" Sheet
 * (playonsports.com Workspace account). PULSEDEV-53/54.
 * ============================================================================
 * This is the DEPLOYED script the VPUs POST to (main.py `_CHECKIN_URL` /
 * `_send_checkin`). Two responsibilities:
 *
 *   1. "Runs" tab  — upsert one row per VPU (first/last seen, run count, latest
 *      identity + version/channel). Keyed by `Key` = serialNumber.
 *   2. "Fleet Status" tab — append one row per readiness transition
 *      (opened/resolved) carried in the beacon's `delta`. Only state-change
 *      beacons carry transitions, so this tab stays a clean changelog.
 *
 * Tabs + headers (must match exactly):
 *   Runs:         Key | First Seen | Last Seen | Run Count | Hostname | Serial |
 *                 Venue ID | VPU Name | Model | Last Version | Last Channel
 *   Fleet Status: Timestamp | VPU Name | Hostname | Serial | Venue ID |
 *                 Transition | Code | Class | Title | Verdict | Recommendation |
 *                 Fingerprint
 *
 * Deploy: Deploy -> New deployment -> Web app, Execute as = Me, Who has access =
 * Anyone. The resulting /exec URL goes in main.py `_CHECKIN_URL`. The Workspace
 * org must permit anonymous web-app access (the VPU POST is unauthenticated,
 * authed only by the shared SECRET in the body).
 *
 * Optional Slack alerting is at the bottom (disabled until wired) — see
 * "OPTIONAL: Slack alerting".
 */

const SHEET_NAME = 'Runs';
const FLEET_SHEET_NAME = 'Fleet Status';
const SECRET = '7a161bad7765fc5078b8375007999160c5687bf5da52ae1ca717ebbad628e648';   // must match Pulse's PULSE_CHECKIN_SECRET

const FLEET_HEADERS = ['Timestamp', 'VPU Name', 'Hostname', 'Serial', 'Venue ID',
                       'Transition', 'Code', 'Class', 'Title', 'Verdict',
                       'Recommendation', 'Fingerprint'];

function doPost(e) {
  const lock = LockService.getScriptLock();
  try {
    lock.waitLock(30000);   // serialize check-ins so the upsert read-modify-write can't race
    const b = JSON.parse(e.postData.contents);
    if (b.secret !== SECRET) return json({ ok: false, error: 'unauthorized' });

    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
    const now = new Date();
    // Stable unit key: serial first, then venueId|hostname as fallback.
    const key = (b.serialNumber || b.venueId || b.hostname || 'unknown').toString().trim();

    const data = sheet.getDataRange().getValues();
    const header = data[0];
    const col = (name) => header.indexOf(name);   // 0-based
    let rowIndex = -1;
    for (let i = 1; i < data.length; i++) {
      if ((data[i][col('Key')] || '').toString().trim() === key) { rowIndex = i + 1; break; }
    }

    if (rowIndex === -1) {
      sheet.appendRow([ key, now, now, 1,
        b.hostname || '', b.serialNumber || '', b.venueId || '',
        b.vpuName || '', b.model || '', b.pulseVersion || '', b.channel || '' ]);
    } else {
      const prev = sheet.getRange(rowIndex, col('Run Count') + 1).getValue() || 0;
      sheet.getRange(rowIndex, col('Last Seen')   + 1).setValue(now);
      sheet.getRange(rowIndex, col('Run Count')   + 1).setValue(prev + 1);
      sheet.getRange(rowIndex, col('Last Version')+ 1).setValue(b.pulseVersion || '');
      sheet.getRange(rowIndex, col('Last Channel')+ 1).setValue(b.channel || '');
      // refresh the descriptive fields in case they changed
      sheet.getRange(rowIndex, col('Hostname') + 1).setValue(b.hostname || '');
      sheet.getRange(rowIndex, col('VPU Name') + 1).setValue(b.vpuName || '');
    }

    logStatusChanges(b, now);   // append opened/resolved transitions to Fleet Status
    // routeToSlack(b);         // <- uncomment after wiring Slack (see bottom)
    return json({ ok: true });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

// Append one row per opened/resolved finding to the Fleet Status tab. Only the
// loop's state-change beacons carry transitions, so this tab stays a clean
// changelog -- steady-state and startup check-ins add nothing here.
function logStatusChanges(b, now) {
  const delta = b && b.delta;
  if (!delta) return;

  // Skip info-class transitions (route === 'log'). Info findings are chronic and
  // flappy (e.g. cpu-elevated crossing 75%); logging them here buries the
  // actionable blocker/risk changes. They still appear in the VPU's own server
  // log -- Fleet Status stays an actionable changelog.
  const events = []
    .concat((delta.opened || []).map((ev) => ({ ev: ev, transition: 'opened' })))
    .concat((delta.resolved || []).map((ev) => ({ ev: ev, transition: 'resolved' })))
    .filter((x) => x.ev.route !== 'log');
  if (!events.length) return;

  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(FLEET_SHEET_NAME);
  if (!sheet) sheet = ss.insertSheet(FLEET_SHEET_NAME);
  if (sheet.getLastRow() === 0) sheet.appendRow(FLEET_HEADERS);   // self-heal header

  const rowFor = (ev, transition) => [
    now, b.vpuName || '', b.hostname || '', b.serialNumber || '', b.venueId || '',
    transition, ev.code || '', ev['class'] || '', ev.title || '',
    delta.status || '', ev.recommendation || '', ev.fingerprint || ''
  ];

  const rows = events.map((x) => rowFor(x.ev, x.transition));
  sheet.getRange(sheet.getLastRow() + 1, 1, rows.length, FLEET_HEADERS.length).setValues(rows);
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/* ============================================================================
 * OPTIONAL: Slack alerting (PULSEDEV-54) — not active until you do all three:
 *   1. Create a Slack incoming webhook; put its URL in Script Properties as
 *      SLACK_WEBHOOK_URL (Project Settings -> Script properties). Optional:
 *      ALERT_MENTION (e.g. "<!here>") prepended to blocker alerts.
 *   2. Uncomment the `routeToSlack(b);` line in doPost above.
 *   3. Redeploy a new version.
 *
 * Routing mirrors the readiness class on each event: blocker -> alert (mention),
 * risk -> quiet, info -> nothing. Dedup is implicit: the VPU only sends a code
 * on its open/resolve transition, so each fires at most once per state change.
 * Transport-agnostic — the same delta graduates to OneUptime later.
 * ==========================================================================*/
function routeToSlack(b) {
  const delta = b && b.delta;
  if (!delta) return;
  const props = PropertiesService.getScriptProperties();
  const webhook = props.getProperty('SLACK_WEBHOOK_URL');
  if (!webhook) return;                       // not configured -> stay silent
  const mention = props.getProperty('ALERT_MENTION') || '';
  const who = b.vpuName || b.hostname || b.serialNumber || 'A VPU';

  (delta.opened || []).forEach((ev) => {
    if (ev.route === 'log') return;           // info: never alert
    const pre = (ev['class'] === 'blocker') ? (mention + ' :red_circle: *BLOCKER* ')
                                            : ':large_yellow_circle: *Risk* ';
    postSlack(webhook, pre + '— *' + who + '*\n> ' + ev.title + '  `' + ev.code + '`\n'
              + (ev.recommendation ? ('> ' + ev.recommendation + '\n') : '')
              + '> Verdict: *' + (delta.status || '?') + '*');
  });
  (delta.resolved || []).forEach((ev) => {
    if (ev.route === 'log') return;
    postSlack(webhook, ':white_check_mark: *Resolved* — *' + who + '*\n> '
              + ev.title + '  `' + ev.code + '`  (verdict now *' + (delta.status || '?') + '*)');
  });
}

function postSlack(webhook, text) {
  try {
    UrlFetchApp.fetch(webhook, {
      method: 'post', contentType: 'application/json',
      payload: JSON.stringify({ text: text }), muteHttpExceptions: true
    });
  } catch (err) { /* fail-open: never break the check-in over a Slack hiccup */ }
}
