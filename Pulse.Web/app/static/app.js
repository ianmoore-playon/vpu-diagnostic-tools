/* Pulse Web — Vanilla JS SPA */

// ── Icons (Feather-style inline SVGs) ────────────────────────
function svgIcon(name, size) {
  const s = size || 16;
  const p = {
    grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    wifi: '<path d="M5 12.55a11 11 0 0 1 14.08 0"/><path d="M1.42 9a16 16 0 0 1 21.16 0"/><path d="M8.53 16.11a6 6 0 0 1 6.95 0"/><circle cx="12" cy="20" r="1"/>',
    camera: '<path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/>',
    monitor: '<rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/>',
    cpu: '<rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><line x1="9" y1="1" x2="9" y2="4"/><line x1="15" y1="1" x2="15" y2="4"/><line x1="9" y1="20" x2="9" y2="23"/><line x1="15" y1="20" x2="15" y2="23"/><line x1="20" y1="9" x2="23" y2="9"/><line x1="20" y1="14" x2="23" y2="14"/><line x1="1" y1="9" x2="4" y2="9"/><line x1="1" y1="14" x2="4" y2="14"/>',
    server: '<rect x="2" y="2" width="20" height="8" rx="2"/><rect x="2" y="14" width="20" height="8" rx="2"/><circle cx="6" cy="6" r="1"/><circle cx="6" cy="18" r="1"/>',
    hdd: '<line x1="22" y1="12" x2="2" y2="12"/><path d="M5.45 5.11L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
    triangle: '<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>',
    file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/>',
    cog: '<circle cx="12" cy="12" r="3"/><path d="M12 1v2m0 18v2M4.22 4.22l1.42 1.42m12.72 12.72l1.42 1.42M1 12h2m18 0h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/>',
    info: '<circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/>',
    play: '<circle cx="12" cy="12" r="10"/><polygon points="10 8 16 12 10 16 10 8"/>',
    download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>',
    refresh: '<polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>',
    check: '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/>',
    chevron: '<polyline points="9 18 15 12 9 6"/>',
    x: '<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>',
    alert: '<circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>',
    heartbeat: '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
    zap: '<polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>',
    thermometer: '<path d="M14 14.76V3.5a2.5 2.5 0 0 0-5 0v11.26a4.5 4.5 0 1 0 5 0z"/>',
    clock: '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
    globe: '<circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>',
    link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
    database: '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>',
    mic: '<path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/>',
    volume: '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>',
    "volume-x": '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><line x1="23" y1="9" x2="17" y2="15"/><line x1="17" y1="9" x2="23" y2="15"/>',
  };
  return `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${p[name] || ""}</svg>`;
}

// ── Pages & Nav Sections ─────────────────────────────────────
const NAV_SECTIONS = [
  { label: "TRIAGE", pages: [
    { id: "dashboard", label: "Dashboard", icon: "grid" },
  ]},
  { label: "CONNECTIVITY", pages: [
    { id: "network", label: "Network", icon: "wifi" },
    { id: "cameras", label: "Camera Connectivity", icon: "camera" },
    { id: "scoreconnect", label: "Score Connect", icon: "monitor" },
    { id: "audio", label: "Audio", icon: "mic" },
  ]},
  { label: "SYSTEM", pages: [
    { id: "system", label: "System Overview", icon: "cpu" },
    { id: "services", label: "Pixellot Services", icon: "server" },
    { id: "disk-health", label: "Disk & System Health", icon: "hdd" },
    { id: "events", label: "Event Viewer", icon: "triangle" },
  ]},
  { label: "EVIDENCE", pages: [
    { id: "reports", label: "Reports", icon: "file" },
  ]},
  { label: "SETUP", pages: [
    { id: "settings", label: "Settings", icon: "cog" },
    { id: "about", label: "About", icon: "info" },
  ]},
];
const PAGES = NAV_SECTIONS.flatMap((s) => s.pages);
// Hidden pages (accessible via hash but not in nav)
const HIDDEN_PAGES = [{ id: "fault-isolator", label: "Fault Isolator" }];

let currentPage = "";
let ws = null;
let wsRetryTimer = null;
let dataCache = {};
let logEntries = [];
let logPaneOpen = false;
let fetchingKeys = new Set();
let fetchPromises = {};

const PAGE_API = {
  dashboard: "/api/dashboard",
  system: "/api/system",
  network: "/api/network",
  cameras: "/api/cameras",
  services: "/api/services",
  "disk-health": "/api/disk-health",
  events: "/api/events",
  audio: "/api/audio",
  scoreconnect: "/api/scoreconnect",
  settings: "/api/settings",
};

// ── Router ───────────────────────────────────────────────────

function navigate(id) {
  if (id === currentPage) return;
  // Abort any in-flight fault-isolator poll when navigating away.
  if (currentPage === "fault-isolator" && _fi) _fi._aborted = true;
  currentPage = id;
  window.location.hash = id;
  updateNav();
  renderPage(id);
}

function updateNav() {
  document.querySelectorAll(".nav-item").forEach((el) => {
    el.classList.toggle("active", el.dataset.page === currentPage);
  });
}

function renderPage(id) {
  const fn = pageRenderers[id];
  if (!fn) { $page().innerHTML = `<p class="text-pulse-muted">Unknown page: ${esc(id)}</p>`; return; }
  try {
    fn();
  } catch (err) {
    console.error("Render error on", id, err);
    $page().innerHTML = `<div class="card"><p class="text-red-400 font-bold">Render Error</p>
      <pre class="text-xs text-pulse-muted mt-2" style="white-space:pre-wrap">${esc(err.message)}\n${esc(err.stack || "")}</pre>
      <button class="btn-outline btn-ol-blue mt-3" onclick="refreshAll()">Retry</button></div>`;
  }
}

// ── Helpers ──────────────────────────────────────────────────

const $page = () => document.getElementById("page");

async function api(path) {
  try {
    const r = await fetch(path);
    return await r.json();
  } catch (e) {
    return { error: true, message: e.message };
  }
}

async function apiPost(path, body) {
  try {
    const r = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return await r.json();
  } catch (e) {
    return { error: true, message: e.message };
  }
}

function esc(s) {
  if (s == null) return "";
  const d = document.createElement("div");
  d.textContent = String(s);
  return d.innerHTML;
}

function badge(text, type) {
  return `<span class="inline-block px-2 py-0.5 rounded text-xs font-medium badge-${esc(type)}">${esc(text)}</span>`;
}

function statusBadge(status) {
  const s = (status || "").toLowerCase();
  const cap = (status || "").charAt(0).toUpperCase() + (status || "").slice(1);
  if (s === "running" || s === "up" || s === "pass" || s === "ok" || s === "healthy")
    return badge(cap, "pass");
  if (s === "stopped" || s === "down" || s === "fail" || s === "critical")
    return badge(cap, "fail");
  if (s === "warning" || s === "warn" || s === "degraded")
    return badge(cap, "warn");
  if (s === "notfound") return badge("Not Found", "muted");
  return badge(cap || "Unknown", "muted");
}

function loading() {
  return `<div class="flex items-center gap-3 text-pulse-muted loading-pulse py-12 justify-center">
    <svg class="w-5 h-5 animate-spin" viewBox="0 0 24 24" fill="none">
      <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3" opacity="0.3"/>
      <path d="M12 2a10 10 0 0 1 10 10" stroke="currentColor" stroke-width="3" stroke-linecap="round"/>
    </svg>
    Loading...
  </div>`;
}

function card(title, body, extra) {
  return `<div class="card ${extra || ""}">
    ${title ? `<h3 class="text-sm font-semibold text-pulse-muted uppercase tracking-wide mb-3">${esc(title)}</h3>` : ""}
    ${body}
  </div>`;
}

function errorBox(msg) {
  return card(
    "",
    `<p class="text-red-400">${esc(msg || "Failed to load data. Is this running on a Windows VPU?")}</p>`
  );
}

function usageBar(pct, color) {
  const c =
    pct > 90
      ? "var(--c-accent-red)"
      : pct > 75
        ? "var(--c-accent-amber)"
        : color || "var(--c-accent-blue)";
  return `<div class="usage-bar-bg"><div class="usage-bar-fill" style="width:${Math.min(pct, 100)}%;background:${c}"></div></div>`;
}

// ── Circular Gauge ───────────────────────────────────────────

function gauge(label, value, unit, color, opts) {
  const o = opts || {};
  const maxVal = o.max || 100;
  const pct = Math.min(Math.max((value || 0) / maxVal * 100, 0), 100);
  const r = 40;
  const circ = 2 * Math.PI * r;
  const offset = circ * (1 - pct / 100);
  const warnAt = o.warn || 75;
  const critAt = o.crit || 90;
  const raw = value || 0;
  const c =
    raw > critAt
      ? "var(--c-accent-red)"
      : raw > warnAt
        ? "var(--c-accent-amber)"
        : color || "var(--c-accent-blue)";
  return `<div class="flex flex-col items-center gap-2">
    <div class="relative" style="width:7rem;height:7rem">
      <svg viewBox="0 0 100 100" class="w-full h-full">
        <circle cx="50" cy="50" r="${r}" stroke="var(--c-border)" stroke-width="8" fill="none"/>
        <circle cx="50" cy="50" r="${r}" stroke="${c}" stroke-width="8" fill="none"
          stroke-dasharray="${circ}" stroke-dashoffset="${offset}"
          stroke-linecap="round" transform="rotate(-90 50 50)" class="gauge-ring"/>
      </svg>
      <div class="absolute inset-0 flex items-center justify-center">
        <span class="text-xl font-bold"><span class="gauge-val">${value != null ? esc(String(value)) : "--"}</span><span class="text-xs text-pulse-muted">${esc(unit || "%")}</span></span>
      </div>
    </div>
    <span class="text-xs text-pulse-muted font-medium">${esc(label)}</span>
  </div>`;
}

// ── Data Preload (progressive) ──────────────────────────────

// Sections whose data feeds the dashboard cards (NIC table, gauges, services, etc.).
// Used by fetchSection to avoid unnecessary dashboard re-renders during preload.
const DASHBOARD_DEPENDENCIES = new Set([
  "dashboard", "cameras", "system", "disk-health", "services",
]);

function fetchSection(key) {
  if (dataCache[key]) return Promise.resolve(dataCache[key]);
  // Return the existing in-flight promise so multiple callers wait for the same request
  if (fetchPromises[key]) return fetchPromises[key];
  const url = PAGE_API[key];
  if (!url) return Promise.resolve(null);
  fetchingKeys.add(key);
  fetchPromises[key] = api(url).then((data) => {
    fetchingKeys.delete(key);
    delete fetchPromises[key];
    // Cache ALL responses including errors. Without this, a renderer that
    // doesn't find cached data falls back to `fetchSection()` which re-fires
    // the request, the API returns an error again, and the re-render loop
    // spins at ~140ms intervals (each renderPage → renderAudio → fetchSection).
    // Renderers check `data.error` themselves and show errorBox.
    if (data) {
      dataCache[key] = data;
    }
    // Re-render the current page only when the completed fetch is relevant to it.
    // For dashboard, only its own deps trigger a refresh — non-dashboard data
    // (events, audio, scoreconnect, etc.) doesn't change anything visible.
    const shouldRender = currentPage === key
      || (currentPage === "dashboard" && DASHBOARD_DEPENDENCIES.has(key));
    if (shouldRender) renderPage(currentPage);
    return data;
  });
  return fetchPromises[key];
}

// ── Splash status helpers ──────────────────────────────────────────────
// Three independently-updatable lines: verb (Loading/Running diagnostics),
// section (the human-readable name of the panel currently being fetched),
// and percentage (animated via tabular-nums so digits don't jiggle).
//
// The section label uses the friendly nav title (e.g. "Disk & System
// Health") rather than the API key (e.g. "disk-health") — we build the
// lookup from NAV_SECTIONS on first use so it stays in sync with the
// sidebar even if labels change later.
let _SECTION_LABELS_CACHE = null;
function _sectionLabels() {
  if (_SECTION_LABELS_CACHE) return _SECTION_LABELS_CACHE;
  const map = {};
  NAV_SECTIONS.forEach((s) => s.pages.forEach((p) => { map[p.id] = p.label; }));
  HIDDEN_PAGES.forEach((p) => { map[p.id] = p.label; });
  _SECTION_LABELS_CACHE = map;
  return map;
}

function _setSplashVerb(text) {
  const el = document.getElementById("splash-verb");
  if (el) el.textContent = text;
}

function _setSplashSection(key) {
  const el = document.getElementById("splash-section");
  if (!el) return;
  // Empty/blank → keep the row reserved (non-breaking space) so layout
  // doesn't bounce when the splash first appears.
  if (!key) { el.innerHTML = "&nbsp;"; return; }
  const label = _sectionLabels()[key] || key.charAt(0).toUpperCase() + key.slice(1);
  el.textContent = label;
}

let _splashPctAnim = null;
function _setSplashPct(targetPct) {
  const el = document.getElementById("splash-pct");
  const fill = document.getElementById("splash-progress-fill");
  if (!el && !fill) return;
  const clamped = Math.max(0, Math.min(100, targetPct));
  if (fill) fill.style.width = clamped + "%";
  if (!el) return;
  // Smoothly tween the displayed number from current → target over ~350ms
  // so the percentage feels like it's growing instead of jumping.
  if (_splashPctAnim) cancelAnimationFrame(_splashPctAnim);
  const start = parseInt(el.textContent, 10) || 0;
  const startTs = performance.now();
  const duration = 350;
  const step = (ts) => {
    const t = Math.min(1, (ts - startTs) / duration);
    const v = Math.round(start + (clamped - start) * t);
    el.textContent = v + "%";
    if (t < 1) _splashPctAnim = requestAnimationFrame(step);
    else _splashPctAnim = null;
  };
  _splashPctAnim = requestAnimationFrame(step);
}

function showSplash(verbText) {
  const splash = document.getElementById("splash");
  if (!splash) return;
  _setSplashVerb(verbText || "Loading diagnostics…");
  _setSplashSection(null);
  _setSplashPct(0);
  splash.classList.remove("splash-hidden");
}

function hideSplash() {
  const splash = document.getElementById("splash");
  if (!splash) return;
  _setSplashSection(null);
  _setSplashPct(100);
  _setSplashVerb("Ready");
  splash.classList.add("splash-hidden");
}

function preloadProgressive(opts) {
  // Returns a Promise that resolves when EVERY preload section has settled.
  // The splash screen waits on this so users see the loading state until
  // every PowerShell-backed endpoint has at least had one chance to respond.
  //
  // Phasing (preserved from earlier impl to avoid CPU saturation on VPU):
  //   1. Dashboard first (the visible page).
  //   2. WS connect once dashboard returns (enables live metrics).
  //   3. Remaining PAGE_API sections in stagger, 300ms apart.
  //   4. Version + log endpoints in parallel.
  const o = opts || {};
  const verb = o.verb || "Loading diagnostics";
  const deferred = Object.keys(PAGE_API).filter((k) => k !== "dashboard");
  const totalSections = 1 + deferred.length;   // dashboard + deferred
  let completedSections = 0;
  const tick = (key) => {
    completedSections++;
    _setSplashSection(key);
    _setSplashPct((completedSections / totalSections) * 100);
  };

  _setSplashVerb(`${verb}…`);
  _setSplashSection(null);
  _setSplashPct(0);

  // Phase 4 helpers — run in parallel, not gated on dashboard
  const versionPromise = api("/api/version").then((data) => {
    if (data?.version) {
      dataCache._version = data.version;
      const footer = document.querySelector(".sidebar-footer");
      if (footer) footer.textContent = data.version;
      if (currentPage === "about") renderPage("about");
    }
  });
  const logsPromise = api("/api/logs").then((logData) => {
    if (logData && !logData.error) {
      appendLogs(logData.logs || []);
      if (logData.demoMode) {
        document.getElementById("demo-banner")?.classList.remove("hidden");
      }
    }
  });

  // Phase 1: dashboard
  const dashboardPromise = fetchSection("dashboard").then((res) => {
    tick("dashboard");
    // Phase 2: WebSocket after dashboard
    connectWS();
    return res;
  });

  // Phase 3: stagger the rest
  const deferredPromises = deferred.map((key, i) => new Promise((resolve) => {
    setTimeout(() => {
      fetchSection(key).then((res) => { tick(key); resolve(res); });
    }, 500 + i * 300);
  }));

  // Resolve when ALL preload work has finished (or errored — we use
  // allSettled so a single failing endpoint doesn't trap the splash).
  return Promise.allSettled([
    dashboardPromise, versionPromise, logsPromise, ...deferredPromises,
  ]);
}

async function refreshAll() {
  // Full re-run: clear caches, drop the live WS, then re-show the splash
  // and gate it on a fresh preload — exactly like a cold start. The user
  // explicitly asked for this on "Run All Diagnostics" so they see the
  // same branded progress UI as on first launch.
  dataCache = {};
  fetchingKeys.clear();
  fetchPromises = {};
  if (ws && ws.readyState <= 1) { try { ws.close(); } catch {} }
  showSplash("Running diagnostics");
  renderPage(currentPage);
  const preloadPromise = preloadProgressive({ verb: "Running diagnostics" });
  const safetyTimeout = new Promise((resolve) => setTimeout(resolve, 60000));
  Promise.race([preloadPromise, safetyTimeout]).then(hideSplash);
}

async function refreshSection(key) {
  dataCache[key] = null;
  fetchingKeys.delete(key);
  delete fetchPromises[key];
  renderPage(currentPage);
  fetchSection(key);
}

function cancelAll() {
  apiPost("/api/scripts/cancel-all", {});
}

function cached(key) {
  return dataCache[key] || null;
}

function sectionLoading(label) {
  const isFetching = fetchingKeys.size > 0;
  return `<div class="section-loading">
    <div class="section-loading-inner">
      <svg class="w-5 h-5 animate-spin" viewBox="0 0 24 24" fill="none">
        <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3" opacity="0.3"/>
        <path d="M12 2a10 10 0 0 1 10 10" stroke="currentColor" stroke-width="3" stroke-linecap="round"/>
      </svg>
      <span>Loading ${esc(label)}...</span>
      ${isFetching ? `<button class="btn-cancel" onclick="cancelAll()">Cancel</button>` : ""}
    </div>
  </div>`;
}

// ── Logging Pane ────────────────────────────────────────────

let activeLogTab = "script";

function _logEmptyState(message) {
  return `<div class="log-empty">${esc(message)}</div>`;
}

function renderLogPane() {
  const pane = document.getElementById("log-pane");
  if (!pane) return;
  const body = pane.querySelector('[data-log-body="script"]');
  if (!body) return;
  const entries = logEntries.slice(-200);
  if (!entries.length) {
    body.innerHTML = _logEmptyState("Waiting for diagnostic activity… script calls will appear here.");
    return;
  }
  body.innerHTML = entries.map((e) => {
    const statusCls = e.status === "ok" ? "log-ok"
      : e.status === "timeout" || e.status === "warn" ? "log-warn"
      : "log-err";
    return `<div class="log-entry">
      <span class="log-ts">${esc(e.ts?.split("T")[1] || "")}</span>
      <span class="log-script">${esc(e.script)}</span>
      <span class="log-dur">${e.durationMs != null ? e.durationMs + "ms" : ""}</span>
      <span class="log-size">${e.bytes > 0 ? formatBytes(e.bytes) : ""}</span>
      <span class="log-status ${statusCls}">${esc(e.status)}</span>
      <span class="log-detail">${esc(e.detail)}</span>
    </div>`;
  }).join("");
  body.scrollTop = body.scrollHeight;
}

function renderServerLog(lines) {
  const pane = document.getElementById("log-pane");
  if (!pane) return;
  const body = pane.querySelector('[data-log-body="server"]');
  if (!body) return;
  if (!lines || !lines.length) {
    body.innerHTML = _logEmptyState("Server log empty. The server logs to pulse-server.log on startup and during requests.");
    return;
  }
  body.innerHTML = lines.map((l) =>
    `<div class="log-entry server-log-line">${esc(l)}</div>`
  ).join("");
  body.scrollTop = body.scrollHeight;
}

async function fetchServerLog() {
  const data = await api("/api/server-log?tail=500");
  if (data && !data.error) renderServerLog(data.lines || []);
}

// Periodically refresh the server log while the user is watching it,
// so they see new entries appear without needing to switch tabs or
// re-open the pane. Auto-refresh stops when pane closes or tab changes.
let _serverLogTimer = null;
function _startServerLogPolling() {
  if (_serverLogTimer) return;
  _serverLogTimer = setInterval(() => {
    if (logPaneOpen && activeLogTab === "server") fetchServerLog();
    else _stopServerLogPolling();
  }, 2000);
}
function _stopServerLogPolling() {
  if (_serverLogTimer) { clearInterval(_serverLogTimer); _serverLogTimer = null; }
}

function switchLogTab(tab) {
  activeLogTab = tab;
  // If the pane is collapsed, open it. toggleLogPane() handles the
  // render/fetch for the now-active tab.
  if (!logPaneOpen) { toggleLogPane(); return; }
  const pane = document.getElementById("log-pane");
  if (!pane) return;
  pane.querySelectorAll(".log-tab").forEach((t) =>
    t.classList.toggle("log-tab-active", t.dataset.logTab === tab)
  );
  pane.querySelectorAll("[data-log-body]").forEach((b) =>
    b.classList.toggle("log-body-hidden", b.dataset.logBody !== tab)
  );
  if (tab === "server") { fetchServerLog(); _startServerLogPolling(); }
  else { _stopServerLogPolling(); renderLogPane(); }
}

function appendLogs(newLogs) {
  if (!newLogs?.length) return;
  logEntries.push(...newLogs);
  if (logEntries.length > 500) logEntries = logEntries.slice(-500);
  if (logPaneOpen && activeLogTab === "script") renderLogPane();
}

function toggleLogPane() {
  logPaneOpen = !logPaneOpen;
  const pane = document.getElementById("log-pane");
  if (!pane) return;
  pane.classList.toggle("log-pane-open", logPaneOpen);
  // Reflect the active tab visually whenever we open — useful when a
  // tab click is what triggered the toggle.
  pane.querySelectorAll(".log-tab").forEach((t) =>
    t.classList.toggle("log-tab-active", t.dataset.logTab === activeLogTab)
  );
  pane.querySelectorAll("[data-log-body]").forEach((b) =>
    b.classList.toggle("log-body-hidden", b.dataset.logBody !== activeLogTab)
  );
  if (logPaneOpen) {
    if (activeLogTab === "script") renderLogPane();
    else { fetchServerLog(); _startServerLogPolling(); }
  } else {
    _stopServerLogPolling();
  }
}

function openServerLog() {
  activeLogTab = "server";
  if (!logPaneOpen) toggleLogPane();
  else switchLogTab("server");
}

function _updateThemeToggle() {
  const btn = document.getElementById("theme-toggle");
  if (!btn) return;
  const isDark = document.documentElement.classList.contains("dark");
  btn.innerHTML = isDark
    ? `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg> Light mode`
    : `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg> Dark mode`;
}

function toggleTheme() {
  const isDark = document.documentElement.classList.toggle("dark");
  localStorage.setItem("pulse-theme", isDark ? "dark" : "light");
  _updateThemeToggle();
}

// ── WebSocket ────────────────────────────────────────────────

function connectWS() {
  if (ws && ws.readyState <= 1) return;
  const proto = location.protocol === "https:" ? "wss" : "ws";
  ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.onopen = () => {
    _wsConnected = true;
    if (currentPage === "network" && _liveNetHealth) _renderLiveNetHealth(_liveNetHealth);
  };
  ws.onmessage = (e) => {
    try {
      const msg = JSON.parse(e.data);
      if (msg.type === "metrics") {
        updateLiveMetrics(msg);
        appendLogs(msg.logs);
      }
    } catch { /* ignore parse errors */ }
  };
  ws.onclose = () => {
    _wsConnected = false;
    if (currentPage === "network" && _liveNetHealth) _renderLiveNetHealth(_liveNetHealth);
    clearTimeout(wsRetryTimer);
    wsRetryTimer = setTimeout(connectWS, 5000);
  };
  ws.onerror = () => ws.close();
}

// Latest network health from WebSocket — shared between pages
var _liveNetHealth = null;
var _wsConnected = false;
// Track previous TCP counters to compute deltas (Get-Counter values are cumulative since boot)
var _prevLiveCounters = null;

function updateLiveMetrics(msg) {
  // Store network health regardless of current page
  if (msg.networkHealth && !msg.networkHealth.error) {
    _liveNetHealth = msg.networkHealth;
    if (currentPage === "network") _renderLiveNetHealth(msg.networkHealth);
  }
  if (currentPage !== "dashboard") return;
  const perf = msg.performance || {};
  const cpu = perf.cpu?.usagePercent;
  const mem = perf.memory?.usedPercent;
  const disk = perf.disk?.usedPercent;

  // Update system status gauge SVGs
  _updateGaugeLive("cpu", cpu);
  _updateGaugeLive("mem", mem);
  _updateGaugeLive("disk", disk);
  const liveT = perf.temperature?.celsius;
  _updateGaugeLive("temp", liveT, { max: 100, warn: 65, crit: 85, unit: "°C" });

  // Auto-refresh findings when live metrics diverge from cached snapshot.
  // We match by (category + severity) instead of title strings so this
  // doesn't silently break when finding wording changes in main.py.
  const dash = dataCache["dashboard"];
  if (dash && dash.findings?.length) {
    const hasFinding = (cat, sev) => dash.findings.some(
      (f) => (f.category || "").toLowerCase() === cat && f.severity === sev
    );
    const hadCpuCrit = hasFinding("performance", "critical")
      && dash.findings.some((f) => /cpu/i.test(f.title || ""));
    const hadCpuWarn = hasFinding("performance", "warning")
      && dash.findings.some((f) => /cpu/i.test(f.title || ""));
    const hadTempCrit = hasFinding("hardware", "critical")
      && dash.findings.some((f) => /temp/i.test(f.title || ""));
    const liveTemp = perf.temperature?.celsius;
    const stale =
      (hadCpuCrit && cpu != null && cpu <= 75) ||
      (hadCpuWarn && cpu != null && cpu <= 60) ||
      (hadTempCrit && liveTemp != null && liveTemp <= 85);
    if (stale) refreshSection("dashboard");
  }
}

function _updateGaugeLive(name, val, opts) {
  const col = document.querySelector(`[data-gauge="${name}"]`);
  if (!col) return;
  const o = opts || {};
  const maxVal = o.max || 100;
  const warnAt = o.warn || 75;
  const critAt = o.crit || 90;
  const ring = col.querySelector(".gauge-ring");
  const valEl = col.querySelector(".gauge-val");
  if (ring) {
    const pct = Math.min(Math.max((val || 0) / maxVal * 100, 0), 100);
    const r = 40;
    const circ = 2 * Math.PI * r;
    ring.setAttribute("stroke-dashoffset", String(circ * (1 - pct / 100)));
    const raw = val || 0;
    ring.setAttribute("stroke", raw > critAt ? "var(--c-accent-red)" : raw > warnAt ? "var(--c-accent-amber)" : "var(--c-accent-blue)");
  }
  if (valEl) valEl.textContent = val != null ? Math.round(val) : "--";
}

// ── Page Renderers ───────────────────────────────────────────

const pageRenderers = {
  dashboard: renderDashboard,
  system: renderSystem,
  network: renderNetwork,
  cameras: renderCameras,
  services: renderServices,
  "disk-health": renderDiskHealth,
  events: renderEvents,
  reports: renderReports,
  audio: renderAudio,
  scoreconnect: renderScoreConnect,
  "fault-isolator": renderFaultIsolator,
  settings: renderSettings,
  about: renderAbout,
};

// ── Dashboard ────────────────────────────────────────────────

function _subsystemHealth(findings) {
  // Map each finding category to the subsystem panel that owns it.
  // Each finding lights up exactly ONE panel — no double-flagging.
  const cats = {};
  (findings || []).forEach((f) => {
    const k = (f.category || "").toLowerCase();
    cats[k] = (cats[k] || 0) + 1;
  });
  return [
    { id: "system", label: "System Overview", icon: "cpu",
      health: (cats.system || cats.hardware || cats.performance) ? "Warning" : "Healthy",
      desc: "Hardware, OS, uptime, and Pixellot software." },
    { id: "network", label: "Network", icon: "wifi",
      health: cats.network ? "Warning" : "Healthy",
      desc: "IP, DNS, firewall, and port connectivity." },
    { id: "cameras", label: "Camera Connectivity", icon: "camera",
      health: cats.camera ? "Warning" : "Healthy",
      desc: "NICs, link status, speed, and camera detection." },
    { id: "services", label: "Pixellot Services", icon: "server",
      health: cats.services ? "Warning" : "Healthy",
      desc: "Agent, encoder, watchdog service status." },
    { id: "disk-health", label: "Disk Health", icon: "hdd",
      health: cats.storage ? "Warning" : "Healthy",
      desc: "Free space, SMART health, disk events." },
    { id: "events", label: "Event Viewer", icon: "triangle",
      // Event Viewer surfaces OS errors but doesn't generate findings of its own —
      // its health rolls up from the dashboard, so it stays Healthy here.
      health: "Healthy",
      desc: "Recent OS errors from VPU providers." },
  ];
}

function _healthBadge(h) {
  if (h === "Warning") return `<span class="health-badge health-warn">Warning</span>`;
  if (h === "Evidence ready") return `<span class="health-badge health-info">Evidence ready</span>`;
  return `<span class="health-badge health-ok">Healthy</span>`;
}

function _findingPageFor(cat) {
  const map = { network: "network", camera: "cameras", services: "services", storage: "disk-health", hardware: "system", performance: "dashboard", system: "system" };
  return map[(cat || "").toLowerCase()] || "dashboard";
}

function _metricColor(val) {
  if (val == null) return "var(--c-muted)";
  if (val > 90) return "var(--c-accent-red)";
  if (val > 75) return "var(--c-accent-amber)";
  return "var(--c-accent-green)";
}

var _dashNicRefreshTimer = null;

function _renderNicRows(ports) {
  const rows = [];
  const count = Math.max(4, ports.length);
  // Assign camera numbers to non-OCR ports with detected cameras
  let camNum = 0;
  const roles = [];
  for (let i = 0; i < count; i++) {
    if (i < ports.length) {
      const p = ports[i];
      if (p.isOcr) roles.push("OCR");
      else if (p.isUp && (p.camerasDetected || []).length > 0) roles.push("Camera " + (++camNum));
      else roles.push(null);
    } else {
      roles.push(null);
    }
  }
  for (let i = 0; i < count; i++) {
    if (i < ports.length) {
      const p = ports[i];
      const speed = p.linkSpeedMbps
        ? p.linkSpeedMbps >= 1000 ? (p.linkSpeedMbps / 1000) + " Gbps" : p.linkSpeedMbps + " Mbps"
        : "—";
      let status, cls;
      if (!p.isUp) { status = "Down"; cls = "muted"; }
      else if (p.isDegraded) { status = "Error"; cls = "warn"; }
      else { status = "Linked"; cls = "pass"; }
      const role = roles[i];
      const roleBadge = role ? ` <span class="badge-ol badge-ol-info">${esc(role)}</span>` : "";
      rows.push(`<div class="dash-nic-row">
        <span class="dash-nic-port">Port ${i + 1}</span>
        <span class="dash-nic-name">${esc(p.name)}</span>
        <span class="dash-nic-speed">${p.isUp ? esc(speed) : "—"}</span>
        <span class="dash-nic-badges"><span class="badge-ol badge-ol-${cls}">${esc(status)}</span>${roleBadge}</span>
      </div>`);
    } else {
      rows.push(`<div class="dash-nic-row">
        <span class="dash-nic-port">Port ${i + 1}</span>
        <span class="dash-nic-name" style="color:var(--c-dimmer)">Not detected</span>
        <span class="dash-nic-speed">—</span>
        <span class="dash-nic-badges"><span class="badge-ol badge-ol-muted">—</span></span>
      </div>`);
    }
  }
  return rows.join("");
}

