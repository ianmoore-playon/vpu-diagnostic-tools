export default function KeyValueRow({ label, value, mono }) {
  return (
    <div className="flex items-baseline justify-between py-1.5">
      <span className="text-sm text-gray-500">{label}</span>
      <span className={`text-sm text-gray-200 text-right ${mono ? "font-mono" : ""}`}>
        {value ?? "--"}
      </span>
    </div>
  );
}
