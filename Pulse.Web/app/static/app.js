/* Pulse Web — Vanilla JS SPA */

// ── Pages ────────────────────────────────────────────────────
const PAGES = [
  { id: "dashboard", label: "Dashboard" },
  { id: "system", label: "System Overview" },
  { id: "network", label: "Network" },
  { id: "cameras", label: "Cameras" },
  { id: "services", label: "Services" },
  { id: "disk-health", label: "Disk Health" },
  { id: "events", label: "Event Viewer" },
  { id: "reports", label: "Reports" },
  { id: "scoreconnect", label: "ScoreConnect" },
  { id: "fault-isolator", label: "Fault Isolator" },
  { id: "settings", label: "Settings" },
  { id: "about", label: "About" },
];

let currentPage = "";
let ws = null;
let wsRetryTimer = null;

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
  if (fn) fn();
  else $page().innerHTML = `<p class="text-pulse-muted">Unknown page: ${esc(id)}</p>`;
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

function gauge(label, value, unit, color) {
  const pct = Math.min(Math.max(value || 0, 0), 100);
  const r = 40;
  const circ = 2 * Math.PI * r;
  const offset = circ * (1 - pct / 100);
  const c =
    pct > 90
      ? "#ef4444"
      : pct > 75
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
        <span class="text-xl font-bold">${value != null ? esc(String(value)) : "--"}<span class="text-xs text-pulse-muted">${esc(unit || "%")}</span></span>
      </div>
    </div>
    <span class="text-xs text-pulse-muted font-medium">${esc(label)}</span>
  </div>`;
}

// ── WebSocket ────────────────────────────────────────────────

function connectWS() {
  if (ws && ws.readyState <= 1) return;
  const proto = location.protocol === "https:" ? "wss" : "ws";
  ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.onmessage = (e) => {
    try {
      const msg = JSON.parse(e.data);
      if (msg.type === "metrics") updateLiveMetrics(msg);
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
  const temp = perf.temperature?.celsius;

  const el = document.getElementById("live-gauges");
  if (el) {
    el.innerHTML =
      gauge("CPU", cpu != null ? Math.round(cpu) : null, "%", "#3b82f6") +
      gauge("Memory", mem != null ? Math.round(mem) : null, "%", "#8b5cf6") +
      gauge("Disk", disk != null ? Math.round(disk) : null, "%", "#f59e0b") +
      gauge("Temp", temp != null ? Math.round(temp) : null, "°C", "#ef4444");
  }
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

async function renderDashboard() {
  $page().innerHTML = loading();
  const data = await api("/api/dashboard");
  if (currentPage !== "dashboard") return;

  if (data.error) {
    $page().innerHTML = errorBox(data.message);
    return;
  }

  const id = data.identity || {};
  const perf = data.performance || {};
  const findings = data.findings || [];

  const cpu = perf.cpu?.usagePercent;
  const mem = perf.memory?.usedPercent;
  const disk = perf.disk?.usedPercent;
  const temp = perf.temperature?.celsius;

  let findingsHtml = "";
  if (findings.length) {
    findingsHtml = findings
      .map(
        (f) => `<div class="sev-${esc(f.severity)} rounded px-3 py-2 mb-2">
        <div class="font-medium text-sm">${esc(f.title)}</div>
        <div class="text-xs mt-0.5 opacity-80">${esc(f.recommendation)}</div>
      </div>`
      )
      .join("");
    findingsHtml = `<div class="mb-6">
      <h2 class="text-sm font-semibold text-pulse-muted uppercase tracking-wide mb-2">Findings</h2>
      ${findingsHtml}
    </div>`;
  }

  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-6">Dashboard</h2>
    ${findingsHtml}
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <div class="lg:col-span-2">
        ${card(
          "Performance",
          `<div id="live-gauges" class="flex justify-around flex-wrap gap-4 py-2">
            ${gauge("CPU", cpu != null ? Math.round(cpu) : null, "%", "#3b82f6")}
            ${gauge("Memory", mem != null ? Math.round(mem) : null, "%", "#8b5cf6")}
            ${gauge("Disk", disk != null ? Math.round(disk) : null, "%", "#f59e0b")}
            ${gauge("Temp", temp != null ? Math.round(temp) : null, "°C", "#ef4444")}
          </div>`
        )}
      </div>
      <div>
        ${card(
          "System Identity",
          `<div class="space-y-2 text-sm">
            ${idRow("Hostname", id.hostname)}
            ${idRow("Serial", id.serialNumber)}
            ${idRow("Model", id.model)}
            ${idRow("Manufacturer", id.manufacturer)}
            ${idRow("OS", id.os)}
            ${idRow("Uptime", id.uptime)}
            ${idRow("Pixellot", id.pixellotVersion)}
            ${idRow("Image", id.imageVersion)}
          </div>`
        )}
      </div>
    </div>
    ${card(
      "Services",
      `<div class="flex flex-wrap gap-2">
        ${(data.services?.services || [])
          .map(
            (s) =>
              `<div class="flex items-center gap-2 bg-pulse-bg rounded px-3 py-1.5 text-sm">
              <span>${esc(s.name)}</span>${statusBadge(s.status)}
            </div>`
          )
          .join("")}
      </div>`,
      "mt-6"
    )}
  `;
}

