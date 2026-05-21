export default function Card({ title, children, className = "", actions, noPad }) {
  return (
    <div className={`rounded-xl border border-gray-800 bg-surface-2 ${className}`}>
      {title && (
        <div className="flex items-center justify-between border-b border-gray-800 px-5 py-3">
          <h3 className="text-sm font-semibold text-gray-200">{title}</h3>
          {actions}
        </div>
      )}
      <div className={noPad ? "" : "p-5"}>{children}</div>
    </div>
  );
}
