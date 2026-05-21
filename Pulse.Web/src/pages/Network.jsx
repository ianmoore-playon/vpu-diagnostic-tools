import { useState } from "react";
import { useApi } from "../hooks/useApi";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import DataTable from "../components/DataTable";
import KeyValueRow from "../components/KeyValueRow";
import StatusPill from "../components/StatusPill";
import RefreshButton from "../components/RefreshButton";
import LoadingSpinner from "../components/LoadingSpinner";

export default function Network() {
  const { data: config, loading: configLoading, refetch: refetchConfig } = useApi("/network/config");
  const { data: ports, loading: portsLoading, refetch: refetchPorts } = useApi("/network/ports", { autoFetch: false });
  const { data: domains, loading: domainsLoading, refetch: refetchDomains } = useApi("/network/domains", { autoFetch: false });
  const { data: ntp, loading: ntpLoading, refetch: refetchNtp } = useApi("/network/ntp", { autoFetch: false });

  const [testsRun, setTestsRun] = useState(false);

  function runAllTests() {
    setTestsRun(true);
    refetchPorts();
    refetchDomains();
    refetchNtp();
  }

  const adapters = config?.adapters || [];
  const ipConfig = config?.ipConfig || [];
  const internetReachable = config?.internetReachable;
  const ntpSource = config?.ntpSource;
  const uplinkAdapter = config?.uplinkAdapter;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Network"
        status={
          internetReachable === true ? "healthy" : internetReachable === false ? "critical" : "unknown"
        }
        statusLabel={
          internetReachable === true ? "Internet reachable" : internetReachable === false ? "No internet" : "Unknown"
        }
        actions={
          <div className="flex gap-2">
            <RefreshButton onClick={refetchConfig} loading={configLoading} />
            <button
              onClick={runAllTests}
              disabled={portsLoading || domainsLoading}
              className="inline-flex items-center gap-1.5 rounded-lg bg-pulse-accent px-3 py-1.5 text-xs font-medium text-white hover:bg-pulse-accent/90 transition-colors disabled:opacity-50"
            >
              {portsLoading || domainsLoading ? "Testing..." : "Run All Tests"}
            </button>
          </div>
        }
      />

      {configLoading && !config ? (
        <LoadingSpinner />
      ) : (
        <>
          {/* IP Configuration */}
          <div className="grid grid-cols-2 gap-4">
            <Card title="IP Configuration">
              {ipConfig.map((iface, i) => (
                <div key={i} className={i > 0 ? "mt-4 border-t border-gray-800 pt-4" : ""}>
                  <p className="text-sm font-medium text-gray-300 mb-2">{iface.interfaceAlias}</p>
                  <KeyValueRow label="IPv4 Address" value={iface.ipv4Address} mono />
                  <KeyValueRow label="Gateway" value={iface.gateway} mono />
                  <KeyValueRow label="DNS" value={iface.dnsServers?.join(", ")} mono />
                </div>
              ))}
              {ipConfig.length === 0 && <p className="text-sm text-gray-600">No IP configuration</p>}
            </Card>

            <Card title="Connectivity">
              <KeyValueRow label="Internet" value={
                <StatusPill
                  status={internetReachable ? "healthy" : "critical"}
                  label={internetReachable ? "Reachable" : "Unreachable"}
                />
              } />
              <KeyValueRow label="NTP Source" value={ntpSource} mono />
              <KeyValueRow label="Uplink Adapter" value={uplinkAdapter} />
            </Card>
          </div>

          {/* Network Adapters */}
          <Card title="Adapters" noPad>
            <DataTable
              columns={[
                { key: "name", label: "Name" },
                { key: "description", label: "Description" },
                { key: "status", label: "Status", render: (v) => (
                  <StatusPill status={v === "Up" ? "healthy" : "critical"} label={v} />
                )},
                { key: "macAddress", label: "MAC", cellClass: "font-mono text-xs" },
                { key: "linkSpeed", label: "Speed" },
              ]}
              rows={adapters}
            />
          </Card>

          {/* Port Tests */}
          <Card
            title="Port Tests"
            actions={
              !testsRun && (
                <button
                  onClick={() => { setTestsRun(true); refetchPorts(); }}
                  className="text-xs text-pulse-accent hover:underline"
                >
                  Run tests
                </button>
              )
            }
            noPad
          >
            {portsLoading ? (
              <LoadingSpinner text="Testing ports..." />
            ) : ports?.results ? (
              <DataTable
                columns={[
                  { key: "protocol", label: "Protocol", className: "w-16" },
                  { key: "port", label: "Port", className: "w-16", cellClass: "font-mono" },
                  { key: "host", label: "Host" },
                  { key: "purpose", label: "Purpose" },
                  { key: "optional", label: "Opt", className: "w-12", render: (v) => v ? "Yes" : "" },
                  { key: "status", label: "Status", render: (v) => (
                    <StatusPill
                      status={v === "pass" ? "healthy" : v === "skip" ? "unknown" : "critical"}
                      label={v}
                    />
                  )},
                ]}
                rows={ports.results}
              />
            ) : (
              <p className="px-5 py-6 text-center text-sm text-gray-600">
                Click "Run All Tests" to test port connectivity
              </p>
            )}
          </Card>

          {/* Domain Tests */}
          <Card title="DNS Resolution" noPad>
            {domainsLoading ? (
              <LoadingSpinner text="Resolving domains..." />
            ) : domains?.results ? (
              <DataTable
                columns={[
                  { key: "domain", label: "Domain" },
                  { key: "resolvedTo", label: "Resolved To", cellClass: "font-mono text-xs" },
                  { key: "status", label: "Status", render: (v) => (
                    <StatusPill status={v === "pass" ? "healthy" : "critical"} label={v} />
                  )},
                ]}
                rows={domains.results}
              />
            ) : (
              <p className="px-5 py-6 text-center text-sm text-gray-600">
                Click "Run All Tests" to test DNS resolution
              </p>
            )}
          </Card>

          {/* NTP Drift */}
          <Card title="NTP Drift">
            {ntpLoading ? (
              <LoadingSpinner text="Checking NTP..." />
            ) : ntp ? (
              <div className="space-y-0">
                <KeyValueRow label="Status" value={
                  <StatusPill
                    status={ntp.ok ? "healthy" : ntp.offsetSeconds >= 5 ? "critical" : "warning"}
                    label={ntp.ok ? "Synced" : `Drift: ${ntp.offsetSeconds?.toFixed(2)}s`}
                  />
                } />
                <KeyValueRow label="Offset" value={ntp.offsetSeconds != null ? `${ntp.offsetSeconds.toFixed(3)}s` : "--"} mono />
                <KeyValueRow label="Source" value={ntp.source} />
              </div>
            ) : (
              <p className="text-sm text-gray-600">Click "Run All Tests" to check NTP drift</p>
            )}
          </Card>
        </>
      )}
    </div>
  );
}
