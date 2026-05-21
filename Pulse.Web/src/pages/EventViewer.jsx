import { useState, useCallback } from "react";
import { useApi } from "../hooks/useApi";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import DataTable from "../components/DataTable";
import SeverityChip from "../components/SeverityChip";
import RefreshButton from "../components/RefreshButton";
import LoadingSpinner from "../components/LoadingSpinner";

const TIME_OPTIONS = [
  { label: "1 hour", value: 1 },
  { label: "24 hours", value: 24 },
  { label: "48 hours", value: 48 },
  { label: "7 days", value: 168 },
];

const LEVEL_OPTIONS = [
  { label: "All", value: "all" },
  { label: "Errors", value: "error" },
  { label: "Warnings", value: "warning" },
  { label: "Info", value: "info" },
];

export default function EventViewer() {
  const [hours, setHours] = useState(48);
  const [level, setLevel] = useState("all");

  const { data, loading, refetch } = useApi(`/events?hours=${hours}&level=${level}`);

  const entries = data?.entries || [];
  const totalCount = data?.totalCount || 0;

  const handleFilterChange = useCallback(
    (newHours, newLevel) => {
      setHours(newHours);
      setLevel(newLevel);
    },
    [],
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title="Event Viewer"
        subtitle={`${totalCount} entries${totalCount >= 500 ? " (capped at 500)" : ""}`}
        actions={<RefreshButton onClick={refetch} loading={loading} />}
      />

      {/* Filters */}
      <Card>
        <div className="flex flex-wrap items-center gap-4">
          <div className="flex items-center gap-2">
            <span className="text-xs text-gray-500">Time window:</span>
            <div className="flex rounded-lg border border-gray-700 overflow-hidden">
              {TIME_OPTIONS.map((opt) => (
                <button
                  key={opt.value}
                  onClick={() => {
                    handleFilterChange(opt.value, level);
                    setTimeout(refetch, 50);
                  }}
                  className={`px-3 py-1.5 text-xs transition-colors ${
                    hours === opt.value
                      ? "bg-pulse-accent text-white"
                      : "bg-surface-3 text-gray-400 hover:text-gray-200"
                  }`}
                >
                  {opt.label}
                </button>
              ))}
            </div>
          </div>

          <div className="flex items-center gap-2">
            <span className="text-xs text-gray-500">Level:</span>
            <div className="flex rounded-lg border border-gray-700 overflow-hidden">
              {LEVEL_OPTIONS.map((opt) => (
                <button
                  key={opt.value}
                  onClick={() => {
                    handleFilterChange(hours, opt.value);
                    setTimeout(refetch, 50);
                  }}
                  className={`px-3 py-1.5 text-xs transition-colors ${
                    level === opt.value
                      ? "bg-pulse-accent text-white"
                      : "bg-surface-3 text-gray-400 hover:text-gray-200"
                  }`}
                >
                  {opt.label}
                </button>
              ))}
            </div>
          </div>

          <div className="ml-auto text-xs text-gray-600">
            {entries.length} event{entries.length !== 1 ? "s" : ""}
          </div>
        </div>
      </Card>

      {/* Events Table */}
      <Card noPad>
        {loading ? (
          <LoadingSpinner text="Loading events..." />
        ) : (
          <DataTable
            columns={[
              {
                key: "timeCreated",
                label: "Time",
                cellClass: "text-xs whitespace-nowrap font-mono",
                className: "w-44",
              },
              {
                key: "level",
                label: "Level",
                className: "w-24",
                render: (v) => (
                  <SeverityChip
                    severity={
                      v === "Error" || v === "Critical"
                        ? "critical"
                        : v === "Warning"
                          ? "warning"
                          : "info"
                    }
                    label={v}
                  />
                ),
              },
              { key: "source", label: "Source", className: "w-48" },
              {
                key: "eventId",
                label: "ID",
                className: "w-16",
                cellClass: "font-mono text-xs",
              },
              {
                key: "message",
                label: "Message",
                cellClass: "text-xs max-w-lg truncate",
              },
            ]}
            rows={entries}
            emptyMessage="No events matching filters"
          />
        )}
      </Card>
    </div>
  );
}