function _renderVolumes(volumes) {
  if (!volumes.length) return '<div class="text-xs text-pulse-muted py-2">No storage data</div>';
  return volumes.map((d) => {
    const pct = d.usedPercent || 0;
    const color = pct > 90 ? "#ef4444" : pct > 80 ? "#eab308" : "#3b82f6";
    const role = d.deviceID === "C:" ? "OS Drive" : "Storage";
    return `<div class="dash-vol-row">
      <div class="dash-vol-top">
        <div class="dash-vol-id">
          <span class="font-semibold font-mono">${esc(d.deviceID)}</span>
          <span class="dash-vol-badge">${esc(role)}</span>
        </div>
        <span class="font-semibold" style="color:${color}">${pct}%</span>
      </div>
      <div class="dash-vol-bottom">
        <div class="dash-vol-bar"><div class="dash-vol-fill" style="width:${Math.min(pct, 100)}%;background:${color}"></div></div>
        <span class="dash-vol-free">${esc(String(d.freeSpaceGB))} free of ${esc(String(d.sizeGB))} GB</span>
      </div>
    </div>`;
  }).join("");
}

function renderDashboard() {
  const dash = cached("dashboard");
  if (!dash) { $page().innerHTML = sectionLoading("Dashboard"); fetchSection("dashboard"); return; }
  if (dash.error) { $page().innerHTML = errorBox(dash.message); return; }

  // Pull from all cached data sources
  const net = cached("network") || {};
  const cam = cached("cameras") || {};
  const diskData = cached("disk-health") || {};
  const svcData = cached("services") || {};
  const sysData = cached("system") || {};

  const id = dash.identity || {};
  const perf = dash.performance || {};
  const findings = dash.findings || [];
  const svcs = (dash.services || svcData)?.services || [];
  const hostname = id.hostname || "VPU";
  const vpuName = id.vpuName;

  const cpu = perf.cpu?.usagePercent;
  const mem = perf.memory?.usedPercent;
  const disk = perf.disk?.usedPercent;
  const temp = perf.temperature?.celsius;

  const warnCount = findings.filter((f) => f.severity === "warning").length;
  const critCount = findings.filter((f) => f.severity === "critical").length;
  const totalFindings = findings.length;
  const sevLabel = critCount > 0 ? `${critCount} Critical` : warnCount > 0 ? `${warnCount} Warnings` : "All Clear";
  const sevColor = critCount > 0 ? "critical" : warnCount > 0 ? "warn" : "ok";

  // Findings are now shown in a single consolidated list in the Command
  // Center. Cap at 10 to keep the panel from sprawling; if more exist,
  // surface a "+N more" hint that drills into the relevant tab.
  const _MAX_FINDINGS_INLINE = 10;
  const visibleFindings = findings.slice(0, _MAX_FINDINGS_INLINE);
  const overflowCount = Math.max(0, findings.length - _MAX_FINDINGS_INLINE);
  const subsystems = _subsystemHealth(findings);
  const now = new Date();
  const timeStr = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });

  // Network config — prefer dashboard-embedded data, fall back to full network cache
  const netCfg = dash.networkConfig || net.config || {};
  const uplinkName = netCfg.uplinkAdapter?.interfaceAlias || "—";
  const ipConfigs = netCfg.ipConfig || netCfg.ipConfigurations || [];
  const uplinkIp = ipConfigs.find((ip) => ip.interfaceAlias === uplinkName);
  const ipAddr = _first(uplinkIp?.ipv4Address) || "—";
  const gw = _first(uplinkIp?.ipv4DefaultGateway) || netCfg.uplinkAdapter?.gateway || "—";
  const dnsRaw = uplinkIp?.dnsServers;
  const dns = dnsRaw ? String(dnsRaw).split(",").map(function(s) { return s.trim(); }).filter(Boolean).join(", ") : "—";
  const ntpSrv = netCfg.ntpSource || "—";
  const internetOk = netCfg.internetReachable;
  const internetFetching = fetchingKeys.has("network");
  const internetLabel = internetOk === true ? "Connected" : internetOk === false ? "Offline" : internetFetching ? "Checking" : "—";
  const internetColor = internetOk === true ? "var(--c-accent-green)" : internetOk === false ? "var(--c-accent-red)" : "var(--c-muted)";

  // Other data
  const nicPorts = cam.ports || [];
  const volumes = diskData.logicalDisks || [];
  const cpuInfo = sysData.hardware?.processors?.[0];
  const cpuName = (cpuInfo?.name || "")
    .replace(/\(R\)/gi, "").replace(/\(TM\)/gi, "")
    .replace(/\s+CPU\s*/i, " ").replace(/\s{2,}/g, " ").trim();
  const memTotalMB = perf.memory?.totalMB;
  const memUsedMB = perf.memory?.usedMB;
  const memCaption = memTotalMB
    ? (memUsedMB != null
        ? (memUsedMB / 1024).toFixed(1) + " / " + (memTotalMB / 1024).toFixed(0) + " GB"
        : (memTotalMB / 1024).toFixed(0) + " GB")
    : "";
  const sysDisk = volumes.find((d) => d.deviceID === "C:") || volumes[0];
  const diskCaption = sysDisk ? `${sysDisk.freeSpaceGB} GB free of ${sysDisk.sizeGB} GB` : "";

  $page().innerHTML = `
    <!-- Header -->
    <div class="dash-header">
      <div>
        <h2 class="text-2xl font-bold text-white">Dashboard</h2>
        ${vpuName ? `<p class="text-sm text-pulse-muted">${esc(vpuName)}</p>` : ""}
      </div>
      <div class="dash-actions">
        <button class="btn-outline btn-ol-green" onclick="refreshAll()">
          ${svgIcon("play", 14)} Run All Diagnostics
        </button>
        <button class="btn-outline btn-ol-blue" onclick="navigate('reports')">
          ${svgIcon("download", 14)} Support Bundle
        </button>
        <button class="btn-outline btn-ol-blue" onclick="dataCache.dashboard=null;renderDashboard()">
          ${svgIcon("refresh", 14)} Refresh Dashboard
        </button>
        <span class="dash-sev-pill dash-sev-${sevColor}">
          <span class="dash-sev-dot"></span> ${esc(sevLabel)}
        </span>
      </div>
    </div>

    <!-- Command Center (left: severity + baseline + top findings) + Subsystems (right) -->
    <div class="dash-top-grid">
      <div class="card command-center">
        <h3 class="card-label">COMMAND CENTER</h3>
        <div class="cc-severity cc-sev-${sevColor}">${esc(sevLabel)}</div>
        <div class="baseline-bar">
          ${svgIcon("check", 14)}
          Baseline completed ${esc(timeStr)} &bull; ${subsystems.length} panel${subsystems.length === 1 ? "" : "s"} checked &bull; ${totalFindings} finding${totalFindings === 1 ? "" : "s"}
        </div>
        <div class="cc-findings">
          <div class="flex justify-between items-center mb-2">
            <h3 class="card-label mb-0">FINDINGS</h3>
            ${totalFindings > 0 ? `<span class="cc-findings-count">${totalFindings} issue${totalFindings === 1 ? "" : "s"}</span>` : ""}
          </div>
          <div class="cc-findings-list">
            ${visibleFindings.length
              ? visibleFindings.map((f) => `
                <a class="finding-item" href="#${esc(_findingPageFor(f.category))}" onclick="event.preventDefault();navigate('${esc(_findingPageFor(f.category))}')">
                  <span class="finding-dot finding-dot-${esc(f.severity)}"></span>
                  <span class="finding-cat">[${esc(f.category)}]</span>
                  <span class="finding-title">${esc(f.title)}</span>
                  <span class="finding-arrow">${svgIcon("chevron", 14)}</span>
                </a>`).join("")
              : `<div class="dash-no-findings">${svgIcon("check", 16)} <span>No active findings detected.</span></div>`
            }
            ${overflowCount > 0 ? `<div class="cc-findings-overflow">+${overflowCount} more — visit the relevant tab for the full list</div>` : ""}
          </div>
        </div>
      </div>
      <div class="card subsystems-panel">
        <h3 class="card-label">SUBSYSTEMS</h3>
        <div class="dash-sub-grid dash-sub-grid-full">
          ${subsystems.map((s) => `
            <a class="dash-sub-tile" href="#${esc(s.id)}" onclick="event.preventDefault();navigate('${esc(s.id)}')">
              <div class="dash-sub-top">
                <span class="dash-sub-icon">${svgIcon(s.icon, 14)}</span>
                <span class="dash-sub-name">${esc(s.label)}</span>
                ${_healthBadge(s.health)}
              </div>
              <p class="dash-sub-desc">${esc(s.desc)}</p>
            </a>`).join("")}
        </div>
      </div>
    </div>

    ${id.isNonVpuHost ? `
    <!-- Non-VPU Host Banner -->
    <div class="dash-info-banner">
      <span class="dash-banner-icon">${svgIcon("info", 20)}</span>
      <div>
        <div class="font-semibold text-sm">Pixellot software not detected</div>
        <div class="text-xs text-pulse-muted mt-1">This host doesn't appear to be a Pixellot VPU — system metrics are still live, but expect blank values for VPU identity, services, and the diagnostic report.</div>
      </div>
    </div>` : ""}

    <!-- VPU Identity + Pixellot Software -->
    <div class="dash-2col">
      <div class="card">
        <h3 class="card-label">VPU IDENTITY</h3>
        ${vpuName ? `<div class="text-sm text-pulse-muted mb-3">${esc(vpuName)}</div>` : ""}
        <div class="dash-kv">
          <span class="dash-kv-l">Model</span><span class="dash-kv-v">${esc(id.model || "—")}</span>
          <span class="dash-kv-l">Hostname</span><span class="dash-kv-v">${esc(hostname)}</span>
          <span class="dash-kv-l">Manufacturer</span><span class="dash-kv-v">${esc(id.manufacturer || "—")}</span>
          <span class="dash-kv-l">Serial</span><span class="dash-kv-v">${esc(id.serialNumber || "—")}</span>
        </div>
      </div>
      <div class="card">
        <h3 class="card-label">PIXELLOT SOFTWARE</h3>
        <div class="text-lg font-bold text-white">${esc(id.pixellotVersion || "—")}</div>
        <div class="text-xs text-pulse-muted mb-3">App Version</div>
        <div class="dash-kv">
          <span class="dash-kv-l">Image Version</span><span class="dash-kv-v">${esc(id.imageVersion || "—")}</span>
          <span class="dash-kv-l">OS</span><span class="dash-kv-v">${esc(id.os || "—")}</span>
        </div>
      </div>
    </div>

    <!-- System Status Gauges -->
    <div class="card dash-gauges-card">
      <h3 class="card-label">SYSTEM STATUS</h3>
      <div class="dash-gauges-row" id="dash-gauges">
        <div class="dash-gauge-col" data-gauge="cpu">
          ${gauge("CPU", cpu != null ? Math.round(cpu) : null, "%")}
          ${cpuInfo ? `<div class="dash-gauge-sub">${esc(cpuName)}</div><div class="dash-gauge-sub">${cpuInfo.numberOfLogicalProcessors || ""} threads</div>` : ""}
        </div>
        <div class="dash-gauge-col" data-gauge="mem">
          ${gauge("Memory", mem != null ? Math.round(mem) : null, "%")}
          <div class="dash-gauge-sub">${esc(memCaption)}</div>
        </div>
        <div class="dash-gauge-col" data-gauge="disk">
          ${gauge("System Disk", disk != null ? Math.round(disk) : null, "%")}
          <div class="dash-gauge-sub">${esc(diskCaption)}</div>
        </div>
        <div class="dash-gauge-col" data-gauge="temp">
          ${gauge("Temperature", temp != null ? Math.round(temp) : null, "°C", "#3b82f6", { max: 100, warn: 65, crit: 85 })}
        </div>
        <div class="dash-gauge-col dash-gauge-col-center">
          <div class="dash-icon-tile">
            <span class="text-blue-400">${svgIcon("clock", 26)}</span>
            <span class="dash-tile-val">${esc(id.uptime || "—")}</span>
          </div>
          <span class="text-xs text-pulse-muted font-medium">Uptime</span>
        </div>
        <div class="dash-gauge-col dash-gauge-col-center">
          <div class="dash-icon-tile">
            <span style="color:${internetColor}">${svgIcon("globe", 26)}</span>
            <span class="dash-tile-val" style="color:${internetColor}">${esc(internetLabel)}</span>
          </div>
          <span class="text-xs text-pulse-muted font-medium">Internet</span>
        </div>
      </div>
    </div>

    <!-- NIC Ports + Network -->
    <div class="dash-2col">
      <div class="card">
        <div class="dash-card-hdr">
          <span class="dash-hdr-icon">${svgIcon("link", 16)}</span>
          <h3 class="card-label mb-0">NETWORK INTERFACE CARD (NIC) CONNECTIONS</h3>
        </div>
        <div class="dash-nic-table" id="dash-nic-table">${_renderNicRows(nicPorts)}</div>
      </div>
      <div class="card">
        <div class="dash-card-hdr">
          <span class="dash-hdr-icon">${svgIcon("wifi", 16)}</span>
          <h3 class="card-label mb-0">NETWORK</h3>
        </div>
        <div class="dash-net-kv">
          <div class="dash-net-row"><span></span><span class="dash-kv-l">Uplink Adapter</span><span class="dash-kv-v">${esc(uplinkName)}</span></div>
          <div class="dash-net-row"><span class="dash-net-dot" style="background:${ipAddr !== "—" ? "var(--c-accent-green)" : "var(--c-dimmer)"}"></span><span class="dash-kv-l">IP Address</span><span class="dash-kv-v font-mono">${esc(ipAddr)}</span></div>
          <div class="dash-net-row"><span class="dash-net-dot" style="background:${gw !== "—" ? "var(--c-accent-green)" : "var(--c-dimmer)"}"></span><span class="dash-kv-l">Gateway</span><span class="dash-kv-v font-mono">${esc(gw)}</span></div>
          <div class="dash-net-row"><span class="dash-net-dot" style="background:${dns !== "—" ? "var(--c-accent-green)" : "var(--c-dimmer)"}"></span><span class="dash-kv-l">DNS Servers</span><span class="dash-kv-v font-mono">${esc(dns)}</span></div>
          <div class="dash-net-row"><span class="dash-net-dot" style="background:${ntpSrv !== "—" ? "var(--c-accent-green)" : "var(--c-dimmer)"}"></span><span class="dash-kv-l">NTP Server</span><span class="dash-kv-v font-mono">${esc(ntpSrv)}</span></div>
        </div>
      </div>
    </div>

    <!-- Storage + Pixellot Services -->
    <div class="dash-2col">
      <div class="card">
        <div class="dash-card-hdr">
          <span class="dash-hdr-icon">${svgIcon("database", 16)}</span>
          <h3 class="card-label mb-0">STORAGE</h3>
        </div>
        ${_renderVolumes(volumes)}
      </div>
      <div class="card">
        <div class="dash-card-hdr">
          <span class="dash-hdr-icon">${svgIcon("server", 16)}</span>
          <h3 class="card-label mb-0">PIXELLOT SERVICES</h3>
        </div>
        <div class="dash-svc-list">
          ${svcs.map((s) => `
            <div class="dash-svc-row">
              <span class="dash-svc-name">${esc(s.displayName || s.name)}</span>
              ${statusBadge(s.status)}
            </div>`).join("")}
          ${!svcs.length ? '<div class="text-xs text-pulse-muted py-2">No services data</div>' : ""}
        </div>
      </div>
    </div>
  `;

  // ── Live NIC refresh: poll /api/cameras every 3s and update NIC table ──
  // Uses an in-flight flag to skip ticks while a previous request is pending,
  // so slow PowerShell on the VPU can't pile up overlapping requests.
  if (_dashNicRefreshTimer) clearInterval(_dashNicRefreshTimer);
  var _nicPollBusy = false;
  _dashNicRefreshTimer = setInterval(function() {
    if (currentPage !== "dashboard") { clearInterval(_dashNicRefreshTimer); _dashNicRefreshTimer = null; return; }
    if (_nicPollBusy) return;
    _nicPollBusy = true;
    api("/api/cameras").then(function(fresh) {
      if (!fresh || fresh.error || currentPage !== "dashboard") return;
      dataCache.cameras = fresh;
      var el = document.getElementById("dash-nic-table");
      if (el) el.innerHTML = _renderNicRows(fresh.ports || []);
    }).catch(function() { /* network blip — skip this tick */ })
      .then(function() { _nicPollBusy = false; });
  }, 3000);
}

function idRow(label, val) {
  return `<div class="flex justify-between"><span class="text-pulse-muted">${esc(label)}</span><span class="font-medium">${val != null ? esc(String(val)) : "--"}</span></div>`;
}

// ── Shared Page Helpers ─────────────────────────────────────

function pageHeader(title, subtitle, actionsHtml) {
  return `<div class="page-header">
    <div>
      <h2 class="page-title">${esc(title)}</h2>
      ${subtitle ? `<p class="page-subtitle">${esc(subtitle)}</p>` : ""}
    </div>
    <div class="page-actions">${actionsHtml || ""}</div>
  </div>`;
}

function sectionTitle(icon, text) {
  return `<div class="section-hdr">
    <span class="section-hdr-icon">${svgIcon(icon, 16)}</span>
    <h3 class="section-hdr-text">${esc(text)}</h3>
  </div>`;
}

function kvRow(label, value) {
  return `<div class="kv-row"><span class="kv-label">${esc(label)}</span><span class="kv-value">${value != null ? esc(String(value)) : "—"}</span></div>`;
}

function kvRowHtml(label, html) {
  return `<div class="kv-row"><span class="kv-label">${esc(label)}</span><span class="kv-value">${html}</span></div>`;
}

function severityChip(sev, text) {
  const s = (sev || "").toLowerCase();
  const cls = s === "critical" || s === "error" ? "sev-chip-crit" : s === "warning" ? "sev-chip-warn" : "sev-chip-ok";
  return `<span class="sev-chip ${cls}">${esc(text || sev)}</span>`;
}

function _debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

// ── System Overview ──────────────────────────────────────────

function renderSystem() {
  const data = cached("system");
  if (!data) { $page().innerHTML = sectionLoading("System Overview"); fetchSection("system"); return; }

  const id = data.identity || {};
  const hw = data.hardware || {};
  const sw = data.software || {};

  if (data.identity?.error && data.hardware?.error) {
    $page().innerHTML = errorBox(data.identity?.message || data.hardware?.message);
    return;
  }

  const os = id.operatingSystem || {};
  const cs = id.computerSystem || {};
  const bios = id.bios || {};
  const pix = id.pixellot || {};
  const procs = hw.processors || [];
  const memory = hw.memory || [];
  const gpus = hw.gpus || [];
  const drives = hw.diskDrives || [];
  const swList = sw.software || [];

  $page().innerHTML = `
    ${pageHeader("System Overview", "Hardware identity, OS, Pixellot software, and installed applications",
      `<button class="btn-outline btn-ol-blue" onclick="dataCache.system=null;renderSystem()">
        ${svgIcon("refresh", 14)} Refresh
      </button>`
    )}

    <!-- Identity + Pixellot Software -->
    <div class="dash-2col">
      <div class="card">
        ${sectionTitle("cpu", "VPU Identity")}
        <div class="kv-grid">
          ${kvRow("Hostname", cs.name)}
          ${kvRow("Manufacturer", cs.manufacturer)}
          ${kvRow("Model", cs.model)}
          ${kvRow("Serial Number", bios.serialNumber)}
          ${kvRow("Uptime", id.uptime?.formatted)}
        </div>
      </div>
      <div class="card">
        ${sectionTitle("server", "Pixellot Software")}
        <div class="kv-grid">
          ${kvRow("App Version", pix.version)}
          ${kvRow("Image Version", pix.imageVersion)}
        </div>
        ${id.isNonVpuHost ? '<div class="info-chip mt-3">Not a VPU host</div>' : ""}
        ${(() => {
          const c = pix.compat;
          if (!c || c.status === "skip") return "";
          let cls = "sys-lifecycle-ok";
          let title = "";
          let detail = "";
          if (c.status === "ok") {
            cls = "sys-lifecycle-ok";
            title = "Version compatible with hardware";
            const capStr = c.maxVersion ? `max ${c.maxVersion}` : "no cap";
            detail = `${esc(c.installedVersion)} on ${esc(c.architecture)} GPU · ${esc(capStr)} · ${esc(c.capReason)}`;
          } else if (c.status === "over") {
            cls = "sys-lifecycle-crit";
            title = "Version exceeds hardware compatibility cap";
            detail = `Installed ${esc(c.installedVersion)} is newer than ${esc(c.maxVersion)} (max for ${esc(c.architecture)}). Downgrade to stay supported.`;
          } else if (c.status === "no-gpu") {
            cls = "sys-lifecycle-crit";
            title = "No NVIDIA GPU detected";
            detail = "Pixellot requires NVIDIA hardware for encoding.";
          } else if (c.status === "anomaly") {
            cls = "sys-lifecycle-crit";
            title = "Unexpected GPU architecture";
            detail = `${esc(c.architecture)} is not a known Pixellot deployment — escalate to support.`;
          }
          return `<div class="sys-lifecycle ${cls} mt-3">
            ${svgIcon(cls === "sys-lifecycle-ok" ? "check" : "alert", 14)}
            <div>
              <div class="font-semibold">${esc(title)}</div>
              <div class="text-xs mt-1">${detail}</div>
            </div>
          </div>`;
        })()}
      </div>
    </div>

    <!-- Processor + Memory -->
    <div class="dash-2col">
      <div class="card">
        ${sectionTitle("cpu", "Processor")}
        ${procs.length ? procs.map(p => `
          <div class="kv-grid">
            ${kvRow("Name", p.name)}
            ${kvRow("Cores", p.numberOfCores)}
            ${kvRow("Logical Processors", p.numberOfLogicalProcessors)}
            ${kvRow("Max Clock", p.maxClockSpeedMHz ? p.maxClockSpeedMHz + " MHz" : null)}
          </div>
        `).join("") : '<p class="text-pulse-muted text-sm">No processor data</p>'}
      </div>
      <div class="card">
        ${sectionTitle("server", "Memory")}
        ${memory.length ? `
          <table class="data-table"><thead><tr>
            <th>Capacity</th><th>Speed</th><th>Type</th><th>Slot</th>
          </tr></thead><tbody>
          ${memory.map(m => `<tr>
            <td>${esc(String(m.capacityGB))} GB</td>
            <td>${m.speedMHz ? esc(String(m.speedMHz)) + " MHz" : "—"}</td>
            <td>${esc(m.memoryType)}</td>
            <td>${esc(m.deviceLocator)}</td>
          </tr>`).join("")}
          </tbody></table>
          ${(() => {
            const totalGb = memory.reduce((s, m) => s + (Number(m.capacityGB) || 0), 0);
            if (totalGb <= 0) return "";
            const formatted = Number.isInteger(totalGb) ? totalGb : totalGb.toFixed(2);
            if (totalGb < 32) {
              return `<div class="sys-mem-warn mt-3">
                ${svgIcon("alert", 14)}
                <span><strong>${esc(String(formatted))} GB installed</strong> — Pixellot VPUs require 32 GB. Encoder workloads may stall or drop frames.</span>
              </div>`;
            }
            return `<div class="text-xs text-pulse-muted mt-2">Total: ${esc(String(formatted))} GB</div>`;
          })()}
        ` : '<p class="text-pulse-muted text-sm">No memory data</p>'}
      </div>
    </div>

    <!-- Graphics + Storage -->
    <div class="dash-2col">
      <div class="card">
        ${sectionTitle("monitor", "Graphics")}
        ${gpus.length ? gpus.map(g => `
          <div class="sub-card mb-2">
            <div class="text-sm font-semibold text-white">${esc(g.name)}</div>
            <div class="text-xs text-pulse-muted mt-1">RAM: ${g.adapterRAMMB ? esc(String(g.adapterRAMMB)) + " MB" : "N/A"} · Driver: ${esc(g.driverVersion)}</div>
          </div>
        `).join("") : '<p class="text-pulse-muted text-sm">No GPU data</p>'}
      </div>
      <div class="card">
        ${sectionTitle("hdd", "Storage")}
        ${drives.length ? `
          <table class="data-table"><thead><tr>
            <th>Model</th><th>Size</th><th>Interface</th><th>Serial</th>
          </tr></thead><tbody>
          ${drives.map(d => `<tr>
            <td>${esc(d.model)}</td>
            <td>${esc(String(d.sizeGB))} GB</td>
            <td>${esc(d.interfaceType)}</td>
            <td class="font-mono text-xs">${esc(d.serialNumber)}</td>
          </tr>`).join("")}
          </tbody></table>
        ` : '<p class="text-pulse-muted text-sm">No drive data</p>'}
      </div>
    </div>

    <!-- OS & Locale -->
    <div class="card mt-4">
      ${sectionTitle("monitor", "Operating System & Locale")}
      <div class="kv-grid kv-grid-wide">
        ${kvRow("OS", os.caption)}
        ${kvRow("Version", os.version)}
        ${kvRow("Build", os.buildNumber)}
        ${kvRow("Architecture", os.osArchitecture)}
        ${kvRow("Install Date", os.installDate)}
        ${kvRow("Timezone", id.timezone)}
        ${kvRow("Locale", id.locale)}
      </div>
      ${(() => {
        const lc = os.lifecycle;
        if (!lc) return "";
        const days = lc.daysToEos;
        let cls = "sys-lifecycle-ok";
        let label = "";
        if (days == null) {
          label = `End-of-support: ${lc.eosDate}`;
        } else if (days < 0) {
          cls = "sys-lifecycle-crit";
          label = `End-of-support reached on ${lc.eosDate} (${Math.abs(days)} days ago)`;
        } else if (days < 90) {
          cls = "sys-lifecycle-crit";
          label = `End-of-support in ${days} days (${lc.eosDate})`;
        } else if (days < 365) {
          cls = "sys-lifecycle-warn";
          const months = Math.floor(days / 30);
          label = `End-of-support in ~${months} months (${lc.eosDate})`;
        } else {
          const years = Math.floor(days / 365);
          label = `End-of-support: ${lc.eosDate} (${years}+ year${years === 1 ? "" : "s"} away)`;
        }
        return `<div class="sys-lifecycle ${cls} mt-3">
          ${svgIcon(cls === "sys-lifecycle-ok" ? "check" : "alert", 14)}
          <div>
            <div class="font-semibold">${esc(lc.ltscRelease)}</div>
            <div class="text-xs mt-1">${esc(label)}${lc.endOfServicingDate ? ` &middot; End-of-servicing: ${esc(lc.endOfServicingDate)}` : ""}</div>
          </div>
        </div>`;
      })()}
    </div>

    <!-- Software Inventory -->
    <div class="card mt-4">
      ${sectionTitle("server", "Software Inventory (" + swList.length + ")")}
      ${(() => {
        // Group concerning entries by severity for the summary banner.
        const flagged = swList.filter(s => s.concern);
        if (!flagged.length) return "";
        const critical = flagged.filter(s => s.concern.severity === "critical");
        const warning  = flagged.filter(s => s.concern.severity === "warning");
        const parts = [];
        if (critical.length) parts.push(`<span class="sw-flag-count sw-flag-critical">${critical.length} critical</span>`);
        if (warning.length)  parts.push(`<span class="sw-flag-count sw-flag-warning">${warning.length} warning</span>`);
        return `<div class="sw-concern-banner">
          ${svgIcon("alert", 14)}
          <span><strong>${flagged.length} concerning entr${flagged.length === 1 ? "y" : "ies"}</strong> ${parts.join(" · ")} — see flagged rows below.</span>
        </div>`;
      })()}
      ${swList.length ? `
        <input type="text" id="sw-filter" placeholder="Filter software..." class="sw-filter-input"/>
        <div class="sw-table-wrap">
          <table class="data-table" id="sw-table"><thead><tr>
            <th>Name</th><th>Version</th><th>Publisher</th><th>Concern</th>
          </tr></thead><tbody>
          ${(() => {
            // Sort concerning entries to the top, critical first
            const sevRank = { critical: 0, warning: 1 };
            const sorted = [...swList].sort((a, b) => {
              const ra = a.concern ? sevRank[a.concern.severity] ?? 9 : 99;
              const rb = b.concern ? sevRank[b.concern.severity] ?? 9 : 99;
              return ra - rb;
            });
            return sorted.map(s => {
              const c = s.concern;
              const rowCls = c ? ` class="sw-row-${esc(c.severity)}"` : "";
              const concernCell = c
                ? `<span class="sw-concern-badge sw-concern-${esc(c.severity)}" title="${esc(c.reason)}">${esc(c.shortLabel || c.label)}</span>`
                : `<span class="text-pulse-muted text-xs">—</span>`;
              return `<tr${rowCls}>
                <td>${esc(s.displayName)}</td>
                <td class="font-mono text-xs">${esc(s.displayVersion)}</td>
                <td class="text-pulse-muted">${esc(s.publisher)}</td>
                <td>${concernCell}</td>
              </tr>`;
            }).join("");
          })()}
          </tbody></table>
        </div>
      ` : '<p class="text-pulse-muted text-sm">No software data</p>'}
    </div>
  `;

  const swFilter = document.getElementById("sw-filter");
  if (swFilter) {
    swFilter.addEventListener("input", () => {
      const q = swFilter.value.toLowerCase();
      document.querySelectorAll("#sw-table tbody tr").forEach(tr => {
        tr.style.display = tr.textContent.toLowerCase().includes(q) ? "" : "none";
      });
    });
  }
}

// ── Network ──────────────────────────────────────────────────

// PS single-element arrays unwrap to bare values — safe first-element accessor
function _first(v) { return Array.isArray(v) ? v[0] : v != null ? String(v) : null; }

// Local ping runner — manages preset and continuous ping modes
var _localPingState = { running: false, continuous: false, abortCtrl: null };

function _renderPingCards(local) {
  var gw = (local || {}).gateway;
  var dns = (local || {}).dns;
  var el = document.getElementById("net-ping-results");
  if (!el) return;
  el.innerHTML = _pingCardHtml(gw) + _pingCardHtml(dns);
}

