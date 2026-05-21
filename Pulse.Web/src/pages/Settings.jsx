import { useState, useEffect } from "react";
import { useApi, apiPost } from "../hooks/useApi";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import LoadingSpinner from "../components/LoadingSpinner";

export default function Settings() {
  const { data, loading } = useApi("/settings");
  const [scoreConnectUrl, setScoreConnectUrl] = useState("");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [baselineRunning, setBaselineRunning] = useState(false);
  const [baselineResult, setBaselineResult] = useState(null);

  useEffect(() => {
    if (data) {
      setScoreConnectUrl(data.scoreConnectUrl || "http://localhost:5000");
    }
  }, [data]);

  async function handleSave() {
    setSaving(true);
    setSaved(false);
    try {
      await apiPost("/settings", { scoreConnectUrl });
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch (err) {
      alert(`Save failed: ${err.message}`);
    } finally {
      setSaving(false);
    }
  }

  async function runBaseline() {
    setBaselineRunning(true);
    setBaselineResult(null);
    try {
      const result = await apiPost("/baseline/run");
      setBaselineResult(result);
    } catch (err) {
      setBaselineResult({ error: err.message });
    } finally {
      setBaselineRunning(false);
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader title="Settings" />

      {loading ? (
        <LoadingSpinner />
      ) : (
        <>
          {/* ScoreConnect URL */}
          <Card title="ScoreConnect">
            <div className="space-y-4">
              <div>
                <label className="block text-sm text-gray-400 mb-1.5">
                  ScoreConnect API URL
                </label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={scoreConnectUrl}
                    onChange={(e) => setScoreConnectUrl(e.target.value)}
                    className="flex-1 rounded-lg border border-gray-700 bg-surface-3 px-3 py-2 text-sm text-gray-200 font-mono focus:border-pulse-accent focus:outline-none"
                    placeholder="http://localhost:5000"
                  />
                  <button
                    onClick={handleSave}
                    disabled={saving}
                    className="rounded-lg bg-pulse-accent px-4 py-2 text-sm font-medium text-white hover:bg-pulse-accent/90 transition-colors disabled:opacity-50"
                  >
                    {saving ? "Saving..." : "Save"}
                  </button>
                </div>
                {saved && (
                  <p className="mt-2 text-xs text-green-400">Settings saved successfully</p>
                )}
              </div>
            </div>
          </Card>

          {/* Baseline Runner */}
          <Card title="Baseline Runner">
            <div className="space-y-4">
              <p className="text-sm text-gray-500">
                Run a full diagnostic baseline across all panels. This will collect system
                information, test network connectivity, check disk health, and generate a
                comprehensive report.
              </p>
              <button
                onClick={runBaseline}
                disabled={baselineRunning}
                className="inline-flex items-center gap-2 rounded-lg bg-pulse-accent px-4 py-2 text-sm font-medium text-white hover:bg-pulse-accent/90 transition-colors disabled:opacity-50"
              >
                {baselineRunning ? (
                  <>
                    <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white" />
                    Running Baseline...
                  </>
                ) : (
                  "Run Baseline"
                )}
              </button>

              {baselineResult && (
                <div
                  className={`rounded-lg p-4 text-sm ${
                    baselineResult.error
                      ? "bg-red-500/10 text-red-400"
                      : "bg-green-500/10 text-green-400"
                  }`}
                >
                  {baselineResult.error ? (
                    <p>Baseline failed: {baselineResult.error}</p>
                  ) : (
                    <>
                      <p className="font-medium">Baseline complete</p>
                      {baselineResult.severity && (
                        <p className="mt-1">
                          Overall: {baselineResult.severity} — {baselineResult.findingsCount}{" "}
                          finding(s)
                        </p>
                      )}
                      {baselineResult.reportPath && (
                        <p className="mt-1 text-xs text-gray-500">
                          Report saved: {baselineResult.reportPath}
                        </p>
                      )}
                    </>
                  )}
                </div>
              )}
            </div>
          </Card>
        </>
      )}
    </div>
  );
}
