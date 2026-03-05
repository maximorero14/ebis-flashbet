/**
 * useFlashBalance — balance de $FLASH del usuario conectado.
 *
 * Lee FlashToken.balanceOf(address) usando wagmi useReadContract.
 * Solo ejecuta la query cuando hay una wallet conectada.
 *
 * @returns Resultado de wagmi con `data` en bigint (6 decimales) o undefined
 */
import { useReadContract, useWatchContractEvent } from 'wagmi'
import { useAccount } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import { CONTRACTS } from '../config/contracts'
import { FlashTokenABI } from '../abi/FlashToken'

export function useFlashBalance() {
  const { address, isConnected } = useAccount()

  const result = useReadContract({
    address: CONTRACTS[sepolia.id].FlashToken,
    abi: FlashTokenABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      enabled: isConnected && !!address,
      // Sin polling — se actualiza tras cada tx y en window focus.
      refetchInterval: false,
      staleTime: 30_000,
    },
  })

  // Refetch inmediato al detectar transferencias que involucren al usuario
  // (ej: al reclamar payout, depositar, redimir)
  useWatchContractEvent({
    address: CONTRACTS[sepolia.id].FlashToken,
    abi: FlashTokenABI,
    eventName: 'Transfer',
    onLogs: (logs) => {
      if (!address) return
      const lower = address.toLowerCase()
      const relevant = logs.some(log =>
        log.args?.to?.toLowerCase() === lower ||
        log.args?.from?.toLowerCase() === lower
      )
      if (relevant) result.refetch()
    },
    enabled: isConnected && !!address,
  })

  return result
}