function _fmtMs(v) {
  if (v == null) return "—";
  if (v === 0) return "< 1 ms";
  if (v < 1) return v.toFixed(2) + " ms";
  if (v < 10) return v.toFixed(1) + " ms";
  return Math.round(v) + " ms";
}

function _pingCardHtml(p) {
  if (!p || !p.target) return "";
  var sc = p.status === "pass" ? "net-ping-pass" : p.status === "warn" ? "net-ping-warn" : "net-ping-fail";
  var dot = p.status === "pass" ? "#22c55e" : p.status === "warn" ? "#eab308" : "#ef4444";
  var latency = _fmtMs(p.avgMs);
  var loss = p.lossPercent != null ? p.lossPercent + "%" : "—";
  var range = (p.minMs != null && p.maxMs != null) ? _fmtMs(p.minMs).replace(" ms","") + " / " + _fmtMs(p.avgMs).replace(" ms","") + " / " + _fmtMs(p.maxMs).replace(" ms","") + " ms" : "—";
  return '<div class="net-ping-card ' + sc + '">' +
    '<div class="net-ping-header">' +
      '<span class="net-ping-dot" style="background:' + dot + '"></span>' +
      '<span class="net-ping-label">' + esc(p.label) + '</span>' +
      '<span class="net-ping-target font-mono">' + esc(p.target) + '</span>' +
    '</div>' +
    '<div class="net-ping-stats">' +
      '<div class="net-ping-stat"><span class="net-ping-stat-label">Latency</span><span class="net-ping-stat-value">' + esc(latency) + '</span></div>' +
      '<div class="net-ping-stat"><span class="net-ping-stat-label">Packet loss</span><span class="net-ping-stat-value">' + esc(loss) + '</span></div>' +
      '<div class="net-ping-stat"><span class="net-ping-stat-label">Min / Avg / Max</span><span class="net-ping-stat-value font-mono">' + esc(range) + '</span></div>' +
      '<div class="net-ping-stat"><span class="net-ping-stat-label">Packets</span><span class="net-ping-stat-value">' + esc(String(p.received || 0)) + ' / ' + esc(String(p.sent || 0)) + ' received</span></div>' +
    '</div>' +
  '</div>';
}

async function runLocalPing(count) {
  // If a run is already in progress, abort it and start a fresh batch with the new count.
  if (_localPingState.running) {
    stopLocalPing();
    // Give the previous abort a tick to settle so we don't race on _localPingState.
    await new Promise(function(r) { setTimeout(r, 30); });
  }
  _localPingState.running = true;
  _localPingState.continuous = (count === 0);
  _localPingState.abortCtrl = new AbortController();
  _updatePingControls();

  var batchSize = _localPingState.continuous ? 4 : count;
  var accum = { gateway: null, dns: null };

  try {
    while (_localPingState.running) {
      var resp = await fetch("/api/network/local-ping?count=" + batchSize, { signal: _localPingState.abortCtrl.signal });
      var data = await resp.json();
      if (!_localPingState.running) break;

      if (!_localPingState.continuous) {
        // One-shot: just show the result
        _renderPingCards(data);
        // Also update the cached data
        if (dataCache.network) dataCache.network.local = data;
        break;
      }

      // Continuous: accumulate stats
      accum = _accumPing(accum, data);
      _renderPingCards(accum);
      if (dataCache.network) dataCache.network.local = accum;
    }
  } catch (e) {
    if (e.name !== "AbortError") console.error("Local ping error:", e);
  }

  _localPingState.running = false;
  _localPingState.continuous = false;
  _localPingState.abortCtrl = null;
  _updatePingControls();
}

function _accumPing(prev, batch) {
  // Gateway should be a local hop (< 10 ms typical); DNS may legitimately be 20–50 ms.
  function merge(old, cur, warnLatencyMs) {
    if (!cur || !cur.target) return old;
    if (!old || !old.target) return cur;
    var sent = (old.sent || 0) + (cur.sent || 0);
    var recv = (old.received || 0) + (cur.received || 0);
    var minMs = (old.minMs != null && cur.minMs != null) ? Math.min(old.minMs, cur.minMs) : (cur.minMs != null ? cur.minMs : old.minMs);
    var maxMs = (old.maxMs != null && cur.maxMs != null) ? Math.max(old.maxMs, cur.maxMs) : (cur.maxMs != null ? cur.maxMs : old.maxMs);
    // Weighted average
    var avgMs = null;
    if (old.avgMs != null && cur.avgMs != null && old.received && cur.received) {
      avgMs = Math.round(((old.avgMs * old.received) + (cur.avgMs * cur.received)) / recv);
    } else if (cur.avgMs != null) { avgMs = cur.avgMs; }
    else { avgMs = old.avgMs; }
    var loss = sent > 0 ? Math.round(((sent - recv) / sent) * 100) : 100;
    var status = recv === 0 ? "fail" : loss > 0 || (avgMs != null && avgMs > warnLatencyMs) ? "warn" : "pass";
    return { target: cur.target, label: cur.label, reachable: recv > 0, sent: sent, received: recv,
             lossPercent: loss, minMs: minMs, avgMs: avgMs, maxMs: maxMs, status: status };
  }
  return {
    gateway: merge(prev.gateway, batch.gateway, 10),
    dns:     merge(prev.dns,     batch.dns,     50),
  };
}

function stopLocalPing() {
  _localPingState.running = false;
  _localPingState.continuous = false;
  if (_localPingState.abortCtrl) {
    _localPingState.abortCtrl.abort();
    _localPingState.abortCtrl = null;
  }
  _updatePingControls();
}

function _updatePingControls() {
  var bar = document.getElementById("net-ping-controls");
  if (!bar) return;
  var btns = bar.querySelectorAll("button");
  for (var i = 0; i < btns.length; i++) {
    btns[i].disabled = _localPingState.running && !btns[i].classList.contains("net-ping-stop");
  }
  var stopBtn = document.getElementById("net-ping-stop-btn");
  if (stopBtn) stopBtn.style.display = _localPingState.running ? "inline-flex" : "none";
  var spinner = document.getElementById("net-ping-spinner");
  if (spinner) spinner.style.display = _localPingState.running ? "inline-flex" : "none";
}

// Advanced diagnostics toggle
function _toggleAdvNet() {
  var sec = document.getElementById("net-adv-section");
  var arrow = document.getElementById("net-adv-arrow");
  if (!sec) return;
  // classList.toggle returns whether the class is present *after* the toggle —
  // i.e., true when the section is now collapsed.
  var collapsed = sec.classList.toggle("net-adv-collapsed");
  if (arrow) arrow.classList.toggle("net-adv-arrow-open", !collapsed);
}

// Re-run all network probes with a button spinner — avoids the flash-to-skeleton
// reload pattern that other tabs use.
async function _rerunNetworkTests(btn) {
  if (btn && btn.disabled) return;
  if (btn) {
    btn.disabled = true;
    var labelSpan = btn.querySelector("span");
    if (labelSpan) labelSpan.textContent = "Running…";
  }
  try {
    dataCache.network = null;
    await fetchSection("network");
  } finally {
    // renderNetwork will rebuild the page (including the button), so no need
    // to restore the label here.
  }
}

// Traceroute runner
var _traceState = { running: false };
async function _runTraceroute(target) {
  if (_traceState.running) return;
  _traceState.running = true;
  var out = document.getElementById("net-trace-results");
  var btn = document.getElementById("net-trace-btn");
  if (btn) btn.disabled = true;
  if (out) out.innerHTML = '<p class="text-pulse-muted text-sm loading-pulse">Running traceroute to ' + esc(target) + '…</p>';

  try {
    var resp = await fetch("/api/network/traceroute?target=" + encodeURIComponent(target));
    var data = await resp.json();
    if (data.error) {
      if (out) out.innerHTML = '<p class="text-sm status-fail">' + esc(data.message) + '</p>';
    } else {
      _renderTraceroute(out, data);
    }
  } catch (e) {
    if (out) out.innerHTML = '<p class="text-sm status-fail">Traceroute failed: ' + esc(String(e)) + '</p>';
  }
  _traceState.running = false;
  if (btn) btn.disabled = false;
}

function _renderTraceroute(el, d) {
  var hops = d.hops || [];
  var reachedCls = d.reached ? "status-pass" : "status-fail";
  var reachedLabel = d.reached ? "Reached" : "Not reached";
  el.innerHTML =
    '<div class="net-trace-summary">' +
      '<span class="text-sm text-pulse-muted">Target: <span class="font-mono text-white">' + esc(d.target) + '</span></span>' +
      '<span class="text-sm text-pulse-muted">IP: <span class="font-mono text-white">' + esc(d.targetIp || "—") + '</span></span>' +
      '<span class="text-sm ' + reachedCls + '">' + esc(reachedLabel) + ' in ' + esc(String(d.hopCount || 0)) + ' hops</span>' +
    '</div>' +
    '<table class="data-table net-trace-table"><thead><tr>' +
      '<th>#</th><th>IP Address</th><th>Hostname</th><th>RTT</th><th>Status</th>' +
    '</tr></thead><tbody>' +
    hops.map(function(h) {
      var sc = h.status === "reached" ? "status-pass" : h.status === "timeout" ? "text-pulse-muted" : h.status === "transit" ? "" : "status-fail";
      var rtt = h.rttMs != null ? h.rttMs + " ms" : "—";
      var statusLabel = h.status === "reached" ? "Reached" : h.status === "transit" ? "OK" : h.status === "timeout" ? "* * *" : esc(h.status);
      return '<tr' + (sc ? ' class="' + sc + '"' : '') + '>' +
        '<td>' + esc(String(h.hop)) + '</td>' +
        '<td class="font-mono">' + esc(h.ip || "* * *") + '</td>' +
        '<td class="text-pulse-muted">' + esc(h.hostname || "") + '</td>' +
        '<td class="font-mono">' + esc(rtt) + '</td>' +
        '<td>' + esc(statusLabel) + '</td>' +
      '</tr>';
    }).join("") +
    '</tbody></table>';
}

// Speed Test — fetch and display Speedtest.net result
async function _fetchSpeedtest() {
  var input = document.getElementById("net-speed-input");
  var out = document.getElementById("net-speed-results");
  var btn = document.getElementById("net-speed-fetch-btn");
  if (!input || !out) return;
  var val = input.value.trim();
  if (!val) { out.innerHTML = '<p class="text-sm status-fail">Please paste a Speedtest result URL or ID.</p>'; return; }

  btn.disabled = true;
  out.innerHTML = '<p class="text-pulse-muted text-sm loading-pulse">Fetching result…</p>';

  try {
    var resp = await fetch("/api/network/speedtest?result_id=" + encodeURIComponent(val));
    var data = await resp.json();
    if (data.error) {
      out.innerHTML = '<p class="text-sm status-fail">' + esc(data.message) + '</p>';
      btn.disabled = false;
      return;
    }
    _renderSpeedResult(out, data);
  } catch (e) {
    out.innerHTML = '<p class="text-sm status-fail">Request failed: ' + esc(String(e)) + '</p>';
  }
  btn.disabled = false;
}

function _renderSpeedResult(el, d) {
  var dlOk = d.download != null && d.download >= 10;
  var ulOk = d.upload != null && d.upload >= 10;
  var dlCls = d.download == null ? "" : dlOk ? "net-speed-ok" : "net-speed-bad";
  var ulCls = d.upload == null ? "" : ulOk ? "net-speed-ok" : "net-speed-bad";

  var findings = [];
  if (d.download != null && d.download < 10)
    findings.push("Download speed (" + d.download + " Mbps) is below the 10 Mbps minimum for Pixellot streaming.");
  if (d.upload != null && d.upload < 10)
    findings.push("Upload speed (" + d.upload + " Mbps) is below the 10 Mbps minimum for Pixellot streaming.");
  if (d.ping != null && d.ping > 50)
    findings.push("Ping (" + d.ping + " ms) is elevated — may cause stream buffering.");

  el.innerHTML =
    '<div class="net-speed-cards">' +
      '<div class="net-speed-card">' +
        '<div class="net-speed-card-label">DOWNLOAD</div>' +
        '<div class="net-speed-card-val ' + dlCls + '">' + (d.download != null ? d.download : "—") + '</div>' +
        '<div class="net-speed-card-unit">Mbps</div>' +
      '</div>' +
      '<div class="net-speed-card">' +
        '<div class="net-speed-card-label">UPLOAD</div>' +
        '<div class="net-speed-card-val ' + ulCls + '">' + (d.upload != null ? d.upload : "—") + '</div>' +
        '<div class="net-speed-card-unit">Mbps</div>' +
      '</div>' +
      '<div class="net-speed-card">' +
        '<div class="net-speed-card-label">PING</div>' +
        '<div class="net-speed-card-val">' + (d.ping != null ? d.ping : "—") + '</div>' +
        '<div class="net-speed-card-unit">ms</div>' +
      '</div>' +
      (d.jitter != null ? '<div class="net-speed-card">' +
        '<div class="net-speed-card-label">JITTER</div>' +
        '<div class="net-speed-card-val">' + d.jitter + '</div>' +
        '<div class="net-speed-card-unit">ms</div>' +
      '</div>' : '') +
    '</div>' +
    (d.isp || d.server ? '<div class="net-speed-meta">' +
      (d.isp ? '<span>ISP: ' + esc(d.isp) + '</span>' : '') +
      (d.server ? '<span>Server: ' + esc(d.server) + '</span>' : '') +
      '<a href="' + esc(d.url) + '" target="_blank" rel="noopener" class="text-xs" style="color:var(--c-accent-blue)">View full result ↗</a>' +
    '</div>' : '') +
    (findings.length ? '<div class="net-speed-findings">' +
      findings.map(function(f) {
        return '<div class="net-speed-finding">' + svgIcon("triangle", 14) + ' <span>' + esc(f) + '</span></div>';
      }).join('') +
    '</div>' :
      // Only claim "meets requirements" when we actually parsed both numbers.
      (d.download != null && d.upload != null
        ? '<div class="net-speed-ok-msg">' + svgIcon("check", 14) + ' Bandwidth meets Pixellot minimum requirements (≥ 10 Mbps up/down)</div>'
        : '<div class="net-speed-finding">' + svgIcon("triangle", 14) + ' <span>Speedtest returned partial results — could not verify all thresholds.</span></div>'));
}

// ── Live Network Health (WebSocket-driven) ──────────────────
function _renderLiveNetHealth(h) {
  var el = document.getElementById("net-live-body");
  if (!el) return;
  var tcp = h.tcp || {};
  var conns = h.connections || [];

  // Update stale indicator (lives in the header, outside #net-live-body)
  var ind = document.querySelector(".net-live-indicator");
  if (ind) {
    ind.classList.toggle("net-live-stale", !_wsConnected);
    var label = ind.querySelector(".text-xs");
    if (label) label.textContent = _wsConnected ? "Live via WebSocket" : "Disconnected — reconnecting…";
  }

  // Retransmission gauge color
  var retrans = tcp.retransmitsSec || 0;
  var retCls = retrans > 10 ? "status-fail" : retrans > 2 ? "status-warn" : "status-pass";

  // Compute deltas for cumulative counters (Failures/Resets are cumulative since boot)
  var curFailures = tcp.connFailures || 0;
  var curResets   = tcp.connResets || 0;
  var failuresDelta = 0;
  var resetsDelta = 0;
  if (_prevLiveCounters) {
    failuresDelta = Math.max(0, curFailures - _prevLiveCounters.failures);
    resetsDelta   = Math.max(0, curResets - _prevLiveCounters.resets);
  }
  _prevLiveCounters = { failures: curFailures, resets: curResets };

  el.innerHTML =
    '<div class="net-live-gauges">' +
      _liveGauge("Retransmits/s", retrans, retCls) +
      _liveGauge("Established", tcp.established || 0, "") +
      _liveGauge("New Failures", failuresDelta, failuresDelta > 0 ? "status-warn" : "") +
      _liveGauge("New Resets", resetsDelta, resetsDelta > 0 ? "status-warn" : "") +
      _liveGauge("Segs Out/s", tcp.segsOutSec || 0, "") +
      _liveGauge("Segs In/s", tcp.segsInSec || 0, "") +
    '</div>' +
    (conns.length ? '<div class="net-live-conns">' +
      '<div class="net-live-conns-title">Active Connections (' + conns.length + ')</div>' +
      '<table class="data-table"><thead><tr>' +
        '<th>Remote Address</th><th>Port</th><th>Local Port</th><th>State</th>' +
      '</tr></thead><tbody>' +
      conns.map(function(c) {
        var stCls = c.state === "Established" ? "status-pass" : c.state === "TimeWait" ? "text-pulse-muted" : "status-warn";
        return '<tr>' +
          '<td class="font-mono text-xs">' + esc(c.remoteAddr) + '</td>' +
          '<td class="font-mono">' + esc(String(c.remotePort)) + '</td>' +
          '<td class="font-mono text-xs text-pulse-muted">' + esc(String(c.localPort || "")) + '</td>' +
          '<td class="' + stCls + '">' + esc(c.state) + '</td>' +
        '</tr>';
      }).join("") +
      '</tbody></table>' +
    '</div>' : '');
}

function _liveGauge(label, val, cls) {
  return '<div class="net-live-gauge">' +
    '<div class="net-live-gauge-val ' + (cls || '') + '">' + esc(String(val)) + '</div>' +
    '<div class="net-live-gauge-label">' + esc(label) + '</div>' +
  '</div>';
}

// ── Network Capture (on-demand pktmon) ──────────────────────
var _captureState = { running: false };

async function _runCapture(duration) {
  if (_captureState.running) return;
  _captureState.running = true;

  var ctrls = document.getElementById("net-capture-controls");
  var spinner = document.getElementById("net-capture-status");
  var out = document.getElementById("net-capture-results");
  var presets = ctrls ? ctrls.querySelectorAll(".net-ping-preset") : [];
  // Highlight which duration is running, disable others.
  presets.forEach(function(b) {
    var bDur = parseInt((b.textContent || "").replace("s",""), 10);
    b.classList.toggle("net-ping-preset-active", bDur === duration);
    b.disabled = true;
  });
  if (spinner) spinner.style.display = "inline-flex";
  if (out) out.innerHTML = '<p class="text-pulse-muted text-sm loading-pulse">Running ' + duration + 's packet capture — analyzing TCP headers on ports 443, 1935, 80, UDP 2088…</p>';

  try {
    var resp = await fetch("/api/network/capture?duration=" + duration);
    var data = await resp.json();
    if (data.error) {
      if (out) out.innerHTML = '<p class="text-sm status-fail">' + esc(data.message) + '</p>';
    } else {
      _renderCapture(out, data);
    }
  } catch (e) {
    if (out) out.innerHTML = '<p class="text-sm status-fail">Capture failed: ' + esc(String(e)) + '</p>';
  }
  _captureState.running = false;
  presets.forEach(function(b) { b.disabled = false; });
  if (spinner) spinner.style.display = "none";
}

function _renderCapture(el, d) {
  var findings = d.findings || [];
  var topTalkers = d.topTalkers || [];

  el.innerHTML =
    // Summary stats
    '<div class="net-cap-summary">' +
      '<div class="net-cap-stat"><span class="net-cap-stat-val">' + esc(String(d.totalPackets || 0)) + '</span><span class="net-cap-stat-label">Packets</span></div>' +
      '<div class="net-cap-stat"><span class="net-cap-stat-val ' + ((d.tcpRetransmits || 0) > 0 ? 'status-warn' : '') + '">' + esc(String(d.tcpRetransmits || 0)) + '</span><span class="net-cap-stat-label">Retransmits</span></div>' +
      '<div class="net-cap-stat"><span class="net-cap-stat-val ' + ((d.tcpResets || 0) > 0 ? 'status-warn' : '') + '">' + esc(String(d.tcpResets || 0)) + '</span><span class="net-cap-stat-label">Resets</span></div>' +
      '<div class="net-cap-stat"><span class="net-cap-stat-val ' + ((d.droppedPackets || 0) > 0 ? 'status-fail' : '') + '">' + esc(String(d.droppedPackets || 0)) + '</span><span class="net-cap-stat-label">Drops</span></div>' +
      '<div class="net-cap-stat"><span class="net-cap-stat-val">' + esc(String(d.tcpSyns || 0)) + '</span><span class="net-cap-stat-label">SYN</span></div>' +
      '<div class="net-cap-stat"><span class="net-cap-stat-val">' + esc(String(d.tcpFins || 0)) + '</span><span class="net-cap-stat-label">FIN</span></div>' +
    '</div>' +
    // Findings
    (findings.length ? '<div class="net-cap-findings">' +
      findings.map(function(f) {
        var cls = f.severity === "critical" ? "net-rec-critical" : f.severity === "warning" ? "net-rec-warn" : f.severity === "pass" ? "net-cap-pass" : "net-rec-info";
        var icon = f.severity === "pass" ? svgIcon("check", 14) : svgIcon("triangle", 14);
        return '<div class="net-cap-finding ' + cls + '">' + icon + ' <strong>' + esc(f.title) + '</strong> — ' + esc(f.body) + '</div>';
      }).join("") +
    '</div>' : '') +
    // Top talkers
    '<div class="net-cap-talkers">' +
      '<div class="net-cap-talkers-title">Top Endpoints by Packet Count</div>' +
      (topTalkers.length
        ? '<table class="data-table"><thead><tr>' +
            '<th>Host</th><th>Address</th><th>Port</th><th>Packets</th>' +
          '</tr></thead><tbody>' +
          topTalkers.map(function(t) {
            return '<tr>' +
              '<td>' + esc(t.remoteHost || "—") + '</td>' +
              '<td class="font-mono text-xs">' + esc(t.remoteAddr) + '</td>' +
              '<td class="font-mono">' + esc(String(t.remotePort)) + '</td>' +
              '<td class="font-mono">' + esc(String(t.packets)) + '</td>' +
            '</tr>';
          }).join("") +
          '</tbody></table>'
        : '<p class="net-cap-empty">No outbound destinations parsed from the capture — this Windows build may not expose IP details via etl2txt.</p>') +
    '</div>';
}

function _prefixToMask(prefix) {
  if (prefix == null) return null;
  var n = parseInt(prefix, 10);
  if (isNaN(n) || n < 0 || n > 32) return null;
  var mask = n === 0 ? 0 : (0xFFFFFFFF << (32 - n)) >>> 0;
  return [24, 16, 8, 0].map(function(s) { return (mask >>> s) & 0xFF; }).join(".");
}

// Severity ordering for Network tab issues. Returns a stable rank where
// critical comes first. The previous inline `(o[severity] || 3)` form
// treated critical as falsy (rank 0) and silently fell through to 3,
// which is why issues rendered in the wrong order.
function _netIssueRank(severity) {
  switch (severity) {
    case "critical": return 0;
    case "warning":  return 1;
    case "info":     return 2;
    default:         return 3;
  }
}

function _buildNetIssues(cfg, ports, domains, local, dnsResolution) {
  var issues = [];
  var gw = (local || {}).gateway;
  var dns = (local || {}).dns;

  // ── Critical: Gateway ────────────────────────────────────
  if (gw && !gw.reachable) {
    if (!gw.target)
      issues.push({ severity: "critical", title: "No default gateway configured",
        body: "The uplink adapter has no IPv4 default gateway. Set one via DHCP or static configuration — the VPU cannot reach the internet without it." });
    else
      issues.push({ severity: "critical", title: "Gateway unreachable (" + gw.target + ")",
        body: "Verify the uplink Ethernet cable is seated, the switch port is active, and the VLAN is correct. No traffic will leave the VPU until this is resolved." });
  }
  else if (gw && gw.reachable && (gw.lossPercent > 0 || (gw.avgMs != null && gw.avgMs > 10)))
    issues.push({ severity: "warning", title: "Unstable gateway — " + (gw.avgMs || "?") + " ms latency, " + (gw.lossPercent || 0) + "% loss",
      body: "Try a different switch port, replace the Ethernet cable, or check for broadcast storms on the venue network." });

  // ── Warning/Info: DNS server ─────────────────────────────
  if (dns && !dns.reachable)
    issues.push({ severity: "warning", title: "DNS server unreachable (" + dns.target + ")",
      body: "Domain resolution will fail. Check DNS server address in adapter settings or try a public DNS (8.8.8.8, 1.1.1.1)." });
  else if (dns && dns.reachable) {
    if (dns.lossPercent > 0)
      issues.push({ severity: "warning", title: "DNS packet loss: " + dns.lossPercent + "% to " + dns.target,
        body: "Resolution may be unreliable. Check cable or try a different DNS server." });
    if (dns.avgMs != null && dns.avgMs > 100)
      issues.push({ severity: "info", title: "High DNS latency: " + dns.avgMs + " ms to " + dns.target,
        body: "Consider switching to a closer DNS server (8.8.8.8 or 1.1.1.1)." });
  }

  // ── Critical: No internet ────────────────────────────────
  if (!cfg.internetReachable) {
    issues.push({ severity: "critical", title: "VPU has no internet connection",
      body: "Verify the uplink cable and the gateway’s WAN status before further triage." });
    // Sort and return early — no point checking ports/domains
    issues.sort(function(a, b) { return _netIssueRank(a.severity) - _netIssueRank(b.severity); });
    return issues;
  }

  // ── Ports: required failures ─────────────────────────────
  // Pushed before DNS-comparison findings so that within the Critical
  // severity bucket, port blockages rank above DNS issues. The Network
  // tab's sort is stable on severity, so insertion order is the
  // tie-breaker within a bucket.
  var reqFailed = (ports || []).filter(function(p) { return !p.optional && (p.status || "").toLowerCase() !== "pass"; });
  var reqPass = (ports || []).filter(function(p) { return !p.optional && (p.status || "").toLowerCase() === "pass"; });
  if (reqFailed.length > 0) {
    var portDetails = reqFailed.map(function(p) {
      var proto = (p.protocol || "TCP").toUpperCase();
      if (p.port === 123 && proto === "UDP")
        return proto + "/" + p.port + " — NTP sync failed. VPU clock will drift, breaking signed-URL streaming.";
      return proto + "/" + p.port + " (" + (p.purpose || "") + ") to " + (p.host || "remote");
    });
    issues.push({ severity: "critical", title: reqFailed.length + " of " + (reqFailed.length + reqPass.length) + " required ports blocked",
      body: "Ensure these ports are allowed by the venue firewall and VLAN policy.",
      details: portDetails });
  }

  // ── DNS comparison vs Google DNS (PDF #10) ──────────────
  // If 8.8.8.8 resolves but the configured DNS doesn't, the school's
  // internal resolver is blocking Pixellot infrastructure. Pushed AFTER
  // required-ports so the port critical sorts above the DNS critical.
  if (dnsResolution && !dnsResolution.error) {
    var sysBlocked = (dnsResolution.results || []).filter(function(r) { return r.discrepancy === "system-blocked"; });
    if (sysBlocked.length) {
      issues.push({
        severity: "critical",
        title: sysBlocked.length + " domain(s) blocked by configured DNS but reachable via Google DNS (8.8.8.8)",
        body: "The local DNS resolver is filtering or failing on Pixellot infrastructure. Change the VPU's DNS servers to 8.8.8.8 / 8.8.4.4, or ask the venue's network admin to whitelist these hostnames.",
        details: sysBlocked.map(function(r) {
          return r.host + " — system: " + (r.system.error || "no answer") + "; google: " + (r.google.resolvedTo || "—");
        }),
      });
    }
    var mismatches = (dnsResolution.results || []).filter(function(r) { return r.discrepancy === "mismatch"; });
    if (mismatches.length) {
      issues.push({
        severity: "warning",
        title: mismatches.length + " domain(s) resolve to different IPs via system vs Google DNS",
        body: "Could indicate a captive portal, school filter, or internal mirror. Verify the resolved IP matches Pixellot's expected ranges.",
        details: mismatches.map(function(r) {
          return r.host + " — system: " + r.system.resolvedTo + "; google: " + r.google.resolvedTo;
        }),
      });
    }
  }

  // ── Ports: optional failures ─────────────────────────────
  var optFailed = (ports || []).filter(function(p) { return p.optional && (p.status || "").toLowerCase() !== "pass"; });
  if (optFailed.length > 0) {
    var optDetails = optFailed.map(function(p) {
      var proto = (p.protocol || "TCP").toUpperCase();
      return proto + "/" + p.port + " (" + (p.purpose || "") + ") to " + (p.host || "remote");
    });
    issues.push({ severity: "info", title: optFailed.length + " optional port(s) blocked",
      body: "These aren’t required at every venue — only act if streaming is failing.",
      details: optDetails });
  }

  // ── Domains: failures ────────────────────────────────────
  var domFailed = (domains || []).filter(function(d) { return (d.status || "").toLowerCase() !== "pass"; });
  var domTotal = (domains || []).length;
  if (domFailed.length > 0) {
    var domDetails = domFailed.map(function(d) {
      return d.domain + " — ensure it is whitelisted (firewall, DNS allow-list, SSL inspection bypass)";
    });
    issues.push({ severity: "warning", title: domFailed.length + " of " + domTotal + " domains failed DNS resolution",
      body: "Check DNS server settings on this adapter.",
      details: domDetails });
  }

  // ── Domains: slow resolution ─────────────────────────────
  var slowDns = (domains || []).filter(function(d) { return d.resolutionMs != null && d.resolutionMs > 500 && (d.status || "").toLowerCase() === "pass"; });
  if (slowDns.length > 0) {
    var slowDetails = slowDns.map(function(d) { return d.domain + " — " + d.resolutionMs + " ms"; });
    issues.push({ severity: "info", title: slowDns.length + " domain(s) resolved slowly (>500 ms)",
      body: "Slow DNS can delay connections. Consider switching to a faster DNS server.",
      details: slowDetails });
  }

  // ── Adapter: half-duplex ─────────────────────────────────
  var uStats = cfg.uplinkStats || {};
  if (uStats.fullDuplex === false)
    issues.push({ severity: "warning", title: "Uplink adapter running in half-duplex",
      body: "Set both the VPU NIC and the switch port to auto-negotiate, or hard-set both to 1 Gbps full-duplex." });

  // ── Adapter: interface errors ────────────────────────────
  var ifaceErrors = (uStats.rxErrors || 0) + (uStats.txErrors || 0);
  if (ifaceErrors > 0)
    issues.push({ severity: "warning", title: ifaceErrors + " interface error(s) on uplink adapter",
      body: "RX errors: " + (uStats.rxPacketErrors || 0) + ", RX discards: " + (uStats.rxDiscards || 0) +
            ", TX errors: " + (uStats.txPacketErrors || 0) + ", TX discards: " + (uStats.txDiscards || 0) +
            ". Try replacing the cable, switching ports, or updating the NIC driver." });

  // Sort by severity: critical → warning → info
  issues.sort(function(a, b) { return _netIssueRank(a.severity) - _netIssueRank(b.severity); });
  return issues;
}

