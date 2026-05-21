import { useState } from "react";
import { useApi, apiPost } from "../hooks/useApi";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import StatusPill from "../components/StatusPill";
import RefreshButton from "../components/RefreshButton";
import LoadingSpinner from "../components/LoadingSpinner";

export default function Services() {
  const { data, loading, refetch } = useApi("/services");
  const [restarting, setRestarting] = useState({});
  const [messages, setMessages] = useState({});

  const services = data?.services || [];

  async function handleRestart(name) {
    setRestarting((prev) => ({ ...prev, [name]: true }));
    setMessages((prev) => ({ ...prev, [name]: null }));
    try {
      const result = await apiPost(`/services/${name}/restart`);
      setMessages((prev) => ({
        ...prev,
        [name]: { ok: result.success, text: result.message },
      }));
      setTimeout(refetch, 1000);
    } catch (err) {
      setMessages((prev) => ({
        ...prev,
        [name]: { ok: false, text: err.message },
      }));
    } finally {
      setRestarting((prev) => ({ ...prev, [name]: false }));
    }
  }

  const allRunning = services.length > 0 && services.every((s) => s.status === "Running");

  return (
    <div className="space-y-6">
      <PageHeader
        title="Pixellot Services"
        status={allRunning ? "healthy" : services.length === 0 ? "unknown" : "warning"}
        statusLabel={
          allRunning
            ? "All services running"
            : `${services.filter((s) => s.status !== "Running").length} service(s) not running`
        }
        actions={<RefreshButton onClick={refetch} loading={loading} />}
      />

      {loading && !data ? (
        <LoadingSpinner />
      ) : (
        <div className="grid grid-cols-1 gap-3">
          {services.map((svc) => (
            <Card key={svc.name}>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-4">
                  <div
                    className={`flex h-10 w-10 items-center justify-center rounded-lg ${
                      svc.status === "Running"
                        ? "bg-green-500/10"
                        : svc.status === "NotFound"
                          ? "bg-gray-500/10"
                          : "bg-red-500/10"
                    }`}
                  >
                    <svg
                      className={`h-5 w-5 ${
                        svc.status === "Running"
                          ? "text-green-400"
                          : svc.status === "NotFound"
                            ? "text-gray-500"
                            : "text-red-400"
                      }`}
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                      strokeWidth={1.5}
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2"
                      />
                    </svg>
                  </div>
                  <div>
                    <p className="text-sm font-medium text-gray-200">{svc.displayName || svc.name}</p>
                    <p className="text-xs text-gray-600 font-mono">{svc.name}</p>
                  </div>
                </div>

                <div className="flex items-center gap-3">
                  <StatusPill
                    status={
                      svc.status === "Running"
                        ? "healthy"
                        : svc.status === "NotFound"
                          ? "unknown"
                          : "critical"
                    }
                    label={svc.status}
                  />
                  {svc.startType && (
                    <span className="text-xs text-gray-600">{svc.startType}</span>
                  )}
                  {svc.status !== "NotFound" && (
                    <button
                      onClick={() => handleRestart(svc.name)}
                      disabled={restarting[svc.name]}
                      className="rounded-lg border border-gray-700 bg-surface-3 px-3 py-1.5 text-xs text-gray-300 hover:bg-surface-4 hover:text-white transition-colors disabled:opacity-50"
                    >
                      {restarting[svc.name] ? (
                        <span className="flex items-center gap-1">
                          <span className="h-3 w-3 animate-spin rounded-full border border-gray-600 border-t-white" />
                          Restarting...
                        </span>
                      ) : (
                        "Restart"
                      )}
                    </button>
                  )}
                </div>
              </div>
              {messages[svc.name] && (
                <div
                  className={`mt-3 rounded px-3 py-2 text-xs ${
                    messages[svc.name].ok
                      ? "bg-green-500/10 text-green-400"
                      : "bg-red-500/10 text-red-400"
                  }`}
                >
                  {messages[svc.name].text}
                </div>
              )}
            </Card>
          ))}
          {services.length === 0 && (
            <Card>
              <p className="text-center text-sm text-gray-600">No services data available</p>
            </Card>
          )}
        </div>
      )}
    </div>
  );
}
