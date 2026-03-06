/**
 * Configuración de wagmi + RainbowKit — solo wallets inyectadas.
 *
 * Usa getDefaultConfig con una lista explícita de wallets que excluye
 * WalletConnect. Así no se necesita VITE_WALLETCONNECT_PROJECT_ID y
 * el conector de MetaMask que genera RainbowKit maneja correctamente
 * el evento accountsChanged para sincronizar cambios de cuenta.
 *
 * Cadena soportada: Sepolia (testnet Ethereum).
 * RPC: endpoint definido en .env.local / variables de entorno.
 */
import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { metaMaskWallet, injectedWallet, rabbyWallet } from '@rainbow-me/rainbowkit/wallets'
import { sepolia } from 'wagmi/chains'
import { http } from 'wagmi'

export const wagmiConfig = getDefaultConfig({
  appName: 'FlashBet',
  // projectId es requerido por el tipo pero no se usa: no hay wallets WalletConnect.
  projectId: 'flashbet-no-walletconnect',
  chains: [sepolia],
  wallets: [
    {
      groupName: 'Browser wallets',
      wallets: [metaMaskWallet, rabbyWallet, injectedWallet],
    },
  ],
  transports: {
    [sepolia.id]: http(import.meta.env.VITE_SEPOLIA_RPC_URL),
  },
  // pollingInterval controla SOLO la detección de receipts de transacciones pendientes.
  // 4s = tx confirmada en máx 4s adicionales a los ~12s de bloque Sepolia.
  pollingInterval: 4_000,
})