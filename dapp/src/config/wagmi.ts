/**
 * Configuración de wagmi + RainbowKit.
 *
 * Cadena soportada: Sepolia (testnet Ethereum).
 * WalletConnect es opcional: si VITE_WALLETCONNECT_PROJECT_ID no está
 * configurado, la app funciona con wallets inyectadas (MetaMask, etc.).
 *
 * Se usa getDefaultConfig de RainbowKit en lugar de createConfig de wagmi
 * directamente porque getDefaultConfig configura los conectores con todas
 * las opciones necesarias para que los eventos de MetaMask (accountsChanged,
 * chainChanged) se propaguen correctamente al estado de React.
 *
 * RPC: endpoint definido en .env.local / variables de entorno.
 */
import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { sepolia }          from 'wagmi/chains'
import { http }             from 'wagmi'

/** Si no hay projectId real de WalletConnect, las wallets inyectadas siguen funcionando */
const walletConnectProjectId =
  import.meta.env.VITE_WALLETCONNECT_PROJECT_ID ?? 'placeholder'

export const wagmiConfig = getDefaultConfig({
  appName:   'FlashBet',
  projectId: walletConnectProjectId,
  chains:    [sepolia],
  transports: {
    [sepolia.id]: http(import.meta.env.VITE_SEPOLIA_RPC_URL),
  },
  // pollingInterval controla SOLO la detección de receipts de transacciones pendientes.
  // 4s = tx confirmada detectada en máx 4s adicionales a los ~12s de bloque Sepolia.
  pollingInterval: 4_000,
})
