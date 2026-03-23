import { useQuery } from '@tanstack/react-query';
import { fetchContractConfig } from './api';

export function useContractConfig() {
  return useQuery({
    queryKey: ['contract-config'],
    queryFn: fetchContractConfig,
    staleTime: 30_000
  });
}
