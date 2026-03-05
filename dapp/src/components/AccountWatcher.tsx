/**
 * AccountWatcher — sincroniza el estado de la app cuando cambia la wallet.
 *
 * Cuando el usuario cambia de cuenta en MetaMask/RainbowKit, invalida
 * todas las queries de React Query para que los balances, apuestas y
 * estado de rondas se recarguen automáticamente con la nueva dirección.
 *
 * Se monta dentro de los providers en App.tsx (no renderiza nada visible).
 */
import { useEffect, useRef } from 'react'
import { useAccount }        from 'wagmi'
import { useQueryClient }    from '@tanstack/react-query'

export function AccountWatcher() {
  const { address } = useAccount()
  const queryClient  = useQueryClient()
  const prevAddress  = useRef(address)

  useEffect(() => {
    // Solo actuar cuando la dirección realmente cambió
    if (prevAddress.current !== address) {
      prevAddress.current = address
      // Invalidar todo el cache para forzar re-fetch con la nueva wallet
      queryClient.invalidateQueries()
    }
  }, [address, queryClient])

  // Componente invisible — solo tiene efecto secundario
  return null
}
