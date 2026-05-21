import StatusPill from "./StatusPill";

export default function PageHeader({ title, status, statusLabel, actions, subtitle }) {
  return (
    <div className="mb-6 flex items-start justify-between">
      <div>
        <div className="flex items-center gap-3">
          <h1 className="text-xl font-bold text-white">{title}</h1>
          {status && <StatusPill status={status} label={statusLabel} />}
        </div>
        {subtitle && <p className="mt-1 text-sm text-gray-500">{subtitle}</p>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </div>
  );
}
