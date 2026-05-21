import { useState } from "react";
import { useApi } from "../hooks/useApi";
import { useWebSocket } from "../hooks/useWebSocket";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import NicPortDiagram from "../components/NicPortDiagram";
import StatusPill from "../components/StatusPill";
import DataTable from "../components/DataTable";
import RefreshButton from "../components/RefreshButton";
import LoadingSpinner from "../components/LoadingSpinner";

export default function CameraConnectivity() {
  const { data, loading, refetch } = useApi("/cameras");
  const { data: wsData } = useWebSocket(["nic-status"]);
  const [selectedPort, setSelectedPort] = useState(null);

  const livePorts = wsData["nic-status"]?.ports || data?.ports || [];
  const cameras = data?.cameras || [];

  const hasIssues = livePorts.some(
    (p) => p.isUp && (p.isDegraded || p.isFlapping || p.rxErrors > 0),
  );
  const allUp = livePorts.every((p) => p.isUp);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Camera Connectivity"
        status={hasIssues ? "warning" : allUp ? "healthy" : "info"}
        statusLabel={
          hasIssues
            ? "Issues detected"
            : allUp
              ? "All ports linked"
              : `${livePorts.filter((p) => p.isUp).length}/${livePorts.length} ports up`
        }
        subtitle="Live NIC port monitoring — updates every second"
        actions={<RefreshButton onClick={refetch} loading={loading} />}
      />

      {loading && !data ? (
        <LoadingSpinner />
      ) : (
        <>
          {/* NIC Diagram */}
          <Card title="NIC Port Status">
            <NicPortDiagram ports={livePorts} />
          </Card>

          {/* Port Details */}
          <div className="grid grid-cols-2 gap-4">
            {livePorts.map((port) => (
              <Card
                key={port.name}
                title={port.name}
                className={
                  selectedPort === port.name ? "ring-1 ring-pulse-accent" : "cursor-pointer"
                }
                actions={
                  <StatusPill
                    status={
                      !port.isUp
                        ? "unknown"
                        : port.isDegraded || port.isFlapping
                          ? "warning"
                          : "healthy"
                    }
                    label={
                      !port.isUp
                        ? "No cable"
                        : port.isFlapping
                          ? "Flapping"
                          : port.isDegraded
                            ? "Degraded"
                            : "Linked"
                    }
                  />
                }
              >
                <div className="space-y-0 text-sm" onClick={() => setSelectedPort(port.name)}>
                  <div className="flex justify-between py-1">
                    <span className="text-gray-500">MAC</span>
                    <span className="font-mono text-xs text-gray-300">{port.mac}</span>
                  </div>
                  <div className="flex justify-between py-1">
                    <span className="text-gray-500">Link Speed</span>
                    <span className="text-gray-300">
                      {port.linkSpeedMbps >= 1000
                        ? `${port.linkSpeedMbps / 1000} Gbps`
                        : `${port.linkSpeedMbps} Mbps`}
                    </span>
                  </div>
                  <div className="flex justify-between py-1">
                    <span className="text-gray-500">RX Errors</span>
                    <span className={port.rxErrors > 0 ? "text-yellow-400" : "text-gray-300"}>
                      {port.rxErrors}
                    </span>
                  </div>
                  <div className="flex justify-between py-1">
                    <span className="text-gray-500">TX Errors</span>
                    <span className={port.txErrors > 0 ? "text-yellow-400" : "text-gray-300"}>
                      {port.txErrors}
                    </span>
                  </div>
                  {port.isOcr && (
                    <div className="mt-2 rounded bg-blue-500/10 px-2 py-1 text-xs text-blue-400">
                      OCR camera detected
                    </div>
                  )}
                  {port.arpEntries?.length > 0 && (
                    <div className="mt-3 border-t border-gray-800 pt-2">
                      <p className="text-xs text-gray-500 mb-1">ARP Entries</p>
                      {port.arpEntries.map((arp, i) => (
                        <div key={i} className="flex justify-between py-0.5 text-xs">
                          <span className="font-mono text-gray-400">{arp.ip}</span>
                          <span className="font-mono text-gray-600">{arp.mac}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </Card>
            ))}
          </div>

          {/* Camera Config */}
          {cameras.length > 0 && (
            <Card title="Configured Cameras" noPad>
              <DataTable
                columns={[
                  { key: "ip", label: "IP Address", cellClass: "font-mono" },
                  { key: "mac", label: "MAC Address", cellClass: "font-mono text-xs" },
                  { key: "role", label: "Role" },
                ]}
                rows={cameras}
              />
            </Card>
          )}
        </>
      )}
    </div>
  );
}
