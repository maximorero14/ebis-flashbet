/**
 * main.tsx — Entry point de FlashBet DApp.
 *
 * Providers (orden de anidamiento importante):
 *   WagmiProvider         → conexión con la blockchain y wallets
 *   QueryClientProvider   → cache de React Query para datos on-chain
 *   RainbowKitProvider    → UI de conexión de wallets (MetaMask, WalletConnect, etc.)
 *
 * Estilos de RainbowKit importados antes de index.css para permitir overrides.
 */
import { StrictMode }          from 'react'
import { createRoot }          from 'react-dom/client'
import { WagmiProvider }       from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RainbowKitProvider, darkTheme }    from '@rainbow-me/rainbowkit'
import '@rainbow-me/rainbowkit/styles.css'
import './index.css'
import App              from './App'
import { wagmiConfig }  from './config/wagmi'

/** Cliente de React Query — configuración para lecturas blockchain */
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Los datos on-chain son válidos por 10s antes de un refetch
      staleTime:   10_000,
      // Retry limitado para no saturar el RPC en caso de error
      retry:       2,
      retryDelay:  1_000,
    },
  },
})

/** Tema personalizado de RainbowKit — dark cyberpunk */
const rainbowTheme = darkTheme({
  accentColor:          '#00f5ff',
  accentColorForeground: '#030712',
  borderRadius:         'medium',
  fontStack:            'system',
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={rainbowTheme} locale="es">
          <App />
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  </StrictMode>,
)
