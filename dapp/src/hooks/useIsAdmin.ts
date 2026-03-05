/**
 * useIsAdmin — comprueba si la wallet conectada es el owner del FlashVault.
 * Usado en la Navbar para mostrar el link de Admin condicionalmente.
 */
import { useAccount, useReadContract } from 'wagmi'
import { sepolia }                     from 'wagmi/chains'
import { CONTRACTS }                   from '../config/contracts'
import { FlashVaultABI }               from '../abi/FlashVault'

const addr = CONTRACTS[sepolia.id]

export function useIsAdmin(): boolean {
  const { address, isConnected } = useAccount()

  const { data: owner } = useReadContract({
    address:      addr.FlashVault,
    abi:          FlashVaultABI,
    functionName: 'owner',
    query: {
      enabled: isConnected && !!address,
    },
  })

  if (!address || !owner) return false
  return (address as string).toLowerCase() === (owner as string).toLowerCase()
}
