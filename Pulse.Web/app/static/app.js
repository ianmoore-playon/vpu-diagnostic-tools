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
  scoreconnect: "/api/scoreconnect",
  settings: "/api/settings",
};

// ── Router ───────────────────────────────────────────────────

function navigate(id) {
  if (id === currentPage) return;
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
  if (s === "running" || s === "up" || s === "pass" || s === "ok" || s === "healthy")
    return badge(status, "pass");
  if (s === "stopped" || s === "down" || s === "fail" || s === "critical")
    return badge(status, "fail");
  if (s === "warning" || s === "warn" || s === "degraded")
    return badge(status, "warn");
  if (s === "notfound") return badge("Not Found", "muted");
  return badge(status || "Unknown", "muted");
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
      ? "#ef4444"
      : pct > 75
        ? "#eab308"
        : color || "#3b82f6";
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
      ? "#ef4444"
      : raw > warnAt
        ? "#eab308"
        : color || "#3b82f6";
  return `<div class="flex flex-col items-center gap-2">
    <div class="relative" style="width:7rem;height:7rem">
      <svg viewBox="0 0 100 100" class="w-full h-full">
        <circle cx="50" cy="50" r="${r}" stroke="#2a2d3e" stroke-width="8" fill="none"/>
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
    if (data && !data.error) {
      dataCache[key] = data;
    }
    if (currentPage === key || currentPage === "dashboard") renderPage(currentPage);
    return data;
  });
  return fetchPromises[key];
}

function preloadProgressive() {
  // Phase 1: Dashboard first (fast scripts — identity, performance, services, nics)
  fetchSection("dashboard").then(() => {
    // Phase 2: After dashboard renders, start WebSocket for live metrics
    connectWS();
    // Phase 3: Background-load remaining pages with small delays
    // to avoid saturating VPU CPU with simultaneous PS processes
    const deferred = Object.keys(PAGE_API).filter((k) => k !== "dashboard");
    let delay = 500;
    deferred.forEach((key) => {
      setTimeout(() => fetchSection(key), delay);
      delay += 300;
    });
  });
  api("/api/version").then((data) => {
    if (data?.version) {
      const footer = document.querySelector(".sidebar-footer");
      if (footer) footer.textContent = data.version;
    }
  });
  api("/api/logs").then((logData) => {
    if (logData && !logData.error) {
      appendLogs(logData.logs || []);
      if (logData.demoMode) {
        document.getElementById("demo-banner")?.classList.remove("hidden");
      }
    }
  });
}

async function refreshAll() {
  dataCache = {};
  fetchingKeys.clear();
  fetchPromises = {};
  renderPage(currentPage);
  preloadProgressive();
  connectWS();
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

function renderLogPane() {
  const pane = document.getElementById("log-pane");
  if (!pane) return;
  const entries = logEntries.slice(-200);
  const body = pane.querySelector('[data-log-body="script"]');
  if (!body) return;
  body.innerHTML = entries.map((e) => {
    const statusCls = e.status === "ok" ? "log-ok" : e.status === "timeout" ? "log-warn" : "log-err";
    return `<div class="log-entry">
      <span class="log-ts">${esc(e.ts?.split("T")[1] || "")}</span>
      <span class="log-script">${esc(e.script)}</span>
      <span class="log-dur">${e.durationMs}ms</span>
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
  body.innerHTML = lines.map((l) =>
    `<div class="log-entry server-log-line">${esc(l)}</div>`
  ).join("");
  body.scrollTop = body.scrollHeight;
}

async function fetchServerLog() {
  const data = await api("/api/server-log?tail=500");
  if (data && !data.error) renderServerLog(data.lines || []);
}

function switchLogTab(tab) {
  activeLogTab = tab;
  const pane = document.getElementById("log-pane");
  if (!pane) return;
  pane.querySelectorAll(".log-tab").forEach((t) =>
    t.classList.toggle("log-tab-active", t.dataset.logTab === tab)
  );
  pane.querySelectorAll("[data-log-body]").forEach((b) =>
    b.classList.toggle("log-body-hidden", b.dataset.logBody !== tab)
  );
  if (tab === "server") fetchServerLog();
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
  if (pane) {
    pane.classList.toggle("log-pane-open", logPaneOpen);
    if (logPaneOpen) {
      if (activeLogTab === "script") renderLogPane();
      else fetchServerLog();
    }
  }
}

// ── WebSocket ────────────────────────────────────────────────

function connectWS() {
  if (ws && ws.readyState <= 1) return;
  const proto = location.protocol === "https:" ? "wss" : "ws";
  ws = new WebSocket(`${proto}://${location.host}/ws`);
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
    clearTimeout(wsRetryTimer);
    wsRetryTimer = setTimeout(connectWS, 5000);
  };
  ws.onerror = () => ws.close();
}

