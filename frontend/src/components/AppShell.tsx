import { NavLink } from 'react-router-dom';
import { WalletPanel } from './WalletPanel';

const navItems = [
  { to: '/dashboard', label: 'Dashboard' },
  { to: '/vault-actions', label: 'Vault Actions' },
  { to: '/positions', label: 'Positions' },
  { to: '/automation', label: 'Automation' },
  { to: '/admin', label: 'Admin' }
];

export function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen px-4 py-6 md:px-8">
      <header className="mx-auto mb-6 flex w-full max-w-7xl items-center justify-between gap-4">
        <div>
          <p className="text-xs uppercase tracking-[0.2em] text-neon-cyan">ALM Project</p>
          <h1 className="text-2xl font-bold md:text-3xl">Volatility-Based Liquidity Manager</h1>
        </div>
        <WalletPanel />
      </header>

      <div className="mx-auto grid w-full max-w-7xl grid-cols-1 gap-4 lg:grid-cols-[240px_1fr]">
        <aside className="glass p-3">
          <nav className="space-y-2">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) =>
                  `block rounded-xl px-3 py-2 text-sm font-medium transition ${
                    isActive
                      ? 'bg-gradient-to-r from-neon-violet to-neon-cyan text-white'
                      : 'bg-white/0 text-slate-300 hover:bg-white/10'
                  }`
                }
              >
                {item.label}
              </NavLink>
            ))}
          </nav>
        </aside>

        <main className="glass min-h-[76vh] p-5 md:p-6">{children}</main>
      </div>
    </div>
  );
}
