/**
 * Configuración de wagmi — solo wallets inyectadas (MetaMask, Rabby, etc.)
 *
 * No usa WalletConnect. Se conecta directamente a la wallet del navegador
 * a través del conector `injected`, que escucha el evento nativo
 * `accountsChanged` del browser tanto en local como en producción.
 *
 * Cadena soportada: Sepolia (testnet Ethereum).
 * RPC: endpoint de Alchemy definido en .env.local / variables de entorno.
 */
import { createConfig } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import { http } from 'wagmi'
import { injected } from 'wagmi/connectors'

export const wagmiConfig = createConfig({
  chains: [sepolia],
  connectors: [injected()],
  transports: {
    [sepolia.id]: http(import.meta.env.VITE_SEPOLIA_RPC_URL),
  },
  // pollingInterval controla SOLO la detección de receipts de transacciones pendientes.
  // 4s = tx confirmada en máx 4s adicionales a los ~12s de bloque Sepolia.
  pollingInterval: 4_000,
})