// Time Sync card — Windows Time service status + peer list from `w32tm /query`.
// PDF #8 in the Pixellot Troubleshooting Tips.
function _netTimeSyncCard(cfg, ntp, ntpPeers) {
  // Always show the card so techs see drift even when w32tm /query fails.
  var st = (ntpPeers && ntpPeers.status) || {};
  var peers = (ntpPeers && ntpPeers.peers) || [];

  // NTP drift summary (from Test-NtpDrift.ps1, separate from w32tm /query)
  var driftStatus = (ntp.status || "").toLowerCase();
  var offset = ntp.offsetSeconds != null ? ntp.offsetSeconds + "s" : "—";
  var driftLabel;
  if (driftStatus === "ok") driftLabel = '<span class="status-pass" style="font-weight:600">In sync (' + esc(offset) + ')</span>';
  else if (driftStatus === "warn") driftLabel = '<span class="status-warn" style="font-weight:600">Drift (' + esc(offset) + ')</span>';
  else if (driftStatus) driftLabel = '<span class="status-fail" style="font-weight:600">Error</span>';
  else driftLabel = "—";

  // Approval chip (mirrors the row in the Adapter card)
  var approvedChip = "";
  if (cfg.ntpSourceApproved === true)
    approvedChip = '<span class="ntp-source-chip ntp-source-ok">Approved</span>';
  else if (cfg.ntpSourceApproved === false)
    approvedChip = '<span class="ntp-source-chip ntp-source-bad">Unapproved</span>';

  var sourceDisplay = st.source || cfg.ntpSource || ntp.source || "—";
  var sourceIpDisplay = st.sourceIp ? st.sourceIp : "—";
  var stratumDisplay = st.stratum != null ? String(st.stratum) : "—";
  var lastSyncDisplay = st.lastSync || "Never synced";

  var peersHtml;
  if (!ntpPeers) {
    peersHtml = '<p class="text-pulse-muted text-sm mt-2">w32tm peer data unavailable.</p>';
  } else if (!peers.length) {
    peersHtml = '<p class="text-pulse-muted text-sm mt-2">No peers configured for the Windows Time service.</p>';
  } else {
    peersHtml =
      '<table class="data-table"><thead><tr>' +
        '<th>Peer</th><th>State</th><th>Stratum</th><th>Last Sync</th><th>Poll</th>' +
      '</tr></thead><tbody>' +
      peers.map(function(p) {
        var stateCls = (p.state || "").toLowerCase() === "active" ? "status-pass" : "text-pulse-muted";
        return '<tr>' +
          '<td class="font-mono text-xs">' + esc(p.name || "—") + '</td>' +
          '<td class="' + stateCls + '">' + esc(p.state || "—") + '</td>' +
          '<td>' + esc(p.stratum != null ? String(p.stratum) : "—") + '</td>' +
          '<td class="text-xs">' + esc(p.lastSyncTimestamp || "Never") + '</td>' +
          '<td class="text-xs text-pulse-muted">' + esc(p.peerPollInterval || "—") + '</td>' +
        '</tr>';
      }).join("") +
      '</tbody></table>';
  }

  return `<div class="card">
    ${sectionTitle("clock", "Time Sync (NTP)")}
    <div class="kv-grid">
      ${kvRowHtml("Source", esc(sourceDisplay) + " " + approvedChip)}
      ${kvRow("Source IP", sourceIpDisplay)}
      ${kvRow("Stratum", stratumDisplay)}
      ${kvRow("Last sync", lastSyncDisplay)}
      ${kvRowHtml("Drift status", driftLabel)}
    </div>
    <div class="net-ntp-peers">
      <div class="net-ntp-peers-title">${svgIcon("activity", 12)} Active Peers</div>
      ${peersHtml}
    </div>
  </div>`;
}

// DNS Resolution card — side-by-side comparison of system DNS vs Google DNS.
// PDF #10: a misconfigured school resolver can block Pixellot infrastructure
// while 8.8.8.8 works fine. Flag those rows clearly.
function _netDnsResolutionCard(dnsResolution, cfg) {
  if (!dnsResolution) {
    return `<div class="card">
      ${sectionTitle("globe", "DNS Resolution Comparison")}
      <p class="text-pulse-muted text-sm">DNS comparison data unavailable.</p>
    </div>`;
  }

  var results = dnsResolution.results || [];
  var googleSrv = dnsResolution.googleServer || "8.8.8.8";
  // Pull the configured system DNS server from the network config if we have it.
  var ipConfigs = cfg.ipConfig || cfg.ipConfigurations || [];
  var uplinkName = cfg.uplinkAdapter && cfg.uplinkAdapter.interfaceAlias;
  var uplinkIpCfg = uplinkName ? ipConfigs.find(function(ip) { return ip.interfaceAlias === uplinkName; }) : null;
  var systemDns = uplinkIpCfg && uplinkIpCfg.dnsServers
    ? String(uplinkIpCfg.dnsServers).split(",").map(function(s) { return s.trim(); }).filter(Boolean).join(", ")
    : "system resolver";

  var rowsHtml = results.length
    ? results.map(function(r) {
        var sys = r.system || {};
        var goog = r.google || {};
        function cellHtml(side) {
          if (side.status === "pass") {
            var ms = side.resolutionMs != null ? side.resolutionMs + " ms" : "";
            return '<div class="net-dns-ok">' +
              '<div class="net-dns-ip font-mono">' + esc(side.resolvedTo || "—") + '</div>' +
              '<div class="net-dns-ms text-xs text-pulse-muted">' + esc(ms) + '</div>' +
            '</div>';
          }
          return '<div class="net-dns-fail">' +
            '<div class="net-dns-ip status-fail">Failed</div>' +
            '<div class="net-dns-ms text-xs text-pulse-muted">' + esc(side.error || "no answer") + '</div>' +
          '</div>';
        }
        var rowCls = "";
        var note = "";
        if (r.discrepancy === "system-blocked") {
          rowCls = "net-dns-row-bad";
          note = '<span class="net-dns-note status-fail">School DNS blocking Pixellot</span>';
        } else if (r.discrepancy === "mismatch") {
          rowCls = "net-dns-row-warn";
          note = '<span class="net-dns-note status-warn">IPs differ — possible DNS rewrite</span>';
        }
        return '<tr class="' + rowCls + '">' +
          '<td class="font-mono text-xs">' + esc(r.host) + '</td>' +
          '<td>' + cellHtml(sys) + '</td>' +
          '<td>' + cellHtml(goog) + '</td>' +
          '<td>' + note + '</td>' +
        '</tr>';
      }).join("")
    : '<tr><td colspan="4" class="text-pulse-muted text-sm">No DNS comparison data.</td></tr>';

  return `<div class="card">
    ${sectionTitle("globe", "DNS Resolution Comparison")}
    <p class="text-pulse-muted text-sm">
      Compares the configured DNS (<span class="font-mono">${esc(systemDns)}</span>)
      against Google DNS (<span class="font-mono">${esc(googleSrv)}</span>) for key Pixellot hosts.
      A row flagged red means the venue's DNS is filtering Pixellot infrastructure.
    </p>
    <table class="data-table net-dns-table"><thead><tr>
      <th>Host</th>
      <th>Configured DNS</th>
      <th>Google DNS (${esc(googleSrv)})</th>
      <th></th>
    </tr></thead><tbody>${rowsHtml}</tbody></table>
  </div>`;
}

function renderNetwork() {
  const data = cached("network");
  if (!data) { $page().innerHTML = sectionLoading("Network"); fetchSection("network"); return; }

  const cfg = data.config || {};
  const domains = data.domains?.results || [];
  const ports = data.ports?.results || [];
  const ntp = data.ntp || {};
  const local = data.local || {};
  const ntpPeers = (data.ntpPeers && !data.ntpPeers.error) ? data.ntpPeers : null;
  const dnsResolution = (data.dnsResolution && !data.dnsResolution.error) ? data.dnsResolution : null;
  const ipConfigs = cfg.ipConfig || cfg.ipConfigurations || [];

  const issues = _buildNetIssues(cfg, ports, domains, local, dnsResolution);

  const hasCrit = issues.some(function(f) { return f.severity === "critical"; });
  const hasWarn = issues.some(function(f) { return f.severity === "warning"; });
  const sevClass = hasCrit ? "critical" : hasWarn ? "warn" : "ok";
  const sevLabel = hasCrit ? "Fail" : hasWarn ? "Warning" : "Pass";
  const statusChip = `<span class="dash-sev-pill dash-sev-${sevClass}"><span class="dash-sev-dot"></span> ${sevLabel}</span>`;

  // Primary adapter — join uplinkAdapter with adapters[] and ipConfig[]
  const uplinkName = cfg.uplinkAdapter?.interfaceAlias;
  const uplinkAdapterRow = uplinkName
    ? (cfg.adapters || []).find(function(a) { return a.name === uplinkName; }) || null
    : null;
  const uplinkIpCfg = uplinkName
    ? ipConfigs.find(function(ip) { return ip.interfaceAlias === uplinkName; }) || null
    : null;
  const adapterLinkState = uplinkAdapterRow
    ? ((uplinkAdapterRow.status || "").toLowerCase() === "up" ? "Up" : uplinkAdapterRow.status || "Unknown")
    : "—";
  const adapterIp = _first(uplinkIpCfg?.ipv4Address) || "—";
  const subnetMask = uplinkIpCfg ? _prefixToMask(uplinkIpCfg.prefixLength) : null;
  const dhcpLabel = uplinkIpCfg?.dhcpEnabled === true ? "DHCP" : uplinkIpCfg?.dhcpEnabled === false ? "Static" : "—";
  const dnsStr = uplinkIpCfg?.dnsServers
    ? String(uplinkIpCfg.dnsServers).split(",").map(function(s) { return s.trim(); }).filter(Boolean).join(", ")
    : "—";

  // Uplink adapter stats (duplex, error counters)
  const uplinkStats = cfg.uplinkStats || {};
  const duplexLabel = uplinkStats.fullDuplex === true ? "Full Duplex" : uplinkStats.fullDuplex === false ? "Half Duplex" : null;
  const totalErrors = (uplinkStats.rxErrors || 0) + (uplinkStats.txErrors || 0);

  const tcpPorts = ports.filter(function(p) { return (p.protocol || "").toUpperCase() === "TCP"; });
  const udpPorts = ports.filter(function(p) { return (p.protocol || "").toUpperCase() === "UDP"; });

  // Group ports that share (protocol, port). Renders as a single multi-host card.
  function groupPorts(list) {
    var byKey = {};
    var order = [];
    list.forEach(function(p) {
      var key = (p.protocol || "").toUpperCase() + "/" + p.port;
      if (!byKey[key]) { byKey[key] = []; order.push(key); }
      byKey[key].push(p);
    });
    return order.map(function(k) { return byKey[k]; });
  }

  function portCard(p) {
    const ok = (p.status || "").toLowerCase() === "pass";
    const cls = ok ? "port-card-pass" : (p.optional ? "port-card-warn" : "port-card-fail");
    return `<div class="port-card ${cls}">
      <div class="port-card-num">${esc(String(p.port))}</div>
      <div class="port-card-name">${esc(p.purpose)}</div>
      <div class="port-card-host">${esc(p.host)}</div>
      ${p.optional ? '<div class="port-card-opt">Optional</div>' : ""}
    </div>`;
  }

  // Multi-host card: one card showing all endpoints tested on the same protocol/port.
  function portCardGroup(group) {
    if (group.length === 1) return portCard(group[0]);
    const anyFail = group.some(function(p) { return (p.status || "").toLowerCase() !== "pass"; });
    const allOptional = group.every(function(p) { return p.optional; });
    const cls = !anyFail ? "port-card-pass" : (allOptional ? "port-card-warn" : "port-card-fail");
    const passCount = group.filter(function(p) { return (p.status || "").toLowerCase() === "pass"; }).length;
    const port = group[0].port;
    const proto = (group[0].protocol || "").toUpperCase();
    const label = proto === "TCP" && port === 443 ? "HTTPS Endpoints" : (group[0].purpose || (proto + "/" + port));
    const hosts = group.map(function(p) {
      const hostOk = (p.status || "").toLowerCase() === "pass";
      const dotColor = hostOk ? "var(--c-accent-green)" : (p.optional ? "var(--c-accent-amber)" : "var(--c-accent-red)");
      return `<li><span class="port-card-host-dot" style="background:${dotColor}"></span>` +
             `<span class="port-card-host-name">${esc(p.host)}</span>` +
             `<span class="port-card-host-purpose">${esc(p.purpose)}</span></li>`;
    }).join("");
    return `<div class="port-card port-card-multi ${cls}">
      <div class="port-card-num">${esc(String(port))}</div>
      <div class="port-card-name">${esc(label)}</div>
      <div class="port-card-summary">${passCount} of ${group.length} passing</div>
      <ul class="port-card-hosts">${hosts}</ul>
    </div>`;
  }

  const issuesPanel = issues.length ? `
    <div class="card">
      <div class="af-header">
        ${svgIcon("triangle", 16)}
        <span class="af-label">ISSUES & RECOMMENDATIONS</span>
        <span class="af-count-badge">${issues.length} item${issues.length !== 1 ? "s" : ""}</span>
      </div>
      <div class="net-issues-list">
        ${issues.map(function(item) {
          var sc = item.severity === "critical" ? "sev-chip-crit" : item.severity === "warning" ? "sev-chip-warn" : item.severity === "info" ? "sev-chip-info" : "sev-chip-ok";
          var borderCls = item.severity === "critical" ? "net-issue-critical" : item.severity === "warning" ? "net-issue-warn" : "net-issue-info";
          var detailsHtml = "";
          if (item.details && item.details.length) {
            detailsHtml = '<ul class="net-issue-details">' +
              item.details.map(function(d) { return '<li>' + esc(d) + '</li>'; }).join("") +
            '</ul>';
          }
          return '<div class="net-issue-row ' + borderCls + '">' +
            '<span class="sev-chip ' + sc + '">' + esc(item.severity.toUpperCase()) + '</span>' +
            '<div class="net-issue-text">' +
              '<div class="net-issue-title">' + esc(item.title) + '</div>' +
              '<div class="net-issue-body">' + esc(item.body) + '</div>' +
              detailsHtml +
            '</div>' +
          '</div>';
        }).join("")}
      </div>
    </div>` : "";

  $page().innerHTML = `
    ${pageHeader("Network", "Adapters, IP configuration, NTP, and reachability for required services.",
      statusChip + `<button id="net-run-test-btn" class="btn-outline btn-ol-blue" onclick="_rerunNetworkTests(this)">
        ${svgIcon("activity", 14)} <span>Run Test</span>
      </button>`
    )}

    ${issuesPanel}

    <!-- Port Connectivity -->
    <div class="card">
      ${sectionTitle("link", "Port Connectivity")}
      <div class="net-port-cols">
        <div class="net-sub-card">
          <div class="net-sub-heading">TCP ports <span class="net-proto-badge net-proto-tcp">TCP</span></div>
          ${tcpPorts.length
            ? `<div class="port-grid">${groupPorts(tcpPorts).map(portCardGroup).join("")}</div>`
            : '<p class="text-pulse-muted text-sm mt-2">No TCP port results</p>'}
        </div>
        <div class="net-sub-card">
          <div class="net-sub-heading">UDP ports <span class="net-proto-badge net-proto-udp">UDP</span></div>
          ${udpPorts.length
            ? `<div class="port-grid">${groupPorts(udpPorts).map(portCardGroup).join("")}</div>`
            : '<p class="text-pulse-muted text-sm mt-2">No UDP port results</p>'}
        </div>
      </div>
    </div>

    <!-- Local Network Health -->
    <div class="card">
      <div class="net-ping-toolbar">
        ${sectionTitle("activity", "Local Network Health")}
        <div id="net-ping-controls" class="net-ping-btns">
          <span id="net-ping-spinner" class="net-ping-spin" style="display:none">${svgIcon("refresh", 14)}</span>
          <button class="net-ping-preset${!local.gateway && !local.dns ? " net-ping-preset-active" : ""}" onclick="runLocalPing(4)">4</button>
          <button class="net-ping-preset" onclick="runLocalPing(10)">10</button>
          <button class="net-ping-preset" onclick="runLocalPing(20)">20</button>
          <button class="net-ping-preset" onclick="runLocalPing(50)">50</button>
          <button class="net-ping-preset net-ping-cont" onclick="runLocalPing(0)">Continuous</button>
          <button id="net-ping-stop-btn" class="net-ping-stop btn-outline btn-ol-blue" style="display:none" onclick="stopLocalPing()">
            ${svgIcon("square", 12)} Stop
          </button>
        </div>
      </div>
      <div id="net-ping-results" class="net-ping-grid">
        ${local && local.error
          ? '<p class="text-sm status-fail">Local network test failed: ' + esc(local.message || 'unknown error') + '</p>'
          : (local.gateway || local.dns)
            ? _pingCardHtml(local.gateway) + _pingCardHtml(local.dns)
            : '<p class="text-pulse-muted text-sm mt-2">Select a ping count above to test local network health.</p>'}
      </div>
    </div>

    <!-- Internet Adapter + IP Config | Domain Reachability -->
    <div class="net-bottom-grid">
      <div class="card">
        ${sectionTitle("globe", "Internet Adapter & IP Configuration")}
        ${uplinkAdapterRow ? `
          <div class="font-semibold text-white mb-1">${esc(uplinkAdapterRow.name)}</div>
          <div class="text-pulse-muted text-xs mb-3">${esc(uplinkAdapterRow.interfaceDescription || "")}</div>` : `
          <p class="text-pulse-muted text-sm mb-3">No internet-bound adapter detected.</p>`}
        <div class="kv-grid">
          ${kvRow("IP address", adapterIp)}
          ${kvRow("Subnet mask", subnetMask || "—")}
          ${kvRow("Assignment", dhcpLabel)}
          ${kvRow("Gateway", cfg.uplinkAdapter?.gateway || "—")}
          ${kvRow("DNS", dnsStr)}
          ${kvRow("MAC address", uplinkAdapterRow?.macAddress || "—")}
          ${kvRowHtml("Link state", uplinkAdapterRow
            ? `<span style="color:${adapterLinkState === "Up" ? "var(--c-accent-green)" : "var(--c-muted)"};font-weight:600">${esc(adapterLinkState)}</span>`
            : "—")}
          ${kvRow("Link speed", uplinkAdapterRow?.linkSpeed || "—")}
          ${duplexLabel ? kvRowHtml("Duplex", duplexLabel === "Half Duplex"
            ? '<span class="status-warn" style="font-weight:600">Half Duplex</span>'
            : '<span style="color:var(--c-accent-green);font-weight:600">Full Duplex</span>') : ""}
          ${kvRowHtml("Internet", cfg.internetReachable
            ? '<span class="status-pass">Reachable</span>'
            : '<span class="status-fail">Unreachable</span>')}
          ${kvRow("Tested host", cfg.testedHost || "—")}
          ${kvRowHtml("NTP server", (function() {
            var src = cfg.ntpSource || ntp.source || "";
            if (!src) return "—";
            // PDF #9: the four *.us.pool.ntp.org hosts are the only approved sources.
            // Show a green Approved chip when matched, amber Unapproved chip otherwise.
            var approved = cfg.ntpSourceApproved;
            var approvedList = (cfg.ntpSourceApprovedList || []).join(", ");
            var chip;
            if (approved === true) {
              chip = '<span class="ntp-source-chip ntp-source-ok" title="Matches Pixellot approved NTP source list">Approved</span>';
            } else if (approved === false) {
              chip = '<span class="ntp-source-chip ntp-source-bad" title="Not in Pixellot approved list. Expected one of: ' + esc(approvedList) + '">Unapproved</span>';
            } else {
              chip = "";
            }
            var tooltip = "Drift is measured against the Windows-configured NTP source. The port test (UDP/123) targets prod-echo.pixellot.tv separately.";
            return '<span title="' + esc(tooltip) + '">' + esc(src) + '</span> ' + chip;
          })())}
          ${kvRowHtml("NTP status", (function() {
            var s = (ntp.status || "").toLowerCase();
            var offset = ntp.offsetSeconds != null ? " (" + ntp.offsetSeconds + "s)" : "";
            if (s === "ok") return '<span class="status-pass" style="font-weight:600">OK' + esc(offset) + '</span>';
            if (s === "warn") return '<span class="status-warn" style="font-weight:600">DRIFT' + esc(offset) + '</span>';
            if (!ntp.status) return "—";
            return '<span class="status-fail" style="font-weight:600">ERROR</span>';
          })())}
        </div>
        ${totalErrors > 0 || (uplinkStats.rxBytes != null) ? `
          <div class="net-iface-stats">
            <div class="net-iface-stats-title">${svgIcon("activity", 12)} Interface Counters</div>
            <div class="net-iface-stats-grid">
              <div class="net-iface-stat">
                <span class="net-iface-stat-label">RX Errors</span>
                <span class="net-iface-stat-val ${uplinkStats.rxPacketErrors > 0 ? 'status-warn' : ''}">${uplinkStats.rxPacketErrors || 0}</span>
              </div>
              <div class="net-iface-stat">
                <span class="net-iface-stat-label">RX Discards</span>
                <span class="net-iface-stat-val ${uplinkStats.rxDiscards > 0 ? 'status-warn' : ''}">${uplinkStats.rxDiscards || 0}</span>
              </div>
              <div class="net-iface-stat">
                <span class="net-iface-stat-label">TX Errors</span>
                <span class="net-iface-stat-val ${uplinkStats.txPacketErrors > 0 ? 'status-warn' : ''}">${uplinkStats.txPacketErrors || 0}</span>
              </div>
              <div class="net-iface-stat">
                <span class="net-iface-stat-label">TX Discards</span>
                <span class="net-iface-stat-val ${uplinkStats.txDiscards > 0 ? 'status-warn' : ''}">${uplinkStats.txDiscards || 0}</span>
              </div>
            </div>
            ${totalErrors > 0 ? '<div class="net-iface-stats-warn">' + svgIcon("triangle", 12) + ' Interface errors detected — check cable, switch port, or NIC driver.</div>' : ''}
          </div>` : ""}
      </div>
      <div class="card">
        ${sectionTitle("wifi", "Domain Reachability")}
        ${domains.length ? `
          <div class="domain-list">
            ${domains.map(function(d) {
              const ok = (d.status || "").toLowerCase() === "pass";
              var dnsTime = d.resolutionMs != null ? d.resolutionMs + " ms" : "";
              var dnsSlow = d.resolutionMs != null && d.resolutionMs > 200;
              var dotColor = ok ? "var(--c-accent-green)" : "var(--c-accent-red)";
              return `<div class="domain-row">
                <span class="domain-dot" style="background:${dotColor}"></span>
                <span class="domain-name">${esc(d.domain)}</span>
                <span class="domain-ip">${esc(d.resolvedTo) || "—"}</span>
                <span class="domain-dns-time font-mono${dnsSlow ? ' status-warn' : ''}">${esc(dnsTime)}</span>
                ${statusBadge(d.status)}
              </div>`;
            }).join("")}
          </div>
        ` : '<p class="text-pulse-muted text-sm">No DNS data</p>'}
      </div>
    </div>

    <!-- Advanced Diagnostics Toggle -->
    <div class="net-adv-toggle" onclick="_toggleAdvNet()">
      <div class="net-adv-toggle-inner">
        <span class="net-adv-toggle-icon" id="net-adv-arrow">${svgIcon("chevron", 14)}</span>
        <span class="net-adv-toggle-label">Advanced Diagnostics</span>
        <span class="text-xs text-pulse-muted">Time sync, DNS comparison, speed test, packet capture, traceroute, live monitoring</span>
      </div>
    </div>

    <!-- Advanced Diagnostics (collapsed by default) -->
    <div id="net-adv-section" class="net-adv-section net-adv-collapsed">

      ${_netTimeSyncCard(cfg, ntp, ntpPeers)}

      ${_netDnsResolutionCard(dnsResolution, cfg)}

      <!-- Speed Test -->
      <div class="card">
        <div class="net-ping-toolbar">
          ${sectionTitle("zap", "Speed Test")}
          <div class="net-ping-btns">
            <a href="https://www.speedtest.net" target="_blank" rel="noopener" class="btn-outline btn-ol-blue" style="text-decoration:none">
              ${svgIcon("globe", 14)} Open Speedtest.net
            </a>
          </div>
        </div>
        <div id="net-speed-ui">
          <p class="text-pulse-muted text-sm mb-3">Run a test at speedtest.net, then paste the result URL below.</p>
          <div class="net-speed-input-row">
            <input id="net-speed-input" type="text" class="net-speed-input" placeholder="https://www.speedtest.net/result/123456789 or result ID" onkeydown="if(event.key==='Enter'){event.preventDefault();_fetchSpeedtest();}">
            <button id="net-speed-fetch-btn" class="btn-outline btn-ol-blue" onclick="_fetchSpeedtest()">
              ${svgIcon("refresh", 14)} Fetch Result
            </button>
          </div>
          <div id="net-speed-results"></div>
        </div>
      </div>

      <!-- Packet Capture -->
      <div class="card">
        <div class="net-ping-toolbar">
          ${sectionTitle("shield", "Packet Capture")}
          <div id="net-capture-controls" class="net-ping-btns">
            <button class="net-ping-preset" onclick="_runCapture(10)">10s</button>
            <button class="net-ping-preset net-ping-preset-active" onclick="_runCapture(30)">30s</button>
            <button class="net-ping-preset" onclick="_runCapture(60)">60s</button>
            <span id="net-capture-status" class="net-ping-spin" style="display:none">${svgIcon("refresh", 14)}</span>
          </div>
        </div>
        <p class="text-pulse-muted text-sm">Captures TCP packet headers using Windows pktmon (ports 443, 1935, 80, UDP 2088). Analyzes retransmissions, resets, and drops.</p>
        <div id="net-capture-results"></div>
      </div>

      <!-- Traceroute -->
      <div class="card">
        <div class="net-ping-toolbar">
          ${sectionTitle("share", "Traceroute")}
          <div class="net-ping-btns">
            <input id="net-trace-target" type="text" class="net-trace-input" placeholder="pixellot.tv" value="pixellot.tv" onkeydown="if(event.key==='Enter'){event.preventDefault();_runTraceroute(this.value.trim()||'pixellot.tv');}">
            <button id="net-trace-btn" class="btn-outline btn-ol-blue" onclick="_runTraceroute(document.getElementById('net-trace-target').value.trim()||'pixellot.tv')">
              ${svgIcon("activity", 14)} Run
            </button>
          </div>
        </div>
        <div id="net-trace-results">
          <p class="text-pulse-muted text-sm mt-2">Click Run to trace the network path to a target host.</p>
        </div>
      </div>

      <!-- Live Network Health (WebSocket-driven) -->
      <div class="card">
        <div class="net-ping-toolbar">
          ${sectionTitle("zap", "Live Network Health")}
          <div class="net-live-indicator">
            <span class="net-live-dot"></span> <span class="text-xs text-pulse-muted">Live via WebSocket</span>
          </div>
        </div>
        <div id="net-live-body">
          <p class="text-pulse-muted text-sm">Waiting for live data…</p>
        </div>
      </div>

    </div>
  `;

  // Seed live health panel if we already have WebSocket data
  if (_liveNetHealth) _renderLiveNetHealth(_liveNetHealth);
}

// ── Cameras ──────────────────────────────────────────────────

var _camerasRefreshTimer = null;
var _camerasFailCount = 0;  // consecutive /api/cameras failures during live refresh
var _camLastSignature = null;  // structural fingerprint of last rendered cameras

// Structural fingerprint of the camera data — everything that affects the
// rendered layout EXCEPT the volatile RX/TX byte counters (which tick every
// few seconds). The live refresh only does a full DOM rebuild when this
// changes; otherwise it surgically updates the byte counters in place, so
// an open Details panel never flickers during steady-state polling.
function _camSignature(data) {
  var ports = (data && data.ports) || [];
  var portSig = ports.map(function(p) {
    var cams = (p.camerasDetected || []).map(function(c) {
      return [c.ip, c.mac, c.cgiMac, c.role, c.identitySource, c.modelNumber, c.cgiConfirmed].join("|");
    }).join(",");
    var errs = (p.rxPacketErrors || 0) + (p.txPacketErrors || 0) + (p.rxDiscards || 0) + (p.txDiscards || 0);
    return [p.portLabel, p.name, p.isUp, p.isOcr, p.isDegraded, p.cameraLabel,
            p.linkSpeedMbps, p.expectedSpeedMbps, p.cameraMovedTo, p.fullDuplex,
            errs, cams].join("~");
  }).join("||");
  var findSig = ((data && data.findings) || []).map(function(f) {
    return f.severity + ":" + f.title;
  }).join(";");
  return portSig + "##" + findSig;
}

function _camDetailKv(label, val) {
  if (!val && val !== 0) return '';
  return '<div class="kv-mini"><span>' + esc(String(label)) + '</span><span class="font-mono">' + esc(String(val)) + '</span></div>';
}

function _camStreamBlock(label, s) {
  if (!s || (!s.codec && !s.resolution && !s.framerate)) return '';
  var enabled = s.enabled !== undefined ? (s.enabled === "yes" || s.enabled === true) : true;
  return '<div class="cam-detail-group">' +
    '<div class="cam-detail-group-title">' + esc(label) +
      (!enabled ? ' <span class="status-warn">Disabled</span>' : '') +
    '</div>' +
    _camDetailKv("Codec", s.codec) +
    _camDetailKv("Resolution", s.resolution) +
    _camDetailKv("Framerate", s.framerate ? s.framerate + " fps" : null) +
  '</div>';
}

