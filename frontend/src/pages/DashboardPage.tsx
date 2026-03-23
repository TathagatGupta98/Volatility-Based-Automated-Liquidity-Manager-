import { useQuery } from '@tanstack/react-query';
import { fetchDashboardSnapshot } from '../lib/api';
import { StatCard } from '../components/StatCard';
import { useContractConfig } from '../lib/useContractConfig';

export function DashboardPage() {
  const snapshot = useQuery({
    queryKey: ['snapshot'],
    queryFn: fetchDashboardSnapshot,
    refetchInterval: 10000
  });
  const contractConfig = useContractConfig();

  const data = snapshot.data;

  return (
    <section className="space-y-6">
      <div>
        <p className="text-xs uppercase tracking-[0.2em] text-neon-cyan">Overview</p>
        <h2 className="text-2xl font-bold">Live Vault Dashboard</h2>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard title="NAV (USDC)" value={data?.navUsdc ?? '--'} accent="cyan" />
        <StatCard title="Total Shares" value={data?.totalShares ?? '--'} accent="violet" />
        <StatCard title="Idle ETH" value={data?.idleEth ?? '--'} accent="green" />
        <StatCard title="Idle USDC" value={data?.idleUsdc ?? '--'} accent="pink" />
      </div>

      <div className="glass grid gap-4 p-5 md:grid-cols-2">
        <div>
          <p className="mb-1 text-xs uppercase tracking-wide text-slate-400">Volatility Class</p>
          <p className="text-xl font-semibold">{data?.volatilityClass ?? '--'}</p>
          <p className="mt-2 text-xs text-slate-400">Updated: {data?.updatedAt ?? '--'}</p>
        </div>
        <div>
          <p className="mb-1 text-xs uppercase tracking-wide text-slate-400">Contract Address</p>
          <p className="break-all text-sm text-slate-200">{contractConfig.data?.address ?? 'Loading...'}</p>
        </div>
      </div>

      {(snapshot.isError || contractConfig.isError) && (
        <p className="rounded-xl border border-red-400/30 bg-red-500/10 p-3 text-sm text-red-200">
          Failed to load backend data. Ensure backend server is running on port 8787.
        </p>
      )}
    </section>
  );
}