function idRow(label, val) {
  return `<div class="flex justify-between"><span class="text-pulse-muted">${esc(label)}</span><span class="font-medium">${val != null ? esc(String(val)) : "--"}</span></div>`;
}

// ── System Overview ──────────────────────────────────────────

async function renderSystem() {
  $page().innerHTML = loading();
  const data = await api("/api/system");
  if (currentPage !== "system") return;

  const id = data.identity || {};
  const hw = data.hardware || {};
  const sw = data.software || {};

  if (data.identity?.error && data.hardware?.error) {
    $page().innerHTML = errorBox(
      data.identity?.message || data.hardware?.message
    );
    return;
  }

  const os = id.operatingSystem || {};

  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-6">System Overview</h2>
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      ${card(
        "Operating System",
        `<div class="space-y-2 text-sm">
          ${idRow("OS", os.caption)}
          ${idRow("Version", os.version)}
          ${idRow("Build", os.buildNumber)}
          ${idRow("Architecture", os.osArchitecture)}
          ${idRow("Timezone", id.timezone)}
        </div>`
      )}
      ${card(
        "Processors",
        hw.processors?.length
          ? `<table class="data-table"><thead><tr>
              <th>Name</th><th>Cores</th><th>Threads</th><th>Clock</th>
            </tr></thead><tbody>
            ${hw.processors
              .map(
                (p) => `<tr>
              <td>${esc(p.name)}</td>
              <td>${p.numberOfCores || "--"}</td>
              <td>${p.numberOfLogicalProcessors || "--"}</td>
              <td>${p.maxClockSpeedMHz ? esc(String(p.maxClockSpeedMHz)) + " MHz" : "--"}</td>
            </tr>`
              )
              .join("")}
            </tbody></table>`
          : '<p class="text-pulse-muted text-sm">No data</p>'
      )}
      ${card(
        "Memory",
        hw.memory?.length
          ? `<table class="data-table"><thead><tr>
              <th>Capacity</th><th>Speed</th><th>Type</th><th>Slot</th>
            </tr></thead><tbody>
            ${hw.memory
              .map(
                (m) => `<tr>
              <td>${esc(String(m.capacityGB))} GB</td>
              <td>${m.speedMHz ? esc(String(m.speedMHz)) + " MHz" : "--"}</td>
              <td>${esc(m.memoryType)}</td>
              <td>${esc(m.deviceLocator)}</td>
            </tr>`
              )
              .join("")}
            </tbody></table>`
          : '<p class="text-pulse-muted text-sm">No data</p>'
      )}
      ${card(
        "GPUs",
        hw.gpus?.length
          ? hw.gpus
              .map(
                (g) => `<div class="text-sm mb-2">
              <div class="font-medium">${esc(g.name)}</div>
              <div class="text-pulse-muted">RAM: ${g.adapterRAMMB ? esc(String(g.adapterRAMMB)) + " MB" : "N/A"} · Driver: ${esc(g.driverVersion)}</div>
            </div>`
              )
              .join("")
          : '<p class="text-pulse-muted text-sm">No data</p>'
      )}
    </div>
    ${card(
      "Disk Drives",
      hw.diskDrives?.length
        ? `<table class="data-table"><thead><tr>
            <th>Model</th><th>Size</th><th>Interface</th><th>Serial</th>
          </tr></thead><tbody>
          ${hw.diskDrives
            .map(
              (d) => `<tr>
            <td>${esc(d.model)}</td>
            <td>${esc(String(d.sizeGB))} GB</td>
            <td>${esc(d.interfaceType)}</td>
            <td class="font-mono text-xs">${esc(d.serialNumber)}</td>
          </tr>`
            )
            .join("")}
          </tbody></table>`
        : '<p class="text-pulse-muted text-sm">No data</p>',
      "mt-6"
    )}
    ${card(
      "Installed Software (" + esc(String(sw.count || 0)) + ")",
      sw.software?.length
        ? `<div class="max-h-72 overflow-y-auto">
          <input type="text" id="sw-filter" placeholder="Filter..." class="w-full mb-2 px-3 py-1.5 bg-pulse-bg border border-pulse-border rounded text-sm text-pulse-text outline-none focus:border-pulse-accent"/>
          <table class="data-table" id="sw-table"><thead><tr>
            <th>Name</th><th>Version</th><th>Publisher</th>
          </tr></thead><tbody>
          ${sw.software
            .map(
              (s) => `<tr>
            <td>${esc(s.displayName)}</td>
            <td>${esc(s.displayVersion)}</td>
            <td>${esc(s.publisher)}</td>
          </tr>`
            )
            .join("")}
          </tbody></table>
        </div>`
        : '<p class="text-pulse-muted text-sm">No data</p>',
      "mt-6"
    )}
  `;

  const swFilter = document.getElementById("sw-filter");
  if (swFilter) {
    swFilter.addEventListener("input", () => {
      const q = swFilter.value.toLowerCase();
      document.querySelectorAll("#sw-table tbody tr").forEach((tr) => {
        tr.style.display = tr.textContent.toLowerCase().includes(q)
          ? ""
          : "none";
      });
    });
  }
}

// ── Network ──────────────────────────────────────────────────

async function renderNetwork() {
  $page().innerHTML = loading();
  const data = await api("/api/network");
  if (currentPage !== "network") return;

  const cfg = data.config || {};
  const domains = data.domains?.results || [];
  const ports = data.ports?.results || [];
  const ntp = data.ntp || {};

  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-6">Network</h2>
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
      ${card(
        "Connectivity",
        `<div class="space-y-2 text-sm">
          ${idRow("Internet", cfg.internetReachable ? '<span class="status-pass">Reachable</span>' : '<span class="status-fail">Unreachable</span>')}
          ${idRow("Tested Host", cfg.testedHost)}
          ${idRow("NTP Source", cfg.ntpSource)}
          ${idRow("NTP Drift", ntp.offsetSeconds != null ? esc(String(ntp.offsetSeconds)) + "s" : "N/A")}
          ${idRow("NTP Status", ntp.status ? statusBadge(ntp.status) : "--")}
        </div>`
      )}
      ${card(
        "Uplink",
        cfg.uplinkAdapter
          ? `<div class="space-y-2 text-sm">
              ${idRow("Adapter", cfg.uplinkAdapter.interfaceAlias)}
              ${idRow("Gateway", cfg.uplinkAdapter.gateway)}
            </div>`
          : '<p class="text-pulse-muted text-sm">No uplink detected</p>'
      )}
    </div>
    ${card(
      "IP Configuration",
      cfg.ipConfig?.length
        ? `<table class="data-table"><thead><tr>
            <th>Interface</th><th>IPv4</th><th>Gateway</th><th>DNS</th>
          </tr></thead><tbody>
          ${cfg.ipConfig
            .map(
              (ip) => `<tr>
            <td>${esc(ip.interfaceAlias)}</td>
            <td>${(ip.ipv4Address || []).map(esc).join(", ") || "--"}</td>
            <td>${(ip.ipv4DefaultGateway || []).map(esc).join(", ") || "--"}</td>
            <td class="text-xs">${(ip.dnsServers || []).flat().map(esc).join(", ") || "--"}</td>
          </tr>`
            )
            .join("")}
          </tbody></table>`
        : '<p class="text-pulse-muted text-sm">No data</p>',
      "mb-6"
    )}
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      ${card(
        "Domain Resolution",
        domains.length
          ? `<table class="data-table"><thead><tr>
              <th>Domain</th><th>Resolved To</th><th>Status</th>
            </tr></thead><tbody>
            ${domains
              .map(
                (d) => `<tr>
              <td>${esc(d.domain)}</td>
              <td class="font-mono text-xs">${esc(d.resolvedTo) || "--"}</td>
              <td>${statusBadge(d.status)}</td>
            </tr>`
              )
              .join("")}
            </tbody></table>`
          : '<p class="text-pulse-muted text-sm">No data</p>'
      )}
      ${card(
        "Port Connectivity",
        ports.length
          ? `<table class="data-table"><thead><tr>
              <th>Service</th><th>Host</th><th>Port</th><th>Proto</th><th>Status</th>
            </tr></thead><tbody>
            ${ports
              .map(
                (p) => `<tr>
              <td>${esc(p.purpose)}</td>
              <td class="font-mono text-xs">${esc(p.host)}</td>
              <td>${esc(String(p.port))}</td>
              <td>${esc(p.protocol)}</td>
              <td>${statusBadge(p.status)}${p.optional ? ' <span class="text-xs text-pulse-muted">(opt)</span>' : ""}</td>
            </tr>`
              )
              .join("")}
            </tbody></table>`
          : '<p class="text-pulse-muted text-sm">No data</p>'
      )}
    </div>
  `;
}