function _camDetailsPanel(cams, portIdx, portData) {
  if (!cams.length) return '';

  // NIC / adapter section
  var nicGroup = '';
  if (portData) {
    var duplexVal = portData.fullDuplex === true ? "Full" : portData.fullDuplex === false ? "Half" : "—";
    // Sum every error/discard counter for the "has errors" check so we
    // don't miss problems that only register on packet-error or discard
    // counters (driver-dependent which fields populate).
    var rxPktErr = portData.rxPacketErrors || 0;
    var txPktErr = portData.txPacketErrors || 0;
    var rxDisc   = portData.rxDiscards || 0;
    var txDisc   = portData.txDiscards || 0;
    var errTotal = (portData.rxErrors || 0) + (portData.txErrors || 0) +
                   rxPktErr + txPktErr + rxDisc + txDisc;
    var errVal = errTotal > 0
      ? 'RX ' + rxPktErr + ' / TX ' + txPktErr + ' / Discards ' + (rxDisc + txDisc)
      : 'None';
    nicGroup = '<div class="cam-detail-group">' +
      '<div class="cam-detail-group-title">NIC Adapter</div>' +
      _camDetailKv("Adapter", portData.name) +
      _camDetailKv("MAC", portData.mac) +
      _camDetailKv("Duplex", duplexVal) +
      _camDetailKv("Errors", errVal) +
    '</div>';
  }

  var inner = nicGroup + cams.map(function(c) {
    var hasCgi = !!c.cgiConfirmed;
    var net = c.network || {};
    var sensor = c.sensor || {};

    // Device section — always show MAC/IP; CGI adds model, serial, firmware
    var deviceRows =
      _camDetailKv("IP", c.ip) +
      _camDetailKv("MAC", c.cgiMac || c.mac) +
      _camDetailKv("Role", c.role) +
      _camDetailKv("Identity", c.identitySource);
    if (hasCgi) {
      deviceRows +=
        _camDetailKv("Model", c.model) +
        _camDetailKv("Model No.", c.modelNumber) +
        _camDetailKv("Serial", c.serialNumber) +
        _camDetailKv("Firmware", c.firmwareVersion) +
        _camDetailKv("Brand", c.brand) +
        _camDetailKv("Type", c.productType);
    }

    return '<div class="cam-detail-camera">' +
      '<div class="cam-detail-camera-header">' +
        svgIcon("camera", 14) + ' ' + esc(c.ip) +
        (c.modelNumber ? ' <span class="cam-model-label">' + esc(c.modelNumber) + '</span>' : '') +
        (hasCgi ? ' <span class="cam-cgi-badge">CGI</span>' : ' <span class="cam-cgi-badge cam-cgi-none">No CGI</span>') +
      '</div>' +

      // Device info
      '<div class="cam-detail-group">' +
        '<div class="cam-detail-group-title">Device</div>' +
        deviceRows +
      '</div>' +

      // Network (CGI only)
      (net.ip || net.subnet || net.gateway ? '<div class="cam-detail-group">' +
        '<div class="cam-detail-group-title">Network Config</div>' +
        _camDetailKv("IP Address", net.ip) +
        _camDetailKv("Subnet", net.subnet) +
        _camDetailKv("Gateway", net.gateway) +
        _camDetailKv("DHCP", net.dhcp) +
      '</div>' : '') +

      // Streams (CGI only)
      _camStreamBlock("Stream 0 — Primary", c.stream0) +
      _camStreamBlock("Stream 1 — Secondary", c.stream1) +

      // Sensor (CGI only)
      (sensor.exposure || sensor.brightness ? '<div class="cam-detail-group">' +
        '<div class="cam-detail-group-title">Image Sensor</div>' +
        _camDetailKv("Exposure", sensor.exposure) +
        _camDetailKv("Brightness", sensor.brightness) +
        _camDetailKv("Contrast", sensor.contrast) +
        _camDetailKv("Saturation", sensor.colorLevel) +
        _camDetailKv("Max Gain", sensor.maxShutterGain) +
        _camDetailKv("Min Shutter", sensor.minShutterSpeed) +
      '</div>' : '') +
    '</div>';
  }).join('');

  return '<details class="cam-details-toggle" data-port-idx="' + portIdx + '">' +
    '<summary class="cam-details-btn">' + svgIcon("info", 14) + ' Details</summary>' +
    '<div class="cam-details-body">' + inner + '</div>' +
  '</details>';
}

function _camPortTile(port, index) {
  if (!port) {
    return `<div class="cam-port-tile cam-port-empty">
      <div class="cam-port-num">Port ${index + 1}</div>
      <div class="cam-port-status">
        <span class="cam-dot cam-dot-muted"></span>
        <span class="text-sm text-pulse-muted">Not detected</span>
      </div>
    </div>`;
  }
  const p = port;
  const speed = p.linkSpeedMbps
    ? p.linkSpeedMbps >= 1000 ? (p.linkSpeedMbps / 1000) + " Gbps" : p.linkSpeedMbps + " Mbps"
    : "No link";
  let statusLabel, dotCls;
  if (!p.isUp) { statusLabel = "Down"; dotCls = "cam-dot-down"; }
  else if (p.isDegraded) { statusLabel = "Degraded · " + speed; dotCls = "cam-dot-warn"; }
  else { statusLabel = "Linked · " + speed; dotCls = p.isOcr ? "cam-dot-info" : "cam-dot-up"; }

  const cams = p.camerasDetected || [];
  var camLabel = p.cameraLabel;
  // Badge color: OCR → blue, Main Camera N → teal, generic Camera/Pixellot → muted.
  var camLabelCls;
  if (p.isOcr) camLabelCls = "badge-ol-info";
  else if (camLabel && camLabel.indexOf("Main") === 0) camLabelCls = "badge-ol-main";
  else camLabelCls = "badge-ol-muted";
  return `<div class="cam-port-tile ${p.isUp ? "cam-port-active" : "cam-port-down"}">
    <div class="cam-port-header">
      <span class="cam-port-num">Port ${index + 1}</span>
      ${camLabel ? '<span class="badge-ol ' + camLabelCls + '">' + esc(camLabel) + '</span>' : ''}
      ${p.isDegraded ? '<span class="badge-ol badge-ol-warn">Degraded</span>' : ""}
    </div>
    <div class="cam-port-name">${esc(p.name)}</div>
    <div class="cam-port-status">
      <span class="cam-dot ${dotCls}"></span>
      <span class="text-sm">${esc(statusLabel)}</span>
    </div>
    <div class="cam-port-detail">
      <div class="kv-mini"><span>RX / TX</span><span id="cam-rxtx-${index}">${formatBytes(p.rxBytes)} / ${formatBytes(p.txBytes)}</span></div>
    </div>
    ${cams.length > 0 ? (() => {
      var c = cams[0];
      var displayModel = c.modelNumber || (c.model && c.model !== "IP Camera" ? c.model : null);
      return `<div class="cam-detected">
        <div class="cam-detected-label">Pixellot camera detected</div>
        <div class="cam-detected-entry">
          <span class="font-mono cam-entry-ip">${esc(c.ip)}</span>
          <span class="font-mono text-pulse-muted cam-entry-mac">${esc(c.mac)}</span>
          ${displayModel ? '<span class="cam-model-label">' + esc(displayModel) + '</span>' : ''}
          <span class="cam-entry-source text-pulse-muted">${esc(c.identitySource || '')}</span>
        </div>
      </div>
      ${_camDetailsPanel(cams, index, p)}`;
    })()
    : p.isUp ? '<div class="cam-no-detect">No Pixellot cameras on this port</div>' : ""}
  </div>`;
}

function _camFindingsHtml(findings) {
  if (!findings.length) return "";
  return `<div class="card" id="cam-findings">
    ${sectionTitle("alert-circle", findings.length + " finding" + (findings.length !== 1 ? "s" : "") + " need attention")}
    ${findings.map(f => `
      <div class="cam-finding-row cam-finding-row-${esc(f.severity)}">
        <div class="cam-finding-header">
          <span class="cam-finding-pill cam-finding-pill-${esc(f.severity)}">${esc(f.severity.toUpperCase())}</span>
          <span class="font-semibold text-sm">${esc(f.title)}</span>
        </div>
        <div class="cam-finding-body">${esc(f.body)}</div>
      </div>`).join("")}
  </div>`;
}

function _camPortGridHtml(ports) {
  const portSlots = [];
  for (let i = 0; i < Math.max(4, ports.length); i++) {
    portSlots.push(ports[i] || null);
  }
  return portSlots.slice().reverse().map((p, ri) => _camPortTile(p, portSlots.length - 1 - ri)).join("");
}

