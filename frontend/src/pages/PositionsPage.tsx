import { useQuery } from '@tanstack/react-query';

async function fetchPositions() {
  const res = await fetch((import.meta.env.VITE_BACKEND_URL || 'http://localhost:8787') + '/api/positions');
  if (!res.ok) throw new Error('Failed to fetch positions');
  return res.json() as Promise<Array<{ slot: number; tickLower: number; tickUpper: number; liquidity: string; active: boolean }>>;
}

export function PositionsPage() {
  const { data, isLoading, isError } = useQuery({ queryKey: ['positions'], queryFn: fetchPositions, refetchInterval: 10000 });

  return (
    <section className="space-y-6">
      <div>
        <p className="text-xs uppercase tracking-[0.2em] text-neon-cyan">Portfolio</p>
        <h2 className="text-2xl font-bold">Current Positions</h2>
      </div>

      <div className="overflow-hidden rounded-2xl border border-white/10">
        <table className="w-full text-left text-sm">
          <thead className="bg-white/5 text-slate-300">
            <tr>
              <th className="px-4 py-3">Slot</th>
              <th className="px-4 py-3">Tick Lower</th>
              <th className="px-4 py-3">Tick Upper</th>
              <th className="px-4 py-3">Liquidity</th>
              <th className="px-4 py-3">Status</th>
            </tr>
          </thead>
          <tbody>
            {isLoading && (
              <tr>
                <td className="px-4 py-3 text-slate-300" colSpan={5}>Loading positions...</td>
              </tr>
            )}
            {isError && (
              <tr>
                <td className="px-4 py-3 text-red-300" colSpan={5}>Failed to load positions. Start backend server.</td>
              </tr>
            )}
            {data?.map((pos) => (
              <tr key={pos.slot} className="border-t border-white/10">
                <td className="px-4 py-3">#{pos.slot}</td>
                <td className="px-4 py-3">{pos.tickLower}</td>
                <td className="px-4 py-3">{pos.tickUpper}</td>
                <td className="px-4 py-3">{pos.liquidity}</td>
                <td className="px-4 py-3">
                  <span className={`rounded-md px-2 py-1 text-xs ${pos.active ? 'bg-emerald-500/20 text-emerald-200' : 'bg-slate-500/20 text-slate-300'}`}>
                    {pos.active ? 'Active' : 'Inactive'}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
