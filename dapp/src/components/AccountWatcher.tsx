/**
 * AccountWatcher — sincroniza el estado de la app cuando cambia la wallet.
 *
 * El conector de RainbowKit (metaMaskWallet/injectedWallet) se suscribe
 * internamente al evento accountsChanged del provider y actualiza wagmi.
 * Este componente invalida el cache de React Query cuando address cambia
 * para que balances, apuestas y rondas se recarguen con la nueva cuenta.
 *
 * Se monta dentro de los providers en App.tsx (no renderiza nada visible).
 */
import { useEffect, useRef } from 'react'
import { useAccount } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'

export function AccountWatcher() {
  const { address } = useAccount()
  const queryClient = useQueryClient()
  const prevAddress = useRef(address)

  useEffect(() => {
    if (prevAddress.current !== address) {
      prevAddress.current = address
      queryClient.invalidateQueries()
    }
  }, [address, queryClient])

  return null
}