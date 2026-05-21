import { useState, useEffect } from "react";
import { useApi, apiPost } from "../hooks/useApi";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import KeyValueRow from "../components/KeyValueRow";
import StatusPill from "../components/StatusPill";
import DataTable from "../components/DataTable";
import RefreshButton from "../components/RefreshButton";
import LoadingSpinner from "../components/LoadingSpinner";

export default function ScoreConnect() {
  const { data: statusData, loading: statusLoading, refetch: refetchStatus } = useApi("/scoreconnect/status");
  const { data: vendorsData, loading: vendorsLoading, refetch: refetchVendors } = useApi("/scoreconnect/vendors", { autoFetch: false });

  const [selectedVendor, setSelectedVendor] = useState(null);
  const [sports, setSports] = useState([]);
  const [sportsLoading, setSportsLoading] = useState(false);
  const [configuring, setConfiguring] = useState(false);
  const [configResult, setConfigResult] = useState(null);

  const reachable = statusData?.reachable;
  const config = statusData?.configuration || {};
  const vendors = vendorsData?.vendors || [];

  useEffect(() => {
    if (reachable) refetchVendors();
  }, [reachable]);

  async function loadSports(vendorId) {
    setSelectedVendor(vendorId);
    setSportsLoading(true);
    try {
      const res = await fetch(`/api/scoreconnect/vendors/${vendorId}/sports`);
      const json = await res.json();
      setSports(json.sports || []);
    } catch {
      setSports([]);
    } finally {
      setSportsLoading(false);
    }
  }

  async function selectConfiguration(vendorSportId) {
    setConfiguring(true);
    setConfigResult(null);
    try {
      const result = await apiPost("/scoreconnect/configure", { vendorSportId });
      setConfigResult(result);
      refetchStatus();
    } catch (err) {
      setConfigResult({ error: err.message });
    } finally {
      setConfiguring(false);
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="ScoreConnect"
        status={reachable === true ? "healthy" : reachable === false ? "critical" : "unknown"}
        statusLabel={reachable ? "Connected" : reachable === false ? "Unreachable" : "Checking..."}
        actions={<RefreshButton onClick={refetchStatus} loading={statusLoading} />}
      />

      {statusLoading && !statusData ? (
        <LoadingSpinner />
      ) : (
        <>
          {/* Current Configuration */}
          <Card title="Current Configuration">
            {reachable ? (
              <div className="space-y-0">
                <KeyValueRow label="Vendor" value={config.vendor} />
                <KeyValueRow label="Sport" value={config.sport} />
                <KeyValueRow label="Device" value={config.device} />
                <KeyValueRow label="Serial Port" value={config.serialPort} mono />
                <KeyValueRow label="Firmware" value={config.firmware} mono />
                <KeyValueRow label="Configuration" value={config.vendorConfigurationName} />
                {config.extendedFields &&
                  Object.entries(config.extendedFields).map(([k, v]) => (
                    <KeyValueRow key={k} label={k} value={String(v)} />
                  ))}
              </div>
            ) : (
              <div className="rounded-lg bg-red-500/10 p-4 text-sm text-red-400">
                ScoreConnect API is not reachable. Check that the ScoreConnect service is running and
                the URL is correct in Settings.
              </div>
            )}
          </Card>

          {/* Vendor Selection */}
          {reachable && (
            <>
              <Card title="Vendor / Sport Selection">
                {vendorsLoading ? (
                  <LoadingSpinner text="Loading vendors..." />
                ) : (
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm text-gray-400 mb-1.5">
                        Select Vendor
                      </label>
                      <div className="flex flex-wrap gap-2">
                        {vendors.map((v) => (
                          <button
                            key={v.id}
                            onClick={() => loadSports(v.id)}
                            className={`rounded-lg border px-3 py-2 text-sm transition-colors ${
                              selectedVendor === v.id
                                ? "border-pulse-accent bg-pulse-accent/10 text-pulse-accent"
                                : "border-gray-700 bg-surface-3 text-gray-300 hover:bg-surface-4"
                            }`}
                          >
                            {v.name}
                          </button>
                        ))}
                        {vendors.length === 0 && (
                          <p className="text-sm text-gray-600">No vendors available</p>
                        )}
                      </div>
                    </div>

                    {selectedVendor && (
                      <div>
                        <label className="block text-sm text-gray-400 mb-1.5">
                          Select Sport
                        </label>
                        {sportsLoading ? (
                          <LoadingSpinner text="Loading sports..." />
                        ) : (
                          <div className="flex flex-wrap gap-2">
                            {sports.map((s) => (
                              <button
                                key={s.id}
                                onClick={() => selectConfiguration(s.id)}
                                disabled={configuring}
                                className="rounded-lg border border-gray-700 bg-surface-3 px-3 py-2 text-sm text-gray-300 hover:bg-surface-4 hover:text-white transition-colors disabled:opacity-50"
                              >
                                {s.name}
                              </button>
                            ))}
                            {sports.length === 0 && (
                              <p className="text-sm text-gray-600">No sports for this vendor</p>
                            )}
                          </div>
                        )}
                      </div>
                    )}

                    {configResult && (
                      <div
                        className={`rounded-lg p-3 text-sm ${
                          configResult.error
                            ? "bg-red-500/10 text-red-400"
                            : "bg-green-500/10 text-green-400"
                        }`}
                      >
                        {configResult.error
                          ? `Configuration failed: ${configResult.error}`
                          : "Configuration applied successfully"}
                      </div>
                    )}
                  </div>
                )}
              </Card>

              {/* Devices */}
              <Card title="Devices" noPad>
                <DataTable
                  columns={[
                    { key: "name", label: "Name" },
                    { key: "port", label: "Port" },
                    { key: "status", label: "Status", render: (v) => (
                      <StatusPill
                        status={v === "Connected" ? "healthy" : "critical"}
                        label={v || "Unknown"}
                      />
                    )},
                  ]}
                  rows={config.devices || []}
                  emptyMessage="No devices configured"
                />
              </Card>
            </>
          )}
        </>
      )}
    </div>
  );
}
