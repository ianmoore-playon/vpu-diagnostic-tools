import { useState } from "react";
import SeverityChip from "./SeverityChip";

export default function FindingsBanner({ findings = [], title = "Findings" }) {
  const [expanded, setExpanded] = useState(true);

  if (findings.length === 0) return null;

  const worstSeverity = findings.some((f) => f.severity === "Critical")
    ? "critical"
    : findings.some((f) => f.severity === "Warning")
      ? "warning"
      : "info";

  const borderColor = {
    critical: "border-red-500/40",
    warning: "border-yellow-500/40",
    info: "border-blue-500/40",
  }[worstSeverity];

  return (
    <div className={`rounded-lg border ${borderColor} bg-surface-2 overflow-hidden`}>
      <button
        onClick={() => setExpanded(!expanded)}
        className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-surface-3 transition-colors"
      >
        <SeverityChip severity={worstSeverity} label={`${findings.length} ${title}`} />
        <svg
          className={`ml-auto h-4 w-4 text-gray-500 transition-transform ${expanded ? "rotate-180" : ""}`}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          strokeWidth={2}
        >
          <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
      {expanded && (
        <div className="border-t border-gray-800 divide-y divide-gray-800/60">
          {findings.map((f, i) => (
            <div key={i} className="flex items-start gap-3 px-4 py-3">
              <SeverityChip severity={f.severity} />
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium text-gray-200">{f.title}</p>
                {f.recommendation && (
                  <p className="mt-0.5 text-xs text-gray-500">{f.recommendation}</p>
                )}
              </div>
              {f.category && (
                <span className="shrink-0 rounded bg-surface-3 px-1.5 py-0.5 text-[10px] text-gray-500">
                  {f.category}
                </span>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
