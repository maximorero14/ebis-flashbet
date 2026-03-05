/**
 * HistoryPage — historial de rondas del usuario.
 *
 * Usa el subgraph de FlashBet (The Graph) via useHistory() para obtener
 * las apuestas indexadas on-chain. Requiere VITE_GRAPH_URL en .env.local.
 */
import { useState, useEffect } from 'react'
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { sepolia } from 'wagmi/chains'
import { GlassCard } from '../components/ui/GlassCard'
import { NeonButton } from '../components/ui/NeonButton'
import { TxStatus } from '../components/ui/TxStatus'
import { CONTRACTS } from '../config/contracts'
import { FlashPredMarketABI } from '../abi/FlashPredMarket'
import { formatFlash, formatPrice } from '../utils/format'
import { useHistory, GRAPH_URL } from '../hooks/useHistory'

const addr = CONTRACTS[sepolia.id]

/** Tamaño de página */
const PAGE_SIZE = 10

/** Formatea un timestamp Unix (segundos) a "DD/MM/YYYY HH:MM:SS" */
function formatTimestamp(ts: bigint | undefined): string {
  if (!ts || ts === 0n) return '—'
  const d = new Date(Number(ts) * 1000)
  const pad = (n: number) => n.toString().padStart(2, '0')
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}

