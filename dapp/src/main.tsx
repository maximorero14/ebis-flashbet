/**
 * main.tsx — Entry point de FlashBet DApp.
 *
 * Providers (orden de anidamiento importante):
 *   WagmiProvider        → conexión con la blockchain y wallets inyectadas
 *   QueryClientProvider  → cache de React Query para datos on-chain
 *   RainbowKitProvider   → UI del botón de conexión (MetaMask, etc.)
 *
 * Estilos de RainbowKit importados antes de index.css para permitir overrides.
 */
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { WagmiProvider } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RainbowKitProvider } from '@rainbow-me/rainbowkit'
import '@rainbow-me/rainbowkit/styles.css'
import './index.css'
import App from './App'
import { wagmiConfig } from './config/wagmi'

/** Cliente de React Query — configuración para lecturas blockchain */
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 10_000, // datos on-chain válidos 10s antes de refetch
      retry: 2,      // reintentos limitados para no saturar el RPC
      retryDelay: 1_000,
    },
  },
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider locale="es">
          <App />
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  </StrictMode>,
)
