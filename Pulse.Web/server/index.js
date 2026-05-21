import express from "express";
import cors from "cors";
import { createServer } from "http";
import { WebSocketServer } from "ws";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

import dashboardRouter from "./routes/dashboard.js";
import systemRouter from "./routes/system.js";
import networkRouter from "./routes/network.js";
import diskRouter from "./routes/disk.js";
import servicesRouter from "./routes/services.js";
import eventsRouter from "./routes/events.js";
import camerasRouter from "./routes/cameras.js";
import scoreconnectRouter from "./routes/scoreconnect.js";
import reportsRouter from "./routes/reports.js";
import settingsRouter from "./routes/settings.js";
import baselineRouter from "./routes/baseline.js";
import faultIsolatorRouter from "./routes/fault-isolator.js";
import aboutRouter from "./routes/about.js";
import { runScript } from "./powershell.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = parseInt(process.env.PORT, 10) || 5173;

// ── Express ──────────────────────────────────────────────────────────
const app = express();
app.use(cors());
app.use(express.json());

// Serve the Vite production build
app.use(express.static(join(__dirname, "..", "dist")));

// API routes
app.use("/api/dashboard", dashboardRouter);
app.use("/api/system", systemRouter);
app.use("/api/network", networkRouter);
app.use("/api/disk", diskRouter);
app.use("/api/services", servicesRouter);
app.use("/api/events", eventsRouter);
app.use("/api/cameras", camerasRouter);
app.use("/api/scoreconnect", scoreconnectRouter);
app.use("/api/reports", reportsRouter);
app.use("/api/settings", settingsRouter);
app.use("/api/baseline", baselineRouter);
app.use("/api/fault-isolator", faultIsolatorRouter);
app.use("/api/about", aboutRouter);

// SPA fallback — serve index.html for any non-API, non-static request
app.get("*", (_req, res) => {
  res.sendFile(join(__dirname, "..", "dist", "index.html"));
});

// ── HTTP + WebSocket ────────────────────────────────────────────────
const server = createServer(app);

const wss = new WebSocketServer({ server, path: "/ws" });

/** Map of channelName -> Set<ws> */
const channels = {
  performance: new Set(),
  "nic-status": new Set(),
};

wss.on("connection", (ws) => {
  // Track which channels this client subscribes to
  ws._channels = new Set();

  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return; // ignore non-JSON
    }

    if (Array.isArray(msg.subscribe)) {
      for (const ch of msg.subscribe) {
        if (channels[ch]) {
          channels[ch].add(ws);
          ws._channels.add(ch);
        }
      }
    }

    if (Array.isArray(msg.unsubscribe)) {
      for (const ch of msg.unsubscribe) {
        if (channels[ch]) {
          channels[ch].delete(ws);
          ws._channels.delete(ch);
        }
      }
    }
  });

  ws.on("close", () => {
    for (const ch of ws._channels) {
      if (channels[ch]) channels[ch].delete(ws);
    }
  });
});

function broadcast(channel, data) {
  const payload = JSON.stringify({ channel, data, ts: Date.now() });
  for (const ws of channels[channel]) {
    if (ws.readyState === ws.OPEN) {
      ws.send(payload);
    }
  }
}

// ── Polling intervals ───────────────────────────────────────────────
const intervals = [];

const perfInterval = setInterval(async () => {
  try {
    if (channels.performance.size === 0) return;
    const data = await runScript("Get-Performance.ps1");
    broadcast("performance", data);
  } catch {
    // swallow — clients will just miss a tick
  }
}, 2000);
intervals.push(perfInterval);

const nicInterval = setInterval(async () => {
  try {
    if (channels["nic-status"].size === 0) return;
    const data = await runScript("Get-NicAdapters.ps1");
    broadcast("nic-status", data);
  } catch {
    // swallow
  }
}, 1000);
intervals.push(nicInterval);

// ── Start ────────────────────────────────────────────────────────────
server.listen(PORT, () => {
  console.log(`Pulse server listening on http://localhost:${PORT}`);
});

// ── Graceful shutdown ────────────────────────────────────────────────
function shutdown() {
  console.log("\nShutting down Pulse server...");
  for (const id of intervals) clearInterval(id);
  wss.close(() => {
    server.close(() => {
      process.exit(0);
    });
  });
  // Force exit after 5 s if something hangs
  setTimeout(() => process.exit(1), 5000).unref();
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