export function HistoryPage() {
  const { isConnected } = useAccount()
  const [page, setPage] = useState(0)

  // Leer ROUND_DURATION para determinar si una ronda no resuelta expiró
  const { data: roundDurationData } = useReadContract({
    address: addr.FlashPredMarket,
    abi: FlashPredMarketABI,
    functionName: 'ROUND_DURATION',
  })
  const roundDuration = (roundDurationData as bigint | undefined) ?? 300n

  // Historial via The Graph
  const { data: rows = [], isLoading: loading, error, refetch } = useHistory()

  // ── Claim desde History ─────────────────────────
  /** Key de la fila que se está reclamando: `${marketId}-${roundId}` */
  const [claimingKey, setClaimingKey] = useState<string | null>(null)

  const {
    writeContract,
    data: claimTxHash,
    isPending: isClaimPending,
    error: claimError,
  } = useWriteContract()

  const { isLoading: isClaimConfirming, isSuccess: isClaimSuccess } =
    useWaitForTransactionReceipt({ hash: claimTxHash })

  /** Llamar claimPayout desde la tabla de historial */
  const handleClaim = (marketId: number, roundId: bigint) => {
    setClaimingKey(`${marketId}-${roundId}`)
    writeContract({
      address: addr.FlashPredMarket,
      abi: FlashPredMarketABI,
      functionName: 'claimPayout',
      args: [marketId, roundId],
    })
  }

  // Refrescar historial tras claim exitoso
  useEffect(() => {
    if (isClaimSuccess) {
      setClaimingKey(null)
      refetch()
    }
  }, [isClaimSuccess])

  const totalPages = Math.ceil(rows.length / PAGE_SIZE)
  const pageRows = rows.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE)

  /** Determina si una ronda expiró (tiempo agotado) aunque no esté resuelta on-chain */
  const isExpired = (openedAt: bigint) =>
    openedAt > 0n && BigInt(Math.floor(Date.now() / 1000)) > openedAt + roundDuration

  if (!isConnected) {
    return (
      <main className="min-h-screen bg-cyber-grid bg-cyber-grid relative">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
          <div className="text-center py-20">
            <p className="text-slate-500 font-mono text-sm">
              Conectá tu wallet para ver tu historial
            </p>
          </div>
        </div>
      </main>
    )
  }

  if (!GRAPH_URL) {
    return (
      <main className="min-h-screen bg-cyber-grid bg-cyber-grid relative">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
          <GlassCard>
            <p className="text-yellow-500 font-mono text-sm text-center py-8">
              Configurá <code className="text-neon-cyan">VITE_GRAPH_URL</code> en{' '}
              <code className="text-slate-400">.env.local</code> para ver el historial
            </p>
          </GlassCard>
        </div>
      </main>
    )
  }

  return (
    <main className="min-h-screen bg-cyber-grid bg-cyber-grid relative">
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div className="mb-8 flex items-center justify-between">
        <div>
          <h1 className="font-orbitron text-2xl font-bold text-white tracking-wider">
            Historial de Rondas
          </h1>
          <p className="text-xs text-slate-500 font-mono mt-1">
            Todas tus apuestas en FlashPredMarket · Sepolia
          </p>
        </div>
        <NeonButton
          variant="ghost"
          size="sm"
          onClick={() => refetch()}
          loading={loading}
        >
          ↻ Actualizar
        </NeonButton>
      </div>

      {loading && (
        <GlassCard>
          <div className="flex items-center justify-center gap-3 py-12 text-slate-500 font-mono text-sm">
            <span className="w-5 h-5 border-2 border-neon-cyan border-t-transparent rounded-full animate-spin" />
            Cargando historial...
          </div>
        </GlassCard>
      )}

      {/* Mostrar error solo si no hay resultados */}
      {!loading && error && rows.length === 0 && (
        <GlassCard>
          <p className="text-down font-mono text-sm text-center py-8">
            Error al cargar el historial. Intentá de nuevo.
          </p>
        </GlassCard>
      )}

      {!loading && !error && rows.length === 0 && (
        <GlassCard>
          <div className="text-center py-12 space-y-2">
            <p className="text-slate-500 font-mono text-sm">
              No encontramos apuestas para esta wallet
            </p>
            <p className="text-xs text-slate-700 font-mono">
              Volvé después de participar en una ronda
            </p>
          </div>
        </GlassCard>
      )}

      {/* Estado del claim (se muestra mientras se procesa) */}
      {claimingKey && (
        <div className="mb-4">
          <TxStatus
            isPending={isClaimPending}
            isConfirming={isClaimConfirming}
            isSuccess={isClaimSuccess}
            hash={claimTxHash}
            error={claimError}
            label="Claim de premio"
          />
        </div>
      )}

      {!loading && rows.length > 0 && (
        <GlassCard padding="none">
          {/* Tabla — sin scroll horizontal */}
          <div className="overflow-x-hidden">
            <table className="w-full text-xs font-mono">
              <thead>
                <tr className="border-b border-border/50">
                  {['Round', 'Market', 'Abierto', 'Cerrado', 'Ref Price', 'Final Price', 'Resultado', 'Pool', 'Mi Apuesta', 'Mi Payout'].map(h => (
                    <th key={h} className="px-2 py-3 text-left text-xs text-slate-500 uppercase tracking-widest whitespace-nowrap">
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {pageRows.map((row, i) => {
                  const userWon =
                    row.resolvedOnChain &&
                    row.totalPool > 0n &&
                    ((row.upWon && row.myBetDir === 0) || (!row.upWon && row.myBetDir === 1))

                  const rowKey = `${row.marketId}-${row.roundId}`
                  const isThisRow = claimingKey === rowKey
                  const isRowLoading = isThisRow && (isClaimPending || isClaimConfirming)

                  // Estado de la ronda para mostrar en "Cerrado" y "Mi Payout"
                  const expired = !row.resolvedOnChain && isExpired(row.openedAt)

                  return (
                    <tr
                      key={rowKey}
                      className={`border-b border-border/20 hover:bg-white/2 transition-colors
                        ${i % 2 === 0 ? '' : 'bg-white/1'}`}
                    >
                      {/* Round */}
                      <td className="px-2 py-3 text-slate-400">
                        #{row.roundId.toString()}
                      </td>

                      {/* Market */}
                      <td className="px-2 py-3 text-white">
                        {row.marketId === 0 ? '₿ BTC' : 'Ξ ETH'}
                      </td>

                      {/* Abierto */}
                      <td className="px-2 py-3 text-slate-400 whitespace-nowrap text-xs">
                        {formatTimestamp(row.openedAt)}
                      </td>

                      {/* Cerrado */}
                      <td className="px-2 py-3 whitespace-nowrap text-xs">
                        {row.closedAt > 0n ? (
                          // Tenemos timestamp exacto del evento RoundResolved
                          <span className="text-slate-400">{formatTimestamp(row.closedAt)}</span>
                        ) : row.resolvedOnChain ? (
                          // Resuelta vía contrato pero sin closedAt (estimado)
                          <span className="text-slate-400">{formatTimestamp(row.openedAt + roundDuration)}</span>
                        ) : expired ? (
                          <span className="text-yellow-600">Expirada</span>
                        ) : (
                          <span className="text-slate-600">En curso</span>
                        )}
                      </td>

                      {/* Ref Price — del evento RoundOpened */}
                      <td className="px-2 py-3 text-slate-300">
                        {row.refPrice > 0n ? `$${formatPrice(row.refPrice)}` : '—'}
                      </td>

                      {/* Final Price */}
                      <td className={`px-2 py-3 ${row.upWon ? 'text-up' : 'text-down'}`}>
                        {row.finalPrice > 0n ? `$${formatPrice(row.finalPrice)}` : '—'}
                      </td>

                      {/* Resultado */}
                      <td className="px-2 py-3">
                        {row.resolvedOnChain ? (
                          <span className={`px-2 py-0.5 rounded text-xs font-bold
                            ${row.upWon
                              ? 'bg-up/10 text-up border border-up/20'
                              : 'bg-down/10 text-down border border-down/20'}`}>
                            {row.upWon ? '▲ UP' : '▼ DOWN'}
                          </span>
                        ) : expired ? (
                          <span className="text-yellow-600 text-xs">Sin resolver</span>
                        ) : (
                          <span className="text-slate-600">Pendiente</span>
                        )}
                      </td>

                      {/* Pool */}
                      <td className="px-2 py-3 text-slate-400 whitespace-nowrap">
                        {row.totalPool > 0n ? `${formatFlash(row.totalPool)} FLASH` : '—'}
                      </td>

                      {/* Mi Apuesta */}
                      <td className={`px-2 py-3 whitespace-nowrap
                        ${row.myBetDir === 0 ? 'text-up' : 'text-down'}`}>
                        {formatFlash(row.myBetAmount)}{' '}
                        {row.myBetDir === 0 ? '▲ UP' : '▼ DOWN'}
                      </td>

                      {/* Mi Payout — con botón Claim si corresponde */}
                      <td className="px-2 py-3 whitespace-nowrap">
                        {row.claimed ? (
                          <span className="text-yellow-400">
                            🏆 {formatFlash(row.myPayout)} FLASH
                          </span>
                        ) : userWon ? (
                          // Premio ganado no cobrado — mostrar botón Claim
                          <button
                            onClick={() => handleClaim(row.marketId, row.roundId)}
                            disabled={!!claimingKey}
                            className={[
                              'px-3 py-1 rounded text-xs font-bold font-mono transition-all',
                              'border border-yellow-400/40 text-yellow-400',
                              'hover:bg-yellow-400/10 hover:border-yellow-400',
                              'disabled:opacity-40 disabled:cursor-not-allowed',
                              isRowLoading ? 'animate-pulse' : '',
                            ].join(' ')}
                          >
                            {isRowLoading ? '⏳ Claiming...' : '🏆 Claim'}
                          </button>
                        ) : row.resolvedOnChain ? (
                          <span className="text-slate-600">—</span>
                        ) : expired ? (
                          <span className="text-slate-600 text-xs">Sin resolver</span>
                        ) : (
                          <span className="text-slate-700 text-xs">En curso</span>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>

          {/* Paginación */}
          {totalPages > 1 && (
            <div className="flex items-center justify-between px-4 py-3 border-t border-border/50">
              <p className="text-xs text-slate-600 font-mono">
                {rows.length} apuestas · Página {page + 1}/{totalPages}
              </p>
              <div className="flex gap-2">
                <NeonButton
                  variant="ghost"
                  size="sm"
                  disabled={page === 0}
                  onClick={() => setPage(p => p - 1)}
                >
                  ← Prev
                </NeonButton>
                <NeonButton
                  variant="ghost"
                  size="sm"
                  disabled={page >= totalPages - 1}
                  onClick={() => setPage(p => p + 1)}
                >
                  Next →
                </NeonButton>
              </div>
            </div>
          )}
        </GlassCard>
      )}
    </div>
    </main>
  )
}