function _camNicDiagramHtml(ports) {
  const count = Math.max(4, ports.length);
  function ledColor(p) {
    if (!p || !p.isUp) return "nic-led-off";
    if (p.isDegraded) return "nic-led-warn";
    if (p.isOcr) return "nic-led-ok";
    return "nic-led-ok";
  }
  function ledDotColor(p) {
    if (!p || !p.isUp) return "var(--c-dim)";
    if (p.isDegraded) return "#f59e0b";
    if (p.isOcr) return "#22c55e";
    return "#22c55e";
  }
  // Physical ports: reversed (highest port on left = physical chassis left)
  var portIcons = "";
  for (var ri = 0; ri < count; ri++) {
    var idx = count - 1 - ri;
    var p = ports[idx] || null;
    var cls = ledColor(p);
    portIcons += '<div class="nic-port-icon">' +
      '<div class="nic-port-body">' +
        '<div class="nic-port-slots"></div>' +
        '<div class="nic-port-led ' + cls + '"></div>' +
      '</div>' +
      '<div class="nic-port-label">Port ' + (idx + 1) + '</div>' +
    '</div>';
  }
  // Vertical legend on the right
  var legend = "";
  for (var li = count - 1; li >= 0; li--) {
    var lp = ports[li] || null;
    legend += '<div class="nic-legend-row">' +
      '<span class="nic-legend-dot" style="background:' + ledDotColor(lp) + '"></span>' +
      '<span class="nic-legend-label">Port ' + (li + 1) + '</span>' +
    '</div>';
  }
  // NIC header: show just the primary card name. Windows appends " #N"
  // to duplicate adapter descriptions from the same card — strip that
  // and use the first port's description as the card label.
  var nicDesc = "";
  for (var ni = 0; ni < ports.length; ni++) {
    var d = ports[ni] && ports[ni].interfaceDescription;
    if (d) { nicDesc = d.replace(/\s*#\d+\s*$/, "").trim(); break; }
  }
  var hasRealPorts = ports.length > 0;
  var headerLabel;
  if (nicDesc) headerLabel = svgIcon("cpu", 16) + ' ' + esc(nicDesc) + ' · ' + count + ' ports';
  else if (hasRealPorts) headerLabel = count + ' ports';
  else headerLabel = svgIcon("cpu", 16) + ' No NIC ports detected';
  var nicHeader = '<div class="nic-diagram-header">' +
    headerLabel +
    '<span id="cam-live-badge" class="cam-live-badge">Auto-Refresh</span>' +
  '</div>';
  // Only show the physical-order note when we actually have NIC data;
  // otherwise it reads misleadingly on an empty system.
  var note = hasRealPorts
    ? '<div class="nic-diagram-note">Port order mirrors the physical orientation of the NIC — Port ' + count + ' is leftmost on the card.</div>'
    : '';
  return nicHeader + '<div class="nic-diagram-wrap">' +
    '<div class="nic-diagram-ports">' + portIcons + '</div>' +
    '<div class="nic-diagram-legend">' + legend + '</div>' +
  '</div>' + note;
}

// Force a fresh camera probe — clears the backend CGI cache and re-polls.
// Used by the manual Refresh button so on-site troubleshooting can override
// any stale ARP/probe data instead of waiting for the TTL.
function _camForceRefresh() {
  var btn = document.querySelector('[onclick*="_camForceRefresh"]');
  if (btn) { btn.disabled = true; btn.style.opacity = "0.5"; }
  api("/api/cameras?refresh=true").then(function(fresh) {
    if (fresh && !fresh.error) {
      dataCache.cameras = fresh;
      if (currentPage === "cameras") renderCameras();
    }
  }).finally(function() {
    if (btn) { btn.disabled = false; btn.style.opacity = ""; }
  });
}

function renderCameras() {
  const data = cached("cameras");
  if (!data) { $page().innerHTML = sectionLoading("Camera Connectivity"); fetchSection("cameras"); return; }

  const ports = data.ports || [];
  const pixCfg = data.pixellotConfig || {};
  const cfgCameras = pixCfg.cameras || [];
  const findings = data.findings || [];

  const portSlots = [];
  for (let i = 0; i < Math.max(4, ports.length); i++) {
    portSlots.push(ports[i] || null);
  }

  $page().innerHTML = `
    ${pageHeader("Camera Connectivity", "NIC ports, link status, speed, and Pixellot camera detection",
      `<button class="btn-outline btn-ol-blue" onclick="_camForceRefresh()">
        ${svgIcon("refresh", 14)} Refresh
      </button>
      <button class="btn-outline btn-ol-blue" onclick="navigate('fault-isolator')">
        ${svgIcon("zap", 14)} Fault Isolator
      </button>`
    )}

    <div id="cam-findings-wrap">${_camFindingsHtml(findings)}</div>

    <div class="card" id="cam-nic-diagram">${_camNicDiagramHtml(ports)}</div>

    <div class="cam-port-grid" id="cam-port-grid">
      ${_camPortGridHtml(ports)}
    </div>

    ${cfgCameras.length ? `
    <div class="card mt-4">
      ${sectionTitle("file", "cameras.cfg")}
      <table class="data-table"><thead><tr>
        <th>Section</th><th>IP</th><th>MAC</th><th>Role</th>
      </tr></thead><tbody>
      ${cfgCameras.map(c => `<tr>
        <td>${esc(c.section)}</td>
        <td class="font-mono">${esc(c.ip)}</td>
        <td class="font-mono">${esc(c.mac)}</td>
        <td>${esc(c.role)}</td>
      </tr>`).join("")}
      </tbody></table>
    </div>` : ""}

  `;

  // ── Live refresh: poll /api/cameras every 3s and update port grid + findings ──
  // Seed the signature from what we just rendered so the first tick can
  // tell whether anything structural actually changed.
  _camLastSignature = _camSignature(data);
  if (_camerasRefreshTimer) clearInterval(_camerasRefreshTimer);
  _camerasFailCount = 0;
  _camerasRefreshTimer = setInterval(function() {
    if (currentPage !== "cameras") { clearInterval(_camerasRefreshTimer); _camerasRefreshTimer = null; return; }
    var markStale = function() {
      // After 3 consecutive failures (~9s) flag the Auto-Refresh badge as stale.
      _camerasFailCount++;
      if (_camerasFailCount >= 3) {
        var b = document.getElementById("cam-live-badge");
        if (b) { b.classList.add("cam-live-stale"); b.textContent = "Stale (" + _camerasFailCount + ")"; }
      }
    };
    api("/api/cameras").then(function(fresh) {
      if (!fresh || fresh.error || currentPage !== "cameras") { markStale(); return; }
      _camerasFailCount = 0;
      dataCache.cameras = fresh;
      var freshPorts = fresh.ports || [];

      var newSig = _camSignature(fresh);
      if (newSig === _camLastSignature) {
        // Steady state — nothing structural changed. Update only the
        // volatile RX/TX counters in place so open Details panels and
        // the rest of the DOM stay untouched (no flicker).
        freshPorts.forEach(function(p, i) {
          var el = document.getElementById("cam-rxtx-" + i);
          if (el) el.textContent = formatBytes(p.rxBytes) + " / " + formatBytes(p.txBytes);
        });
      } else {
        // Structural change (port up/down, camera moved, speed, findings…)
        // — do a full rebuild. A brief flicker here is acceptable and even
        // useful: it signals a real change the tech should notice.
        _camLastSignature = newSig;
        var grid = document.getElementById("cam-port-grid");
        if (grid) {
          var openDetails = {};
          grid.querySelectorAll('details[open][data-port-idx]').forEach(function(d) {
            openDetails[d.dataset.portIdx] = true;
          });
          grid.innerHTML = _camPortGridHtml(freshPorts);
          Object.keys(openDetails).forEach(function(idx) {
            var d = grid.querySelector('details[data-port-idx="' + idx + '"]');
            if (d) d.setAttribute('open', '');
          });
        }
        var diag = document.getElementById("cam-nic-diagram");
        if (diag) diag.innerHTML = _camNicDiagramHtml(freshPorts);
        var fw = document.getElementById("cam-findings-wrap");
        if (fw) fw.innerHTML = _camFindingsHtml(fresh.findings || []);
      }

      // Pulse the live badge to show the tick happened and clear any stale state
      var badge = document.getElementById("cam-live-badge");
      if (badge) {
        badge.classList.remove("cam-live-stale");
        badge.textContent = "Auto-Refresh";
        badge.classList.add("cam-live-tick");
        setTimeout(function() { badge.classList.remove("cam-live-tick"); }, 600);
      }
    }).catch(function() { markStale(); });
  }, 3000);
}

function formatBytes(b) {
  if (b == null) return "--";
  if (b < 1024) return b + " B";
  if (b < 1048576) return (b / 1024).toFixed(1) + " KB";
  if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB";
  return (b / 1073741824).toFixed(2) + " GB";
}

// ── Services ─────────────────────────────────────────────────

function renderServices() {
  const data = cached("services");
  if (!data) { $page().innerHTML = sectionLoading("Pixellot Services"); fetchSection("services"); return; }

  if (data.error) { $page().innerHTML = errorBox(data.message); return; }

  const svcs = data.services || [];

  function svcTile(s) {
    const st = (s.status || "").toLowerCase();
    let borderCls = "svc-tile-muted";
    if (st === "running") borderCls = "svc-tile-running";
    else if (st === "stopped") borderCls = "svc-tile-stopped";
    return `<div class="svc-tile ${borderCls}" data-svc="${esc(s.name)}">
      <div class="svc-tile-top">
        <span class="svc-tile-name">${esc(s.name)}</span>
        ${statusBadge(s.status)}
      </div>
      ${s.displayName && s.displayName !== s.name ? `<div class="svc-tile-display">${esc(s.displayName)}</div>` : ""}
      ${s.startType ? `<div class="svc-tile-start">Start: ${esc(s.startType)}</div>` : ""}
      <div class="svc-tile-actions">
        ${s.status !== "NotFound" ? `<button class="btn-outline btn-ol-blue svc-restart-btn" data-name="${esc(s.name)}">
          ${svgIcon("refresh", 12)} Restart
        </button>` : ""}
      </div>
    </div>`;
  }

  $page().innerHTML = `
    ${pageHeader("Pixellot Services", "Pixellot Agent, VPU encoder, and related Windows services",
      `<button class="btn-outline btn-ol-blue" onclick="dataCache.services=null;renderServices()">
        ${svgIcon("refresh", 14)} Refresh
      </button>`
    )}

    <!-- keepagentup.exe — PDF #13 fast-remedy action -->
    <div class="card svc-quick-action">
      <div class="svc-quick-action-row">
        <div>
          <div class="svc-quick-action-title">Restart Agent + Coordinator</div>
          <div class="svc-quick-action-body">
            Runs <span class="font-mono">c:\\pixellot\\bin\\keepagentup.exe</span> — the documented fast remedy when the Pixellot Agent or Coordinator is unresponsive. Try this before escalating to an RMA.
          </div>
        </div>
        <button class="btn-outline btn-ol-amber" id="svc-keepagent-btn">
          ${svgIcon("zap", 14)} Restart Agent + Coordinator
        </button>
      </div>
      <div id="svc-keepagent-result" class="svc-quick-action-result hidden"></div>
    </div>

    <!-- Reinstall Pixellot Dependencies — PDF #2 -->
    <!-- HIDDEN by default. ONLY revealed if /api/pixellot-logs reports
         depsErrorDetected=true (CUDNN/TensorFlow patterns found). Never
         show this as a casual action — it's a tier-2 remedy. -->
    <div class="card svc-quick-action svc-rare-action hidden" id="svc-reinstall-card">
      <div class="svc-quick-action-row">
        <div>
          <div class="svc-quick-action-title">
            Reinstall Pixellot Dependencies
            <span class="svc-rare-pill">RARELY USED</span>
          </div>
          <div class="svc-quick-action-body" id="svc-reinstall-body">
            Downloads <span class="font-mono">Pixellot-Installer-Dependencies-5.0.0.exe</span> to <span class="font-mono">C:\\pixellot\\downloadedversion\\</span> and runs it silently — documented remedy per PDF #2.
          </div>
          <div class="svc-rare-warn">
            ${svgIcon("alert", 12)}
            <span><strong>Do not run unless explicitly directed by Pixellot support or escalation.</strong> This is a last-resort remedy for confirmed CUDNN/TensorFlow dependency failures — recording is paused for 5–15 minutes and a reboot is recommended.</span>
          </div>
        </div>
        <button class="btn-outline btn-ol-red" id="svc-reinstall-btn">
          ${svgIcon("download", 14)} Reinstall Dependencies
        </button>
      </div>
      <div id="svc-reinstall-result" class="svc-quick-action-result hidden"></div>
    </div>

    <div class="svc-grid" id="svc-grid">
      ${svcs.map(svcTile).join("")}
      ${!svcs.length ? '<p class="text-pulse-muted text-sm">No services data</p>' : ""}
    </div>
  `;

  // Check the log scanner for CUDNN/TensorFlow errors — show the reinstall
  // card only when those errors are present so we don't suggest a 10-min
  // install on a healthy box.
  (async () => {
    const r = await api("/api/pixellot-logs?hours=48");
    if (currentPage !== "services") return;
    const card = document.getElementById("svc-reinstall-card");
    const body = document.getElementById("svc-reinstall-body");
    if (!card) return;
    if (r && !r.error && r.depsErrorDetected) {
      card.classList.remove("hidden");
      if (body) {
        body.innerHTML = `
          <span class="font-semibold" style="color:var(--c-accent-red)">${svgIcon("alert", 12)} CUDNN/TensorFlow errors detected in the VPU logs.</span>
          Downloads <span class="font-mono">Pixellot-Installer-Dependencies-5.0.0.exe</span> to <span class="font-mono">C:\\pixellot\\downloadedversion\\</span> and runs it silently — documented remedy per PDF #2.
        `;
      }
    }
  })();

  document.getElementById("svc-grid")?.addEventListener("click", async (e) => {
    const btn = e.target.closest(".svc-restart-btn");
    if (!btn) return;
    const name = btn.dataset.name;
    btn.disabled = true;
    btn.innerHTML = "Restarting...";
    const result = await apiPost("/api/services/restart", { serviceName: name });
    btn.disabled = false;
    btn.innerHTML = `${svgIcon("refresh", 12)} Restart`;
    if (result.success) {
      dataCache.services = null;
      renderServices();
    } else {
      btn.innerHTML = result.message || "Failed";
      setTimeout(() => { btn.innerHTML = `${svgIcon("refresh", 12)} Restart`; }, 3000);
    }
  });

  // keepagentup.exe — confirmation modal + inline result
  document.getElementById("svc-keepagent-btn")?.addEventListener("click", async () => {
    const ok = confirm(
      "Restart Pixellot Agent + Coordinator?\n\n" +
      "This runs c:\\pixellot\\bin\\keepagentup.exe, which will briefly stop and " +
      "relaunch both services. Recording may pause for a few seconds.\n\n" +
      "Proceed?"
    );
    if (!ok) return;

    const btn = document.getElementById("svc-keepagent-btn");
    const resultEl = document.getElementById("svc-keepagent-result");
    btn.disabled = true;
    btn.innerHTML = `${svgIcon("refresh", 14)} Running keepagentup.exe...`;
    resultEl.classList.add("hidden");

    const r = await apiPost("/api/services/restart-agent", {});
    btn.disabled = false;
    btn.innerHTML = `${svgIcon("zap", 14)} Restart Agent + Coordinator`;

    const ok2 = r && r.success;
    resultEl.className = "svc-quick-action-result " + (ok2 ? "svc-result-ok" : "svc-result-err");
    resultEl.innerHTML = `
      <div class="font-semibold">${ok2 ? svgIcon("check", 14) + " Success" : svgIcon("alert", 14) + " Failed"}</div>
      <div class="text-sm mt-1">${esc(r?.message || "(no message)")}</div>
      ${r?.agentStatus ? `<div class="text-xs mt-2 text-pulse-muted">Agent: <span class="font-mono">${esc(r.agentStatus)}</span> &middot; Coordinator: <span class="font-mono">${esc(r.coordinatorStatus || "?")}</span></div>` : ""}
      ${r?.stdout ? `<pre class="svc-result-output">${esc(r.stdout)}</pre>` : ""}
      ${r?.stderr ? `<pre class="svc-result-output svc-result-stderr">${esc(r.stderr)}</pre>` : ""}
    `;

    if (ok2) {
      // Refresh service-tile statuses in-place so the result panel stays visible
      api("/api/services").then(fresh => {
        if (!fresh || fresh.error || currentPage !== "services") return;
        dataCache.services = fresh;
        const grid = document.getElementById("svc-grid");
        if (grid) grid.innerHTML = (fresh.services || []).map(svcTile).join("");
      });
    }
  });

  // Reinstall Pixellot Dependencies (PDF #2) — confirm + run + show result
  document.getElementById("svc-reinstall-btn")?.addEventListener("click", async () => {
    const ok = confirm(
      "⚠ RARELY USED — Reinstall Pixellot Dependencies?\n\n" +
      "This is a tier-2 remedy. ONLY run it when:\n" +
      "  • Pixellot support or an escalation engineer has directed you to, OR\n" +
      "  • You have confirmed CUDNN_STATUS_* or TensorFlow errors in the VPU logs\n" +
      "    (see Event Viewer → Pixellot Logs).\n\n" +
      "Effects:\n" +
      "  • Downloads ~90 MB installer to C:\\pixellot\\downloadedversion\\\n" +
      "  • Runs silently — recording is PAUSED for 5–15 minutes\n" +
      "  • Reboot recommended afterward\n\n" +
      "Proceed?"
    );
    if (!ok) return;

    const btn = document.getElementById("svc-reinstall-btn");
    const result = document.getElementById("svc-reinstall-result");
    btn.disabled = true;
    btn.innerHTML = `${svgIcon("refresh", 14)} Downloading + installing…`;
    result.classList.remove("hidden");
    result.className = "svc-quick-action-result";
    result.innerHTML = `<div class="text-xs text-pulse-muted">Running — this can take 5–15 minutes. Watch the Script Log for progress.</div>`;

    const r = await apiPost("/api/services/reinstall-deps", {});
    btn.disabled = false;
    btn.innerHTML = `${svgIcon("download", 14)} Reinstall Dependencies`;

    const okState = r && r.success;
    result.className = "svc-quick-action-result " + (okState ? "svc-result-ok" : "svc-result-err");
    const stepsHtml = (r?.steps || []).map(s =>
      `<li class="px-step px-step-${esc(s.status)}">
        ${svgIcon(s.status === "ok" ? "check" : s.status === "skipped" ? "info" : "alert", 12)}
        <span class="font-semibold">${esc(s.label)}</span>
        <span class="text-xs text-pulse-muted">${esc(s.detail || "")}</span>
        ${s.durationMs ? `<span class="text-xs text-pulse-muted">· ${Math.round(s.durationMs/1000)}s</span>` : ""}
      </li>`
    ).join("");
    result.innerHTML = `
      <div class="font-semibold">${okState ? svgIcon("check", 14) + " Success" : svgIcon("alert", 14) + " Failed"}</div>
      <div class="text-sm mt-1">${esc(r?.message || "(no message)")}</div>
      ${stepsHtml ? `<ul class="px-steps mt-2">${stepsHtml}</ul>` : ""}
      ${r?.targetFile ? `<div class="text-xs text-pulse-muted mt-2">Installer: <span class="font-mono">${esc(r.targetFile)}</span></div>` : ""}
    `;
  });
}

// ── Disk Health ──────────────────────────────────────────────

function renderDiskHealth() {
  const data = cached("disk-health");
  if (!data) { $page().innerHTML = sectionLoading("Disk & System Health"); fetchSection("disk-health"); return; }

  if (data.error) { $page().innerHTML = errorBox(data.message); return; }

  const logical = data.logicalDisks || [];
  const physical = data.physicalDisks || [];
  const events = data.diskEvents || [];
  const paths = data.pixellotPaths || [];

  const allHealthy = physical.every(d => (d.healthStatus || "").toLowerCase() === "healthy");
  const smartLabel = allHealthy ? "All Disks Healthy" : "Issue Detected";
  const smartSev = allHealthy ? "ok" : "critical";

  const errorCount = events.length;
  const errorLabel = errorCount === 0 ? "No disk errors" : `${errorCount} event(s) in last 48h`;
  const errorSev = errorCount > 5 ? "critical" : errorCount > 0 ? "warning" : "ok";

  const osDrive = logical.find(d => d.deviceID === "C:") || logical[0];
  const osFreeGB = osDrive?.freeSpaceGB;
  const osLabel = osDrive ? `${osFreeGB} GB free of ${osDrive.sizeGB} GB` : "No data";
  const osSev = osFreeGB != null && osFreeGB < 50 ? "critical" : osFreeGB != null && osFreeGB < 100 ? "warning" : "ok";

  function summaryCard(icon, title, chipSev, chipText, value, desc) {
    return `<div class="card dh-summary-card">
      <div class="dh-summary-top">
        <span class="dh-summary-icon">${svgIcon(icon, 18)}</span>
        <span class="dh-summary-title">${esc(title)}</span>
        ${severityChip(chipSev, chipText)}
      </div>
      <div class="dh-summary-val">${esc(value)}</div>
      <div class="dh-summary-desc">${esc(desc)}</div>
    </div>`;
  }

  $page().innerHTML = `
    ${pageHeader("Disk & System Health", "SMART, free space, and the Pixellot data paths that fill up first",
      `<button class="btn-outline btn-ol-blue" onclick="dataCache['disk-health']=null;renderDiskHealth()">
        ${svgIcon("refresh", 14)} Refresh
      </button>`
    )}

    <!-- 3 Summary Cards -->
    <div class="dh-summary-row">
      ${summaryCard("heartbeat", "SMART Health", smartSev, smartLabel, smartLabel, "Per-disk health attributes")}
      ${summaryCard("alert", "Disk & Driver Errors", errorSev, errorLabel, errorLabel, "From the Windows Event Log (last 48 h)")}
      ${summaryCard("hdd", "OS Drive", osSev, osSev === "ok" ? "OK" : osSev === "warning" ? "Low" : "Critical", osLabel, "Drops below 50 GB → Critical")}
    </div>

    <!-- Volumes -->
    <div class="card">
      ${sectionTitle("database", "Volumes")}
      ${logical.length ? logical.map(d => {
        const pct = d.usedPercent || 0;
        const color = pct > 90 ? "#ef4444" : pct > 80 ? "#eab308" : "#3b82f6";
        const role = d.deviceID === "C:" ? "OS Drive" : "Storage";
        const status = pct > 90 ? "Critical" : pct > 80 ? "Low" : "OK";
        const statusColor = pct > 90 ? "var(--c-accent-red)" : pct > 80 ? "var(--c-accent-amber)" : "var(--c-accent-green)";
        return `<div class="dh-vol-row">
          <span class="dh-vol-drive font-mono">${esc(d.deviceID)}</span>
          <span class="dh-vol-role">${esc(role)}</span>
          <div class="dh-vol-bar-wrap">
            <div class="dash-vol-bar"><div class="dash-vol-fill" style="width:${Math.min(pct, 100)}%;background:${color}"></div></div>
          </div>
          <span class="dh-vol-free">${esc(String(d.freeSpaceGB))} free of ${esc(String(d.sizeGB))} GB</span>
          <span class="dh-vol-status" style="color:${statusColor}">${esc(status)}</span>
        </div>`;
      }).join("") : '<p class="text-pulse-muted text-sm">No volume data</p>'}
    </div>

    <!-- Pixellot Storage Paths -->
    ${paths.length ? `
    <div class="card mt-4">
      ${sectionTitle("file", "Pixellot Storage Paths")}
      <table class="data-table"><thead><tr>
        <th>Path</th><th>Description</th><th>Size</th><th>Status</th>
      </tr></thead><tbody>
      ${paths.map(p => `<tr>
        <td class="font-mono text-xs">${esc(p.path)}</td>
        <td class="text-pulse-muted">${esc(p.description || "")}</td>
        <td class="font-semibold">${p.sizeGB != null ? esc(String(p.sizeGB)) + " GB" : esc(p.error || "—")}</td>
        <td>${p.status ? statusBadge(p.status) : "—"}</td>
      </tr>`).join("")}
      </tbody></table>
    </div>` : ""}

    <!-- Physical Disks -->
    ${physical.length ? `
    <div class="card mt-4">
      ${sectionTitle("hdd", "Physical Disks")}
      <table class="data-table"><thead><tr>
        <th>Name</th><th>Type</th><th>Bus</th><th>Size</th><th>Health</th>
      </tr></thead><tbody>
      ${physical.map(d => `<tr>
        <td>${esc(d.friendlyName)}</td>
        <td>${esc(d.mediaType)}</td>
        <td>${esc(d.busType)}</td>
        <td>${esc(String(d.sizeGB))} GB</td>
        <td>${statusBadge(d.healthStatus || "Unknown")}</td>
      </tr>`).join("")}
      </tbody></table>
    </div>` : ""}

    <!-- Recent Disk Events -->
    ${events.length ? `
    <div class="card mt-4">
      ${sectionTitle("triangle", "Recent Disk Events")}
      <div class="max-h-60 overflow-y-auto">
        <table class="data-table"><thead><tr>
          <th>Time</th><th>Level</th><th>Source</th><th>Message</th>
        </tr></thead><tbody>
        ${events.map(e => `<tr>
          <td class="text-xs whitespace-nowrap">${formatTime(e.timeCreated)}</td>
          <td>${statusBadge(e.level)}</td>
          <td class="text-xs">${esc(e.source)}</td>
          <td class="text-xs max-w-md truncate">${esc(e.message)}</td>
        </tr>`).join("")}
        </tbody></table>
      </div>
    </div>` : ""}

    <!-- Repair Tools (PDF #1) — DISM CheckHealth / RestoreHealth, sfc, chkdsk -->
    <div class="card mt-4" id="dh-repair">
      ${sectionTitle("zap", "Repair Tools")}
      <p class="text-xs text-pulse-muted mb-3">
        Windows image &amp; file repair sequence. The first three tail
        <span class="font-mono">C:\\Windows\\Logs\\CBS\\CBS.log</span> on completion.
        <strong>RestoreHealth and SFC can take 10–30 minutes</strong> — leave the tab open.
      </p>
      <div class="dh-repair-grid">
        ${_repairCard("CheckHealth", "Check Image Health", "Fast (~30s) — reports component-store corruption without repairing.", "dism /Online /Cleanup-Image /CheckHealth")}
        ${_repairCard("RestoreHealth", "Restore Image", "Slow (5–20 min) — downloads + replaces corrupt component-store files.", "dism /Online /Cleanup-Image /RestoreHealth")}
        ${_repairCard("SfcScan", "Scan System Files", "Slow (10–30 min) — verifies protected system files against the image.", "sfc /scannow")}
        ${_repairCard("ChkdskSchedule", "Schedule chkdsk on Next Reboot", "Queues chkdsk /f /r C: — actual check runs on next boot. Returns immediately.", "chkdsk /f /r C:", /*amber*/ true)}
      </div>
    </div>
  `;

  // Wire up repair buttons
  document.querySelectorAll(".dh-repair-btn").forEach(btn => {
    btn.addEventListener("click", () => _runRepairTool(btn.dataset.action));
  });
}

function _repairCard(action, title, body, command, amber) {
  const cls = amber ? "btn-ol-amber" : "btn-ol-blue";
  return `<div class="dh-repair-card">
    <div class="dh-repair-title">${esc(title)}</div>
    <div class="dh-repair-body">${esc(body)}</div>
    <div class="dh-repair-cmd font-mono">${esc(command)}</div>
    <button class="btn-outline ${cls} dh-repair-btn" data-action="${esc(action)}">
      ${svgIcon("play", 12)} Run
    </button>
    <div class="dh-repair-result hidden" id="dh-repair-result-${esc(action)}"></div>
  </div>`;
}

async function _runRepairTool(action) {
  const titles = {
    CheckHealth: "Check Image Health",
    RestoreHealth: "Restore Image",
    SfcScan: "Scan System Files",
    ChkdskSchedule: "Schedule chkdsk",
  };
  const slow = action === "RestoreHealth" || action === "SfcScan";
  if (slow) {
    const ok = confirm(
      `${titles[action]} can take 10–30 minutes to complete. ` +
      `Pulse will block waiting for it.\n\nProceed?`
    );
    if (!ok) return;
  }

  const btn = document.querySelector(`.dh-repair-btn[data-action="${action}"]`);
  const result = document.getElementById(`dh-repair-result-${action}`);
  if (!btn || !result) return;

  btn.disabled = true;
  btn.innerHTML = `${svgIcon("refresh", 12)} Running…`;
  result.classList.remove("hidden");
  result.innerHTML = `<div class="text-xs text-pulse-muted">Running ${esc(titles[action] || action)}… ${slow ? "this may take a long time." : ""}</div>`;

  const r = await apiPost("/api/disk-health/repair", { action });

  btn.disabled = false;
  btn.innerHTML = `${svgIcon("play", 12)} Run again`;

  if (!r || r.error) {
    result.innerHTML = `<div class="dh-repair-result-err">
      ${svgIcon("alert", 14)} <span class="font-semibold">Failed</span>
      <div class="text-xs mt-1">${esc(r?.message || "(no message)")}</div>
    </div>`;
    return;
  }

  const okState = !!r.success;
  const durSec = r.durationMs ? Math.round(r.durationMs / 1000) : null;
  result.innerHTML = `
    <div class="${okState ? "dh-repair-result-ok" : "dh-repair-result-err"}">
      ${svgIcon(okState ? "check" : "alert", 14)}
      <span class="font-semibold">${okState ? "Completed" : (r.timedOut ? "Timed out" : "Failed")}</span>
      ${durSec != null ? ` <span class="text-xs text-pulse-muted">· ${durSec}s · exit code ${esc(String(r.exitCode))}</span>` : ""}
    </div>
    <details class="dh-repair-details mt-2">
      <summary class="text-xs text-pulse-muted">Command output</summary>
      <pre class="dh-repair-output">${esc(r.stdout || "(empty)")}</pre>
      ${r.stderr ? `<pre class="dh-repair-output dh-repair-stderr">${esc(r.stderr)}</pre>` : ""}
    </details>
    ${(r.cbsTail || []).length ? `
      <details class="dh-repair-details">
        <summary class="text-xs text-pulse-muted">CBS.log tail (last ${r.cbsTail.length} lines)</summary>
        <pre class="dh-repair-output">${esc((r.cbsTail || []).join("\n"))}</pre>
      </details>
    ` : ""}
  `;
}

function formatTime(iso) {
  if (!iso) return "--";
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return esc(iso);
  }
}

// ── Event Viewer ─────────────────────────────────────────────

function renderEvents() {
  $page().innerHTML = `
    ${pageHeader("Event Viewer", "Filtered Windows event-log entries for disk, NIC, Pixellot, and core service sources",
      `<button class="btn-outline btn-ol-blue" id="ev-refresh">
        ${svgIcon("refresh", 14)} Refresh
      </button>`
    )}

    <!-- Filter Row -->
    <div class="card ev-filter-card">
      <div class="ev-filter-row">
        <div class="ev-filter-group">
          <label class="ev-filter-label">TIME WINDOW</label>
          <select id="ev-hours" class="ev-select">
            <option value="12">Last 12 hours</option>
            <option value="24">Last 24 hours</option>
            <option value="48" selected>Last 48 hours</option>
            <option value="168">Last 7 days</option>
          </select>
        </div>
        <div class="ev-filter-group">
          <label class="ev-filter-label">LEVELS</label>
          <div class="ev-checks">
            <label class="ev-check"><input type="checkbox" id="ev-error" checked> <span style="color:var(--c-accent-red)">Error</span></label>
            <label class="ev-check"><input type="checkbox" id="ev-warning" checked> <span style="color:var(--c-accent-amber)">Warning</span></label>
            <label class="ev-check"><input type="checkbox" id="ev-info" checked> <span style="color:var(--c-accent-blue)">Information</span></label>
          </div>
        </div>
        <div class="ev-filter-group ev-filter-grow">
          <label class="ev-filter-label">SOURCE OR MESSAGE CONTAINS</label>
          <input type="text" id="ev-source" placeholder="e.g. disk, Pixellot, WHEA" class="ev-input"/>
        </div>
      </div>
    </div>

    <div class="card mt-4" id="ev-body">${loading()}</div>

    <!-- Pixellot Logs scan (PDF #5) — separate from Windows event log -->
    <div class="card mt-4" id="ev-pixellot-body">${loading()}</div>
  `;

  const loadEvents = async () => {
    const hours = document.getElementById("ev-hours").value;
    const evBody = document.getElementById("ev-body");
    evBody.innerHTML = loading();
    const data = await api(`/api/events?hours=${encodeURIComponent(hours)}&level=all`);
    if (currentPage !== "events") return;

    const showError = document.getElementById("ev-error")?.checked;
    const showWarning = document.getElementById("ev-warning")?.checked;
    const showInfo = document.getElementById("ev-info")?.checked;
    const sourceFilter = (document.getElementById("ev-source")?.value || "").toLowerCase();

    let entries = data.entries || [];
    entries = entries.filter(e => {
      const lvl = (e.level || "").toLowerCase();
      if (lvl === "error" && !showError) return false;
      if (lvl === "warning" && !showWarning) return false;
      if ((lvl === "information" || lvl === "info") && !showInfo) return false;
      if (sourceFilter && !(e.source || "").toLowerCase().includes(sourceFilter) && !(e.message || "").toLowerCase().includes(sourceFilter)) return false;
      return true;
    });

    if (!entries.length) {
      evBody.innerHTML = '<div class="text-center py-8 text-pulse-muted">No events found for this filter.</div>';
      return;
    }

    function levelChip(level) {
      const l = (level || "").toLowerCase();
      if (l === "error") return '<span class="ev-level-chip ev-level-error">Error</span>';
      if (l === "warning") return '<span class="ev-level-chip ev-level-warn">Warning</span>';
      return '<span class="ev-level-chip ev-level-info">Information</span>';
    }

    evBody.innerHTML = `
      <div class="ev-count">${entries.length} events</div>
      <div class="ev-table-wrap">
        <table class="data-table ev-table"><thead><tr>
          <th>Timestamp</th><th>Level</th><th>Source</th><th>Event ID</th><th>Message</th>
        </tr></thead><tbody>
        ${entries.map(e => `<tr>
          <td class="text-xs whitespace-nowrap font-mono">${formatTime(e.timeCreated)}</td>
          <td>${levelChip(e.level)}</td>
          <td class="text-xs">${esc(e.source)}</td>
          <td class="text-xs font-mono">${esc(String(e.eventId || ""))}</td>
          <td class="text-xs ev-msg-cell" title="${esc(e.message)}">${esc(e.message)}</td>
        </tr>`).join("")}
        </tbody></table>
      </div>
    `;
  };

  // Pixellot logs scanner (PDF #5) — scans C:\Pixellot\Data\Log for
  // error / fatal / restart markers. Surfaces CUDNN/TensorFlow patterns
  // with a "reinstall dependencies" hint per PDF #2.
  const loadPixellotLogs = async () => {
    const hours = document.getElementById("ev-hours").value;
    const body = document.getElementById("ev-pixellot-body");
    if (!body) return;
    body.innerHTML = loading();
    const data = await api(`/api/pixellot-logs?hours=${encodeURIComponent(hours)}`);
    if (currentPage !== "events") return;

    if (data.error) {
      body.innerHTML = `${sectionTitle("file", "Pixellot Logs")}
        <p class="text-sm text-pulse-muted">${esc(data.message || "Failed to scan Pixellot logs")}</p>`;
      return;
    }

    const entries = data.entries || [];
    const stats = data.stats || {};
    const depsErr = !!data.depsErrorDetected;

    const levelChip = (lvl) => {
      const l = (lvl || "").toLowerCase();
      if (l === "fatal")   return '<span class="ev-level-chip ev-level-error">Fatal</span>';
      if (l === "error")   return '<span class="ev-level-chip ev-level-error">Error</span>';
      if (l === "restart") return '<span class="ev-level-chip ev-level-warn">Restart</span>';
      return `<span class="ev-level-chip ev-level-info">${esc(l)}</span>`;
    };

    body.innerHTML = `
      ${sectionTitle("file", "Pixellot Logs")}
      <p class="text-xs text-pulse-muted mb-3">
        Scanned ${esc(String(data.scannedFiles || 0))} log file(s) in <span class="font-mono">C:\\Pixellot\\Data\\Log</span> over the last ${esc(String(data.hoursBack || ""))} hour(s).
      </p>

      <div class="px-log-summary">
        <span class="px-log-stat ${stats.fatal > 0 ? 'px-log-stat-bad' : ''}">${esc(String(stats.fatal || 0))} fatal</span>
        <span class="px-log-stat ${stats.error > 0 ? 'px-log-stat-bad' : ''}">${esc(String(stats.error || 0))} error</span>
        <span class="px-log-stat ${stats.restart > 0 ? 'px-log-stat-warn' : ''}">${esc(String(stats.restart || 0))} restart</span>
      </div>

      ${depsErr ? `<div class="px-log-deps-warn mt-3">
        ${svgIcon("alert", 14)}
        <div>
          <div class="font-semibold">CUDNN / TensorFlow failure detected</div>
          <div class="text-xs mt-1">A known Pixellot dependency error appeared in the logs. The documented remedy is to reinstall the Pixellot dependencies installer — see PDF #2.</div>
        </div>
      </div>` : ""}

      ${data.warning ? `<p class="text-xs text-pulse-muted mt-2">${esc(data.warning)}</p>` : ""}

      ${entries.length ? `
        <div class="ev-table-wrap mt-3">
          <table class="data-table ev-table"><thead><tr>
            <th>Time</th><th>Level</th><th>File</th><th>Line</th><th>Content</th>
          </tr></thead><tbody>
          ${entries.map(e => `<tr class="${e.depsError ? 'px-log-row-deps' : ''}">
            <td class="text-xs whitespace-nowrap font-mono">${esc(e.timestamp || formatTime(e.fileMTime))}</td>
            <td>${levelChip(e.level)}</td>
            <td class="text-xs font-mono">${esc(e.file)}</td>
            <td class="text-xs font-mono">${esc(String(e.lineNumber || ""))}</td>
            <td class="text-xs ev-msg-cell" title="${esc(e.content)}">${esc(e.content)}${e.depsError ? ' <span class="px-log-deps-pill">DEPS</span>' : ''}</td>
          </tr>`).join("")}
          </tbody></table>
        </div>
        ${data.truncated ? '<p class="text-xs text-pulse-muted mt-2">Results truncated at 500 matches.</p>' : ""}
      ` : '<p class="text-sm text-pulse-muted mt-3">No matching entries.</p>'}
    `;
  };

  document.getElementById("ev-refresh")?.addEventListener("click", () => { loadEvents(); loadPixellotLogs(); });
  document.getElementById("ev-hours")?.addEventListener("change", () => { loadEvents(); loadPixellotLogs(); });
  ["ev-error", "ev-warning", "ev-info"].forEach(id => {
    document.getElementById(id)?.addEventListener("change", loadEvents);
  });
  document.getElementById("ev-source")?.addEventListener("input", _debounce(loadEvents, 300));
  loadEvents();
  loadPixellotLogs();
}

// ── Reports ──────────────────────────────────────────────────

function renderReports() {
  $page().innerHTML = `
    ${pageHeader("Reports", "Diagnostic-run snapshots — generate and download full system reports",
      `<button class="btn-outline btn-ol-green" id="rpt-export">
        ${svgIcon("download", 14)} Generate Report
      </button>
      <button class="btn-outline btn-ol-blue" onclick="refreshAll()">
        ${svgIcon("play", 14)} Run All Diagnostics
      </button>`
    )}

    <div class="card">
      ${sectionTitle("file", "Full Diagnostic Export")}
      <p class="text-sm text-pulse-muted mb-4">Generate a complete diagnostic report containing all system, network, and service data. This runs every data collection script and bundles the output into a downloadable JSON file.</p>
      <span id="rpt-status" class="text-sm text-pulse-muted"></span>
      <div id="rpt-result" class="mt-4"></div>
    </div>
  `;

  document.getElementById("rpt-export")?.addEventListener("click", async () => {
    const btn = document.getElementById("rpt-export");
    const status = document.getElementById("rpt-status");
    btn.disabled = true;
    status.textContent = "Collecting data from all scripts...";
    const data = await api("/api/reports/export");
    btn.disabled = false;
    if (data.error) {
      status.textContent = "Error: " + (data.message || "Unknown");
      return;
    }
    status.textContent = "Report ready.";

    const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const hostname = data.identity?.computerSystem?.name || "vpu";
    const ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
    const filename = "pulse-report-" + hostname + "-" + ts + ".json";

    document.getElementById("rpt-result").innerHTML = `
      <a href="${url}" download="${esc(filename)}" class="btn-outline btn-ol-green" style="display:inline-flex;align-items:center;gap:6px">
        ${svgIcon("download", 14)} Download ${esc(filename)}
      </a>
      <details class="mt-4">
        <summary class="text-sm text-pulse-muted cursor-pointer">Preview data</summary>
        <pre class="mt-2 p-4 bg-pulse-bg rounded text-xs overflow-auto max-h-96 text-pulse-muted">${esc(JSON.stringify(data, null, 2))}</pre>
      </details>
    `;
  });
}

// ── ScoreConnect ─────────────────────────────────────────────

// ── SC III Installer ─────────────────────────────────────────

var _sc3InstallPoll = null;  // polling interval handle

async function installSc3(btn) {
  // Replace the upgrade banner contents with a progress UI
  var card = btn.closest(".card");
  if (!card) return;
  _renderSc3Progress(card, { stage: "starting", percent: 2, message: "Requesting elevation…" });

  // Kick off the install — backend returns immediately
  var result = await apiPost("/api/scoreconnect/install-sc3");
  if (!result || !result.ok) {
    _renderSc3Progress(card, {
      stage: "failed", percent: 0,
      message: "Failed to start install",
      error: (result && (result.error || result.message)) || "Unknown error"
    });
    return;
  }

  // Begin polling for progress every 1.5s
  if (_sc3InstallPoll) clearInterval(_sc3InstallPoll);
  _sc3InstallPoll = setInterval(async function() {
    var s = await api("/api/scoreconnect/install-sc3/status");
    _renderSc3Progress(card, s);

    if (s.stage === "complete") {
      clearInterval(_sc3InstallPoll); _sc3InstallPoll = null;
      // Refresh the SC data after a moment so the user sees SC III detected
      setTimeout(function() {
        dataCache.scoreconnect = null;
        if (window.location.hash === "#scoreconnect") renderScoreConnect();
      }, 3000);
    } else if (s.stage === "failed" || s.stale) {
      clearInterval(_sc3InstallPoll); _sc3InstallPoll = null;
    }
  }, 1500);
}

function _renderSc3Progress(card, status) {
  var stage = status.stage || "unknown";
  var pct = Math.max(0, Math.min(100, status.percent || 0));
  var msg = status.message || "";
  var err = status.error || null;
  var stale = status.stale;

  var stageLabel = {
    starting:    "Starting…",
    downloading: "Downloading",
    installing:  "Installing",
    verifying:   "Verifying",
    complete:    "Complete",
    failed:      "Failed",
    idle:        "Idle"
  }[stage] || stage;

  var barColor = stage === "failed" ? "var(--c-accent-red)"
    : stage === "complete" ? "var(--c-accent-green)"
    : "var(--c-accent-blue)";

  var iconName = stage === "complete" ? "check"
    : stage === "failed" ? "x"
    : "refresh";

  card.innerHTML = `
    <div style="display:flex;align-items:flex-start;gap:0.75rem">
      <div style="margin-top:2px;color:${barColor}">${svgIcon(iconName, 18)}</div>
      <div style="flex:1">
        <div class="font-semibold" style="margin-bottom:0.25rem">
          ScoreConnect III Install — ${esc(stageLabel)}${pct ? ' <span class="text-pulse-muted" style="font-weight:normal">(' + pct + '%)</span>' : ''}
        </div>
        <div class="text-pulse-muted" style="font-size:0.8rem;line-height:1.5">${esc(msg)}</div>
        <div style="margin-top:0.6rem;height:8px;background:var(--c-deep-bg);border-radius:4px;overflow:hidden;border:1px solid var(--c-border)">
          <div style="height:100%;width:${pct}%;background:${barColor};transition:width 0.5s ease-out"></div>
        </div>
        ${err ? `<div class="status-fail" style="font-size:0.75rem;margin-top:0.5rem">${esc(err)}</div>` : ""}
        ${stale ? `<div class="text-pulse-muted" style="font-size:0.72rem;margin-top:0.35rem">Install appears stalled — the UAC prompt may have been declined.</div>` : ""}
        ${(stage === "failed" || stale) ? `<button class="btn-outline btn-ol-blue" style="margin-top:0.6rem" onclick="installSc3(this)">${svgIcon("refresh", 14)} Retry Install</button>` : ""}
        ${stage === "complete" ? `<div class="status-pass" style="font-size:0.8rem;margin-top:0.5rem">ScoreConnect III is now installed. Refreshing data…</div>` : ""}
      </div>
    </div>
  `;
}

// ── RTD Score Parser ─────────────────────────────────────────
// Multi-strategy parser for scoreboard data from SC III.
// Supports all major vendors: Daktronics, Fairplay, Nevco,
// Electro-Mech, Spectrum/Sportable/Varsity.
//
// Strategy order:
//   1. JSON — if raw data is a JSON string with named fields, parse it.
//      (Sportzcast TCP socket format uses JSON; SC III may pass it through.)
//   2. Vendor-specific positional — fixed-width field maps per vendor.
//   3. Heuristic — regex pattern matching for clock/score/period in any string.
//
// Returns { clock, homeScore, guestScore, period, down, toGo, ballOn,
//           possession, _strategy } or null if nothing extractable.
function parseRtdScores(rawData, vendor, sport) {
  if (!rawData || typeof rawData !== "string") return null;
  var vLower = (vendor || "").toLowerCase();
  var sLower = (sport  || "").toLowerCase();

  // ── Strategy 1: JSON parse ──────────────────────────────────────────
  // Sportzcast data may arrive as JSON: {"homeScore":"14","awayScore":"7",...}
  var trimmed = rawData.trim();
  if (trimmed.charAt(0) === "{") {
    try {
      var j = JSON.parse(trimmed);
      // Normalize field names (Sportzcast uses multiple conventions)
      var _jv = function() { for (var i=0;i<arguments.length;i++) { var v=j[arguments[i]]; if (v!=null&&v!=="") return v; } return null; };
      var r = {
        clock:      _jv("clock","Clock","time","Time","gameTime","gameClock"),
        homeScore:  _jv("homeScore","HomeScore","scoreHome","home_score","hScore"),
        guestScore: _jv("awayScore","AwayScore","guestScore","GuestScore","scoreAway","away_score","vScore","visitor_score"),
        period:     _jv("period","Period","quarter","Quarter","half","Half","inning","Inning"),
        down:       _jv("down","Down"),
        toGo:       _jv("toGo","ToGo","yardsToGo"),
        ballOn:     _jv("ballOn","BallOn"),
        possession: _jv("possession","Possession","poss"),
        _strategy:  "json"
      };
      // Coerce scores to numbers
      if (r.homeScore  != null) r.homeScore  = parseInt(r.homeScore, 10);
      if (r.guestScore != null) r.guestScore = parseInt(r.guestScore, 10);
      if (r.period     != null && !isNaN(parseInt(r.period,10))) r.period = parseInt(r.period, 10);
      if (r.down       != null) r.down = parseInt(r.down, 10);
      if (r.toGo       != null) r.toGo = parseInt(r.toGo, 10);
      if (r.ballOn     != null) r.ballOn = parseInt(r.ballOn, 10);
      if (r.clock || r.homeScore != null || r.guestScore != null) return r;
    } catch(e) { /* not JSON, continue */ }
  }

  // ── Strategy 2: Vendor-specific positional parsing ──────────────────
  // Strip trailing metadata (serial/ID blocks like "S:S ..." or MAC addresses)
  var cleaned = rawData.replace(/\s*S:S\s.*$/, "").replace(/\s+$/, "");
  if (cleaned.length < 5) { /* fall through to heuristic */ }
  else {
    // Helpers
    function chars(p, n) {
      if (p + n > cleaned.length) return null;
      var s = cleaned.substring(p, p + n).trim();
      return s.length ? s : null;
    }
    function num(p, n) {
      var s = chars(p, n);
      if (!s) return null;
      var v = parseInt(s, 10);
      return isNaN(v) ? null : v;
    }
    function numFlex(p, n) {
      // Try n chars, then n-1 at same position
      var v = num(p, n);
      if (v !== null) return v;
      return n > 1 ? num(p, n - 1) : null;
    }
    function extractClock(region) {
      var m = region.match(/(\d{1,2}:\d{2})/);
      if (m) return m[1];
      m = region.match(/(\d{1,2}\.\d)/);
      return m ? m[1] : null;
    }

    var r2 = { clock: null, homeScore: null, guestScore: null, period: null,
               down: null, toGo: null, ballOn: null, possession: null, _strategy: null };

    // ── Daktronics All Sport CG ───────────────────────────────────────
    // Clock pos 0-4, Guest 5-7, Home 8-10, Period 11, Poss 12, Down 13-14
    if (vLower.includes("daktronics")) {
      r2._strategy = "daktronics";
      r2.clock = extractClock(cleaned.substring(0, 12));
      r2.guestScore = numFlex(5, 3);
      r2.homeScore  = numFlex(8, 3);
      r2.period     = num(11, 1);
      if (sLower.includes("football")) {
        var pChar = chars(12, 1);
        if (pChar === "<" || pChar === ">") r2.possession = pChar;
        r2.down   = numFlex(13, 2);
        r2.ballOn = numFlex(15, 2);
        r2.toGo   = numFlex(17, 2);
      }
    }

    // ── Fairplay (MP-69, MP-80, Proline) ──────────────────────────────
    // BCD-decoded output: clock first, then digit-pair scores.
    // Format: Clock(5) Guest(3) Home(3) Period(1) — similar to Daktronics
    // but score digits are BCD-decoded pairs (Tens+Ones).
    else if (vLower.includes("fairplay") || vLower.includes("fair play") || vLower.includes("fair-play")) {
      r2._strategy = "fairplay";
      r2.clock = extractClock(cleaned.substring(0, 12));
      r2.guestScore = numFlex(5, 3);
      r2.homeScore  = numFlex(8, 3);
      r2.period     = num(11, 1);
    }

    // ── Nevco ─────────────────────────────────────────────────────────
    // BCD-decoded output via NevcoDigit/NevcoShotclockBcd.
    // Decoded layout follows similar positional convention.
    else if (vLower.includes("nevco")) {
      r2._strategy = "nevco";
      r2.clock = extractClock(cleaned.substring(0, 12));
      r2.guestScore = numFlex(5, 3);
      r2.homeScore  = numFlex(8, 3);
      r2.period     = num(11, 1);
    }

    // ── Electro-Mech ──────────────────────────────────────────────────
    // Multiple controller models (ElectromechModel enum).
    // Try common positional layout.
    else if (vLower.includes("electro") && vLower.includes("mech")) {
      r2._strategy = "electromech";
      r2.clock = extractClock(cleaned.substring(0, 12));
      r2.guestScore = numFlex(5, 3);
      r2.homeScore  = numFlex(8, 3);
      r2.period     = num(11, 1);
    }

    // ── Spectrum / Sportable / Varsity ────────────────────────────────
    // Multiple protocol generations (V2E, V2W, Gen2).
    // Try common positional layout.
    else if (vLower.includes("spectrum") || vLower.includes("sportable") || vLower.includes("varsity")) {
      r2._strategy = "spectrum";
      r2.clock = extractClock(cleaned.substring(0, 12));
      r2.guestScore = numFlex(5, 3);
      r2.homeScore  = numFlex(8, 3);
      r2.period     = num(11, 1);
    }

    // ── Unknown vendor — still try positional ─────────────────────────
    else if (cleaned.length >= 10) {
      r2._strategy = "positional-generic";
      r2.clock = extractClock(cleaned.substring(0, 12));
      r2.guestScore = numFlex(5, 3);
      r2.homeScore  = numFlex(8, 3);
      r2.period     = num(11, 1);
    }

    // Did positional parsing find anything?
    if (r2._strategy && (r2.clock || r2.homeScore != null || r2.guestScore != null)) {
      return r2;
    }
  }

  // ── Strategy 3: Heuristic regex extraction ──────────────────────────
  // Last resort — try to pull recognizable patterns from any data string.
  var h = { clock: null, homeScore: null, guestScore: null, period: null,
            down: null, toGo: null, ballOn: null, possession: null, _strategy: "heuristic" };

  // Clock: look for MM:SS or M:SS or SS.T anywhere in the string
  var cm = rawData.match(/\b(\d{1,2}:\d{2})\b/);
  if (cm) h.clock = cm[1];
  else { cm = rawData.match(/\b(\d{1,2}\.\d)\b/); if (cm) h.clock = cm[1]; }

  // Scores: look for two small numbers (0-199) separated by whitespace
  // near the clock, skipping the clock digits themselves.
  var afterClock = h.clock ? rawData.substring(rawData.indexOf(h.clock) + h.clock.length) : rawData;
  var scoreNums = [];
  var numRe = /\b(\d{1,3})\b/g;
  var nm;
  while ((nm = numRe.exec(afterClock)) !== null) {
    var v = parseInt(nm[1], 10);
    if (v <= 199) scoreNums.push(v);
    if (scoreNums.length >= 3) break;
  }
  if (scoreNums.length >= 2) {
    h.guestScore = scoreNums[0];
    h.homeScore  = scoreNums[1];
    if (scoreNums.length >= 3 && scoreNums[2] <= 9) h.period = scoreNums[2];
  }

  if (h.clock || h.homeScore != null || h.guestScore != null) return h;
  return null;
}

function renderScoreConnect() {
  const data = cached("scoreconnect");
  if (!data) { $page().innerHTML = sectionLoading("ScoreConnect"); fetchSection("scoreconnect"); return; }

  const sc2 = data.sc2;  // SC II data (from settings.json on disk)
  const config = data.configuration || {};
  const botStatus = data.botStatus || {};
  const isDetected = data.reachable;  // SC III
  const anySC = isDetected || (sc2 && sc2.reachable);
  const version = data.version;
  const hasData = data.dataStatus && !data.dataStatus.toLowerCase().includes("no scoreboard");
  const dataReceiving = hasData && data.rawData;

  // RTD parsed scores from SC III raw data
  const rtdParsed = dataReceiving ? parseRtdScores(data.rawData, config.vendor, config.sport) : null;

  // SC II config/teams
  const sc2Teams = sc2 && sc2.teamNames || {};
  const sc2HasConfig = sc2 && sc2.reachable && (sc2.vendor || sc2.botNumber || sc2.version);

  // Team name source: SC II settings.json has configured names, use as labels
  const visitorLabel = sc2Teams.visitor || "GUEST";
  const homeLabel = sc2Teams.home || "HOME";

  // SC II status LED helper: 0=grey 1=yellow 2=green
  function ledClass(val) {
    return val === 2 ? "status-pass" : val === 1 ? "status-warn" : "text-pulse-muted";
  }
  function ledLabel(val) {
    return val === 2 ? "OK" : val === 1 ? "Warning" : "Off";
  }

  // Build BOT and ScoreLink cards independently
  const botCard = botStatus.isConnected != null ? `
    <div class="card">
      ${sectionTitle("globe", "Cloud (BOT) Status")}
      <div class="kv-grid">
        ${kvRowHtml("Connected", botStatus.isConnected
          ? '<span class="status-pass">Yes</span>'
          : '<span class="status-fail">No</span>')}
        ${botStatus.scoreConnectId ? kvRowHtml("ScoreConnect ID",
          `${esc(botStatus.scoreConnectId)} <span class="text-pulse-muted" style="font-size:0.75rem">(may be stale)</span>`)
          : ""}
        ${kvRow("BOT Server", botStatus.botServerAddress)}
        ${botStatus.lastErrorMessage ? kvRowHtml("Last Error", `<span class="text-pulse-muted">${esc(botStatus.lastErrorMessage)}</span>`) : ""}
      </div>
    </div>` : "";

  const slCard = data.scoreLinkConnected != null && anySC ? `
    <div class="card sc-sl-card">
      ${sectionTitle("link", "ScoreLink Device")}
      <div class="sc-scorelink ${data.scoreLinkConnected ? "sc-scorelink-ok" : "sc-scorelink-err"}">
        <span class="sc-scorelink-dot"></span>
        <span class="font-semibold">${esc(data.scoreLinkStatusLabel || (data.scoreLinkConnected ? "ScoreLink Connected" : "ScoreLink Not Detected"))}</span>
      </div>
    </div>` : "";

  // Determine page subtitle based on what's detected
  const subtitle = sc2 && sc2.reachable && isDetected
    ? "ScoreConnect II + III detected"
    : sc2 && sc2.reachable
    ? "ScoreConnect II — configuration from device"
    : "ScoreConnect III — service, configuration, and live data";

  $page().innerHTML = `
    ${pageHeader("Score Connect", subtitle,
      `<button class="btn-outline btn-ol-blue" onclick="dataCache.scoreconnect=null;renderScoreConnect()">
        ${svgIcon("refresh", 14)} Refresh
      </button>`
    )}

    <!-- SC II hero — config from settings.json on disk -->
    ${sc2HasConfig ? `
    <div class="sc-board sc-board-hero">
      <div class="sc-header">
        <div class="sc-team-home">
          <div class="sc-team-label">${esc(sc2Teams.visitor || "VISITOR")}</div>
          <div class="sc-team-name" style="font-size:1.1rem">${esc(sc2.vendor || "—")}</div>
        </div>
        <div class="sc-center">
          <div class="sc-data-status">
            <span class="sc-data-dot sc-data-dot-on"></span>
            <span class="sc-data-label">SC II Running</span>
          </div>
          <div class="sc-data-desc">${esc(sc2.hardware || "ScoreConnect II")} v${esc(sc2.version || "?")}</div>
        </div>
        <div class="sc-team-away">
          <div class="sc-team-label">${esc(sc2Teams.home || "HOME")}</div>
          <div class="sc-team-name" style="font-size:1.1rem">Bot# ${esc(String(sc2.botNumber || "—"))}</div>
        </div>
      </div>
      <div class="sc-stats">
        <div class="sc-stat-group">
          ${sc2.uid ? `<div class="sc-stat"><span class="sc-stat-val">${esc(sc2.uid)}</span><span class="sc-stat-lbl">UID</span></div>` : ""}
          ${sc2.license ? `<div class="sc-stat"><span class="sc-stat-val">${esc(sc2.license)}</span><span class="sc-stat-lbl">License Exp</span></div>` : ""}
        </div>
        <div class="sc-stat-group sc-stat-right">
          ${sc2.scoreLink ? `<div class="sc-stat"><span class="sc-stat-val">${esc(sc2.scoreLink.description || "—")}</span><span class="sc-stat-lbl">ScoreLink</span></div>` : ""}
          ${sc2.scoreLink && sc2.scoreLink.serial ? `<div class="sc-stat"><span class="sc-stat-val">${esc(sc2.scoreLink.serial)}</span><span class="sc-stat-lbl">Serial</span></div>` : ""}
        </div>
      </div>
    </div>
    ` : sc2 && sc2.reachable ? `
    <div class="sc-board sc-board-hero">
      <div class="sc-header">
        <div class="sc-center">
          <div class="sc-data-status">
            <span class="sc-data-dot sc-data-dot-on"></span>
            <span class="sc-data-label">SC II Running</span>
          </div>
          <div class="sc-data-desc">Service detected on port 1400</div>
        </div>
      </div>
    </div>
    ` : ""}

    <!-- SC III Parsed Scoreboard — when RTD parser extracts scores -->
    ${rtdParsed ? `
    <div class="sc-board ${sc2HasConfig ? "mt-4" : "sc-board-hero"}">
      <div class="sc-header">
        <div class="sc-team-home">
          <div class="sc-team-label">${esc(visitorLabel)}</div>
          <div class="sc-score">${rtdParsed.guestScore != null ? esc(String(rtdParsed.guestScore)) : "—"}</div>
        </div>
        <div class="sc-center">
          <div class="sc-period-label">${rtdParsed.period ? "Q" + rtdParsed.period : "GAME CLOCK"}</div>
          <div class="sc-clock">${esc(rtdParsed.clock || "--:--")}</div>
          ${rtdParsed.down ? `<div class="sc-data-desc">${esc(String(rtdParsed.down))}${rtdParsed.toGo ? " &amp; " + esc(String(rtdParsed.toGo)) : ""}${rtdParsed.ballOn ? " on " + esc(String(rtdParsed.ballOn)) : ""}</div>` : ""}
        </div>
        <div class="sc-team-away">
          <div class="sc-team-label">${esc(homeLabel)}</div>
          <div class="sc-score">${rtdParsed.homeScore != null ? esc(String(rtdParsed.homeScore)) : "—"}</div>
        </div>
      </div>
      <div class="sc-stats">
        <div class="sc-stat-group">
          ${config.vendor ? `<div class="sc-stat"><span class="sc-stat-val">${esc(config.vendor)}</span><span class="sc-stat-lbl">Vendor</span></div>` : ""}
          ${config.sport ? `<div class="sc-stat"><span class="sc-stat-val">${esc(config.sport)}</span><span class="sc-stat-lbl">Sport</span></div>` : ""}
        </div>
        <div class="sc-stat-group sc-stat-right">
          ${config.vendorConfigurationName ? `<div class="sc-stat"><span class="sc-stat-val">${esc(config.vendorConfigurationName)}</span><span class="sc-stat-lbl">Connection</span></div>` : ""}
          ${version ? `<div class="sc-stat"><span class="sc-stat-val">${esc(version)}</span><span class="sc-stat-lbl">SC III Version</span></div>` : ""}
        </div>
      </div>
    </div>
    ` : ""}

    <!-- SC III Data Flow — shown when SC III detected (raw data + status) -->
    ${isDetected ? `
    <div class="sc-board ${sc2HasConfig || rtdParsed ? "mt-4" : "sc-board-hero"}">
      <div class="sc-header">
        <div class="sc-team-home">
          <div class="sc-team-label">Vendor</div>
          <div class="sc-team-name">${esc(config.vendor || "—")}</div>
        </div>
        <div class="sc-center">
          <div class="sc-data-status">
            <span class="sc-data-dot ${dataReceiving ? "sc-data-dot-on" : "sc-data-dot-off"}"></span>
            <span class="sc-data-label">${dataReceiving ? "Receiving Data" : "No Data"}</span>
          </div>
          ${data.dataStatus ? `<div class="sc-data-desc">${esc(data.dataStatus)}</div>` : ""}
        </div>
        <div class="sc-team-away">
          <div class="sc-team-label">Sport</div>
          <div class="sc-team-name">${esc(config.sport || "—")}</div>
        </div>
      </div>
      ${data.rawData ? `
      <div class="sc-raw-data">
        <div class="sc-raw-label">RAW SCOREBOARD DATA (SC III)</div>
        <div class="sc-raw-value">${esc(data.rawData)}</div>
      </div>` : ""}
      <div class="sc-stats">
        <div class="sc-stat-group">
          ${data.hasLocalStream != null ? `<div class="sc-stat"><span class="sc-stat-val">${data.hasLocalStream ? "Yes" : "No"}</span><span class="sc-stat-lbl">Local Stream</span></div>` : ""}
          ${data.networkStatus ? `<div class="sc-stat"><span class="sc-stat-val">${data.networkStatus.includes("detected") ? "Yes" : "No"}</span><span class="sc-stat-lbl">Internet</span></div>` : ""}
        </div>
        <div class="sc-stat-group sc-stat-right">
          ${config.vendorConfigurationName ? `<div class="sc-stat"><span class="sc-stat-val">${esc(config.vendorConfigurationName)}</span><span class="sc-stat-lbl">Connection</span></div>` : ""}
          ${version ? `<div class="sc-stat"><span class="sc-stat-val">${esc(version)}</span><span class="sc-stat-lbl">Version</span></div>` : ""}
        </div>
      </div>
    </div>
    ` : !(sc2 && sc2.reachable) ? `<div class="sc-board sc-board-hero sc-board-empty">No ScoreConnect service detected</div>` : ""}

    <!-- SC II → SC III Upgrade Prompt -->
    ${sc2 && sc2.reachable && !isDetected ? `
    <div class="card mt-4" style="border:1px solid var(--c-accent-blue)">
      <div style="display:flex;align-items:flex-start;gap:0.75rem">
        <div style="margin-top:2px;color:var(--c-accent-blue)">${svgIcon("refresh", 18)}</div>
        <div style="flex:1">
          <div class="font-semibold" style="margin-bottom:0.25rem">Upgrade to ScoreConnect III</div>
          <div class="text-pulse-muted" style="font-size:0.8rem;line-height:1.5">
            SC III is the preferred version. It provides live scoreboard data, parsed scores,
            and real-time status through a REST API — no interference with the data stream.
          </div>
          <div style="margin-top:0.75rem">
            <button class="btn-outline btn-ol-blue" id="btn-install-sc3" onclick="installSc3(this)">
              ${svgIcon("download", 14)} Install ScoreConnect III
            </button>
          </div>
          <div class="text-pulse-muted" style="font-size:0.72rem;margin-top:0.5rem">
            Downloads the official installer from the Canopy CDN and runs it in the background.
            A UAC prompt will appear on the VPU desktop to approve elevation.
          </div>
        </div>
      </div>
    </div>
    ` : ""}

    <!-- SC II Detail Card -->
    ${sc2HasConfig ? `
    <div class="card mt-4">
      ${sectionTitle("heartbeat", "SC II Details")}
      <div class="kv-grid">
        ${kvRowHtml("Status", '<span class="status-pass">Running</span>')}
        ${kvRow("Version", sc2.version)}
        ${kvRow("Hardware", sc2.hardware)}
        ${kvRow("UID", sc2.uid)}
        ${sc2.botNumber ? kvRow("Bot Number", sc2.botNumber) : ""}
        ${sc2.vendor ? kvRow("Vendor", sc2.vendor) : ""}
        ${sc2.sport ? kvRow("Sport Code", sc2.sport) : ""}
        ${sc2.license ? kvRow("License Expires", sc2.license) : ""}
        ${sc2.scoreLink ? kvRow("ScoreLink", sc2.scoreLink.description) : ""}
        ${sc2.scoreLink && sc2.scoreLink.serial ? kvRow("ScoreLink Serial", sc2.scoreLink.serial) : ""}
        ${sc2Teams.visitor ? kvRow("Visitor Name", sc2Teams.visitor) : ""}
        ${sc2Teams.home ? kvRow("Home Name", sc2Teams.home) : ""}
      </div>
      ${sc2.networkIfaces && sc2.networkIfaces.length ? `
      <div style="margin-top:0.75rem;padding-top:0.75rem;border-top:1px solid var(--border)">
        <div style="font-size:0.7rem;text-transform:uppercase;letter-spacing:0.05em;color:var(--text-muted);margin-bottom:0.5rem">Network Interfaces</div>
        <div class="kv-grid">
          ${sc2.networkIfaces.map(n => kvRow(n.name, n.address)).join("")}
        </div>
      </div>` : ""}
    </div>` : ""}

    <!-- SC III Service Status -->
    ${isDetected ? `
    <div class="card mt-4">
      ${sectionTitle("server", "SC III Service Status")}
      <div class="kv-grid">
        ${kvRowHtml("Detected", '<span class="status-pass">Yes</span>')}
        ${kvRow("Base URL", data.baseUrl)}
        ${kvRow("Version", version)}
        ${kvRow("Network", data.networkStatus)}
        ${kvRowHtml("Local Stream", data.hasLocalStream != null
          ? (data.hasLocalStream ? '<span class="status-pass">Yes</span>' : '<span class="status-fail">No</span>')
          : '—')}
        ${data.error && !isDetected ? kvRowHtml("Error", `<span class="status-fail">${esc(typeof data.error === "string" ? data.error : data.message || "Connection failed")}</span>`) : ""}
      </div>
    </div>` : ""}

    <!-- Configuration -->
    ${config.vendor || config.sport ? `
    <div class="card mt-4">
      ${sectionTitle("cog", "Configuration")}
      <div class="kv-grid">
        ${kvRow("Vendor", config.vendor)}
        ${kvRow("Sport", config.sport)}
        ${config.vendorConfigurationName ? kvRow("Connection Type", config.vendorConfigurationName) : ""}
        ${config.device ? kvRow("Device", config.device) : ""}
        ${config.serialPort ? kvRow("Serial Port", config.serialPort) : ""}
        ${config.firmware ? kvRow("Firmware", config.firmware) : ""}
        ${config.eventType ? kvRow("Event Type", config.eventType) : ""}
      </div>
    </div>` : ""}

    <!-- Cloud BOT + ScoreLink -->
    ${botCard && slCard ? `<div class="dash-2col">${botCard}${slCard}</div>`
     : botCard || slCard ? `<div class="mt-4">${botCard}${slCard}</div>`
     : ""}
  `;
}

// ── Camera Fault Isolator ────────────────────────────────────
//
// 4-phase swap test — process of elimination:
//   Phase 1 (Baseline): measure suspect port speed.
//   Phase 2 (NIC Port): move same cable+camera to test port. Fault follows?
//     Pass (1 Gbps on test) → NIC Port fault.  Fail (still degraded) → Phase 3.
//   Phase 3 (Cable): swap cable for known-good on test port. Fault follows?
//     Pass → Cable fault.  Fail → Phase 4.
//   Phase 4 (Camera): swap camera for known-good on test port. Fault follows?
//     Pass → Camera fault.  Fail → NIC Hardware fault.
//     "No spare CHU" → infer camera fault from Phase 2+3 eliminations.
//
// Ported from FaultIsolatorViewModel.cs (v0.8.21-beta).

var _fi = null;

function _fiReset() {
  // Abort any in-flight poll from a previous run before replacing state.
  if (_fi) _fi._aborted = true;
  _fi = {
    phase: 0,           // 0=PickPort 1=AwaitingNicPortTest 2=AwaitingCableTest 3=AwaitingCameraTest 4=Concluded
    conclusion: "",     // NicPort | Cable | Camera | NicHardware | LikelyCamera
    suspectIdx: -1,
    testIdx: -1,
    testPreSpeedMbps: null,
    expectedSpeedMbps: null,  // captured from suspect port at baseline time
    suspectCameraMacs: [],    // captured at end of baseline; used to verify the physical swap in phase 1
    history: [],        // [{ts,phase,config,speed,verdict,severity}]
    resultHeadline: "",
    resultDetail: "",
    resultSeverity: "", // pass | info | fail
    phaseTitle: "SELECT A PORT TO BEGIN",
    phaseInstruction: "Select the NIC port showing a degraded or missing link and click Start Baseline.",
    actionLabel: "Start Baseline",
    checking: false,
    _aborted: false,
  };
}

function renderFaultIsolator() {
  var cams = cached("cameras");
  if (!cams) {
    $page().innerHTML = sectionLoading("Camera Fault Isolator");
    api("/api/cameras").then(function(d) { dataCache.cameras = d; renderFaultIsolator(); });
    return;
  }

  var ports = cams.ports || [];
  if (!_fi) _fiReset();

  // ── helpers ──────────────────────────────────────────────────

  function portLabel(idx) {
    return "Port " + (idx + 1);
  }

  function formatSpeed(mbps) {
    if (mbps === null || mbps === undefined) return "—";
    if (mbps >= 1000) {
      var g = mbps / 1000;
      return (g === Math.floor(g) ? g : g.toFixed(1)) + " Gbps";
    }
    if (mbps > 0) return mbps + " Mbps";
    return "No link";
  }

  function stepDots() {
    var labels = ["Baseline", "NIC Port", "Cable", "Camera", "Verdict"];
    var html = '<div class="fi-stepper">';
    for (var i = 0; i < 5; i++) {
      var cls = "fi-step-dot";
      var lblCls = "fi-step-label";
      if (_fi.phase > i) { cls += " fi-dot-done"; lblCls += " fi-step-label-done"; }
      else if (_fi.phase === i) { cls += " fi-dot-active"; lblCls += " fi-step-label-active"; }
      html += '<div class="fi-step-cell">' +
        '<div class="' + cls + '">' + (i + 1) + "</div>" +
        '<div class="' + lblCls + '">' + labels[i] + "</div>" +
      '</div>';
      if (i < 4) html += '<div class="fi-step-line' + (_fi.phase > i ? " fi-line-done" : "") + '"></div>';
    }
    return html + "</div>";
  }

  function resultRow() {
    if (!_fi.resultHeadline) return "";
    var sev = _fi.resultSeverity || "info";
    var chip = sev === "pass" ? "PASS" : sev === "fail" ? "FAIL" : "INFO";
    return '<div class="fi-result-row fi-result-' + sev + '">' +
      '<span class="fi-result-chip">' + chip + "</span>" +
      "<div>" +
        '<div class="fi-result-note">' + esc(_fi.resultHeadline) + "</div>" +
        (_fi.resultDetail ? '<div class="fi-result-detail">' + esc(_fi.resultDetail) + "</div>" : "") +
      "</div>" +
      "</div>";
  }

  function historyTable() {
    if (!_fi.history.length) return "";
    var rows = _fi.history.map(function(h) {
      var sc = h.severity === "Pass" ? "status-pass" : h.severity === "Fail" ? "status-fail" : "status-info";
      return "<tr>" +
        '<td class="font-mono" style="font-size:0.7rem;color:var(--c-dim)">' + esc(h.ts) + "</td>" +
        '<td><span class="' + sc + '">' + esc(h.severity) + "</span></td>" +
        "<td><strong>" + esc(h.phase) + "</strong></td>" +
        '<td class="text-pulse-muted" style="font-size:0.78rem">' + esc(h.config) + "</td>" +
        '<td class="font-mono" style="font-size:0.78rem">' + esc(h.speed) + "</td>" +
        '<td class="text-pulse-muted" style="font-size:0.78rem">' + esc(h.verdict) + "</td>" +
        "</tr>";
    }).join("");
    return '<div class="mt-4">' +
      '<div class="text-sm font-semibold mb-2 text-pulse-muted">Phase history (newest first)</div>' +
      '<div style="overflow-x:auto"><table class="data-table">' +
      "<thead><tr><th>Time</th><th>Result</th><th>Phase</th><th>Configuration</th><th>Speed</th><th>Verdict</th></tr></thead>" +
      "<tbody>" + rows + "</tbody></table></div></div>";
  }

  // ── port option builder (shared by Phase 0 and Phase 1 dropdowns) ──
  function portOption(p, i, excludeIdx) {
    if (i === excludeIdx) return "";
    // Camera label (Main Camera 1, OCR, etc.) — same one shown on the port tile.
    var camLbl = p.cameraLabel ? " (" + p.cameraLabel + ")" : "";
    var spd;
    if (!p.isUp) spd = " — No link";
    // Trust the backend isDegraded flag — it knows the expected speed for
    // each camera model. A 100 Mbps OCR isn't degraded; an unknown 100 Mbps
    // camera might be.
    else if (p.isDegraded) spd = " — " + formatSpeed(p.linkSpeedMbps) + " (FAULT)";
    else if (p.isOcr) spd = " — " + formatSpeed(p.linkSpeedMbps || 100) + " (expected)";
    else if (p.linkSpeedMbps > 0) spd = " — " + formatSpeed(p.linkSpeedMbps);
    else spd = " — No link";
    return '<option value="' + i + '">Port ' + (i + 1) + esc(camLbl) + esc(spd) + "</option>";
  }

  // ── phase HTML ───────────────────────────────────────────────
  var inner = "";

  if (_fi.phase === 0) {
    var allOpts = ports.map(function(p, i) { return portOption(p, i, -1); }).join("");
    var def = '<option value="-1">— Select —</option>';
    inner = '<div class="fi-phase-card">' +
      '<div class="fi-phase-title">' + esc(_fi.phaseTitle) + "</div>" +
      '<div class="fi-phase-instr">' + esc(_fi.phaseInstruction) + "</div>" +
      resultRow() +
      '<div style="margin:16px 0;max-width:480px">' +
        '<div class="text-xs text-pulse-muted mb-1">Suspect port (has the fault)</div>' +
        '<select id="fi-suspect" class="ev-select" style="width:100%">' + def + allOpts + "</select>" +
      "</div>" +
      '<div style="display:flex;gap:10px;justify-content:flex-end">' +
        '<button id="fi-action" class="btn-outline btn-ol-blue" disabled>' + esc(_fi.actionLabel) + " →</button>" +
      "</div>" +
      "</div>";

  } else if (_fi.phase === 4) {
    var verdictClsMap = {
      NicPort: "fi-verdict-nic", Cable: "fi-verdict-cable",
      Camera: "fi-verdict-camera", LikelyCamera: "fi-verdict-camera", NicHardware: "fi-verdict-nic"
    };
    var vCls = verdictClsMap[_fi.conclusion] || "fi-verdict-unknown";
    inner = '<div class="fi-verdict-card ' + esc(vCls) + '">' +
      '<div class="fi-verdict-title">' + esc(_fi.phaseTitle) + "</div>" +
      '<div class="fi-verdict-body">' + esc(_fi.phaseInstruction) + "</div>" +
      "</div>" +
      '<div style="display:flex;gap:10px;margin-top:16px">' +
        '<button id="fi-action" class="btn-outline btn-ol-blue">' + esc(_fi.actionLabel) + "</button>" +
        '<button id="fi-startover" class="btn-outline btn-ol-blue">Start Over</button>' +
      "</div>";

  } else {
    // Phases 1-3: active swap phases
    var btnLabel = _fi.checking ? ("Checking... " + (_fi.checkElapsed || 0) + "s / 20s") : _fi.actionLabel;
    // Phase 1 (AwaitingNicPortTest): show test port dropdown so the tech can
    // change it after a pre-check failure without starting over entirely.
    // Mirrors WPF's IsPickingTestPort => Phase == AwaitingNicPortTest.
    var testPortPicker = "";
    if (_fi.phase === 1 && !_fi.checking) {
      var testOpts = ports.map(function(p, i) { return portOption(p, i, _fi.suspectIdx); }).join("");
      testPortPicker = '<div style="margin:12px 0">' +
        '<div class="text-xs text-pulse-muted mb-1">Test port (known-good)</div>' +
        '<select id="fi-test" class="ev-select" style="width:100%;max-width:320px">' + testOpts + "</select>" +
        "</div>";
    }
    inner = '<div class="fi-phase-card">' +
      '<div class="fi-phase-title">' + esc(_fi.phaseTitle) + "</div>" +
      '<div class="fi-phase-instr">' + esc(_fi.phaseInstruction) + "</div>" +
      resultRow() +
      testPortPicker +
      "</div>" +
      '<div style="display:flex;gap:10px;justify-content:flex-end;margin-top:12px">' +
        '<button id="fi-startover" class="btn-outline btn-ol-blue">Start Over</button>' +
        (_fi.phase === 3 && !_fi.checking ? '<button id="fi-infer" class="btn-outline btn-ol-muted">No Spare CHU — Infer</button>' : "") +
        '<button id="fi-action" class="btn-outline btn-ol-blue"' + (_fi.checking ? " disabled" : "") + ">" + esc(btnLabel) + "</button>" +
      "</div>";
  }

  $page().innerHTML = pageHeader(
    "Camera Fault Isolator",
    "Process-of-elimination swap test — isolate a camera fault to NIC port, cable, or camera (CHU).",
    '<button class="btn-outline btn-ol-blue" onclick="navigate(\'cameras\')">' + svgIcon("arrow-left", 14) + " Back to Camera Connectivity</button>"
  ) + '<div class="card">' + stepDots() + inner + historyTable() + "</div>";

  // ── event wiring ─────────────────────────────────────────────
  var suspectSel = document.getElementById("fi-suspect");
  var testSel    = document.getElementById("fi-test");
  var actionBtn  = document.getElementById("fi-action");
  var inferBtn   = document.getElementById("fi-infer");
  var soBtn      = document.getElementById("fi-startover");

  // Phase 0: only suspect dropdown — baseline is discovery only
  if (suspectSel && _fi.phase === 0) {
    if (_fi.suspectIdx >= 0) suspectSel.value = String(_fi.suspectIdx);
    var updateBegin = function() {
      var s = parseInt(suspectSel.value);
      if (actionBtn) actionBtn.disabled = (s < 0);
    };
    suspectSel.addEventListener("change", function() {
      _fi.suspectIdx = parseInt(suspectSel.value);
      updateBegin();
    });
    updateBegin();
  }

  // Phase 1: test port dropdown (change-only, no suspect dropdown)
  if (testSel && _fi.phase === 1) {
    if (_fi.testIdx >= 0) testSel.value = String(_fi.testIdx);
    testSel.addEventListener("change", function() {
      _fi.testIdx = parseInt(testSel.value);
      // Re-capture pre-swap speed for the newly-selected test port
      var tp = ports[_fi.testIdx];
      _fi.testPreSpeedMbps = tp ? (tp.linkSpeedMbps || 0) : 0;
      // Visual feedback: confirm the selection by updating the instruction text
      // so the tech can see "Check Now" will use the new port.
      if (_fi.testIdx >= 0 && _fi.suspectIdx >= 0) {
        var sn = portLabel(_fi.suspectIdx);
        var tn = portLabel(_fi.testIdx);
        _fi.phaseInstruction = "Move the SAME cable and camera from " + sn +
          " to " + tn + " (test port). Click Check Now when ready.";
        renderFaultIsolator();
      }
    });
  }

  if (actionBtn && _fi.phase === 4) {
    actionBtn.addEventListener("click", function() { navigate("cameras"); });
  } else if (actionBtn && !_fi.checking) {
    actionBtn.addEventListener("click", doAction);
  }
  if (inferBtn) inferBtn.addEventListener("click", doInfer);
  if (soBtn) soBtn.addEventListener("click", function() { _fiReset(); renderFaultIsolator(); });

  // ── async state machine ──────────────────────────────────────

  // expectedMbps: optional. If provided, polling exits early once peak
  // hits or exceeds the camera's expected speed. Defaults to 1 Gbps.
  async function pollPeakSpeed(portIdx, windowSec, expectedMbps) {
    var threshold = expectedMbps || 1000;
    var peak = 0;
    var start = Date.now();
    var deadline = start + windowSec * 1000;
    while (Date.now() < deadline) {
      if (_fi._aborted) return peak;
      var elapsed = Math.floor((Date.now() - start) / 1000);
      _fi.checkElapsed = elapsed;
      var btn = document.getElementById("fi-action");
      if (btn) btn.textContent = "Checking... " + elapsed + "s / " + windowSec + "s";
      var fresh;
      try { fresh = await api("/api/cameras"); dataCache.cameras = fresh; }
      catch (e) { fresh = { ports: [] }; }
      var portData = (fresh.ports || [])[portIdx];
      var sample = portData ? (portData.linkSpeedMbps || 0) : 0;
      if (sample > peak) peak = sample;
      if (peak >= threshold) return peak;
      await new Promise(function(r) { setTimeout(r, 1000); });
    }
    return peak;
  }

  function addHistory(phaseName, config, speed, verdict, severity) {
    _fi.history.unshift({ ts: new Date().toLocaleTimeString(), phase: phaseName,
      config: config, speed: speed, verdict: verdict, severity: severity });
  }

  function showResult(headline, detail, severity) {
    _fi.resultHeadline = headline;
    _fi.resultDetail   = detail;
    _fi.resultSeverity = severity.toLowerCase();
  }

  function clearResult() {
    _fi.resultHeadline = "";
    _fi.resultDetail   = "";
    _fi.resultSeverity = "";
  }

  function conclude(conclusion, title, instruction) {
    _fi.conclusion = conclusion;
    _fi.phase = 4;
    _fi.phaseTitle = title;
    _fi.phaseInstruction = instruction;
    _fi.actionLabel = "Run Full Diagnostic";
    _fi.checking = false;
  }

  async function doAction() {
    if (_fi.checking) return;
    // Clear the previous phase's PASS/FAIL chip so the user sees only the
    // current phase's status while polling.
    clearResult();

    // Phase 0 — Baseline: poll suspect port speed (discovery only, no test port yet)
    if (_fi.phase === 0) {
      var si = _fi.suspectIdx;
      if (si < 0) return;
      // Per-port expected speed. Backend sets expectedSpeedMbps from the
      // camera model when CGI probe succeeded. If absent, fall back to
      // 100 Mbps for OCR (most common OCR variant) or 1 Gbps for Main.
      var suspectPort = ports[si] || {};
      var expectedSpd = suspectPort.expectedSpeedMbps
        || (suspectPort.isOcr ? 100 : 1000);
      var expectedLbl = formatSpeed(expectedSpd);
      _fi.checking = true;
      renderFaultIsolator();

      var spd0 = await pollPeakSpeed(si, 20, expectedSpd);
      if (_fi._aborted) return;
      _fi.checking = false;
      var sl0 = formatSpeed(spd0);
      var sn0 = portLabel(si);
      var cfg0 = "Port: " + sn0 + "  |  Cable: (original)  |  Camera: (original)";

      // Healthy if speed meets or exceeds expected for the camera type.
      if (spd0 >= expectedSpd) {
        addHistory("Phase 1 - Baseline", cfg0, sl0, "Port healthy — no fault on this port.", "Pass");
        showResult("Baseline: " + sl0 + " — Port is operating normally.",
          "The selected port is at the expected " + expectedLbl + ". No fault detected.", "pass");
        _fi.phaseTitle = "BASELINE — PORT HEALTHY";
        _fi.phaseInstruction = "Pick a different port from the dropdown above and click Run Baseline, or close the wizard.";
        _fi.actionLabel = "Run Baseline";
        // Reset to phase 0 so the suspect dropdown reappears for re-selection.
        _fi.phase = 0;
        renderFaultIsolator();
        return;
      }

      var bMsg, bInstr;
      if (spd0 <= 0) {
        bMsg = "No link detected";
        // Split the no-link case into a clear two-step prompt so the tech
        // first verifies basics, then moves on to the swap test if still no link.
        bInstr = "Step 1: Confirm the camera is powered on and the cable is firmly seated on both ends. " +
                 "Step 2: If there's still no link, select a known-good test port below and click Check Now.";
      } else {
        bMsg   = "Link is degraded at " + sl0 + " (expected " + expectedLbl + ")";
        bInstr = "Select a known-good test port below, then move the SAME cable and camera from " + sn0 + " to it. Click Check Now when ready.";
      }
      addHistory("Phase 1 - Baseline", cfg0, sl0, bMsg + " — beginning isolation.", "Fail");
      showResult("Baseline: " + sl0 + " — " + bMsg + ".", bInstr, "fail");
      // Remember expected speed so subsequent phases use the right pass threshold.
      _fi.expectedSpeedMbps = expectedSpd;
      // Capture the suspect's camera MAC(s) so Phase 1 can verify the swap
      // actually moved the camera to the test port (vs. user clicked Check
      // Now without doing anything).
      _fi.suspectCameraMacs = (suspectPort.camerasDetected || []).map(function(c) {
        return String(c.mac || "").toUpperCase().replace(/-/g, ":");
      }).filter(function(m) { return m; });
      _fi.phase = 1;
      _fi.phaseTitle = "PHASE 2 — DOES THE FAULT FOLLOW THE NIC PORT?";
      _fi.phaseInstruction = bInstr;
      _fi.actionLabel = "Check Now";
      renderFaultIsolator();
      return;
    }

    // Phase 1 — NIC Port Test: poll test port after moving cable+camera
    if (_fi.phase === 1) {
      // Re-read test port index from dropdown (may have changed via test port picker)
      var testSel1 = document.getElementById("fi-test");
      if (testSel1) _fi.testIdx = parseInt(testSel1.value);
      if (_fi.testIdx < 0 || _fi.testIdx === _fi.suspectIdx) {
        showResult("No test port selected.", "Pick a test port from the dropdown before continuing.", "fail");
        renderFaultIsolator();
        return;
      }
      // Pre-check: was the test port already running below 1 Gbps before
      // the swap? Even an OCR test port should provide 1 Gbps capacity once
      // a Main camera is moved to it, so 1 Gbps is the correct sanity bar
      // here regardless of the suspect camera's expected speed.
      var preSpd = _fi.testPreSpeedMbps || 0;
      if (preSpd > 0 && preSpd < 1000) {
        showResult(
          "Pre-check: " + portLabel(_fi.testIdx) + " was at " + preSpd + " Mbps BEFORE the swap.",
          portLabel(_fi.testIdx) + " was already degraded before you moved anything. Phase 2 results will be unreliable — pick a different test port from the dropdown above, or click Start Over.",
          "fail"
        );
        renderFaultIsolator();
        return;
      }
      // Expected speed for the suspect camera — drives the pass threshold.
      var expSpd1 = _fi.expectedSpeedMbps || 1000;
      var expLbl1 = formatSpeed(expSpd1);
      _fi.checking = true;
      renderFaultIsolator();
      var spd1 = await pollPeakSpeed(_fi.testIdx, 20, expSpd1);
      if (_fi._aborted) return;
      _fi.checking = false;
      var sl1 = formatSpeed(spd1);
      var tn1 = portLabel(_fi.testIdx);
      var sn1 = portLabel(_fi.suspectIdx);
      var cfg1 = "Port: " + tn1 + " (test port)  |  Cable: (original)  |  Camera: (original)";

      // Swap verification: the suspect camera's MAC should now appear on
      // the test port's ARP. If it doesn't AND the suspect port still has
      // it, the user clicked Check Now without performing the physical
      // swap. Without this check, a healthy test port + unmoved cable
      // would falsely conclude "NIC port fault".
      // Skipped in demo mode — static demo data can't simulate the ARP change.
      var swapVerified = true;
      var isDemo = !!(dataCache.cameras && dataCache.cameras.demoMode);
      if (!isDemo && (_fi.suspectCameraMacs || []).length > 0) {
        var fresh = dataCache.cameras || {};
        var freshPorts = fresh.ports || [];
        var testPortFresh = freshPorts[_fi.testIdx] || {};
        var suspectPortFresh = freshPorts[_fi.suspectIdx] || {};
        var macsOnTest = (testPortFresh.camerasDetected || []).map(function(c) {
          return String(c.mac || "").toUpperCase().replace(/-/g, ":");
        });
        var macsOnSuspect = (suspectPortFresh.camerasDetected || []).map(function(c) {
          return String(c.mac || "").toUpperCase().replace(/-/g, ":");
        });
        var movedToTest = _fi.suspectCameraMacs.some(function(m) {
          return macsOnTest.indexOf(m) >= 0;
        });
        var stillOnSuspect = _fi.suspectCameraMacs.some(function(m) {
          return macsOnSuspect.indexOf(m) >= 0;
        });
        // If the camera didn't appear on the test port AND it's still on
        // the suspect port, the swap clearly wasn't done.
        if (!movedToTest && stillOnSuspect) {
          swapVerified = false;
          var suspectMac = _fi.suspectCameraMacs[0];
          addHistory("Phase 2 - NIC Port Test", cfg1, sl1,
            "Swap not verified — camera " + suspectMac + " still on " + sn1 + ", not on " + tn1 + ".", "Info");
          showResult(
            "Swap not detected — test inconclusive.",
            "The suspect camera (" + suspectMac + ") still appears on " + sn1 +
            " and was not detected on " + tn1 + ". Please physically move the cable and camera from " +
            sn1 + " to " + tn1 + ", then click Check Now again. " +
            "Note: ARP can take up to 30 seconds to refresh after a swap.",
            "fail"
          );
          renderFaultIsolator();
          return;
        }
      }

      if (spd1 >= expSpd1) {
        var v1 = "Link restored on the test port. The fault follows the original NIC port.";
        addHistory("Phase 2 - NIC Port Test", cfg1, sl1, v1, "Pass");
        showResult("Phase 2: " + sl1 + " — Fault follows the original NIC port.", v1, "pass");
        conclude("NicPort", "CONCLUSION — FAULTY NIC PORT",
          "Moving the cable and camera to " + tn1 + " restored the link. The original NIC port is the source of the fault. Escalate for NIC or motherboard repair.");
        renderFaultIsolator();
        return;
      }
      if (spd1 <= 0) {
        addHistory("Phase 2 - NIC Port Test", cfg1, sl1, "No link detected — test inconclusive.", "Info");
        _fi.phaseInstruction = "No link on " + tn1 + ". Verify the cable is fully seated on the test port and the camera is powered on, then click Check Now to re-measure.";
        showResult("Phase 2: No link — test inconclusive.", _fi.phaseInstruction, "info");
        renderFaultIsolator();
        return;
      }
      var cv1 = "Fault stayed with the cable / camera. The original NIC port is not the source.";
      addHistory("Phase 2 - NIC Port Test", cfg1, sl1, cv1, "Info");
      showResult("Phase 2: " + sl1 + " — Fault follows cable / camera, not the NIC port.", cv1, "info");
      _fi.phase = 2;
      _fi.phaseTitle = "PHASE 3 — DOES THE FAULT FOLLOW THE CABLE?";
      _fi.phaseInstruction = "Keep the camera on " + tn1 + ". Disconnect the original cable on both ends and replace it with a known-good cable. Then click Check Now.";
      _fi.actionLabel = "Check Now";
      renderFaultIsolator();
      return;
    }

    // Phase 2 — Cable Test: poll test port after swapping cable
    if (_fi.phase === 2) {
      var expSpd2 = _fi.expectedSpeedMbps || 1000;
      _fi.checking = true;
      renderFaultIsolator();
      var spd2 = await pollPeakSpeed(_fi.testIdx, 20, expSpd2);
      if (_fi._aborted) return;
      _fi.checking = false;
      var sl2 = formatSpeed(spd2);
      var tn2 = portLabel(_fi.testIdx);
      var cfg2 = "Port: " + tn2 + "  |  Cable: (NEW — known good)  |  Camera: (original)";

      if (spd2 >= expSpd2) {
        var v2 = "Link restored with a known-good cable. The original cable is the source of the fault.";
        addHistory("Phase 3 - Cable Test", cfg2, sl2, v2, "Pass");
        showResult("Phase 3: " + sl2 + " — Fault follows the cable.", v2, "pass");
        conclude("Cable", "CONCLUSION — FAULTY CABLE",
          "Replacing the cable restored the link. The original cable (or its termination) is the source of the fault. Replace the cable end-to-end.");
        renderFaultIsolator();
        return;
      }
      if (spd2 <= 0) {
        addHistory("Phase 3 - Cable Test", cfg2, sl2, "No link detected — test inconclusive.", "Info");
        _fi.phaseInstruction = "No link on " + tn2 + ". Verify the new cable is fully seated on both ends and the camera is powered on, then click Check Now to re-measure.";
        showResult("Phase 3: No link — test inconclusive.", _fi.phaseInstruction, "info");
        renderFaultIsolator();
        return;
      }
      var cv2 = "Fault stayed with the camera. The original cable is not the source.";
      addHistory("Phase 3 - Cable Test", cfg2, sl2, cv2, "Info");
      showResult("Phase 3: " + sl2 + " — Fault is not the cable.", cv2, "info");
      _fi.phase = 3;
      _fi.phaseTitle = "PHASE 4 — DOES THE FAULT FOLLOW THE CAMERA?";
      _fi.phaseInstruction = "Stay on " + tn2 + " with the new cable. Connect a known-good camera, then click Check Now. If you don't have a spare camera, click \"No Spare CHU — Infer\" to conclude from what's already been ruled out.";
      _fi.actionLabel = "Check Now";
      renderFaultIsolator();
      return;
    }

    // Phase 3 — Camera Test: poll test port after swapping camera
    // Note: known-good camera is most likely a Main Camera (1 Gbps) since
    // OCR spares are rare. Pass threshold is 1 Gbps here, not the suspect's
    // expected speed — we're testing the NEW camera's capability.
    if (_fi.phase === 3) {
      _fi.checking = true;
      renderFaultIsolator();
      var spd3 = await pollPeakSpeed(_fi.testIdx, 20);
      if (_fi._aborted) return;
      _fi.checking = false;
      var sl3 = formatSpeed(spd3);
      var tn3 = portLabel(_fi.testIdx);
      var cfg3 = "Port: " + tn3 + "  |  Cable: (NEW)  |  Camera: (NEW — known good)";

      if (spd3 >= 1000) {
        var v3 = "Link restored with a known-good camera. The original camera is the source of the fault.";
        addHistory("Phase 4 - Camera Test", cfg3, sl3, v3, "Pass");
        showResult("Phase 4: " + sl3 + " — Fault follows the camera.", v3, "pass");
        conclude("Camera", "CONCLUSION — FAULTY CAMERA (CHU)",
          "Replacing the camera restored the link. The original camera (CHU) is the source of the fault. Replace the camera unit.");
        renderFaultIsolator();
        return;
      }
      if (spd3 <= 0) {
        addHistory("Phase 4 - Camera Test", cfg3, sl3, "No link detected — test inconclusive.", "Info");
        _fi.phaseInstruction = "No link on " + tn3 + ". Verify the known-good camera is connected and powered on, then click Check Now to re-measure.";
        showResult("Phase 4: No link — test inconclusive.", _fi.phaseInstruction, "info");
        renderFaultIsolator();
        return;
      }
      var vf3 = "Fault persists with known-good cable and camera. The fault is likely in the NIC hardware or the VPU motherboard.";
      addHistory("Phase 4 - Camera Test", cfg3, sl3, vf3, "Fail");
      showResult("Phase 4: " + sl3 + " — Fault persists with known-good equipment.", vf3, "fail");
      conclude("NicHardware", "CONCLUSION — NIC / HARDWARE FAULT",
        "Known-good cable and camera still fail on " + tn3 + ". This indicates a fault in the NIC hardware or the VPU motherboard. Run the full diagnostic from the Camera Connectivity panel and escalate to hardware repair.");
      renderFaultIsolator();
      return;
    }
  }

  function doInfer() {
    if (_fi.phase !== 3) return;
    var tn = portLabel(_fi.testIdx);
    var cfg = "Port: " + tn + "  |  Cable: (NEW)  |  Camera: (no spare available)";
    addHistory("Phase 4 - SKIPPED", cfg, "—",
      "No spare CHU available. Conclusion inferred from Phase 2 and Phase 3 outcomes.", "Info");
    showResult("Phase 4 skipped — inferred conclusion.",
      "Phase 2 cleared the original NIC port; Phase 3 cleared the original cable. The remaining suspect is the camera (CHU).", "info");
    conclude("LikelyCamera", "LIKELY CAMERA (CHU) FAULT — UNVERIFIED",
      "Cable replacement did not restore the link, and the original NIC port has already been cleared (Phase 2). The remaining suspect is the camera (CHU). Replace the camera unit when a known-good spare is available; if the link still fails with a known-good camera, the issue is likely NIC hardware and a full diagnostic + escalation is warranted.");
    renderFaultIsolator();
  }
}

// ── Audio ────────────────────────────────────────────────────

// Thresholds & timing constants
const AUDIO_SIGNAL_THRESHOLD = 1;
const AUDIO_PEAK_HOT = 80;
const AUDIO_REFRESH_MS = 2000;

let _audioRefreshTimer = null;
let _audioFetchInFlight = false;

function renderAudio() {
  const data = cached("audio");
  if (!data) { $page().innerHTML = sectionLoading("Audio"); fetchSection("audio"); return; }

  // Clear any previous live-refresh timer + reset in-flight guard
  if (_audioRefreshTimer) { clearInterval(_audioRefreshTimer); _audioRefreshTimer = null; }
  _audioFetchInFlight = false;

  // Hard error — show errorBox like other renderers
  if (data.error) { $page().innerHTML = errorBox(data.message || "Failed to enumerate audio devices"); return; }

  const devices = data.devices || [];
  const inputs = devices.filter(d => d.dataFlow === "Input");
  const outputs = devices.filter(d => d.dataFlow === "Output");
  // WMI fallback returns dataFlow="Unknown" — surface these so they're not invisible
  const others = devices.filter(d => d.dataFlow !== "Input" && d.dataFlow !== "Output");
  const activeInputs = inputs.filter(d => d.state === "Active");
  const activeOutputs = outputs.filter(d => d.state === "Active");

  // Page-level indicator: is anything making sound?
  const anySignal = devices.some(d => d.peak != null && d.peak > AUDIO_SIGNAL_THRESHOLD);

  // Findings — surface diagnostic warnings (PULSEDEV-38)
  const findings = _audioFindings(devices, data);

  $page().innerHTML = `
    ${pageHeader("Audio", "Audio devices, volume, and signal activity",
      `<button class="btn-outline btn-ol-blue" onclick="dataCache.audio=null;renderAudio()">
        ${svgIcon("refresh", 14)} Refresh
      </button>`
    )}

    ${findings.length ? `<div class="card audio-findings">
      ${findings.map(f => `<div class="audio-finding audio-finding-${esc(f.severity)}">
        <span class="audio-finding-pill audio-finding-pill-${esc(f.severity)}">${esc(f.severity.toUpperCase())}</span>
        <div><div class="audio-finding-title">${esc(f.title)}</div>
          <div class="audio-finding-body">${esc(f.body)}</div></div>
      </div>`).join("")}
    </div>` : ""}

    <div class="audio-summary">
      ${_audioSummaryCard("Input Devices", activeInputs.length, inputs.length, "mic")}
      ${_audioSummaryCard("Output Devices", activeOutputs.length, outputs.length, "volume")}
      <div class="card audio-signal-card">
        <div class="audio-signal-dot ${anySignal ? "audio-signal-active" : "audio-signal-silent"}"></div>
        <div>
          <div class="text-sm font-semibold">${anySignal ? "Signal Detected" : "No Signal"}</div>
          <div class="text-xs text-pulse-muted">${anySignal ? "Audio activity on one or more devices" : "All devices silent"}</div>
        </div>
      </div>
    </div>

    <div class="card mt-4">
      ${sectionTitle("mic", "Input Devices")}
      ${inputs.length
        ? inputs.map(d => _audioDeviceRow(d)).join("")
        : '<p class="text-sm text-pulse-muted">No input devices detected</p>'}
    </div>

    <div class="card mt-4">
      ${sectionTitle("volume", "Output Devices")}
      ${outputs.length
        ? outputs.map(d => _audioDeviceRow(d)).join("")
        : '<p class="text-sm text-pulse-muted">No output devices detected</p>'}
    </div>

    ${others.length ? `<div class="card mt-4">
      ${sectionTitle("info", "Other Devices")}
      <p class="text-xs text-pulse-muted mb-2">Devices reported by WMI without input/output direction.</p>
      ${others.map(d => _audioDeviceRow(d)).join("")}
    </div>` : ""}
  `;

  // Wire up volume sliders with success/error feedback
  devices.forEach(d => {
    if (d.state !== "Active" || d.volume == null) return;
    const slug = _audioSlug(d.id);
    const slider = document.getElementById(`vol-${slug}`);
    const label  = document.getElementById(`vol-lbl-${slug}`);
    const msg    = document.getElementById(`vol-msg-${slug}`);
    if (!slider) return;

    slider.addEventListener("change", async () => {
      const val = parseInt(slider.value, 10);
      if (label) label.textContent = val + "%";
      const r = await apiPost("/api/audio/volume", { deviceId: d.id, volume: val });
      if (!msg) return;
      if (r && r.error) {
        msg.textContent = "Failed: " + (r.message || "unknown error");
        msg.className = "audio-vol-msg audio-vol-msg-err";
      } else {
        msg.textContent = "Saved";
        msg.className = "audio-vol-msg audio-vol-msg-ok";
        setTimeout(() => { if (msg) msg.textContent = ""; }, 1500);
      }
    });
    slider.addEventListener("input", () => {
      if (label) label.textContent = parseInt(slider.value, 10) + "%";
    });
  });

  // Live-refresh peak meters. In-flight guard prevents overlapping requests
  // when the backend script takes longer than the refresh interval on slow VPUs.
  _audioRefreshTimer = setInterval(() => {
    if (currentPage !== "audio") {
      clearInterval(_audioRefreshTimer); _audioRefreshTimer = null; return;
    }
    if (_audioFetchInFlight) return;
    _audioFetchInFlight = true;
    api("/api/audio").then(fresh => {
      _audioFetchInFlight = false;
      if (!fresh || fresh.error || currentPage !== "audio") return;
      (fresh.devices || []).forEach(d => _audioUpdateMeter(d));
    }).catch(() => { _audioFetchInFlight = false; });
  }, AUDIO_REFRESH_MS);
}

function _audioUpdateMeter(d) {
  const slug = _audioSlug(d.id);
  const bar = document.getElementById(`peak-${slug}`);
  const lbl = document.getElementById(`peak-lbl-${slug}`);
  if (bar && d.peak != null) {
    bar.style.width = Math.min(d.peak, 100) + "%";
    bar.className = "audio-peak-fill" + _audioPeakClass(d.peak);
  }
  if (lbl) lbl.textContent = d.peak != null ? d.peak + "%" : "—";
}

function _audioPeakClass(peak) {
  if (peak == null) return "";
  if (peak > AUDIO_PEAK_HOT) return " audio-peak-hot";
  if (peak > AUDIO_SIGNAL_THRESHOLD) return " audio-peak-ok";
  return "";
}

// Surface diagnostic findings — e.g. "Line-In active but silent" (PULSEDEV-38).
function _audioFindings(devices, data) {
  const out = [];
  const silentLineIns = devices.filter(d =>
    d.state === "Active" &&
    d.dataFlow === "Input" &&
    (d.formFactor === "LineLevel" || /line.in/i.test(d.name || "")) &&
    d.peak != null && d.peak <= AUDIO_SIGNAL_THRESHOLD
  );
  silentLineIns.forEach(d => {
    out.push({
      severity: "warning",
      title: "Line-in source is silent",
      body: `${d.name || "Line-in device"} is active but no audio signal detected. Verify the source is connected and unmuted.`
    });
  });
  if (data.wmiFallback) {
    out.push({
      severity: "info",
      title: "Limited device info",
      body: "CoreAudio enumeration failed — falling back to WMI. Volume, mute, and peak meters are unavailable."
    });
  }
  return out;
}

// Short stable slug from a device ID — djb2-style hash so HTML IDs stay
// compact even for long Windows endpoint GUIDs.
function _audioSlug(id) {
  const s = String(id || "");
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return "d" + (h >>> 0).toString(36);
}

function _audioSummaryCard(label, active, total, icon) {
  return `<div class="card audio-summary-card">
    <div class="audio-summary-icon">${svgIcon(icon, 20)}</div>
    <div class="audio-summary-num">${active}<span class="text-pulse-muted text-sm font-normal"> / ${total}</span></div>
    <div class="text-xs text-pulse-muted">${esc(label)}</div>
  </div>`;
}

function _audioFormFactorBadge(ff) {
  const labels = {
    LineLevel: "Line-In", Microphone: "Mic", Headphones: "Headphones",
    Headset: "Headset", Speakers: "Speakers", SPDIF: "S/PDIF",
    DigitalDisplay: "HDMI/DP", DigitalPassthrough: "Digital", RemoteNetwork: "Network",
    Handset: "Handset", Unknown: "Unknown"
  };
  const text = labels[ff] || ff || "Unknown";
  return `<span class="audio-port-badge">${esc(text)}</span>`;
}

function _audioFormFactorLabel(ff) {
  const labels = {
    LineLevel: "Line-in", Microphone: "Microphone", Headphones: "Headphone",
    Headset: "Headset", Speakers: "Speaker", SPDIF: "S/PDIF",
    DigitalDisplay: "Display audio (HDMI/DisplayPort)",
    DigitalPassthrough: "Digital passthrough", RemoteNetwork: "Network",
    Handset: "Handset"
  };
  return labels[ff] || ff;
}

function _audioDeviceRow(d) {
  const slug = _audioSlug(d.id);
  const isActive = d.state === "Active";
  const stateClass = isActive ? "status-pass" : d.state === "Disabled" ? "status-warn" : "status-fail";

  return `<div class="audio-device${isActive ? "" : " audio-device-inactive"}">
    <div class="audio-device-header">
      <div class="audio-device-name">${esc(d.name || "Unknown Device")}</div>
      <div class="audio-device-badges">
        ${_audioFormFactorBadge(d.formFactor)}
        <span class="${stateClass}">${esc(d.state)}</span>
      </div>
    </div>
    ${isActive ? `
      <div class="audio-device-controls">
        <div class="audio-meter-row">
          <span class="audio-meter-label">Signal</span>
          <div class="audio-peak-track">
            <div id="peak-${slug}" class="audio-peak-fill${_audioPeakClass(d.peak)}" style="width:${Math.min(d.peak || 0, 100)}%"></div>
          </div>
          <span id="peak-lbl-${slug}" class="audio-meter-val">${d.peak != null ? d.peak + "%" : "—"}</span>
        </div>
        ${d.volume != null ? `
          <div class="audio-meter-row">
            <span class="audio-meter-label">${d.muted ? svgIcon("volume-x", 14) : svgIcon("volume", 14)}</span>
            <input type="range" id="vol-${slug}" class="audio-slider${d.muted ? " audio-slider-muted" : ""}" min="0" max="100" value="${Math.round(d.volume)}"/>
            <span id="vol-lbl-${slug}" class="audio-meter-val">${Math.round(d.volume)}%</span>
            <span id="vol-msg-${slug}" class="audio-vol-msg"></span>
          </div>` : ""}
      </div>
    ` : (d.formFactor && d.formFactor !== "Unknown" ? `
      <div class="audio-device-controls">
        <p class="text-xs text-pulse-muted">${esc(_audioFormFactorLabel(d.formFactor))} device — controls unavailable while ${esc(d.state.toLowerCase())}.</p>
      </div>
    ` : "")}
  </div>`;
}

// ── Settings ─────────────────────────────────────────────────

function renderSettings() {
  const data = cached("settings");
  if (!data) { $page().innerHTML = sectionLoading("Settings"); fetchSection("settings"); return; }

  const scUrl = data.scoreConnectUrl || "http://localhost:5000";
  const pollMs = data.pollIntervalMs || 3000;

  $page().innerHTML = `
    ${pageHeader("Settings", "App preferences and diagnostic helpers")}

    <!-- ScoreConnect III API -->
    <div class="card">
      ${sectionTitle("link", "ScoreConnect III API")}
      <p class="text-sm text-pulse-muted mb-3">Base URL Pulse uses to talk to the local ScoreConnect III service. Default is http://localhost:5000.</p>
      <input type="text" id="set-sc-url" value="${esc(scUrl)}" class="settings-input"/>
      <div class="settings-actions">
        <button class="btn-outline btn-ol-blue" id="set-save-url">
          ${svgIcon("check", 14)} Save
        </button>
        <button class="btn-outline btn-ol-blue" id="set-reset-url">
          ${svgIcon("refresh", 14)} Reset to default
        </button>
        <span id="set-url-msg" class="text-sm text-pulse-muted"></span>
      </div>
    </div>

    <!-- Poll Interval -->
    <div class="card mt-4">
      ${sectionTitle("clock", "Live Metrics")}
      <p class="text-sm text-pulse-muted mb-3">How often the WebSocket refreshes live performance metrics (1000–30000 ms).</p>
      <input type="number" id="set-poll" value="${pollMs}" min="1000" max="30000" step="500" class="settings-input" style="max-width:200px"/>
      <div class="settings-actions">
        <button class="btn-outline btn-ol-blue" id="set-save-poll">
          ${svgIcon("check", 14)} Save
        </button>
        <span id="set-poll-msg" class="text-sm text-pulse-muted"></span>
      </div>
    </div>

    <!-- Logs & Reports -->
    <div class="card mt-4">
      ${sectionTitle("file", "Logs & Reports")}
      <p class="text-sm text-pulse-muted mb-3">File paths used by Pulse on this VPU.</p>
      <div class="kv-grid mb-3" style="max-width:640px">
        ${kvRow("Server log", data._paths?.serverLog || "—")}
        ${kvRow("Settings file", data._paths?.settingsFile || "—")}
      </div>
      <button class="btn-outline btn-ol-blue" onclick="openServerLog()">
        ${svgIcon("file", 14)} View Server Log
      </button>
    </div>

    <!-- Diagnostics -->
    <div class="card mt-4">
      ${sectionTitle("zap", "Diagnostics")}
      <p class="text-sm text-pulse-muted mb-3">Re-run all diagnostics on demand. Each script re-collects live data from the VPU.</p>
      <button class="btn-outline btn-ol-green" onclick="refreshAll()">
        ${svgIcon("play", 14)} Run All Diagnostics
      </button>
    </div>
  `;

  async function saveSettings() {
    return apiPost("/api/settings", {
      scoreConnectUrl: document.getElementById("set-sc-url").value.trim(),
      pollIntervalMs: parseInt(document.getElementById("set-poll").value, 10) || 3000,
    });
  }

  document.getElementById("set-save-url")?.addEventListener("click", async () => {
    const result = await saveSettings();
    const msgEl = document.getElementById("set-url-msg");
    msgEl.textContent = result.ok ? "Saved" : "Error saving";
    if (result.ok) setTimeout(() => { if (msgEl) msgEl.textContent = ""; }, 2000);
  });

  document.getElementById("set-reset-url")?.addEventListener("click", () => {
    document.getElementById("set-sc-url").value = "http://localhost:5000";
  });

  document.getElementById("set-save-poll")?.addEventListener("click", async () => {
    const result = await saveSettings();
    const msgEl = document.getElementById("set-poll-msg");
    msgEl.textContent = result.ok ? "Saved" : "Error saving";
    if (result.ok) setTimeout(() => { if (msgEl) msgEl.textContent = ""; }, 2000);
  });
}

// ── About ────────────────────────────────────────────────────

function renderAbout() {
  const dash = cached("dashboard");
  if (!dash) fetchSection("dashboard");
  const id = (dash || {}).identity || {};
  const ver = dataCache._version;

  $page().innerHTML = `
    <div class="about-container">
      <div class="card about-card">
        <div class="about-icon">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#3b82f6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M22 12h-4l-3 9L9 3l-3 9H2"/>
          </svg>
        </div>
        <h2 class="about-title">Pulse</h2>
        <p class="about-tagline">Pixellot Unified Live System Evaluator</p>
        <div class="about-version" id="about-version">${ver ? esc(ver) + " · Web Edition" : "… · Web Edition"}</div>
        <p class="about-desc">A lightweight, self-contained diagnostic tool for Pixellot VPU systems. Collects system identity, hardware, performance metrics, network configuration, camera connectivity, service status, disk health, and event logs.</p>
        <div class="about-info">
          <div class="kv-grid kv-grid-center">
            ${kvRow("Hostname", id.hostname || "—")}
            ${kvRow("OS", id.os || "—")}
            ${kvRow("Backend", "Python + FastAPI + Uvicorn")}
            ${kvRow("Frontend", "Vanilla HTML/JS + Tailwind CSS")}
            ${kvRow("Data Collection", "PowerShell + WMI/CIM")}
          </div>
        </div>
        <div class="about-links">
          <a href="https://github.com/ianmoore-playon/pulse-releases" target="_blank" rel="noopener" class="btn-outline btn-ol-blue">
            ${svgIcon("globe", 14)} View Releases
          </a>
          <a href="https://github.com/ianmoore-playon/vpu-diagnostic-tools" target="_blank" rel="noopener" class="btn-outline btn-ol-blue">
            ${svgIcon("info", 14)} Source Repo
          </a>
        </div>
      </div>
    </div>
  `;
  if (!ver) {
    api("/api/version").then((d) => {
      const el = document.getElementById("about-version");
      if (el && d?.version) el.textContent = d.version + " · Web Edition";
    }).catch(() => {});
  }
}

// ── Init ─────────────────────────────────────────────────────

async function init() {
  const navEl = document.getElementById("nav-links");
  navEl.innerHTML = NAV_SECTIONS.map((section) => `
    <div class="nav-section">
      <div class="nav-section-header">${esc(section.label)}</div>
      ${section.pages.map((p) =>
        `<a class="nav-item" data-page="${esc(p.id)}" href="#${esc(p.id)}">
          <span class="nav-icon">${svgIcon(p.icon, 16)}</span>
          <span>${esc(p.label)}</span>
        </a>`
      ).join("")}
    </div>
  `).join("");

  navEl.addEventListener("click", (e) => {
    const item = e.target.closest(".nav-item");
    if (item) {
      e.preventDefault();
      navigate(item.dataset.page);
    }
  });

  window.addEventListener("hashchange", () => {
    const hash = window.location.hash.slice(1) || "dashboard";
    if (hash !== currentPage) navigate(hash);
  });

  const startPage = window.location.hash.slice(1) || "dashboard";
  navigate(startPage);
  _updateThemeToggle();
  // Hold the splash screen until every preload section has settled
  // (success or error), so users see the loading state through a full
  // cold start instead of a half-rendered dashboard.
  //
  // Belt-and-suspenders: also enforce a maximum 60s splash duration so
  // a single hung endpoint can't strand the user behind the splash.
  const preloadPromise = preloadProgressive();
  const safetyTimeout = new Promise((resolve) => setTimeout(resolve, 60000));
  Promise.race([preloadPromise, safetyTimeout]).then(hideSplash);
  // WebSocket is started inside preloadProgressive() after dashboard loads
}

document.addEventListener("DOMContentLoaded", init);
