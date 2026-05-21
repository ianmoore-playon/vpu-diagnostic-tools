export default function LoadingSpinner({ text = "Loading..." }) {
  return (
    <div className="flex flex-col items-center justify-center py-12">
      <div className="h-8 w-8 animate-spin rounded-full border-2 border-gray-700 border-t-pulse-accent" />
      <p className="mt-3 text-sm text-gray-500">{text}</p>
    </div>
  );
}
