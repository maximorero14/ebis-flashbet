/**
 * AdminPage — dashboard exclusivo para el deployer del protocolo.
 *
 * Solo accesible si la wallet conectada es el owner del FlashVault (Ownable).
 *
 * Muestra:
 *   - Gestión de rondas: abrir / cerrar BTC y ETH
 *   - Estadísticas globales de apuestas (bettors, volume, fees, ganadores)
 *   - Top 5 wallets ganadoras y perdedoras
 *   - Yield de Aave: pendiente y total cosechado
 *   - Botón para ejecutar harvestYield() y mover yield al Treasury
 */
import { useEffect }        from 'react'
import { useAccount }       from 'wagmi'
import { GlassCard }        from '../components/ui/GlassCard'
import { NeonButton }       from '../components/ui/NeonButton'
import { TxStatus }         from '../components/ui/TxStatus'
import { useAdminStats }    from '../hooks/useAdminStats'
import { usePredMarket, RoundPhase } from '../hooks/usePredMarket'
import type { MarketId }    from '../hooks/usePredMarket'
import { useRoundTimer }    from '../hooks/useRoundTimer'
import { formatFlash, shortAddress } from '../utils/format'
import type { WalletStats } from '../hooks/useAdminStats'

export function AdminPage() {
  const { isConnected } = useAccount()

  const {
    isAdmin,
    stats,
    loading,
    error,
    fetchStats,
    harvestYield,
    harvestTxHash,
    isHarvestPending,
    isHarvestConfirming,
    isHarvestSuccess,
    harvestError,
  } = useAdminStats()

  // ── Wallet no conectada ──────────────────────────────
  if (!isConnected) {
    return (
      <main className="min-h-screen bg-cyber-grid bg-cyber-grid relative">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
          <div className="flex flex-col items-center justify-center gap-4">
            <div className="text-4xl">🔒</div>
            <p className="text-slate-500 font-mono text-sm">
              Conectá tu wallet para acceder al panel de administración
            </p>
          </div>
        </div>
      </main>
    )
  }

  // ── No es admin ──────────────────────────────────────
  if (!isAdmin) {
    return (
      <main className="min-h-screen bg-cyber-grid bg-cyber-grid relative">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
          <div className="flex flex-col items-center justify-center gap-4">
            <div className="text-5xl">⛔</div>
            <h2 className="font-orbitron text-xl font-bold text-down tracking-wider">
              Acceso Denegado
            </h2>
            <p className="text-slate-500 font-mono text-sm text-center max-w-sm">
              Esta sección solo está disponible para el deployer del protocolo.
            </p>
          </div>
        </div>
      </main>
    )
  }

  // ── Admin dashboard ──────────────────────────────────
  return (
    <main className="min-h-screen bg-cyber-grid bg-cyber-grid relative">
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">

      {/* Header */}
      <div className="mb-8 flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="px-2 py-0.5 rounded text-xs font-mono font-bold bg-purple-500/20 text-purple-400 border border-purple-500/30 uppercase tracking-widest">
              Admin
            </span>
          </div>
          <h1 className="font-orbitron text-2xl font-bold text-white tracking-wider">
            Panel de Administración
          </h1>
          <p className="text-xs text-slate-500 font-mono mt-1">
            Estadísticas globales del protocolo FlashBet · Sepolia
          </p>
        </div>
        <NeonButton
          variant="ghost"
          size="sm"
          onClick={fetchStats}
          loading={loading}
        >
          ↻ Actualizar
        </NeonButton>
      </div>

      {loading && (
        <GlassCard>
          <div className="flex items-center justify-center gap-3 py-12 text-slate-500 font-mono text-sm">
            <span className="w-5 h-5 border-2 border-neon-cyan border-t-transparent rounded-full animate-spin" />
            Leyendo eventos on-chain...
          </div>
        </GlassCard>
      )}

      {!loading && error && (
        <GlassCard className="mb-6">
          <p className="text-down font-mono text-sm text-center py-4">{error}</p>
        </GlassCard>
      )}

      {!loading && (
        <div className="space-y-6">

          {/* ── Gestión de Rondas ── */}
          <div>
            <h2 className="font-orbitron text-sm font-bold text-slate-400 uppercase tracking-widest mb-3">
              Gestión de Rondas
            </h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <RoundControl marketId={0} label="BTC / USD" />
              <RoundControl marketId={1} label="ETH / USD" />
            </div>
          </div>

          {/* ── Métricas de apuestas ── */}
          <div>
            <h2 className="font-orbitron text-sm font-bold text-slate-400 uppercase tracking-widest mb-3">
              Métricas de Apuestas
            </h2>
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
              <StatCard
                label="Total Apuestas"
                value={stats.totalBets.toLocaleString()}
                unit="bets"
                color="cyan"
              />
              <StatCard
                label="Apostadores Únicos"
                value={stats.uniqueBettors.toLocaleString()}
                unit="wallets"
                color="purple"
              />
              <StatCard
                label="Ganadores Únicos"
                value={stats.totalWinners.toLocaleString()}
                unit="wallets"
                color="up"
              />
              <StatCard
                label="Volumen Total"
                value={formatFlash(stats.totalVolume)}
                unit="FLASH"
                color="cyan"
              />
              <StatCard
                label="Fees al Treasury"
                value={formatFlash(stats.totalFees)}
                unit="FLASH"
                color="gold"
              />
            </div>
          </div>

          {/* ── Yield ── */}
          <div>
            <h2 className="font-orbitron text-sm font-bold text-slate-400 uppercase tracking-widest mb-3">
              Yield de Aave
            </h2>
            <GlassCard>
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-5">
                <div>
                  <p className="text-xs text-slate-500 font-mono uppercase tracking-wider mb-1">
                    USDT en Aave
                  </p>
                  <p className="font-mono text-lg text-green-400 font-bold">
                    {formatFlash(stats.totalDeposited)}{' '}
                    <span className="text-sm text-slate-500 font-normal">USDT</span>
                  </p>
                  <p className="text-xs text-slate-600 font-mono mt-0.5">
                    capital generando yield
                  </p>
                </div>
                <div>
                  <p className="text-xs text-slate-500 font-mono uppercase tracking-wider mb-1">
                    Yield Pendiente
                  </p>
                  <p className="font-mono text-lg text-neon-cyan font-bold">
                    {formatFlash(stats.pendingYield)}{' '}
                    <span className="text-sm text-slate-500 font-normal">USDT</span>
                  </p>
                  <p className="text-xs text-slate-600 font-mono mt-0.5">
                    listo para cosechar
                  </p>
                </div>
                <div>
                  <p className="text-xs text-slate-500 font-mono uppercase tracking-wider mb-1">
                    Treasury $FLASH
                  </p>
                  <p className="font-mono text-lg text-yellow-400 font-bold">
                    {formatFlash(stats.treasuryFlashBalance)}{' '}
                    <span className="text-sm text-slate-500 font-normal">FLASH</span>
                  </p>
                  <p className="text-xs text-slate-600 font-mono mt-0.5">
                    fees acumulados
                  </p>
                </div>
                <div>
                  <p className="text-xs text-slate-500 font-mono uppercase tracking-wider mb-1">
                    Treasury USDT
                  </p>
                  <p className="font-mono text-lg text-purple-400 font-bold">
                    {formatFlash(stats.treasuryUsdtBalance)}{' '}
                    <span className="text-sm text-slate-500 font-normal">USDT</span>
                  </p>
                  <p className="text-xs text-slate-600 font-mono mt-0.5">
                    yield cosechado
                  </p>
                </div>
              </div>

              <div className="flex flex-col sm:flex-row items-start sm:items-center gap-3 mb-5">
                <NeonButton
                  variant="cyan"
                  onClick={harvestYield}
                  loading={isHarvestPending || isHarvestConfirming}
                  disabled={stats.pendingYield === 0n}
                >
                  ↻ Harvest Yield
                </NeonButton>
                {stats.pendingYield === 0n && (
                  <p className="text-xs text-slate-600 font-mono">
                    Sin yield disponible
                  </p>
                )}
              </div>

              <TxStatus
                isPending={isHarvestPending}
                isConfirming={isHarvestConfirming}
                isSuccess={isHarvestSuccess}
                hash={harvestTxHash}
                error={harvestError}
                label="Harvest Yield"
              />
            </GlassCard>
          </div>

          {/* ── Top Wallets ── */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">

            {/* Top Ganadores */}
            <div>
              <h2 className="font-orbitron text-sm font-bold text-slate-400 uppercase tracking-widest mb-3">
                Top 5 Wallets Ganadoras
              </h2>
              <GlassCard padding="none">
                {stats.topWinners.length === 0 ? (
                  <p className="text-slate-600 font-mono text-sm text-center py-8">
                    Sin datos aún
                  </p>
                ) : (
                  <table className="w-full text-sm font-mono">
                    <thead>
                      <tr className="border-b border-border/50">
                        <th className="px-4 py-3 text-left text-xs text-slate-500 uppercase tracking-widest">#</th>
                        <th className="px-4 py-3 text-left text-xs text-slate-500 uppercase tracking-widest">Wallet</th>
                        <th className="px-4 py-3 text-right text-xs text-slate-500 uppercase tracking-widest">Apostado</th>
                        <th className="px-4 py-3 text-right text-xs text-slate-500 uppercase tracking-widest">Cobrado</th>
                      </tr>
                    </thead>
                    <tbody>
                      {stats.topWinners.map((w, i) => (
                        <WalletRow
                          key={w.address}
                          rank={i + 1}
                          wallet={w}
                          variant="winner"
                        />
                      ))}
                    </tbody>
                  </table>
                )}
              </GlassCard>
            </div>

            {/* Top Perdedores */}
            <div>
              <h2 className="font-orbitron text-sm font-bold text-slate-400 uppercase tracking-widest mb-3">
                Top 5 Wallets Perdedoras
              </h2>
              <GlassCard padding="none">
                {stats.topLosers.length === 0 ? (
                  <p className="text-slate-600 font-mono text-sm text-center py-8">
                    Sin datos aún
                  </p>
                ) : (
                  <table className="w-full text-sm font-mono">
                    <thead>
                      <tr className="border-b border-border/50">
                        <th className="px-4 py-3 text-left text-xs text-slate-500 uppercase tracking-widest">#</th>
                        <th className="px-4 py-3 text-left text-xs text-slate-500 uppercase tracking-widest">Wallet</th>
                        <th className="px-4 py-3 text-right text-xs text-slate-500 uppercase tracking-widest">Apostado</th>
                        <th className="px-4 py-3 text-right text-xs text-slate-500 uppercase tracking-widest">Pérdida Neta</th>
                      </tr>
                    </thead>
                    <tbody>
                      {stats.topLosers.map((w, i) => (
                        <WalletRow
                          key={w.address}
                          rank={i + 1}
                          wallet={w}
                          variant="loser"
                        />
                      ))}
                    </tbody>
                  </table>
                )}
              </GlassCard>
            </div>

          </div>
        </div>
      )}
    </div>
    </main>
  )
}

// ── Sub-componentes ──────────────────────────────────────

// ── RoundControl ─────────────────────────────────────────

interface RoundControlProps {
  marketId: MarketId
  label:    string
}

const phaseInfo: Record<number, { label: string; cls: string }> = {
  0: { label: 'IDLE',     cls: 'text-slate-400 bg-slate-500/10 border-slate-500/30' },
  1: { label: 'OPEN',     cls: 'text-up bg-up/10 border-up/30' },
  2: { label: 'RESOLVED', cls: 'text-purple-400 bg-purple-400/10 border-purple-400/30' },
}

function RoundControl({ marketId, label }: RoundControlProps) {
  const {
    round,
    roundDuration,
    phase,
    openRound,
    resolveRound,
    isWritePending,
    isTxConfirming,
    isTxSuccess,
    txHash,
    writeError,
    refetch,
  } = usePredMarket(marketId)

  useEffect(() => {
    if (isTxSuccess) refetch()
  }, [isTxSuccess])

  const timeLeft = useRoundTimer(round?.openedAt, roundDuration)

  const isOpen    = phase === RoundPhase.Open
  const isExpired = isOpen && timeLeft === 0
  const isBusy    = isWritePending || isTxConfirming

  const { label: phaseLabel, cls: phaseColor } = phaseInfo[phase] ?? phaseInfo[0]

  return (
    <GlassCard>
      <div className="flex items-start justify-between mb-4">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="font-orbitron text-base font-bold text-white">{label}</span>
            <span className={`px-2 py-0.5 rounded text-xs font-mono font-bold border uppercase tracking-widest ${phaseColor}`}>
              {phaseLabel}
            </span>
          </div>
          {round && round.id > 0n && (
            <p className="text-xs text-slate-500 font-mono">Ronda #{round.id.toString()}</p>
          )}
        </div>
        {isOpen && (
          <div className="text-right">
            <p className="text-xs text-slate-500 font-mono uppercase tracking-wider mb-0.5">
              Tiempo restante
            </p>
            <p className={`font-mono text-xl font-bold tabular-nums ${timeLeft === 0 ? 'text-down' : 'text-neon-cyan'}`}>
              {timeLeft}s
            </p>
          </div>
        )}
      </div>

      {!isOpen ? (
        <NeonButton variant="cyan" onClick={openRound} loading={isBusy}>
          ▶ Abrir Ronda
        </NeonButton>
      ) : (
        <NeonButton
          variant={isExpired ? 'purple' : 'ghost'}
          onClick={resolveRound}
          loading={isBusy}
          disabled={!isExpired}
        >
          {isExpired ? '■ Cerrar Ronda' : `⏳ ${timeLeft}s para cerrar`}
        </NeonButton>
      )}

      <TxStatus
        isPending={isWritePending}
        isConfirming={isTxConfirming}
        isSuccess={isTxSuccess}
        hash={txHash}
        error={writeError as Error | null}
        label={isOpen ? 'Cerrar Ronda' : 'Abrir Ronda'}
      />
    </GlassCard>
  )
}

// ── StatCard ──────────────────────────────────────────────

interface StatCardProps {
  label: string
  value: string
  unit:  string
  color: 'cyan' | 'purple' | 'up' | 'down' | 'gold'
}

const colorMap: Record<StatCardProps['color'], string> = {
  cyan:   'text-neon-cyan',
  purple: 'text-purple-400',
  up:     'text-up',
  down:   'text-down',
  gold:   'text-yellow-400',
}

function StatCard({ label, value, unit, color }: StatCardProps) {
  return (
    <div className="rounded-xl bg-surface border border-border p-4">
      <p className="text-xs text-slate-500 font-mono uppercase tracking-wider mb-2">{label}</p>
      <p className={`font-mono text-xl font-bold ${colorMap[color]}`}>{value}</p>
      <p className="text-xs text-slate-600 font-mono mt-0.5">{unit}</p>
    </div>
  )
}

interface WalletRowProps {
  rank:    number
  wallet:  WalletStats
  variant: 'winner' | 'loser'
}

function WalletRow({ rank, wallet, variant }: WalletRowProps) {
  return (
    <tr className="border-b border-border/20 hover:bg-white/2 transition-colors">
      <td className="px-4 py-3 text-slate-500">
        {rank === 1 ? (
          <span>{variant === 'winner' ? '🥇' : '💀'}</span>
        ) : rank === 2 ? (
          <span>{variant === 'winner' ? '🥈' : '💀'}</span>
        ) : rank === 3 ? (
          <span>{variant === 'winner' ? '🥉' : '💀'}</span>
        ) : (
          <span className="text-slate-600">#{rank}</span>
        )}
      </td>
      <td className="px-4 py-3">
        <span className={variant === 'winner' ? 'text-up' : 'text-down'}>
          {shortAddress(wallet.address)}
        </span>
        <span className="text-slate-600 text-xs ml-1">({wallet.betCount} apuestas)</span>
      </td>
      <td className="px-4 py-3 text-right text-slate-400 whitespace-nowrap">
        {formatFlash(wallet.totalBet)}
      </td>
      <td className="px-4 py-3 text-right whitespace-nowrap">
        {variant === 'winner' ? (
          <span className="text-up font-bold">{formatFlash(wallet.totalClaimed)}</span>
        ) : (
          <span className="text-down font-bold">-{formatFlash(wallet.totalLost)}</span>
        )}
      </td>
    </tr>
  )
}
