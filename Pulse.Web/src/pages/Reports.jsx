import { useState } from "react";
import { useApi } from "../hooks/useApi";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import RefreshButton from "../components/RefreshButton";
import LoadingSpinner from "../components/LoadingSpinner";

export default function Reports() {
  const { data, loading, refetch } = useApi("/reports");
  const [selectedReport, setSelectedReport] = useState(null);
  const [reportContent, setReportContent] = useState(null);
  const [loadingContent, setLoadingContent] = useState(false);

  const reports = data?.reports || [];

  async function loadReport(filename) {
    setSelectedReport(filename);
    setLoadingContent(true);
    try {
      const res = await fetch(`/api/reports/${encodeURIComponent(filename)}`);
      if (!res.ok) throw new Error(`${res.status}`);
      const json = await res.json();
      setReportContent(json.content);
    } catch (err) {
      setReportContent(`Error loading report: ${err.message}`);
    } finally {
      setLoadingContent(false);
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reports"
        subtitle={`${reports.length} report${reports.length !== 1 ? "s" : ""}`}
        actions={<RefreshButton onClick={refetch} loading={loading} />}
      />

      {loading && !data ? (
        <LoadingSpinner />
      ) : (
        <div className="grid grid-cols-3 gap-4" style={{ minHeight: 400 }}>
          {/* Report List */}
          <Card title="Saved Reports" noPad className="col-span-1">
            <div className="divide-y divide-gray-800/60 max-h-[600px] overflow-y-auto">
              {reports.map((r) => (
                <button
                  key={r.filename}
                  onClick={() => loadReport(r.filename)}
                  className={`w-full text-left px-4 py-3 transition-colors ${
                    selectedReport === r.filename
                      ? "bg-pulse-accent/10 border-l-2 border-pulse-accent"
                      : "hover:bg-surface-3"
                  }`}
                >
                  <p className="text-sm text-gray-200 truncate">{r.filename}</p>
                  {r.size && (
                    <p className="text-xs text-gray-600 mt-0.5">
                      {(r.size / 1024).toFixed(1)} KB
                    </p>
                  )}
                  {r.modified && (
                    <p className="text-xs text-gray-600">{r.modified}</p>
                  )}
                </button>
              ))}
              {reports.length === 0 && (
                <p className="px-4 py-6 text-center text-sm text-gray-600">
                  No reports found
                </p>
              )}
            </div>
          </Card>

          {/* Report Content */}
          <Card
            title={selectedReport || "Select a report"}
            className="col-span-2"
            noPad
          >
            {loadingContent ? (
              <LoadingSpinner text="Loading report..." />
            ) : reportContent ? (
              <pre className="overflow-auto p-4 text-xs text-gray-300 font-mono whitespace-pre-wrap max-h-[600px] leading-relaxed">
                {reportContent}
              </pre>
            ) : (
              <div className="flex items-center justify-center py-16">
                <p className="text-sm text-gray-600">
                  Select a report from the list to view its contents
                </p>
              </div>
            )}
          </Card>
        </div>
      )}
    </div>
  );
}