function updateLiveMetrics(msg) {
  if (currentPage !== "dashboard") return;
  const perf = msg.performance || {};
  const cpu = perf.cpu?.usagePercent;
  const mem = perf.memory?.usedPercent;
  const disk = perf.disk?.usedPercent;

  // Update command center metric boxes
  const container = document.getElementById("live-metrics");
  if (container) {
    const boxes = container.querySelectorAll(".metric-box");
    function setMetric(box, val) {
      if (!box) return;
      const el = box.querySelector(".metric-val");
      if (!el) return;
      const v = val != null ? Math.round(val) : null;
      el.textContent = v != null ? v + "%" : "--";
      el.style.color = _metricColor(val);
    }
    setMetric(boxes[0], cpu);
    setMetric(boxes[1], mem);
    setMetric(boxes[2], disk);
  }

  // Update system status gauge SVGs
  _updateGaugeLive("cpu", cpu);
  _updateGaugeLive("mem", mem);
  _updateGaugeLive("disk", disk);
  const liveT = perf.temperature?.celsius;
  _updateGaugeLive("temp", liveT, { max: 100, warn: 65, crit: 85, unit: "°C" });

  // Auto-refresh findings when live metrics diverge from cached snapshot
  const dash = dataCache["dashboard"];
  if (dash && dash.findings?.length) {
    const hadCpuCrit = dash.findings.some((f) => f.title === "CPU Usage Critical");
    const hadCpuWarn = dash.findings.some((f) => f.title === "CPU Usage Elevated");
    const hadTempCrit = dash.findings.some((f) => f.title === "Temperature Critical");
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
    ring.setAttribute("stroke", raw > critAt ? "#ef4444" : raw > warnAt ? "#eab308" : "#3b82f6");
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
  scoreconnect: renderScoreConnect,
  "fault-isolator": renderFaultIsolator,
  settings: renderSettings,
  about: renderAbout,
};

// ── Dashboard ────────────────────────────────────────────────

function _subsystemHealth(findings) {
  const cats = {};
  (findings || []).forEach((f) => {
    const k = (f.category || "").toLowerCase();
    cats[k] = (cats[k] || 0) + 1;
  });
  return [
    { id: "system", label: "System Overview", icon: "cpu",
      health: cats.system ? "Warning" : "Healthy",
      desc: "Hardware, OS, uptime, and Pixellot software." },
    { id: "network", label: "Network", icon: "wifi",
      health: cats.network ? "Warning" : "Healthy",
      desc: "IP, DNS, firewall, and port connectivity." },
    { id: "cameras", label: "Camera Connectivity", icon: "camera",
      health: (cats.network || cats.camera) ? "Warning" : "Healthy",
      desc: "NICs, link status, speed, and camera detection." },
    { id: "services", label: "Pixellot Services", icon: "server",
      health: cats.services ? "Warning" : "Healthy",
      desc: "Agent, encoder, watchdog service status." },
    { id: "disk-health", label: "Disk Health", icon: "hdd",
      health: (cats.storage || cats.hardware) ? "Warning" : "Healthy",
      desc: "Free space, SMART health, disk events." },
    { id: "events", label: "Event Viewer", icon: "triangle",
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
  if (val == null) return "#94a3b8";
  if (val > 90) return "#ef4444";
  if (val > 75) return "#eab308";
  return "#22c55e";
}

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
        <span class="dash-nic-name" style="color:#475569">Not detected</span>
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
  const vpuLabel = [id.manufacturer, id.model].filter(Boolean).join(" ") || hostname;

  const cpu = perf.cpu?.usagePercent;
  const mem = perf.memory?.usedPercent;
  const disk = perf.disk?.usedPercent;
  const temp = perf.temperature?.celsius;

  const warnCount = findings.filter((f) => f.severity === "warning").length;
  const critCount = findings.filter((f) => f.severity === "critical").length;
  const totalFindings = findings.length;
  const sevLabel = critCount > 0 ? `${critCount} Critical` : warnCount > 0 ? `${warnCount} Warnings` : "All Clear";
  const sevColor = critCount > 0 ? "critical" : warnCount > 0 ? "warn" : "ok";

  const topFindings = findings.slice(0, 3);
  const moreCount = Math.max(0, findings.length - 3);
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
  const internetColor = internetOk === true ? "#22c55e" : internetOk === false ? "#ef4444" : "#94a3b8";

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
        <p class="text-sm text-pulse-muted">${esc(vpuLabel)}</p>
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

    <!-- Command Center + Top Findings -->
    <div class="dash-top-grid">
      <div class="card command-center">
        <h3 class="card-label">COMMAND CENTER</h3>
        <div class="cc-severity cc-sev-${sevColor}">${esc(sevLabel)}</div>
        <div class="text-sm text-pulse-muted mb-3">${esc(vpuLabel)}</div>
        <div class="baseline-bar">
          ${svgIcon("check", 14)}
          Baseline completed ${esc(timeStr)} &bull; ${subsystems.length}/${subsystems.length} panels &bull; ${totalFindings} finding(s)
        </div>
        <div id="live-metrics" class="metrics-row">
          <div class="metric-box"><span class="metric-label">CPU</span><span class="metric-val" style="color:${_metricColor(cpu)}">${cpu != null ? Math.round(cpu) + "%" : "--"}</span></div>
          <div class="metric-box"><span class="metric-label">MEMORY</span><span class="metric-val" style="color:${_metricColor(mem)}">${mem != null ? Math.round(mem) + "%" : "--"}</span></div>
          <div class="metric-box"><span class="metric-label">DISK</span><span class="metric-val" style="color:${_metricColor(disk)}">${disk != null ? Math.round(disk) + "%" : "--"}</span></div>
          <div class="metric-box"><span class="metric-label">INTERNET</span><span class="metric-val" style="color:${internetColor}">${internetLabel}</span></div>
        </div>
      </div>
      <div class="card findings-panel">
        <div class="flex justify-between items-center mb-3">
          <h3 class="card-label mb-0">TOP FINDINGS</h3>
          ${moreCount > 0 ? `<span class="text-xs text-pulse-muted">${moreCount} more below</span>` : ""}
        </div>
        ${topFindings.length
          ? topFindings.map((f) => `
            <a class="finding-item" href="#${esc(_findingPageFor(f.category))}" onclick="event.preventDefault();navigate('${esc(_findingPageFor(f.category))}')">
              <span class="finding-dot finding-dot-${esc(f.severity)}"></span>
              <span class="finding-cat">[${esc(f.category)}]</span>
              <span class="finding-title">${esc(f.title)}</span>
              <span class="finding-arrow">${svgIcon("chevron", 14)}</span>
            </a>`).join("")
          : `<div class="dash-no-findings">${svgIcon("check", 16)} <span>No active findings detected.</span></div>`
        }
        <h3 class="card-label mt-4 mb-2">SUBSYSTEMS</h3>
        <div class="dash-sub-grid">
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

    <!-- Active Findings -->
    ${findings.length ? `
    <div class="card dash-findings-card">
      <div class="af-header">
        <span class="af-icon">${svgIcon("triangle", 18)}</span>
        <span class="af-label">ACTIVE FINDINGS</span>
        <span class="af-count-badge">${totalFindings} issue(s) found</span>
      </div>
      <div class="af-list">
        ${findings.slice(0, 10).map((f) => `
          <a class="finding-item" href="#${esc(_findingPageFor(f.category))}" onclick="event.preventDefault();navigate('${esc(_findingPageFor(f.category))}')">
            <span class="finding-dot finding-dot-${esc(f.severity)}"></span>
            <span class="finding-cat">[${esc(f.category)}]</span>
            <span class="finding-title">${esc(f.title)}</span>
            <span class="finding-arrow">${svgIcon("chevron", 14)}</span>
          </a>`).join("")}
        ${findings.length > 10 ? `<div class="text-xs text-pulse-muted px-3 py-2">${findings.length - 10} more findings...</div>` : ""}
      </div>
    </div>` : ""}

    <!-- VPU Identity + Pixellot Software -->
    <div class="dash-2col">
      <div class="card">
        <h3 class="card-label">VPU IDENTITY</h3>
        <div class="text-lg font-bold text-white mb-3">${esc(vpuLabel)}</div>
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
            <span class="dash-tile-val" style="color:${internetColor}">${internetLabel === "Connected" ? "Connected" : internetLabel === "Offline" ? "No connection" : internetLabel}</span>
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
        <div class="dash-nic-table">${_renderNicRows(nicPorts)}</div>
      </div>
      <div class="card">
        <div class="dash-card-hdr">
          <span class="dash-hdr-icon">${svgIcon("wifi", 16)}</span>
          <h3 class="card-label mb-0">NETWORK</h3>
        </div>
        <div class="dash-net-kv">
          <div class="dash-net-row"><span></span><span class="dash-kv-l">Uplink Adapter</span><span class="dash-kv-v">${esc(uplinkName)}</span></div>
          <div class="dash-net-row"><span class="dash-net-dot" style="background:${ipAddr !== "—" ? "#22c55e" : "#475569"}"></span><span class="dash-kv-l">IP Address</span><span class="dash-kv-v font-mono">${esc(ipAddr)}</span></div>
          <div class="dash-net-row"><span class="dash-net-dot" style="background:${gw !== "—" ? "#22c55e" : "#475569"}"></span><span class="dash-kv-l">Gateway</span><span class="dash-kv-v font-mono">${esc(gw)}</span></div>
          <div class="dash-net-row"><span class="dash-net-dot" style="background:${dns !== "—" ? "#22c55e" : "#475569"}"></span><span class="dash-kv-l">DNS Servers</span><span class="dash-kv-v font-mono">${esc(dns)}</span></div>
          <div class="dash-net-row"><span class="dash-net-dot" style="background:${ntpSrv !== "—" ? "#22c55e" : "#475569"}"></span><span class="dash-kv-l">NTP Server</span><span class="dash-kv-v font-mono">${esc(ntpSrv)}</span></div>
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
    </div>

    <!-- Software Inventory -->
    <div class="card mt-4">
      ${sectionTitle("server", "Software Inventory (" + swList.length + ")")}
      ${swList.length ? `
        <input type="text" id="sw-filter" placeholder="Filter software..." class="sw-filter-input"/>
        <div class="sw-table-wrap">
          <table class="data-table" id="sw-table"><thead><tr>
            <th>Name</th><th>Version</th><th>Publisher</th>
          </tr></thead><tbody>
          ${swList.map(s => `<tr>
            <td>${esc(s.displayName)}</td>
            <td class="font-mono text-xs">${esc(s.displayVersion)}</td>
            <td class="text-pulse-muted">${esc(s.publisher)}</td>
          </tr>`).join("")}
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

function _prefixToMask(prefix) {
  if (prefix == null) return null;
  var n = parseInt(prefix, 10);
  if (isNaN(n) || n < 0 || n > 32) return null;
  var mask = n === 0 ? 0 : (0xFFFFFFFF << (32 - n)) >>> 0;
  return [24, 16, 8, 0].map(function(s) { return (mask >>> s) & 0xFF; }).join(".");
}

function _buildNetFindings(cfg, ports, domains) {
  var findings = [];
  if (!cfg.internetReachable) {
    findings.push({ severity: "critical", title: "VPU has no internet connection", body: "Check the uplink cable and the gateway’s WAN status." });
    return findings;
  }
  var reqFail = 0, reqPass = 0, optFail = 0;
  (ports || []).forEach(function(p) {
    var pass = (p.status || "").toLowerCase() === "pass";
    if (p.optional) { if (!pass) optFail++; }
    else { if (pass) reqPass++; else reqFail++; }
  });
  if (reqFail > 0)
    findings.push({ severity: "critical", title: reqFail + " of " + (reqFail + reqPass) + " required ports failed", body: "Check the firewall, router, or content-filter / VLAN policy." });
  if (optFail > 0)
    findings.push({ severity: "info", title: optFail + " optional port(s) failed", body: "Optional ports (SportzCast / Zixi UDP/443 fallback) aren’t required at every venue." });
  var domFail = 0, domPass = 0;
  (domains || []).forEach(function(d) {
    if ((d.status || "").toLowerCase() === "pass") domPass++; else domFail++;
  });
  if (domFail > 0)
    findings.push({ severity: "warning", title: domFail + " of " + (domFail + domPass) + " domains failed DNS resolution", body: "Check DNS server settings on this adapter." });
  return findings;
}

function _buildNetRecommendations(cfg, ports, domains) {
  var recs = [];
  if (!cfg.internetReachable) {
    recs.push({ severity: "critical", title: "No internet ping", body: "VPU has no internet connectivity. Verify the uplink cable and the gateway’s WAN status before further triage." });
    return recs;
  }
  (ports || []).forEach(function(p) {
    if ((p.status || "").toLowerCase() === "pass") return;
    var purpose = p.purpose || "purpose unknown";
    var proto = (p.protocol || "TCP").toUpperCase();
    var host = p.host || "remote";
    var isNtp = p.port === 123 && proto === "UDP";
    if (p.optional) {
      recs.push({ severity: "info", title: proto + " " + p.port + " blocked (optional)", body: proto + "/" + p.port + " (" + purpose + ") is blocked. May not be required at this venue — only act if streaming is failing. If required, ensure outbound " + proto + " " + p.port + " to " + host + " is allowed by the venue firewall." });
    } else if (isNtp) {
      recs.push({ severity: "critical", title: "NTP time sync failed", body: "NTP sync to " + host + " failed (UDP/123). Without a clock peer the VPU’s time will drift, breaking signed-URL streaming and log correlation. Ensure outbound UDP/123 is allowed by the venue firewall." });
    } else {
      recs.push({ severity: "critical", title: proto + " " + p.port + " blocked", body: proto + "/" + p.port + " (" + purpose + ") is blocked. Ensure outbound " + proto + " " + p.port + " to " + host + " is allowed by the venue firewall, content-filter, and VLAN policy." });
    }
  });
  (domains || []).forEach(function(d) {
    if ((d.status || "").toLowerCase() === "pass") return;
    recs.push({ severity: "warning", title: d.domain + " unreachable", body: "Domain " + d.domain + " is unreachable. Ensure it is whitelisted on the venue network (firewall, DNS allow-list, SSL inspection bypass)." });
  });
  return recs;
}

function renderNetwork() {
  const data = cached("network");
  if (!data) { $page().innerHTML = sectionLoading("Network"); fetchSection("network"); return; }

  const cfg = data.config || {};
  const domains = data.domains?.results || [];
  const ports = data.ports?.results || [];
  const ntp = data.ntp || {};
  const ipConfigs = cfg.ipConfig || cfg.ipConfigurations || [];

  const findings = _buildNetFindings(cfg, ports, domains);
  const recs = _buildNetRecommendations(cfg, ports, domains);

  const hasCrit = findings.some(function(f) { return f.severity === "critical"; });
  const hasWarn = findings.some(function(f) { return f.severity === "warning"; });
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

  const tcpPorts = ports.filter(function(p) { return (p.protocol || "").toUpperCase() === "TCP"; });
  const udpPorts = ports.filter(function(p) { return (p.protocol || "").toUpperCase() === "UDP"; });

  function portCard(p) {
    const ok = (p.status || "").toLowerCase() === "pass";
    const cls = ok ? "port-card-pass" : "port-card-fail";
    return `<div class="port-card ${cls}">
      <div class="port-card-num">${esc(String(p.port))}</div>
      <div class="port-card-name">${esc(p.purpose)}</div>
      <div class="port-card-host">${esc(p.host)}</div>
      ${p.optional ? '<div class="port-card-opt">Optional</div>' : ""}
    </div>`;
  }

  const findingsBanner = findings.length ? `
    <div class="card net-findings-banner">
      <div class="af-header">
        ${svgIcon("triangle", 16)}
        <span class="af-label">FINDINGS</span>
        <span class="af-count-badge">${findings.length} issue${findings.length !== 1 ? "s" : ""}</span>
      </div>
      <div class="net-finding-list">
        ${findings.map(function(f) {
          const sc = f.severity === "critical" ? "sev-chip-crit" : f.severity === "warning" ? "sev-chip-warn" : "sev-chip-ok";
          return `<div class="net-finding-row">
            <span class="sev-chip ${sc}">${esc(f.severity.toUpperCase())}</span>
            <div>
              <div class="net-finding-title">${esc(f.title)}</div>
              <div class="net-finding-body">${esc(f.body)}</div>
            </div>
          </div>`;
        }).join("")}
      </div>
    </div>` : "";

  const recsPanel = recs.length ? `
    <div class="card">
      ${sectionTitle("triangle", "Recommended Actions")}
      <div class="net-rec-list">
        ${recs.map(function(r) {
          const cls = r.severity === "critical" ? "net-rec-critical" : r.severity === "warning" ? "net-rec-warn" : "net-rec-info";
          const sc = r.severity === "critical" ? "sev-chip-crit" : r.severity === "warning" ? "sev-chip-warn" : "sev-chip-ok";
          return `<div class="net-rec-card ${cls}">
            <div class="net-rec-header">
              <span class="sev-chip ${sc}">${esc(r.severity.toUpperCase())}</span>
              <span class="net-rec-title">${esc(r.title)}</span>
            </div>
            <div class="net-rec-body">${esc(r.body)}</div>
          </div>`;
        }).join("")}
      </div>
    </div>` : "";

  $page().innerHTML = `
    ${pageHeader("Network", "Adapters, IP, NTP, and reachability — what the box can talk to right now",
      statusChip + `<button class="btn-outline btn-ol-blue" onclick="dataCache.network=null;renderNetwork()">
        ${svgIcon("refresh", 14)} Refresh
      </button>`
    )}

    ${findingsBanner}

    ${recsPanel}

    <!-- Port Connectivity -->
    <div class="card">
      ${sectionTitle("link", "Port Connectivity")}
      <div class="net-port-cols">
        <div class="net-sub-card">
          <div class="net-sub-heading">TCP ports <span class="net-proto-badge net-proto-tcp">TCP</span></div>
          ${tcpPorts.length
            ? `<div class="port-grid">${tcpPorts.map(portCard).join("")}</div>`
            : '<p class="text-pulse-muted text-sm mt-2">No TCP port results</p>'}
        </div>
        <div class="net-sub-card">
          <div class="net-sub-heading">UDP ports <span class="net-proto-badge net-proto-udp">UDP</span></div>
          ${udpPorts.length
            ? `<div class="port-grid">${udpPorts.map(portCard).join("")}</div>`
            : '<p class="text-pulse-muted text-sm mt-2">No UDP port results</p>'}
        </div>
      </div>
    </div>

    <!-- Internet Adapter + IP Config | Domain Reachability -->
    <div class="net-bottom-grid">
      <div class="card">
        ${sectionTitle("globe", "Internet Adapter & IP Configuration")}
        <div class="net-adapter-cols">
          <div class="net-sub-card">
            <div class="net-sub-heading">ADAPTER</div>
            ${uplinkAdapterRow ? `
              <div class="font-semibold text-white mb-3">${esc(uplinkAdapterRow.name)}</div>
              <div class="net-kv">
                ${kvRow("IP address", adapterIp)}
                ${kvRowHtml("Link state", `<span style="color:${adapterLinkState === "Up" ? "#22c55e" : "#94a3b8"};font-weight:600">${esc(adapterLinkState)}</span>`)}
                ${kvRow("Link speed", uplinkAdapterRow.linkSpeed || "—")}
                ${kvRowHtml("Internet", cfg.internetReachable
                  ? '<span class="status-pass">Reachable</span>'
                  : '<span class="status-fail">Unreachable</span>')}
                ${kvRow("Gateway", cfg.uplinkAdapter?.gateway || "—")}
              </div>` : `
              <p class="text-pulse-muted text-sm">No internet-bound adapter detected.</p>
              ${kvRowHtml("Internet", cfg.internetReachable
                ? '<span class="status-pass">Reachable</span>'
                : '<span class="status-fail">Unreachable</span>')}`}
          </div>
          <div class="net-sub-card">
            <div class="net-sub-heading">IP CONFIGURATION</div>
            <div class="net-kv">
              ${kvRow("IP address", adapterIp)}
              ${kvRow("Assignment", dhcpLabel)}
              ${kvRow("Subnet mask", subnetMask || "—")}
              ${kvRow("Gateway", cfg.uplinkAdapter?.gateway || "—")}
              ${kvRow("DNS", dnsStr)}
              ${kvRow("NTP server", cfg.ntpSource || "—")}
              ${kvRowHtml("NTP drift", ntp.offsetSeconds != null ? esc(ntp.offsetSeconds + "s") : "—")}
              ${kvRowHtml("NTP status", ntp.status ? statusBadge(ntp.status) : "—")}
            </div>
          </div>
        </div>
      </div>
      <div class="card">
        ${sectionTitle("wifi", "Domain Reachability")}
        ${domains.length ? `
          <div class="domain-list">
            ${domains.map(function(d) {
              const ok = (d.status || "").toLowerCase() === "pass";
              return `<div class="domain-row">
                <span class="domain-dot" style="background:${ok ? "#22c55e" : "#ef4444"}"></span>
                <span class="domain-name">${esc(d.domain)}</span>
                <span class="domain-ip">${esc(d.resolvedTo) || "—"}</span>
                ${statusBadge(d.status)}
              </div>`;
            }).join("")}
          </div>
        ` : '<p class="text-pulse-muted text-sm">No DNS data</p>'}
      </div>
    </div>
  `;
}

// ── Cameras ──────────────────────────────────────────────────

function renderCameras() {
  const data = cached("cameras");
  if (!data) { $page().innerHTML = sectionLoading("Camera Connectivity"); fetchSection("cameras"); return; }

  const ports = data.ports || [];
  const pixCfg = data.pixellotConfig || {};
  const cfgCameras = pixCfg.cameras || [];

  const portSlots = [];
  for (let i = 0; i < Math.max(4, ports.length); i++) {
    portSlots.push(ports[i] || null);
  }

  function portTile(port, index) {
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
    else if (p.isOcr) { statusLabel = "OCR (100 Mbps)"; dotCls = "cam-dot-info"; }
    else if (p.isDegraded) { statusLabel = "Degraded"; dotCls = "cam-dot-warn"; }
    else { statusLabel = "Linked · " + speed; dotCls = "cam-dot-up"; }

    const cams = p.camerasDetected || [];
    return `<div class="cam-port-tile ${p.isUp ? "cam-port-active" : "cam-port-down"}">
      <div class="cam-port-header">
        <span class="cam-port-num">Port ${index + 1}</span>
        ${p.isOcr ? '<span class="badge-ol badge-ol-info">OCR</span>' : ""}
        ${p.isDegraded ? '<span class="badge-ol badge-ol-warn">Degraded</span>' : ""}
      </div>
      <div class="cam-port-name">${esc(p.name)}</div>
      <div class="cam-port-status">
        <span class="cam-dot ${dotCls}"></span>
        <span class="text-sm">${esc(statusLabel)}</span>
      </div>
      <div class="cam-port-detail">
        <div class="kv-mini"><span>MAC</span><span class="font-mono">${esc(p.mac)}</span></div>
        <div class="kv-mini"><span>RX / TX</span><span>${formatBytes(p.rxBytes)} / ${formatBytes(p.txBytes)}</span></div>
      </div>
      ${cams.length > 0 ? `
        <div class="cam-detected">
          <div class="cam-detected-label">${cams.length} Pixellot camera${cams.length > 1 ? "s" : ""} detected</div>
          ${cams.map(c => `<div class="cam-detected-entry">
            <span class="font-mono">${esc(c.ip)}</span>
            <span class="font-mono text-pulse-muted">${esc(c.mac)}</span>
          </div>`).join("")}
        </div>
      ` : p.isUp ? '<div class="cam-no-detect">No Pixellot cameras on this port</div>' : ""}
    </div>`;
  }

  $page().innerHTML = `
    ${pageHeader("Camera Connectivity", "NIC ports, link status, speed, and Pixellot camera detection",
      `<button class="btn-outline btn-ol-blue" onclick="navigate('fault-isolator')">
        ${svgIcon("zap", 14)} Fault Isolator
      </button>
      <button class="btn-outline btn-ol-blue" onclick="dataCache.cameras=null;renderCameras()">
        ${svgIcon("refresh", 14)} Refresh
      </button>`
    )}

    <div class="cam-port-grid">
      ${portSlots.map((p, i) => portTile(p, i)).join("")}
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

    ${ports.filter(p => p.arpEntries?.length).map(p => `
    <div class="card mt-4">
      <details>
        <summary class="text-sm text-pulse-muted cursor-pointer font-medium">
          ${esc(p.name)} — ARP entries (${p.arpEntries.length})
        </summary>
        <div class="mt-3 max-h-48 overflow-y-auto">
          <table class="data-table"><thead><tr><th>IP</th><th>MAC</th></tr></thead><tbody>
          ${p.arpEntries.map(a => `<tr>
            <td class="font-mono text-xs">${esc(a.ip)}</td>
            <td class="font-mono text-xs">${esc(a.mac)}</td>
          </tr>`).join("")}
          </tbody></table>
        </div>
      </details>
    </div>`).join("")}
  `;
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

    <div class="svc-grid" id="svc-grid">
      ${svcs.map(svcTile).join("")}
      ${!svcs.length ? '<p class="text-pulse-muted text-sm">No services data</p>' : ""}
    </div>
  `;

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
        const statusColor = pct > 90 ? "#ef4444" : pct > 80 ? "#eab308" : "#22c55e";
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
            <label class="ev-check"><input type="checkbox" id="ev-error" checked> <span style="color:#ef4444">Error</span></label>
            <label class="ev-check"><input type="checkbox" id="ev-warning" checked> <span style="color:#eab308">Warning</span></label>
            <label class="ev-check"><input type="checkbox" id="ev-info" checked> <span style="color:#3b82f6">Information</span></label>
          </div>
        </div>
        <div class="ev-filter-group ev-filter-grow">
          <label class="ev-filter-label">SOURCE OR MESSAGE CONTAINS</label>
          <input type="text" id="ev-source" placeholder="e.g. disk, Pixellot, WHEA" class="ev-input"/>
        </div>
      </div>
    </div>

    <div class="card mt-4" id="ev-body">${loading()}</div>
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

  document.getElementById("ev-refresh")?.addEventListener("click", loadEvents);
  document.getElementById("ev-hours")?.addEventListener("change", loadEvents);
  ["ev-error", "ev-warning", "ev-info"].forEach(id => {
    document.getElementById(id)?.addEventListener("change", loadEvents);
  });
  document.getElementById("ev-source")?.addEventListener("input", _debounce(loadEvents, 300));
  loadEvents();
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

function renderScoreConnect() {
  const data = cached("scoreconnect");
  if (!data) { $page().innerHTML = sectionLoading("ScoreConnect"); fetchSection("scoreconnect"); return; }

  const status = data.status || {};
  const config = data.configuration || {};
  const botStatus = data.botStatus || {};
  const liveScore = data.liveScoreData || {};
  const isDetected = data.reachable || status.isDetected;

  $page().innerHTML = `
    ${pageHeader("Score Connect", "ScoreConnect III scoreboard integration — service, configuration, and live data",
      `<button class="btn-outline btn-ol-blue" onclick="dataCache.scoreconnect=null;renderScoreConnect()">
        ${svgIcon("refresh", 14)} Refresh
      </button>`
    )}

    <!-- Service Status + Live Scoreboard -->
    <div class="dash-2col">
      <div class="card">
        ${sectionTitle("server", "Service Status")}
        <div class="kv-grid">
          ${kvRowHtml("Detected", isDetected
            ? '<span class="status-pass">Yes</span>'
            : '<span class="status-fail">No</span>')}
          ${kvRow("Base URL", status.baseUrl || data.baseUrl)}
          ${kvRow("Version", status.version)}
          ${data.error && !isDetected ? kvRowHtml("Error", `<span class="text-red-400">${esc(typeof data.error === "string" ? data.error : data.message || "Connection failed")}</span>`) : ""}
        </div>
      </div>
      <div class="card">
        ${sectionTitle("monitor", "Live Scoreboard")}
        ${liveScore.homeTeam || liveScore.awayTeam ? `
          <div class="sc-teams">
            <div class="sc-team-card">
              <div class="sc-team-label">HOME</div>
              <div class="sc-team-name">${esc(liveScore.homeTeam || "—")}</div>
              ${liveScore.homeScore != null ? `<div class="sc-team-score">${esc(String(liveScore.homeScore))}</div>` : ""}
            </div>
            <div class="sc-team-card">
              <div class="sc-team-label">AWAY</div>
              <div class="sc-team-name">${esc(liveScore.awayTeam || "—")}</div>
              ${liveScore.awayScore != null ? `<div class="sc-team-score">${esc(String(liveScore.awayScore))}</div>` : ""}
            </div>
          </div>
          <div class="sc-game-info">
            <div><span class="text-pulse-muted">Period</span> <span class="font-mono">${esc(String(liveScore.period || "—"))}</span></div>
            <div><span class="text-pulse-muted">Clock</span> <span class="font-mono">${esc(String(liveScore.clock || "—"))}</span></div>
          </div>
        ` : '<div class="text-sm text-pulse-muted">No live scoreboard data available</div>'}
      </div>
    </div>

    <!-- Connected Device / Configuration -->
    ${config.vendor || config.sport ? `
    <div class="card mt-4">
      ${sectionTitle("cog", "Connected Device")}
      <div class="dash-2col" style="margin-top:0">
        <div class="sub-card">
          <div class="kv-grid">
            ${kvRow("Vendor", config.vendor)}
            ${kvRow("Sport", config.sport)}
            ${kvRow("Configuration", config.vendorConfigurationName || config.device)}
          </div>
        </div>
        <div class="sub-card">
          <div class="kv-grid">
            ${kvRow("Serial Port", config.serialPort)}
            ${kvRow("Firmware", config.firmware)}
            ${kvRow("Event Type", config.eventType)}
          </div>
        </div>
      </div>
    </div>` : ""}

    <!-- Cloud BOT + ScoreLink -->
    ${botStatus.isConnected != null ? `
    <div class="dash-2col">
      <div class="card">
        ${sectionTitle("globe", "Cloud (BOT) Status")}
        <div class="kv-grid">
          ${kvRowHtml("Connected", botStatus.isConnected
            ? '<span class="status-pass">Yes</span>'
            : '<span class="status-fail">No</span>')}
          ${kvRow("ScoreConnect ID", botStatus.scoreConnectId)}
          ${kvRow("BOT Server", botStatus.botServerAddress)}
          ${botStatus.lastErrorMessage ? kvRowHtml("Last Error", `<span class="text-pulse-muted">${esc(botStatus.lastErrorMessage)}</span>`) : ""}
        </div>
      </div>
      <div class="card">
        ${sectionTitle("link", "ScoreLink Device")}
        <div class="sc-scorelink ${data.scoreLinkConnected ? "sc-scorelink-ok" : "sc-scorelink-err"}">
          <span class="sc-scorelink-dot"></span>
          <span class="font-semibold">${esc(data.scoreLinkStatusLabel || (data.scoreLinkConnected ? "ScoreLink Connected" : "ScoreLink Not Detected"))}</span>
        </div>
      </div>
    </div>` : ""}

    <!-- Raw Data Fallback -->
    ${!config.vendor && botStatus.isConnected == null && (data.status || data.configuration) ? `
    <div class="card mt-4">
      ${sectionTitle("file", "Raw Response")}
      <pre class="text-xs text-pulse-muted overflow-auto max-h-60 p-3 bg-pulse-bg rounded">${esc(JSON.stringify(data, null, 2))}</pre>
    </div>` : ""}
  `;
}

// ── Fault Isolator ───────────────────────────────────────────

function renderFaultIsolator() {
  const steps = [
    { id: "internet", label: "Internet Connectivity" },
    { id: "dns", label: "DNS Resolution" },
    { id: "ports", label: "Port Connectivity" },
    { id: "services", label: "Service Status" },
    { id: "cameras", label: "Camera Detection" },
    { id: "performance", label: "System Performance" },
  ];

  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-4">Fault Isolator</h2>
    <p class="text-sm text-pulse-muted mb-6">Run a sequential diagnostic check across all subsystems.</p>
    <button class="btn btn-primary mb-6" id="fi-start">Start Diagnosis</button>
    <button class="btn btn-secondary mb-6 ml-2 hidden" id="fi-reset">Reset</button>
    <div id="fi-steps">
      ${steps.map((s) => `<div class="wizard-step" id="fi-${esc(s.id)}"><div class="flex items-center gap-3"><span class="text-sm font-medium">${esc(s.label)}</span><span id="fi-badge-${esc(s.id)}" class="text-xs text-pulse-muted">Pending</span></div><div id="fi-detail-${esc(s.id)}" class="text-xs text-pulse-muted mt-1 hidden"></div></div>`).join("")}
    </div>
    <div id="fi-summary" class="mt-6 hidden"></div>
  `;

  document.getElementById("fi-start").addEventListener("click", async () => {
    document.getElementById("fi-start").classList.add("hidden");
    document.getElementById("fi-reset").classList.remove("hidden");

    let passCount = 0;
    let warnCount = 0;
    let failCount = 0;

    async function runStep(id, fn) {
      const el = document.getElementById("fi-" + id);
      const badgeEl = document.getElementById("fi-badge-" + id);
      const detailEl = document.getElementById("fi-detail-" + id);
      el.className = "wizard-step step-running";
      badgeEl.textContent = "Checking...";
      detailEl.classList.remove("hidden");
      detailEl.textContent = "";

      try {
        const result = await fn();
        el.className = "wizard-step step-" + result.status;
        badgeEl.innerHTML = statusBadge(
          result.status === "pass" ? "Pass" : result.status === "warn" ? "Warning" : "Fail"
        );
        detailEl.textContent = result.detail;
        if (result.status === "pass") passCount++;
        else if (result.status === "warn") warnCount++;
        else failCount++;
      } catch (e) {
        el.className = "wizard-step step-fail";
        badgeEl.innerHTML = statusBadge("Fail");
        detailEl.textContent = e.message;
        failCount++;
      }
    }

    await runStep("internet", async () => {
      const d = await api("/api/network");
      const ok = d.config?.internetReachable;
      return {
        status: ok ? "pass" : "fail",
        detail: ok
          ? "Internet reachable via " + (d.config?.testedHost || "ping")
          : "No internet connectivity detected",
      };
    });

    await runStep("dns", async () => {
      const d = await api("/api/network");
      const results = d.domains?.results || [];
      const fails = results.filter((r) => r.status === "fail");
      if (!results.length) return { status: "fail", detail: "No DNS results" };
      if (fails.length === 0)
        return { status: "pass", detail: "All " + results.length + " domains resolved" };
      if (fails.length < results.length)
        return {
          status: "warn",
          detail: fails.length + " of " + results.length + " domains failed: " + fails.map((f) => f.domain).join(", "),
        };
      return { status: "fail", detail: "All DNS resolution failed" };
    });

    await runStep("ports", async () => {
      const d = await api("/api/network");
      const results = d.ports?.results || [];
      const required = results.filter((r) => !r.optional);
      const reqFails = required.filter((r) => r.status === "fail");
      if (!results.length) return { status: "fail", detail: "No port test results" };
      if (reqFails.length === 0)
        return { status: "pass", detail: "All " + required.length + " required ports open" };
      return {
        status: "fail",
        detail: reqFails.length + " required port(s) blocked: " + reqFails.map((f) => f.purpose).join(", "),
      };
    });

    await runStep("services", async () => {
      const d = await api("/api/services");
      const svcs = d.services || [];
      const critical = ["agent", "vpu"];
      const stopped = svcs.filter(
        (s) => s.status === "Stopped" && critical.includes(s.name.toLowerCase())
      );
      const missing = svcs.filter(
        (s) => s.status === "NotFound" && critical.includes(s.name.toLowerCase())
      );
      if (stopped.length)
        return { status: "fail", detail: "Stopped: " + stopped.map((s) => s.name).join(", ") };
      if (missing.length)
        return { status: "warn", detail: "Not installed: " + missing.map((s) => s.name).join(", ") };
      return { status: "pass", detail: "All critical services running" };
    });

    await runStep("cameras", async () => {
      const d = await api("/api/cameras");
      const cPorts = d.ports || [];
      const allCams = cPorts.flatMap((p) => p.camerasDetected || []);
      const downPorts = cPorts.filter((p) => !p.isUp);
      if (downPorts.length)
        return {
          status: "warn",
          detail: downPorts.length + " NIC port(s) down. " + allCams.length + " camera(s) detected on other ports.",
        };
      if (allCams.length === 0)
        return { status: "warn", detail: "No Pixellot cameras detected in ARP tables" };
      return {
        status: "pass",
        detail: allCams.length + " Pixellot camera(s) detected across " + cPorts.filter((p) => (p.camerasDetected || []).length > 0).length + " port(s)",
      };
    });

    await runStep("performance", async () => {
      const d = await api("/api/dashboard");
      const perf = d.performance || {};
      const issues = [];
      const cpuVal = perf.cpu?.usagePercent || 0;
      const memVal = perf.memory?.usedPercent || 0;
      const diskVal = perf.disk?.usedPercent || 0;
      if (cpuVal > 90) issues.push("CPU at " + cpuVal + "%");
      if (memVal > 90) issues.push("Memory at " + memVal + "%");
      if (diskVal > 90) issues.push("Disk at " + diskVal + "%");
      if (issues.length)
        return { status: "fail", detail: issues.join("; ") };
      return {
        status: "pass",
        detail: "CPU " + cpuVal + "%, Memory " + memVal + "%, Disk " + diskVal + "%",
      };
    });

    const summaryEl = document.getElementById("fi-summary");
    summaryEl.classList.remove("hidden");
    const overall =
      failCount > 0 ? "critical" : warnCount > 0 ? "warning" : "ok";
    summaryEl.innerHTML = `<div class="sev-${esc(overall)} rounded px-4 py-3">
      <div class="font-semibold">Diagnosis Complete</div>
      <div class="text-sm mt-1">${passCount} passed, ${warnCount} warning(s), ${failCount} failed</div>
    </div>`;
  });

  document
    .getElementById("fi-reset")
    .addEventListener("click", () => renderFaultIsolator());
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
        <div class="about-version">v0.9.0-beta · Web Edition</div>
        <p class="about-desc">A lightweight, self-contained diagnostic tool for Pixellot VPU systems. Collects system identity, hardware, performance metrics, network configuration, camera connectivity, service status, disk health, and event logs.</p>
        <div class="about-info">
          <div class="kv-grid kv-grid-center">
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
  preloadProgressive();
  // WebSocket is started inside preloadProgressive() after dashboard loads
}

document.addEventListener("DOMContentLoaded", init);
