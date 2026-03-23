import { useMemo, useState } from 'react';
import { parseEther, parseUnits } from 'viem';
import { useAccount, useWaitForTransactionReceipt, useWriteContract } from 'wagmi';
import { TxButton } from '../components/TxButton';
import { useContractConfig } from '../lib/useContractConfig';

export function VaultActionsPage() {
  const { isConnected } = useAccount();
  const { data: config, isLoading } = useContractConfig();
  const { writeContract, data: txHash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const [ethAmount, setEthAmount] = useState('0.01');
  const [usdcAmount, setUsdcAmount] = useState('10');
  const [shares, setShares] = useState('1');

  const status = useMemo(() => {
    if (isConfirming) return 'Transaction submitted. Waiting for confirmation...';
    if (isSuccess) return 'Transaction confirmed on-chain.';
    if (error) return error.message;
    return '';
  }, [isConfirming, isSuccess, error]);

  const onDeposit = () => {
    if (!config) return;
    writeContract({
      address: config.address,
      abi: config.abi,
      functionName: config.functions.deposit as never,
      args: [parseUnits(usdcAmount || '0', 6)] as never,
      value: parseEther(ethAmount || '0')
    });
  };

  const onWithdraw = () => {
    if (!config) return;
    writeContract({
      address: config.address,
      abi: config.abi,
      functionName: config.functions.withdraw as never,
      args: [parseUnits(shares || '0', 18)] as never
    });
  };

  return (
    <section className="space-y-6">
      <div>
        <p className="text-xs uppercase tracking-[0.2em] text-neon-cyan">Vault</p>
        <h2 className="text-2xl font-bold">Deposit & Withdraw</h2>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <div className="glass p-5">
          <h3 className="mb-4 text-lg font-semibold">Deposit Liquidity</h3>
          <div className="space-y-3">
            <input className="input" value={ethAmount} onChange={(e) => setEthAmount(e.target.value)} placeholder="ETH amount" />
            <input className="input" value={usdcAmount} onChange={(e) => setUsdcAmount(e.target.value)} placeholder="USDC amount" />
            <TxButton
              label="Deposit"
              busyLabel="Depositing..."
              isBusy={isPending}
              onClick={onDeposit}
              disabled={!isConnected || isLoading || !config}
            />
          </div>
        </div>

        <div className="glass p-5">
          <h3 className="mb-4 text-lg font-semibold">Withdraw Liquidity</h3>
          <div className="space-y-3">
            <input className="input" value={shares} onChange={(e) => setShares(e.target.value)} placeholder="Shares to burn" />
            <TxButton
              label="Withdraw"
              busyLabel="Withdrawing..."
              isBusy={isPending}
              onClick={onWithdraw}
              disabled={!isConnected || isLoading || !config}
              variant="secondary"
            />
          </div>
        </div>
      </div>

      {status && <p className="rounded-xl border border-white/15 bg-white/5 p-3 text-sm text-slate-200">{status}</p>}
      {!isConnected && <p className="text-sm text-amber-300">Connect your wallet to enable all transaction buttons.</p>}
    </section>
  );
}
