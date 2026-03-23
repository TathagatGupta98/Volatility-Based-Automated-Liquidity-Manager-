import { ContractConfig, DashboardSnapshot } from './types';

const API_BASE = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8787';

export async function fetchDashboardSnapshot(): Promise<DashboardSnapshot> {
  const res = await fetch(`${API_BASE}/api/market-snapshot`);
  if (!res.ok) throw new Error('Failed to fetch dashboard snapshot');
  return res.json();
}

export async function fetchContractConfig(): Promise<ContractConfig> {
  const res = await fetch(`${API_BASE}/api/contract`);
  if (!res.ok) throw new Error('Failed to fetch contract config');
  return res.json();
}
