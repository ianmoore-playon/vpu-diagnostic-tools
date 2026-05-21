const SEVERITY_MAP = {
  critical: { bg: "bg-red-500/15", text: "text-red-400", dot: "bg-red-400" },
  warning: { bg: "bg-yellow-500/15", text: "text-yellow-400", dot: "bg-yellow-400" },
  info: { bg: "bg-blue-500/15", text: "text-blue-400", dot: "bg-blue-400" },
};

export default function SeverityChip({ severity, label }) {
  const key = (severity || "info").toLowerCase();
  const s = SEVERITY_MAP[key] || SEVERITY_MAP.info;
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded px-2 py-0.5 text-xs font-medium ${s.bg} ${s.text}`}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${s.dot}`} />
      {label || severity}
    </span>
  );
}
