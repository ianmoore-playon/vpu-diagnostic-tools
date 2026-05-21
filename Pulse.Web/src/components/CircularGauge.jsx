const RADIUS = 40;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

function colorForPercent(pct) {
  if (pct >= 85) return "text-pulse-red";
  if (pct >= 60) return "text-pulse-yellow";
  return "text-pulse-green";
}

function strokeForPercent(pct) {
  if (pct >= 85) return "#ef4444";
  if (pct >= 60) return "#eab308";
  return "#22c55e";
}

export default function CircularGauge({ value, label, unit = "%", size = 120 }) {
  const pct = Math.min(100, Math.max(0, value ?? 0));
  const offset = CIRCUMFERENCE - (pct / 100) * CIRCUMFERENCE;

  return (
    <div className="flex flex-col items-center gap-1">
      <div className="relative" style={{ width: size, height: size }}>
        <svg width={size} height={size} viewBox="0 0 100 100" className="-rotate-90">
          <circle cx="50" cy="50" r={RADIUS} fill="none" stroke="#1f2937" strokeWidth="8" />
          <circle
            cx="50"
            cy="50"
            r={RADIUS}
            fill="none"
            stroke={strokeForPercent(pct)}
            strokeWidth="8"
            strokeDasharray={CIRCUMFERENCE}
            strokeDashoffset={offset}
            strokeLinecap="round"
            className="transition-all duration-500"
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className={`text-2xl font-bold tabular-nums ${colorForPercent(pct)}`}>
            {value != null ? Math.round(pct) : "--"}
          </span>
          <span className="text-[10px] text-gray-500 uppercase tracking-wider">{unit}</span>
        </div>
      </div>
      <span className="text-xs text-gray-400">{label}</span>
    </div>
  );
}
