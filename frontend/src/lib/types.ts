import type { Abi } from 'viem';

export type ContractFunctionMap = {
  deposit: string;
  withdraw: string;
  rebalance: string;
  pause: string;
  unpause: string;
};

export type ContractConfig = {
  address: `0x${string}`;
  abi: Abi;
  functions: ContractFunctionMap;
};

export type DashboardSnapshot = {
  navUsdc: string;
  totalShares: string;
  idleEth: string;
  idleUsdc: string;
  volatilityClass: number;
  updatedAt: string;
};
