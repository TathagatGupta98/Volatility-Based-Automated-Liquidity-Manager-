import { useContractConfig } from '../lib/useContractConfig';

export function AdminPage() {
  const { data, isLoading, isError } = useContractConfig();

  return (
    <section className="space-y-6">
      <div>
        <p className="text-xs uppercase tracking-[0.2em] text-neon-cyan">Admin</p>
        <h2 className="text-2xl font-bold">Contract Configuration</h2>
      </div>

      <div className="glass p-5">
        <p className="mb-2 text-sm text-slate-300">
          Update only the backend file <span className="font-semibold text-white">backend/src/config/almContract.ts</span>.
        </p>
        <ul className="list-disc space-y-1 pl-5 text-sm text-slate-300">
          <li>Set contract address in <span className="font-semibold text-white">ALM_CONTRACT_ADDRESS</span></li>
          <li>Paste ABI in <span className="font-semibold text-white">ALM_CONTRACT_ABI</span></li>
        </ul>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="glass p-5">
          <p className="mb-1 text-xs uppercase tracking-wide text-slate-400">Current Address</p>
          <p className="break-all text-sm text-white">
            {isLoading ? 'Loading...' : isError ? 'Unavailable' : data?.address}
          </p>
        </div>
        <div className="glass p-5">
          <p className="mb-1 text-xs uppercase tracking-wide text-slate-400">ABI Entries</p>
          <p className="text-sm text-white">{isLoading ? 'Loading...' : isError ? 'Unavailable' : data?.abi?.length ?? 0}</p>
        </div>
      </div>
    </section>
  );
}
