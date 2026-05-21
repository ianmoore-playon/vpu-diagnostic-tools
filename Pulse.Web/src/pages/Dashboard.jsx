import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useApi } from "../hooks/useApi";
import { useWebSocket } from "../hooks/useWebSocket";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import CircularGauge from "../components/CircularGauge";
import NicPortDiagram from "../components/NicPortDiagram";
import FindingsBanner from "../components/FindingsBanner";
import StatusPill from "../components/StatusPill";
import KeyValueRow from "../components/KeyValueRow";
import RefreshButton from "../components/RefreshButton";
import LoadingSpinner from "../components/LoadingSpinner";

function overallHealth(findings) {
  if (!findings || findings.length === 0) return "healthy";
  if (findings.some((f) => f.severity === "Critical")) return "critical";
  if (findings.some((f) => f.severity === "Warning")) return "warning";
  return "healthy";
}

const HUB_TILES = [
  { key: "system", label: "System", path: "/system", icon: "M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" },
  { key: "network", label: "Network", path: "/network", icon: "M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9" },
  { key: "cameras", label: "Cameras", path: "/cameras", icon: "M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" },
  { key: "services", label: "Services", path: "/services", icon: "M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2" },
  { key: "disk", label: "Disk", path: "/disk", icon: "M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4" },
  { key: "events", label: "Events", path: "/events", icon: "M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" },
];

export default function Dashboard() {
  const navigate = useNavigate();
  const { data, loading, refetch } = useApi("/dashboard");
  const { data: wsData } = useWebSocket(["performance", "nic-status"]);

  const gauges = wsData.performance || data?.gauges;
  const nicPorts = wsData["nic-status"]?.ports || data?.nicPorts || [];
  const findings = data?.findings || [];
  const identity = data?.identity || {};
  const services = data?.services || [];
  const volumes = data?.volumes || [];
  const health = overallHealth(findings);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Dashboard"
        status={loading ? "unknown" : health}
        statusLabel={loading ? "Loading" : health === "healthy" ? "All systems healthy" : `${findings.length} finding${findings.length !== 1 ? "s" : ""}`}
        actions={<RefreshButton onClick={refetch} loading={loading} />}
      />

      {loading && !data ? (
        <LoadingSpinner text="Collecting diagnostics..." />
      ) : (
        <>
          {/* Identity Bar */}
          <Card>
            <div className="flex flex-wrap items-center gap-x-6 gap-y-2 text-sm">
              <span className="font-medium text-white">{identity.hostname || "--"}</span>
              <span className="text-gray-500">{identity.manufacturer} {identity.model}</span>
              {identity.serialNumber && (
                <span className="font-mono text-xs text-gray-600">S/N {identity.serialNumber}</span>
              )}
              {identity.isNonVpuHost && (
                <StatusPill status="warning" label="Non-VPU host" />
              )}
              {identity.uptime && (
                <span className="ml-auto text-gray-500">Uptime: {identity.uptime}</span>
              )}
            </div>
          </Card>

          {/* Gauges */}
          <div className="grid grid-cols-4 gap-4">
            {[
              { label: "CPU", value: gauges?.cpu },
              { label: "Memory", value: gauges?.memory },
              { label: "Disk", value: gauges?.disk },
              { label: "Temp", value: gauges?.temperature, unit: "°C" },
            ].map((g) => (
              <Card key={g.label} className="flex items-center justify-center py-6">
                <div className="relative flex flex-col items-center">
                  <CircularGauge value={g.value} label={g.label} unit={g.unit} />
                </div>
              </Card>
            ))}
          </div>

          {/* Findings */}
          <FindingsBanner findings={findings} />

          {/* NIC Ports */}
          <Card title="NIC Ports">
            <NicPortDiagram ports={nicPorts} />
          </Card>

          {/* Services + Volumes side by side */}
          <div className="grid grid-cols-2 gap-4">
            <Card title="Services" noPad>
              <div className="divide-y divide-gray-800/60">
                {services.map((svc) => (
                  <div key={svc.name} className="flex items-center justify-between px-5 py-2.5">
                    <span className="text-sm text-gray-300">{svc.displayName || svc.name}</span>
                    <StatusPill
                      status={svc.status === "Running" ? "healthy" : svc.status === "NotFound" ? "unknown" : "critical"}
                      label={svc.status}
                    />
                  </div>
                ))}
                {services.length === 0 && (
                  <p className="px-5 py-4 text-sm text-gray-600">No services data</p>
                )}
              </div>
            </Card>
            <Card title="Volumes" noPad>
              <div className="divide-y divide-gray-800/60">
                {volumes.map((vol) => {
                  const usedPct = vol.size > 0 ? ((vol.size - vol.freeSpace) / vol.size) * 100 : 0;
                  return (
                    <div key={vol.deviceId} className="px-5 py-2.5">
                      <div className="flex items-center justify-between text-sm">
                        <span className="text-gray-300">
                          {vol.deviceId} {vol.volumeName && `(${vol.volumeName})`}
                        </span>
                        <span className="text-gray-500 font-mono text-xs">
                          {formatBytes(vol.freeSpace)} free / {formatBytes(vol.size)}
                        </span>
                      </div>
                      <div className="mt-1.5 h-1.5 rounded-full bg-surface-4 overflow-hidden">
                        <div
                          className={`h-full rounded-full transition-all ${
                            usedPct >= 85 ? "bg-pulse-red" : usedPct >= 60 ? "bg-pulse-yellow" : "bg-pulse-green"
                          }`}
                          style={{ width: `${usedPct}%` }}
                        />
                      </div>
                    </div>
                  );
                })}
                {volumes.length === 0 && (
                  <p className="px-5 py-4 text-sm text-gray-600">No volume data</p>
                )}
              </div>
            </Card>
          </div>

          {/* Hub Tiles */}
          <div className="grid grid-cols-3 gap-3">
            {HUB_TILES.map((tile) => (
              <button
                key={tile.key}
                onClick={() => navigate(tile.path)}
                className="flex items-center gap-3 rounded-xl border border-gray-800 bg-surface-2 p-4 text-left transition-all hover:border-gray-700 hover:bg-surface-3"
              >
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-surface-3">
                  <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                    <path strokeLinecap="round" strokeLinejoin="round" d={tile.icon} />
                  </svg>
                </div>
                <div>
                  <p className="text-sm font-medium text-gray-200">{tile.label}</p>
                  <p className="text-xs text-gray-600">View details</p>
                </div>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

function formatBytes(bytes) {
  if (bytes == null || bytes === 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
}
