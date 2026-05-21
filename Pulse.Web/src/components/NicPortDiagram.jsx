function portColor(port) {
  if (!port.isUp) return "bg-gray-600";
  if (port.isDegraded || port.isFlapping || port.rxErrors > 0) return "bg-pulse-yellow";
  return "bg-pulse-green";
}

function portBorder(port) {
  if (!port.isUp) return "border-gray-700";
  if (port.isDegraded || port.isFlapping || port.rxErrors > 0) return "border-yellow-500/40";
  return "border-green-500/40";
}

function portStatusText(port) {
  if (!port.isUp) return "No cable";
  const speed = port.linkSpeedMbps >= 1000 ? `${port.linkSpeedMbps / 1000} Gbps` : `${port.linkSpeedMbps} Mbps`;
  let text = `Linked · ${speed}`;
  if (port.isOcr) text += " · OCR";
  if (port.isFlapping) text += " · Flapping";
  return text;
}

export default function NicPortDiagram({ ports = [] }) {
  const displayPorts = [...ports].reverse();

  return (
    <div className="flex items-center gap-1 rounded-lg bg-surface-3 p-3">
      <div className="mr-2 text-[10px] text-gray-600 rotate-180" style={{ writingMode: "vertical-rl" }}>
        NIC CARD
      </div>
      {displayPorts.map((port, i) => (
        <div
          key={port.name || i}
          className={`flex flex-col items-center rounded-lg border ${portBorder(port)} bg-surface-2 px-3 py-2 min-w-[100px]`}
        >
          <div className={`h-3 w-3 rounded-full ${portColor(port)} mb-1.5`} />
          <div className="flex flex-col items-center">
            <span className="text-xs font-medium text-gray-300">{port.name || `Port ${ports.length - i}`}</span>
            <span className="text-[10px] text-gray-500 mt-0.5">{portStatusText(port)}</span>
            {port.isUp && port.rxErrors > 0 && (
              <span className="text-[10px] text-yellow-400 mt-0.5">{port.rxErrors} errors</span>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
