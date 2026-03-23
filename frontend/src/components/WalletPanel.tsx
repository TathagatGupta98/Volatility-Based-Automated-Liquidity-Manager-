import { useConnect, useDisconnect, useAccount } from 'wagmi';

export function WalletPanel() {
  const { isConnected, address } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  return (
    <div className="glass flex items-center gap-2 p-2">
      {isConnected ? (
        <>
          <span className="rounded-lg bg-white/10 px-3 py-1.5 text-xs text-slate-200">
            {address?.slice(0, 6)}...{address?.slice(-4)}
          </span>
          <button className="btn-secondary" onClick={() => disconnect()}>
            Disconnect
          </button>
        </>
      ) : (
        <button
          className="btn-primary"
          onClick={() => connect({ connector: connectors[0] })}
          disabled={isPending || !connectors.length}
        >
          {isPending ? 'Connecting...' : 'Connect Wallet'}
        </button>
      )}
    </div>
  );
}
