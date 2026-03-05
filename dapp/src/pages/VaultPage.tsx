/**
 * VaultPage — página dedicada al Flash Vault.
 *
 * Layout centrado con el VaultSection como protagonista.
 */
import { useAccount, useChainId, useSwitchChain } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import { VaultSection } from '../components/sections/VaultSection'

export function VaultPage() {
  const { isConnected } = useAccount()
  const chainId = useChainId()
  const { switchChain } = useSwitchChain()

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
            FLASH<span className="text-neon-cyan">VAULT</span>
          </h1>
          <p className="text-slate-500 font-mono text-sm max-w-lg mx-auto">
            Depositá USDT · Obtené $FLASH
          </p>
        </div>

        {/* ── VaultSection centrado ─────────────────────── */}
        <div className="max-w-lg mx-auto">
          <VaultSection />
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
