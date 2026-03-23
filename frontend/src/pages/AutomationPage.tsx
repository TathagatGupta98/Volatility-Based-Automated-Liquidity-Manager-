import { useMemo } from 'react';
import { useAccount, useWaitForTransactionReceipt, useWriteContract } from 'wagmi';
import { TxButton } from '../components/TxButton';
import { useContractConfig } from '../lib/useContractConfig';

export function AutomationPage() {
  const { isConnected } = useAccount();
  const { data: config } = useContractConfig();
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const status = useMemo(() => {
    if (isConfirming) return 'Waiting for confirmation...';
    if (isSuccess) return 'Done. Transaction confirmed.';
    if (error) return error.message;
    return '';
  }, [isConfirming, isSuccess, error]);

  const runAction = (functionName: string) => {
    if (!config) return;
    writeContract({
      address: config.address,
      abi: config.abi,
      functionName: functionName as never,
      args: [] as never
    });
  };

  return (
    <section className="space-y-6">
      <div>
        <p className="text-xs uppercase tracking-[0.2em] text-neon-cyan">Automation</p>
        <h2 className="text-2xl font-bold">Rebalance & Risk Controls</h2>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <div className="glass p-5">
          <h3 className="mb-3 font-semibold">Rebalance</h3>
          <TxButton label="Trigger Rebalance" isBusy={isPending} onClick={() => runAction(config?.functions.rebalance || 'rebalance')} disabled={!isConnected || !config} />
        </div>
        <div className="glass p-5">
          <h3 className="mb-3 font-semibold">Pause Vault</h3>
          <TxButton label="Pause" variant="danger" isBusy={isPending} onClick={() => runAction(config?.functions.pause || 'pause')} disabled={!isConnected || !config} />
        </div>
        <div className="glass p-5">
          <h3 className="mb-3 font-semibold">Resume Vault</h3>
          <TxButton label="Unpause" variant="secondary" isBusy={isPending} onClick={() => runAction(config?.functions.unpause || 'unpause')} disabled={!isConnected || !config} />
        </div>
      </div>

      {status && <p className="rounded-xl border border-white/15 bg-white/5 p-3 text-sm text-slate-200">{status}</p>}
    </section>
  );
}
