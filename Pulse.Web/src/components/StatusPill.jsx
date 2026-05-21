const VARIANTS = {
  healthy: { bg: "bg-pulse-green/15", text: "text-pulse-green", dot: "bg-pulse-green" },
  warning: { bg: "bg-pulse-yellow/15", text: "text-pulse-yellow", dot: "bg-pulse-yellow" },
  critical: { bg: "bg-pulse-red/15", text: "text-pulse-red", dot: "bg-pulse-red" },
  info: { bg: "bg-pulse-blue/15", text: "text-pulse-blue", dot: "bg-pulse-blue" },
  unknown: { bg: "bg-gray-700/30", text: "text-gray-400", dot: "bg-gray-500" },
};

export default function StatusPill({ status = "unknown", label }) {
  const v = VARIANTS[status] || VARIANTS.unknown;
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium ${v.bg} ${v.text}`}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${v.dot}`} />
      {label || status}
    </span>
  );
}