// ── Cameras ──────────────────────────────────────────────────

async function renderCameras() {
  $page().innerHTML = loading();
  const data = await api("/api/cameras");
  if (currentPage !== "cameras") return;

  const ports = data.ports || [];
  const pixCfg = data.pixellotConfig || {};
  const cfgCameras = pixCfg.cameras || [];

  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-6">Camera Connectivity</h2>
    ${
      ports.length === 0
        ? card("", '<p class="text-pulse-muted">No camera-facing NICs detected (Intel I210/I350/82574L/I211, Realtek).</p>')
        : ports
            .map(
              (p) => `
        <div class="card mb-4">
          <div class="flex items-center justify-between mb-3">
            <div>
              <h3 class="font-semibold">${esc(p.name)}</h3>
              <p class="text-xs text-pulse-muted">${esc(p.interfaceDescription)}</p>
            </div>
            <div class="flex items-center gap-2">
              ${p.isOcr ? badge("OCR", "info") : ""}
              ${p.isDegraded ? badge("Degraded", "warn") : ""}
              ${statusBadge(p.status)}
              <span class="text-xs text-pulse-muted">${p.linkSpeedMbps ? esc(String(p.linkSpeedMbps)) + " Mbps" : "No link"}</span>
            </div>
          </div>
          <div class="text-xs text-pulse-muted mb-2">MAC: ${esc(p.mac)} · RX: ${formatBytes(p.rxBytes)} · TX: ${formatBytes(p.txBytes)}</div>
          ${
            p.camerasDetected?.length
              ? `<div class="mt-2">
              <p class="text-sm font-medium text-green-400 mb-1">Pixellot cameras detected:</p>
              ${p.camerasDetected
                .map(
                  (c) =>
                    `<div class="text-sm bg-pulse-bg rounded px-3 py-1.5 mb-1">IP: <span class="font-mono">${esc(c.ip)}</span> · MAC: <span class="font-mono">${esc(c.mac)}</span></div>`
                )
                .join("")}
            </div>`
              : '<p class="text-sm text-pulse-muted mt-2">No Pixellot cameras detected on this port.</p>'
          }
          ${
            p.arpEntries?.length
              ? `<details class="mt-2"><summary class="text-xs text-pulse-muted cursor-pointer">ARP entries (${esc(String(p.arpEntries.length))})</summary>
              <div class="mt-1 max-h-32 overflow-y-auto">
                ${p.arpEntries.map((a) => `<div class="text-xs font-mono text-pulse-muted">${esc(a.ip)} → ${esc(a.mac)}</div>`).join("")}
              </div></details>`
              : ""
          }
        </div>`
            )
            .join("")
    }
    ${
      cfgCameras.length
        ? card(
            "cameras.cfg",
            `<table class="data-table"><thead><tr>
              <th>Section</th><th>IP</th><th>MAC</th><th>Role</th>
            </tr></thead><tbody>
            ${cfgCameras
              .map(
                (c) => `<tr>
              <td>${esc(c.section)}</td>
              <td class="font-mono">${esc(c.ip)}</td>
              <td class="font-mono">${esc(c.mac)}</td>
              <td>${esc(c.role)}</td>
            </tr>`
              )
              .join("")}
            </tbody></table>`,
            "mt-6"
          )
        : ""
    }
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

async function renderServices() {
  $page().innerHTML = loading();
  const data = await api("/api/services");
  if (currentPage !== "services") return;

  if (data.error) {
    $page().innerHTML = errorBox(data.message);
    return;
  }

  const svcs = data.services || [];

  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-6">Services</h2>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4" id="svc-grid">
      ${svcs
        .map(
          (s) => `
        <div class="card" data-svc="${esc(s.name)}">
          <div class="flex items-center justify-between mb-2">
            <h3 class="font-semibold text-sm">${esc(s.name)}</h3>
            ${statusBadge(s.status)}
          </div>
          ${s.displayName ? `<p class="text-xs text-pulse-muted mb-2">${esc(s.displayName)}</p>` : ""}
          ${s.startType ? `<p class="text-xs text-pulse-muted mb-3">Start: ${esc(s.startType)}</p>` : ""}
          ${
            s.status !== "NotFound"
              ? `<button class="btn btn-secondary text-xs svc-restart-btn" data-name="${esc(s.name)}">Restart</button>`
              : ""
          }
        </div>`
        )
        .join("")}
    </div>
  `;

  document.getElementById("svc-grid").addEventListener("click", async (e) => {
    const btn = e.target.closest(".svc-restart-btn");
    if (!btn) return;
    const name = btn.dataset.name;
    btn.disabled = true;
    btn.textContent = "Restarting...";
    const result = await apiPost("/api/services/restart", { serviceName: name });
    btn.disabled = false;
    btn.textContent = "Restart";
    if (result.success) {
      renderServices();
    } else {
      btn.textContent = result.message || "Failed";
      setTimeout(() => { btn.textContent = "Restart"; }, 3000);
    }
  });
}

// ── Disk Health ──────────────────────────────────────────────

async function renderDiskHealth() {
  $page().innerHTML = loading();
  const data = await api("/api/disk-health");
  if (currentPage !== "disk-health") return;

  if (data.error) {
    $page().innerHTML = errorBox(data.message);
    return;
  }

  const logical = data.logicalDisks || [];
  const physical = data.physicalDisks || [];
  const events = data.diskEvents || [];
  const paths = data.pixellotPaths || [];

  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-6">Disk Health</h2>
    ${card(
      "Logical Disks",
      logical.length
        ? `<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          ${logical
            .map(
              (d) => `<div class="bg-pulse-bg rounded-lg p-4">
              <div class="flex justify-between mb-1">
                <span class="font-semibold">${esc(d.deviceID)}</span>
                <span class="text-sm text-pulse-muted">${esc(String(d.usedPercent))}%</span>
              </div>
              ${usageBar(d.usedPercent)}
              <div class="text-xs text-pulse-muted mt-2">${esc(String(d.freeSpaceGB))} GB free of ${esc(String(d.sizeGB))} GB · ${esc(d.fileSystem)}</div>
            </div>`
            )
            .join("")}
        </div>`
        : '<p class="text-pulse-muted text-sm">No data</p>',
      "mb-6"
    )}
    ${card(
      "Physical Disks",
      physical.length
        ? `<table class="data-table"><thead><tr>
            <th>Name</th><th>Type</th><th>Bus</th><th>Size</th><th>Health</th>
          </tr></thead><tbody>
          ${physical
            .map(
              (d) => `<tr>
            <td>${esc(d.friendlyName)}</td>
            <td>${esc(d.mediaType)}</td>
            <td>${esc(d.busType)}</td>
            <td>${esc(String(d.sizeGB))} GB</td>
            <td>${statusBadge(d.healthStatus || "Unknown")}</td>
          </tr>`
            )
            .join("")}
          </tbody></table>`
        : '<p class="text-pulse-muted text-sm">No data</p>',
      "mb-6"
    )}
    ${
      paths.length
        ? card(
            "Pixellot Directories",
            `<table class="data-table"><thead><tr>
              <th>Path</th><th>Size</th><th>Files</th>
            </tr></thead><tbody>
            ${paths
              .map(
                (p) => `<tr>
              <td class="font-mono text-xs">${esc(p.path)}</td>
              <td>${p.sizeGB != null ? esc(String(p.sizeGB)) + " GB" : esc(p.error)}</td>
              <td>${p.fileCount != null ? esc(String(p.fileCount)) : "--"}</td>
            </tr>`
              )
              .join("")}
            </tbody></table>`,
            "mb-6"
          )
        : ""
    }
    ${
      events.length
        ? card(
            "Recent Disk Events (24h)",
            `<div class="max-h-60 overflow-y-auto">
            <table class="data-table"><thead><tr>
              <th>Time</th><th>Level</th><th>Source</th><th>Message</th>
            </tr></thead><tbody>
            ${events
              .map(
                (e) => `<tr>
              <td class="text-xs whitespace-nowrap">${formatTime(e.timeCreated)}</td>
              <td>${statusBadge(e.level)}</td>
              <td class="text-xs">${esc(e.source)}</td>
              <td class="text-xs max-w-md truncate">${esc(e.message)}</td>
            </tr>`
              )
              .join("")}
            </tbody></table>
          </div>`
          )
        : ""
    }
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

async function renderEvents() {
  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-4">Event Viewer</h2>
    <div class="flex items-center gap-4 mb-4">
      <label class="text-sm text-pulse-muted">Hours:
        <select id="ev-hours" class="ml-1 bg-pulse-card border border-pulse-border rounded px-2 py-1 text-sm text-pulse-text">
          <option value="12">12</option>
          <option value="24">24</option>
          <option value="48" selected>48</option>
          <option value="168">7 days</option>
        </select>
      </label>
      <label class="text-sm text-pulse-muted">Level:
        <select id="ev-level" class="ml-1 bg-pulse-card border border-pulse-border rounded px-2 py-1 text-sm text-pulse-text">
          <option value="all" selected>All</option>
          <option value="error">Error</option>
          <option value="warning">Warning</option>
          <option value="info">Info</option>
        </select>
      </label>
      <button class="btn btn-primary text-xs" id="ev-load">Load</button>
      <span id="ev-count" class="text-xs text-pulse-muted"></span>
    </div>
    <div id="ev-body">${loading()}</div>
  `;

  const loadEvents = async () => {
    const hours = document.getElementById("ev-hours").value;
    const level = document.getElementById("ev-level").value;
    document.getElementById("ev-body").innerHTML = loading();
    const data = await api(`/api/events?hours=${encodeURIComponent(hours)}&level=${encodeURIComponent(level)}`);
    if (currentPage !== "events") return;
    const entries = data.entries || [];
    document.getElementById("ev-count").textContent = entries.length + " events";
    if (!entries.length) {
      document.getElementById("ev-body").innerHTML = card(
        "",
        '<p class="text-pulse-muted text-sm">No events found for this filter.</p>'
      );
      return;
    }
    document.getElementById("ev-body").innerHTML = `
      <div class="card" style="max-height:60vh;overflow:auto">
        <table class="data-table"><thead><tr>
          <th>Time</th><th>Level</th><th>Source</th><th>ID</th><th>Message</th>
        </tr></thead><tbody>
        ${entries
          .map(
            (e) => `<tr>
          <td class="text-xs whitespace-nowrap">${formatTime(e.timeCreated)}</td>
          <td>${statusBadge(e.level)}</td>
          <td class="text-xs">${esc(e.source)}</td>
          <td class="text-xs">${esc(String(e.eventId))}</td>
          <td class="text-xs" style="max-width:400px"><div class="truncate" title="${esc(e.message)}">${esc(e.message)}</div></td>
        </tr>`
          )
          .join("")}
        </tbody></table>
      </div>
    `;
  };

  document.getElementById("ev-load").addEventListener("click", loadEvents);
  loadEvents();
}

// ── Reports ──────────────────────────────────────────────────

async function renderReports() {
  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-6">Reports</h2>
    ${card(
      "Full Diagnostic Export",
      `<p class="text-sm text-pulse-muted mb-4">Generate a complete diagnostic report containing all system, network, and service data. This runs all data collection scripts.</p>
      <button class="btn btn-primary" id="rpt-export">Generate Report</button>
      <span id="rpt-status" class="ml-3 text-sm text-pulse-muted"></span>
      <div id="rpt-result" class="mt-4"></div>`
    )}
  `;

  document.getElementById("rpt-export").addEventListener("click", async () => {
    const btn = document.getElementById("rpt-export");
    const status = document.getElementById("rpt-status");
    btn.disabled = true;
    status.textContent = "Collecting data...";
    const data = await api("/api/reports/export");
    btn.disabled = false;
    if (data.error) {
      status.textContent = "Error: " + (data.message || "Unknown");
      return;
    }
    status.textContent = "Report ready.";

    const blob = new Blob([JSON.stringify(data, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const hostname = data.identity?.computerSystem?.name || "vpu";
    const ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
    const filename = "pulse-report-" + hostname + "-" + ts + ".json";

    const resultEl = document.getElementById("rpt-result");
    resultEl.innerHTML = "";

    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    link.className = "btn btn-secondary inline-block";
    link.textContent = "Download JSON";
    resultEl.appendChild(link);

    const details = document.createElement("details");
    details.className = "mt-4";
    const summary = document.createElement("summary");
    summary.className = "text-sm text-pulse-muted cursor-pointer";
    summary.textContent = "Preview data";
    details.appendChild(summary);
    const pre = document.createElement("pre");
    pre.className = "mt-2 p-4 bg-pulse-bg rounded text-xs overflow-auto max-h-96 text-pulse-muted";
    pre.textContent = JSON.stringify(data, null, 2);
    details.appendChild(pre);
    resultEl.appendChild(details);
  });
}

// ── ScoreConnect ─────────────────────────────────────────────

async function renderScoreConnect() {
  $page().innerHTML = loading();
  const data = await api("/api/scoreconnect");
  if (currentPage !== "scoreconnect") return;

  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-6">ScoreConnect</h2>
    ${card(
      "Connection Status",
      `<div class="space-y-2 text-sm">
        ${idRow("Reachable", data.reachable ? '<span class="status-pass">Yes</span>' : '<span class="status-fail">No</span>')}
        ${data.error ? idRow("Error", data.error) : ""}
      </div>`
    )}
    ${
      data.status
        ? card(
            "Status",
            buildPreBlock(data.status),
            "mt-6"
          )
        : ""
    }
    ${
      data.configuration
        ? card(
            "Configuration",
            buildPreBlock(data.configuration),
            "mt-6"
          )
        : ""
    }
  `;
}

function buildPreBlock(obj) {
  const pre = document.createElement("pre");
  pre.className = "text-xs text-pulse-muted overflow-auto max-h-60";
  pre.textContent = JSON.stringify(obj, null, 2);
  const wrapper = document.createElement("div");
  wrapper.appendChild(pre);
  return wrapper.innerHTML;
}

// ── Fault Isolator ───────────────────────────────────────────

async function renderFaultIsolator() {
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
      const stopped = svcs.filter(
        (s) => s.status === "Stopped" && s.name !== "LogMeIn"
      );
      const missing = svcs.filter(
        (s) =>
          s.status === "NotFound" &&
          ["PixellotAgent", "PixellotVPU"].includes(s.name)
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

async function renderSettings() {
  $page().innerHTML = loading();
  const data = await api("/api/settings");
  if (currentPage !== "settings") return;

  const scUrl = esc(data.scoreConnectUrl || "http://localhost:5000");
  const pollMs = data.pollIntervalMs || 3000;

  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-6">Settings</h2>
    ${card(
      "Configuration",
      `<div class="space-y-4 max-w-md">
        <div>
          <label class="block text-sm text-pulse-muted mb-1">ScoreConnect URL</label>
          <input type="text" id="set-sc-url" value="${scUrl}" class="w-full px-3 py-2 bg-pulse-bg border border-pulse-border rounded text-sm text-pulse-text outline-none focus:border-pulse-accent"/>
        </div>
        <div>
          <label class="block text-sm text-pulse-muted mb-1">Poll Interval (ms)</label>
          <input type="number" id="set-poll" value="${pollMs}" min="1000" max="30000" step="500" class="w-full px-3 py-2 bg-pulse-bg border border-pulse-border rounded text-sm text-pulse-text outline-none focus:border-pulse-accent"/>
          <p class="text-xs text-pulse-muted mt-1">How often live metrics refresh (1000-30000 ms)</p>
        </div>
        <div class="flex items-center gap-3">
          <button class="btn btn-primary" id="set-save">Save</button>
          <span id="set-msg" class="text-sm text-pulse-muted"></span>
        </div>
      </div>`
    )}
  `;

  document.getElementById("set-save").addEventListener("click", async () => {
    const body = {
      scoreConnectUrl: document.getElementById("set-sc-url").value.trim(),
      pollIntervalMs:
        parseInt(document.getElementById("set-poll").value, 10) || 3000,
    };
    const result = await apiPost("/api/settings", body);
    const msgEl = document.getElementById("set-msg");
    msgEl.textContent = result.ok ? "Saved" : "Error saving";
    if (result.ok) {
      setTimeout(() => {
        if (msgEl) msgEl.textContent = "";
      }, 2000);
    }
  });
}

// ── About ────────────────────────────────────────────────────

function renderAbout() {
  $page().innerHTML = `
    <h2 class="text-xl font-bold mb-6">About</h2>
    ${card(
      "",
      `<div class="space-y-4">
        <div>
          <h3 class="text-lg font-bold text-white">Pulse Web</h3>
          <p class="text-sm text-pulse-muted">VPU Diagnostic Tools — v0.9.0-beta</p>
        </div>
        <p class="text-sm text-pulse-muted">
          A lightweight, self-contained diagnostic tool for Pixellot VPU systems.
          Collects system identity, hardware, performance metrics, network configuration,
          camera connectivity, service status, disk health, and event logs.
        </p>
        <div>
          <h4 class="text-sm font-semibold text-pulse-muted uppercase tracking-wide mb-2">Technology</h4>
          <div class="text-sm space-y-1 text-pulse-muted">
            <div>Backend: Python (embedded) + FastAPI + Uvicorn</div>
            <div>Frontend: Vanilla HTML/JS + Tailwind CSS</div>
            <div>Data Collection: PowerShell + WMI/CIM</div>
          </div>
        </div>
        <div>
          <h4 class="text-sm font-semibold text-pulse-muted uppercase tracking-wide mb-2">Data Scripts</h4>
          <div class="text-xs text-pulse-muted grid grid-cols-2 gap-1">
            <div>Get-SystemIdentity</div>
            <div>Get-Hardware</div>
            <div>Get-Performance</div>
            <div>Get-NetworkConfig</div>
            <div>Get-NicAdapters</div>
            <div>Get-Services</div>
            <div>Get-DiskHealth</div>
            <div>Get-EventLogs</div>
            <div>Get-ScoreConnectStatus</div>
            <div>Get-PixellotConfig</div>
            <div>Get-InstalledSoftware</div>
            <div>Get-Temperature</div>
            <div>Test-NetworkDomains</div>
            <div>Test-NetworkPorts</div>
            <div>Test-NtpDrift</div>
            <div>Restart-Service</div>
          </div>
        </div>
      </div>`
    )}
  `;
}

// ── Init ─────────────────────────────────────────────────────

function init() {
  const navEl = document.getElementById("nav-links");
  navEl.innerHTML = PAGES.map(
    (p) =>
      `<a class="nav-item" data-page="${esc(p.id)}" href="#${esc(p.id)}">${esc(p.label)}</a>`
  ).join("");

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
  connectWS();
}

document.addEventListener("DOMContentLoaded", init);
