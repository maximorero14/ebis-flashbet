/**
 * AccountWatcher — sincroniza el estado de la app cuando cambia la wallet.
 *
 * Estrategia dual para máxima fiabilidad:
 *
 * 1. useAccount() de wagmi: detecta cambios cuando wagmi propaga el evento.
 * 2. window.ethereum 'accountsChanged': listener nativo como fallback.
 *    En wagmi v2, el conector injected() a veces no propaga el evento a
 *    React state; escuchar directamente el provider garantiza la detección.
 *    Al detectarlo, se llama reconnect() para que wagmi actualice su estado
 *    interno (useAccount) y luego se invalida todo el cache de React Query.
 *
 * Se monta dentro de los providers en App.tsx (no renderiza nada visible).
 */
import { useEffect, useRef } from 'react'
import { useAccount, useConfig } from 'wagmi'
import { reconnect }             from 'wagmi/actions'
import { useQueryClient }        from '@tanstack/react-query'

export function AccountWatcher() {
  const { address }  = useAccount()
  const config       = useConfig()
  const queryClient  = useQueryClient()
  const prevAddress  = useRef(address)

  // Camino 1: wagmi propaga el cambio correctamente → invalida cache
  useEffect(() => {
    if (prevAddress.current !== address) {
      prevAddress.current = address
      queryClient.invalidateQueries()
    }
  }, [address, queryClient])

  // Camino 2: listener nativo por si wagmi no propaga el evento
  useEffect(() => {
    const ethereum = (window as { ethereum?: { on: (e: string, cb: (a: string[]) => void) => void; removeListener: (e: string, cb: (a: string[]) => void) => void } }).ethereum
    if (!ethereum) return

    const handleAccountsChanged = async (_accounts: string[]) => {
      // Forzar que wagmi re-lea la cuenta activa del provider
      await reconnect(config)
      // Asegurar que el cache de React Query se invalida aunque wagmi
      // ya hubiese actualizado el estado (evita doble invalidación costosa
      // porque invalidateQueries es idempotente)
      queryClient.invalidateQueries()
    }

    ethereum.on('accountsChanged', handleAccountsChanged)
    return () => {
      ethereum.removeListener('accountsChanged', handleAccountsChanged)
    }
  }, [config, queryClient])

  // Componente invisible — solo tiene efectos secundarios
  return null
}
