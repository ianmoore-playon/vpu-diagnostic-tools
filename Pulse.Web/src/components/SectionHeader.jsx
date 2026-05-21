export default function SectionHeader({ title, actions }) {
  return (
    <div className="flex items-center justify-between border-b border-gray-800 pb-3 mb-4">
      <h2 className="text-base font-semibold text-gray-200">{title}</h2>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </div>
  );
}
