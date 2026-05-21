import { useApi } from "../hooks/useApi";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import DataTable from "../components/DataTable";
import StatusPill from "../components/StatusPill";
import KeyValueRow from "../components/KeyValueRow";
import RefreshButton from "../components/RefreshButton";
import LoadingSpinner from "../components/LoadingSpinner";

function formatBytes(bytes) {
  if (!bytes) return "--";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
}

export default function DiskHealth() {
  const { data, loading, refetch } = useApi("/disk");

  const volumes = data?.volumes || [];
  const physicalDisks = data?.physicalDisks || [];
  const recentErrors = data?.recentErrors || [];
  const pathSizes = data?.pathSizes || {};

  const hasErrors = recentErrors.length > 0;
  const unhealthyDisk = physicalDisks.some(
    (d) => d.healthStatus && d.healthStatus !== "Healthy",
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title="Disk Health"
        status={unhealthyDisk ? "critical" : hasErrors ? "warning" : "healthy"}
        statusLabel={
          unhealthyDisk
            ? "Unhealthy disk detected"
            : hasErrors
              ? `${recentErrors.length} disk errors in 24h`
              : "All disks healthy"
        }
        actions={<RefreshButton onClick={refetch} loading={loading} />}
      />

      {loading && !data ? (
        <LoadingSpinner />
      ) : (
        <>
          {/* Volumes */}
          <Card title="Volumes">
            <div className="space-y-4">
              {volumes.map((vol) => {
                const total = vol.size || 1;
                const used = total - (vol.freeSpace || 0);
                const pct = (used / total) * 100;
                return (
                  <div key={vol.deviceId}>
                    <div className="flex items-center justify-between mb-1.5">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium text-gray-200">
                          {vol.deviceId}
                        </span>
                        {vol.volumeName && (
                          <span className="text-xs text-gray-500">({vol.volumeName})</span>
                        )}
                        <span className="text-xs text-gray-600">{vol.fileSystem}</span>
                      </div>
                      <span className="text-xs font-mono text-gray-400">
                        {formatBytes(vol.freeSpace)} free / {formatBytes(total)}
                      </span>
                    </div>
                    <div className="h-2 rounded-full bg-surface-4 overflow-hidden">
                      <div
                        className={`h-full rounded-full transition-all ${
                          pct >= 85
                            ? "bg-pulse-red"
                            : pct >= 60
                              ? "bg-pulse-yellow"
                              : "bg-pulse-green"
                        }`}
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                    <p className="mt-1 text-right text-xs text-gray-600">
                      {pct.toFixed(1)}% used
                    </p>
                  </div>
                );
              })}
              {volumes.length === 0 && (
                <p className="text-sm text-gray-600">No volume data</p>
              )}
            </div>
          </Card>

          {/* Physical Disks */}
          <Card title="Physical Disks" noPad>
            <DataTable
              columns={[
                { key: "friendlyName", label: "Name" },
                { key: "mediaType", label: "Type" },
                { key: "busType", label: "Bus" },
                {
                  key: "healthStatus",
                  label: "Health",
                  render: (v) => (
                    <StatusPill
                      status={v === "Healthy" ? "healthy" : "critical"}
                      label={v || "--"}
                    />
                  ),
                },
                { key: "operationalStatus", label: "Status" },
                { key: "size", label: "Size", render: (v) => formatBytes(v) },
              ]}
              rows={physicalDisks}
              emptyMessage="No physical disk data"
            />
          </Card>

          {/* Path Sizes */}
          {Object.keys(pathSizes).length > 0 && (
            <Card title="Pixellot Directory Sizes">
              {Object.entries(pathSizes).map(([path, size]) => (
                <KeyValueRow key={path} label={path} value={formatBytes(size)} mono />
              ))}
            </Card>
          )}

          {/* Recent Disk Errors */}
          <Card
            title={`Disk Errors (Last 24h)${recentErrors.length > 0 ? ` — ${recentErrors.length}` : ""}`}
            noPad
          >
            <DataTable
              columns={[
                { key: "timeCreated", label: "Time", cellClass: "text-xs whitespace-nowrap" },
                { key: "source", label: "Source" },
                { key: "eventId", label: "ID", className: "w-16" },
                { key: "message", label: "Message", cellClass: "text-xs max-w-md truncate" },
              ]}
              rows={recentErrors}
              emptyMessage="No disk errors in the last 24 hours"
            />
          </Card>
        </>
      )}
    </div>
  );
}
