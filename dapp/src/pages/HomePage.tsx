/**
 * HomePage — página principal de FlashBet.
 *
 * Layout (2 columnas desktop / stacked mobile):
 *   Columna izquierda:  VaultSection  — id="vault-section"
 *   Columna derecha:    MarketCards   — id="markets-section"
 *
 * Los IDs permiten que el Navbar haga scroll suave a cada sección.
 */
import { useAccount, useChainId, useSwitchChain } from 'wagmi'
import { sepolia }         from 'wagmi/chains'
import { VaultSection }    from '../components/sections/VaultSection'
import { MarketCard }      from '../components/sections/MarketCard'
import { useState }        from 'react'
import type { MarketId } from '../hooks/usePredMarket'

export function HomePage() {
  const { isConnected }   = useAccount()
  const chainId           = useChainId()
  const { switchChain }   = useSwitchChain()
  const [activeMarket, setActiveMarket] = useState<MarketId>(0)

  const isWrongNetwork = isConnected && chainId !== sepolia.id

  return (
    <main className="min-h-screen bg-cyber-grid bg-cyber-grid relative">
      {/* ── Banner red incorrecta ────────────────────── */}
      {isWrongNetwork && (
        <div className="sticky top-16 z-40 bg-down/90 backdrop-blur-sm border-b border-down/50 py-2.5 px-4 text-center">
          <p className="text-white font-mono text-sm font-bold tracking-wide flex items-center justify-center gap-3">
            ⚠ Red incorrecta — cambiá a Sepolia
            <button
              onClick={() => switchChain?.({ chainId: sepolia.id })}
              className="px-3 py-1 text-xs bg-white/20 hover:bg-white/30 rounded border border-white/30 transition-colors"
            >
              Switch to Sepolia
            </button>
          </p>
        </div>
      )}

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* ── Hero ─────────────────────────────────────── */}
        <div className="text-center mb-10">
          <h1
            className="font-orbitron text-3xl md:text-5xl font-black text-white tracking-widest mb-3"
            style={{ textShadow: '0 0 40px rgba(0,245,255,0.4)' }}
          >
            FLASH<span className="text-neon-cyan">BET</span>
          </h1>
          <p className="text-slate-500 font-mono text-sm max-w-lg mx-auto">
            Deposita USDT · Obtené $FLASH · Apostá en BTC o ETH · Cobrá en 60 segundos
          </p>
        </div>

        {/* ── Layout principal ──────────────────────────── */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">

          {/* Columna izquierda: Vault — id para scroll desde Navbar */}
          <div id="vault-section" style={{ scrollMarginTop: '80px' }}>
            <VaultSection />
          </div>

          {/* Columna derecha: Prediction Market — id para scroll desde Navbar */}
          <div id="markets-section" className="space-y-4" style={{ scrollMarginTop: '80px' }}>
            {/* Tabs BTC / ETH */}
            <div className="flex rounded-xl overflow-hidden border border-border bg-surface/50">
              {([0, 1] as MarketId[]).map(id => (
                <button
                  key={id}
                  onClick={() => setActiveMarket(id)}
                  className={[
                    'flex-1 py-3 font-orbitron text-sm font-bold tracking-widest uppercase transition-all duration-200',
                    activeMarket === id
                      ? 'bg-neon-cyan/10 text-neon-cyan border-b-2 border-neon-cyan'
                      : 'text-slate-500 hover:text-slate-300',
                  ].join(' ')}
                >
                  {id === 0 ? '₿ BTC/USD' : 'Ξ ETH/USD'}
                </button>
              ))}
            </div>

            <MarketCard key={activeMarket} marketId={activeMarket} />
          </div>
        </div>

        {!isConnected && (
          <div className="mt-10 text-center">
            <p className="text-slate-600 font-mono text-xs tracking-widest uppercase">
              Conectá tu wallet MetaMask o compatible con Ethereum para empezar
            </p>
          </div>
        )}
      </div>
    </main>
  )
}
