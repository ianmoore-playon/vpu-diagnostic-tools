import { useState, useEffect, useCallback } from "react";
import { useApi, apiPost } from "../hooks/useApi";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import StatusPill from "../components/StatusPill";
import SeverityChip from "../components/SeverityChip";
import NicPortDiagram from "../components/NicPortDiagram";
import LoadingSpinner from "../components/LoadingSpinner";

const PHASES = [
  { key: "baseline", label: "Phase 1: Baseline", description: "Document starting port states" },
  { key: "nic-port", label: "Phase 2: NIC Port Test", description: "Move camera to spare port" },
  { key: "cable", label: "Phase 3: Cable Test", description: "Swap cable between ports" },
  { key: "camera", label: "Phase 4: Camera Test", description: "Swap camera unit" },
  { key: "concluded", label: "Concluded", description: "Verdict rendered" },
];

const VERDICT_MAP = {
  NicPort: { label: "Faulty NIC Port", severity: "critical", recommendation: "The NIC port on the VPU is defective. Use a different port or replace the NIC." },
  Cable: { label: "Faulty Cable", severity: "warning", recommendation: "The Ethernet cable is defective. Replace the cable." },
  Camera: { label: "Faulty Camera", severity: "critical", recommendation: "The camera unit is defective. Replace the camera." },
  NicHardware: { label: "NIC Hardware Failure", severity: "critical", recommendation: "The NIC card itself may be failing. Consider replacing the NIC card." },
  LikelyCamera: { label: "Likely Camera Issue", severity: "warning", recommendation: "Evidence points to the camera, but this could not be fully verified without a spare unit." },
};

