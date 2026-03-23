export function StatCard({
  title,
  value,
  accent
}: {
  title: string;
  value: string;
  accent?: 'cyan' | 'pink' | 'green' | 'violet';
}) {
  const ring = {
    cyan: 'border-neon-cyan/40',
    pink: 'border-neon-pink/40',
    green: 'border-neon-green/40',
    violet: 'border-neon-violet/40'
  }[accent || 'violet'];

  return (
    <div className={`glass border ${ring} p-4`}>
      <p className="mb-2 text-xs uppercase tracking-wide text-slate-400">{title}</p>
      <p className="text-2xl font-bold text-white">{value}</p>
    </div>
  );
}