export default function FaultIsolator() {
  const { data: portsData, loading: portsLoading, refetch: refetchPorts } = useApi("/fault-isolator/ports");
  const [session, setSession] = useState(null);
  const [suspectedPort, setSuspectedPort] = useState("");
  const [testPort, setTestPort] = useState("");
  const [advancing, setAdvancing] = useState(false);
  const [pollInterval, setPollInterval] = useState(null);

  const ports = portsData?.ports || [];

  const refreshSession = useCallback(async () => {
    try {
      const res = await fetch("/api/fault-isolator/status");
      const json = await res.json();
      if (json.active) setSession(json);
      else setSession(null);
    } catch {}
  }, []);

  useEffect(() => {
    refreshSession();
  }, [refreshSession]);

  useEffect(() => {
    if (session?.phase && session.phase !== "concluded") {
      const id = setInterval(refreshSession, 1000);
      setPollInterval(id);
      return () => clearInterval(id);
    }
    if (pollInterval) clearInterval(pollInterval);
  }, [session?.phase]);

  async function startSession() {
    if (!suspectedPort || !testPort) return;
    try {
      await apiPost("/fault-isolator/start", {
        suspectedPortMac: suspectedPort,
        testPortMac: testPort,
      });
      refreshSession();
    } catch (err) {
      alert(`Failed to start: ${err.message}`);
    }
  }

  async function advancePhase() {
    setAdvancing(true);
    try {
      await apiPost("/fault-isolator/advance");
      refreshSession();
    } catch (err) {
      alert(`Failed to advance: ${err.message}`);
    } finally {
      setAdvancing(false);
    }
  }

  async function conclude() {
    try {
      await apiPost("/fault-isolator/conclude");
      refreshSession();
    } catch (err) {
      alert(`Failed to conclude: ${err.message}`);
    }
  }

  async function resetSession() {
    try {
      await apiPost("/fault-isolator/reset");
      setSession(null);
      setSuspectedPort("");
      setTestPort("");
    } catch {}
  }

  const currentPhaseIndex = session
    ? PHASES.findIndex((p) => p.key === session.phase)
    : -1;
  const verdict = session?.verdict ? VERDICT_MAP[session.verdict] : null;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Fault Isolator"
        subtitle="4-phase NIC/cable/camera swap test wizard"
        status={session ? (session.phase === "concluded" ? "info" : "warning") : "unknown"}
        statusLabel={
          session
            ? session.phase === "concluded"
              ? "Test complete"
              : `${PHASES[currentPhaseIndex]?.label || session.phase}`
            : "No active session"
        }
      />

      {/* Phase Progress */}
      <Card>
        <div className="flex items-center gap-1">
          {PHASES.map((phase, i) => {
            const isActive = session?.phase === phase.key;
            const isPast = currentPhaseIndex > i;
            return (
              <div key={phase.key} className="flex flex-1 items-center">
                <div className="flex flex-col items-center flex-1">
                  <div
                    className={`flex h-8 w-8 items-center justify-center rounded-full text-xs font-bold ${
                      isActive
                        ? "bg-pulse-accent text-white"
                        : isPast
                          ? "bg-pulse-green text-white"
                          : "bg-surface-4 text-gray-500"
                    }`}
                  >
                    {isPast ? (
                      <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                        <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                      </svg>
                    ) : (
                      i + 1
                    )}
                  </div>
                  <span className={`mt-1.5 text-[10px] text-center ${isActive ? "text-pulse-accent font-medium" : "text-gray-600"}`}>
                    {phase.label}
                  </span>
                </div>
                {i < PHASES.length - 1 && (
                  <div className={`h-0.5 w-full mx-1 mt-[-16px] ${isPast ? "bg-pulse-green" : "bg-surface-4"}`} />
                )}
              </div>
            );
          })}
        </div>
      </Card>

      {!session ? (
        <>
          {/* Setup */}
          <Card title="Start New Test">
            {portsLoading ? (
              <LoadingSpinner text="Detecting NIC ports..." />
            ) : (
              <div className="space-y-4">
                <NicPortDiagram ports={ports} />

                <div className="grid grid-cols-2 gap-4 mt-4">
                  <div>
                    <label className="block text-sm text-gray-400 mb-1.5">
                      Suspected Bad Port
                    </label>
                    <select
                      value={suspectedPort}
                      onChange={(e) => setSuspectedPort(e.target.value)}
                      className="w-full rounded-lg border border-gray-700 bg-surface-3 px-3 py-2 text-sm text-gray-200 focus:border-pulse-accent focus:outline-none"
                    >
                      <option value="">Select port...</option>
                      {ports.map((p) => (
                        <option key={p.mac} value={p.mac}>
                          {p.name} — {p.isUp ? `${p.linkSpeedMbps} Mbps` : "No cable"} {p.isDegraded ? "(degraded)" : ""}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="block text-sm text-gray-400 mb-1.5">
                      Spare Test Port
                    </label>
                    <select
                      value={testPort}
                      onChange={(e) => setTestPort(e.target.value)}
                      className="w-full rounded-lg border border-gray-700 bg-surface-3 px-3 py-2 text-sm text-gray-200 focus:border-pulse-accent focus:outline-none"
                    >
                      <option value="">Select port...</option>
                      {ports
                        .filter((p) => p.mac !== suspectedPort)
                        .map((p) => (
                          <option key={p.mac} value={p.mac}>
                            {p.name} — {p.isUp ? `${p.linkSpeedMbps} Mbps` : "No cable"}
                          </option>
                        ))}
                    </select>
                  </div>
                </div>

                <button
                  onClick={startSession}
                  disabled={!suspectedPort || !testPort}
                  className="rounded-lg bg-pulse-accent px-4 py-2 text-sm font-medium text-white hover:bg-pulse-accent/90 transition-colors disabled:opacity-50"
                >
                  Begin Fault Isolation
                </button>
              </div>
            )}
          </Card>
        </>
      ) : (
        <>
          {/* Active Session */}
          <Card title={PHASES[currentPhaseIndex]?.label || "Session"}>
            <p className="text-sm text-gray-400 mb-4">
              {PHASES[currentPhaseIndex]?.description}
            </p>

            {/* Live port status during session */}
            {session.ports && <NicPortDiagram ports={session.ports} />}

            {/* Phase-specific readings */}
            {session.currentReading && (
              <div className="mt-4 rounded-lg bg-surface-3 p-4">
                <p className="text-xs text-gray-500 mb-2">Current Reading</p>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span className="text-gray-500">Suspected Port:</span>
                    <span className="ml-2 text-gray-200">
                      {session.currentReading.suspectedPortSpeed
                        ? `${session.currentReading.suspectedPortSpeed} Mbps`
                        : "No link"}
                    </span>
                  </div>
                  <div>
                    <span className="text-gray-500">Test Port:</span>
                    <span className="ml-2 text-gray-200">
                      {session.currentReading.testPortSpeed
                        ? `${session.currentReading.testPortSpeed} Mbps`
                        : "No link"}
                    </span>
                  </div>
                </div>
              </div>
            )}

            {/* Phase history */}
            {session.history?.length > 0 && (
              <div className="mt-4 space-y-2">
                <p className="text-xs text-gray-500">Phase History</p>
                {session.history.map((h, i) => (
                  <div key={i} className="flex items-center gap-3 rounded bg-surface-3 px-3 py-2 text-sm">
                    <SeverityChip severity={h.severity || "info"} label={h.phase} />
                    <span className="text-gray-300">{h.configuration}</span>
                    {h.speedReading && (
                      <span className="ml-auto font-mono text-xs text-gray-500">
                        {h.speedReading}
                      </span>
                    )}
                  </div>
                ))}
              </div>
            )}
          </Card>

          {/* Verdict */}
          {verdict && (
            <Card
              title="Verdict"
              className={`border-${verdict.severity === "critical" ? "red" : "yellow"}-500/30`}
            >
              <div className="flex items-start gap-4">
                <SeverityChip severity={verdict.severity} label={verdict.label} />
                <p className="text-sm text-gray-300">{verdict.recommendation}</p>
              </div>
            </Card>
          )}

          {/* Actions */}
          <div className="flex gap-3">
            {session.phase !== "concluded" && (
              <button
                onClick={advancePhase}
                disabled={advancing}
                className="inline-flex items-center gap-2 rounded-lg bg-pulse-accent px-4 py-2 text-sm font-medium text-white hover:bg-pulse-accent/90 transition-colors disabled:opacity-50"
              >
                {advancing ? (
                  <>
                    <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white" />
                    Monitoring...
                  </>
                ) : (
                  `Advance to ${PHASES[currentPhaseIndex + 1]?.label || "Next"}`
                )}
              </button>
            )}
            {session.phase !== "concluded" && currentPhaseIndex >= 2 && (
              <button
                onClick={conclude}
                className="rounded-lg border border-gray-700 bg-surface-3 px-4 py-2 text-sm text-gray-300 hover:bg-surface-4 transition-colors"
              >
                Skip to Verdict
              </button>
            )}
            <button
              onClick={resetSession}
              className="rounded-lg border border-gray-700 bg-surface-3 px-4 py-2 text-sm text-gray-300 hover:bg-surface-4 transition-colors"
            >
              {session.phase === "concluded" ? "Start Over" : "Cancel"}
            </button>
          </div>
        </>
      )}
    </div>
  );
}
