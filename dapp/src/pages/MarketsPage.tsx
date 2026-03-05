/**
 * MarketsPage — página dedicada al mercado de predicción.
 *
 * Layout de 2 columnas para aprovechar el espacio completo de la pantalla:
 *   Columna izquierda (60%): gráfico de precio en vivo (grande) + pool bar
 *   Columna derecha  (40%): panel de acciones según la fase de la ronda
 *
 * Las fases y toda la lógica se manejan con usePredMarket (mismo hook que MarketCard).
 */
import { useEffect, useState }     from 'react'
import { useAccount, useChainId, useSwitchChain } from 'wagmi'
import { sepolia }                 from 'wagmi/chains'
import { GlassCard }               from '../components/ui/GlassCard'
import { NeonButton }              from '../components/ui/NeonButton'
import { CountdownTimer }          from '../components/ui/CountdownTimer'
import { PoolBar }                 from '../components/ui/PoolBar'
import { TxStatus }                from '../components/ui/TxStatus'
import { PriceChart }              from '../components/ui/PriceChart'
import { ClaimBanner }             from '../components/sections/ClaimBanner'
import { usePredMarket, RoundPhase, BetDir } from '../hooks/usePredMarket'
import type { MarketId }           from '../hooks/usePredMarket'
import { useRoundTimer }           from '../hooks/useRoundTimer'
import { formatFlash, formatPrice, calcPayout, calcMultiplier } from '../utils/format'

const MARKET_META: Record<MarketId, { symbol: string; icon: string; label: string }> = {
  0: { symbol: 'BTC', icon: '₿', label: 'BTC/USD' },
  1: { symbol: 'ETH', icon: 'Ξ', label: 'ETH/USD' },
}

const FEE_BPS = 100n

// ─────────────────────────────────────────────────────────────────────────────
// Sub-componente: panel de mercado completo (chart izquierda + acciones derecha)
// ─────────────────────────────────────────────────────────────────────────────
function MarketContent({ marketId, isConnected }: { marketId: MarketId; isConnected: boolean }) {
  const meta = MARKET_META[marketId]

  const {
    round, roundCount, roundDuration, phase,
    userBet, hasUserBet, userBetDir,
    flashBalance,
    needsApproval,
    insufficientBalance,
    betInput, setBetInput, parsedBet,
    placeBetWithApprove, claimPayout,
    txHash, txStep, isWritePending, isTxConfirming, isTxSuccess, writeError,
    refetch,
  } = usePredMarket(marketId)

  const timeLeft = useRoundTimer(round?.openedAt, roundDuration)

  useEffect(() => {
    if (isTxSuccess) {
      setBetInput('')
      refetch()
    }
  }, [isTxSuccess])

  // ── Cálculos derivados ──────────────────────────────
  const netAmount     = parsedBet > 0n ? parsedBet - (parsedBet * FEE_BPS / 10_000n) : 0n
  const feeAmount     = parsedBet > 0n ? parsedBet * FEE_BPS / 10_000n : 0n
  const totalPool     = (round?.totalUp ?? 0n) + (round?.totalDown ?? 0n)
  const estPayoutUp   = calcPayout(netAmount, totalPool + netAmount, (round?.totalUp ?? 0n) + netAmount)
  const estPayoutDown = calcPayout(netAmount, totalPool + netAmount, (round?.totalDown ?? 0n) + netAmount)
  const multUp        = calcMultiplier((round?.totalUp ?? 0n) + netAmount, totalPool + netAmount)
  const multDown      = calcMultiplier((round?.totalDown ?? 0n) + netAmount, totalPool + netAmount)
  const canResolve    = phase === RoundPhase.Open && timeLeft === 0

  const userWon =
    phase === RoundPhase.Resolved &&
    hasUserBet &&
    !userBet?.claimed &&
    userBet?.amount !== undefined && userBet.amount > 0n &&
    ((round?.upWon && userBetDir === BetDir.UP) || (!round?.upWon && userBetDir === BetDir.DOWN))

  const phaseLabel =
    phase === RoundPhase.Open     ? { text: '● OPEN',     cls: 'text-green-400' } :
    phase === RoundPhase.Resolved ? { text: '■ RESOLVED', cls: 'text-yellow-400' } :
                                    { text: '○ IDLE',     cls: 'text-slate-500' }

  const isBetLoading  = isWritePending || isTxConfirming || txStep !== 'idle'
  const betStepLabel  =
    txStep === 'approving' ? 'Aprobando FLASH...' :
    txStep === 'placing'   ? 'Apostando...'        : null

  return (
    <div className="grid grid-cols-1 lg:grid-cols-5 gap-6 items-start">

      {/* ══ Columna izquierda: gráfico + pool ══════════════════════════════ */}
      <div className="lg:col-span-3 space-y-4">
        <GlassCard>
          {/* Header del gráfico */}
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="font-orbitron text-xl font-bold text-white tracking-wider">
                {meta.icon} {meta.label}
              </h2>
              {round && round.referencePrice > 0n && (
                <p className="font-mono text-sm text-neon-cyan mt-0.5">
                  REF: ${formatPrice(round.referencePrice)}
                </p>
              )}
            </div>
            <div className="flex flex-col items-end gap-1">
              <span className={`text-xs font-mono font-bold ${phaseLabel.cls}`}>
                {phaseLabel.text}
              </span>
              {roundCount > 0n && (
                <span className="text-xs text-slate-600 font-mono">
                  Ronda #{(roundCount - 1n).toString()}
                </span>
              )}
            </div>
          </div>

          {/* Gráfico grande */}
          <PriceChart
            marketId={marketId}
            referencePrice={phase === RoundPhase.Open ? round?.referencePrice : undefined}
            showRefLine={phase === RoundPhase.Open}
            chartHeight={280}
          />
        </GlassCard>

        {/* Pool bar — card separada para darle protagonismo */}
        <GlassCard padding="sm">
          <p className="text-xs text-slate-500 font-mono uppercase tracking-wider mb-3 px-2">
            Pool Distribution
          </p>
          <PoolBar totalUp={round?.totalUp ?? 0n} totalDown={round?.totalDown ?? 0n} />
          {totalPool > 0n && (
            <p className="text-xs text-slate-600 font-mono mt-3 px-2">
              Total acumulado:{' '}
              <span className="text-white">{formatFlash(totalPool)} FLASH</span>
            </p>
          )}
        </GlassCard>
      </div>

      {/* ══ Columna derecha: panel de acciones ════════════════════════════ */}
      <div className="lg:col-span-2">
        <GlassCard className="min-h-[420px]">

          {/* ── IDLE ─────────────────────────────────── */}
          {phase === RoundPhase.Idle && (
            <div className="flex flex-col items-center justify-center min-h-[380px] gap-6 text-center">
              <div className="space-y-3">
                <div className="text-5xl opacity-10 font-orbitron text-neon-cyan">○</div>
                <h3 className="font-orbitron text-base font-bold text-slate-400 tracking-wider">
                  Sin Ronda Activa
                </h3>
                <p className="text-slate-500 font-mono text-sm max-w-xs">
                  El administrador abrirá una nueva ronda pronto.
                </p>
              </div>
            </div>
          )}

          {/* ── OPEN ─────────────────────────────────── */}
          {phase === RoundPhase.Open && (
            <div className="space-y-5">
              {/* Countdown */}
              <CountdownTimer seconds={timeLeft} totalSeconds={Number(roundDuration)} />

              {/* Apuesta del usuario (si ya apostó) */}
              {hasUserBet && userBetDir !== null && (
                <div className={`rounded-lg px-4 py-3 border text-sm font-mono
                  ${userBetDir === BetDir.UP
                    ? 'border-up/30 bg-up/5 text-up'
                    : 'border-down/30 bg-down/5 text-down'}`}
                >
                  Ya apostaste: {formatFlash(userBet?.amount ?? 0n)} FLASH{' '}
                  {userBetDir === BetDir.UP ? '▲ UP' : '▼ DOWN'}
                </div>
              )}

              {/* Formulario de apuesta */}
              {isConnected && !canResolve && (
                <div className="space-y-4">
                  <div>
                    <div className="flex justify-between items-center mb-1.5">
                      <label className="text-xs text-slate-500 font-mono uppercase tracking-wider">
                        Amount ($FLASH)
                      </label>
                      <span className="text-xs text-slate-600 font-mono">
                        Balance: {formatFlash(flashBalance)}
                      </span>
                    </div>
                    <input
                      type="number"
                      min="0"
                      step="0.000001"
                      value={betInput}
                      onChange={e => setBetInput(e.target.value)}
                      placeholder="0.00"
                      disabled={hasUserBet}
                      className="w-full bg-surface border border-border rounded-lg px-3 py-2.5 font-mono text-sm text-white placeholder-slate-600 focus:outline-none focus:border-neon-cyan/50 transition-colors disabled:opacity-40"
                    />
                  </div>

                  {insufficientBalance && (
                    <div className="flex items-center gap-2 px-3 py-2 rounded-lg border border-down/40 bg-down/10 text-down text-xs font-mono">
                      <span>✗</span>
                      <span>
                        Saldo insuficiente — tenés{' '}
                        <span className="font-bold text-white">{formatFlash(flashBalance)} FLASH</span>
                      </span>
                    </div>
                  )}

                  {parsedBet > 0n && !insufficientBalance && (
                    <div className="text-xs font-mono text-slate-600 space-y-0.5 px-1">
                      <p>Fee 1%: <span className="text-slate-500">−{formatFlash(feeAmount)} FLASH → Treasury</span></p>
                      <p>Net al pool: <span className="text-white">{formatFlash(netAmount)} FLASH</span></p>
                      {needsApproval && (
                        <p className="text-neon-purple">⚡ Se enviará un approve automático primero</p>
                      )}
                    </div>
                  )}

                  {!hasUserBet && (
                    <div className="grid grid-cols-2 gap-3">
                      <NeonButton
                        variant="up"
                        loading={isBetLoading}
                        onClick={() => placeBetWithApprove(BetDir.UP)}
                        disabled={parsedBet === 0n || insufficientBalance}
                        title={parsedBet > 0n && !insufficientBalance ? `Retorno est.: ${formatFlash(estPayoutUp)} FLASH` : ''}
                      >
                        {betStepLabel ?? (
                          <>▲ BET UP {parsedBet > 0n && !insufficientBalance && <span className="text-xs opacity-70">{multUp}</span>}</>
                        )}
                      </NeonButton>

                      <NeonButton
                        variant="down"
                        loading={isBetLoading}
                        onClick={() => placeBetWithApprove(BetDir.DOWN)}
                        disabled={parsedBet === 0n || insufficientBalance}
                        title={parsedBet > 0n && !insufficientBalance ? `Retorno est.: ${formatFlash(estPayoutDown)} FLASH` : ''}
                      >
                        {betStepLabel ?? (
                          <>▼ BET DOWN {parsedBet > 0n && !insufficientBalance && <span className="text-xs opacity-70">{multDown}</span>}</>
                        )}
                      </NeonButton>
                    </div>
                  )}

                  <TxStatus
                    isPending={isWritePending} isConfirming={isTxConfirming}
                    isSuccess={isTxSuccess} hash={txHash} error={writeError}
                    label={txStep === 'approving' ? 'Aprobando FLASH' : 'Apuesta'}
                  />
                </div>
              )}

              {!isConnected && (
                <p className="text-center text-sm text-slate-500 font-mono py-2">
                  Conectá tu wallet para apostar
                </p>
              )}

              {/* Tiempo agotado — esperando al admin */}
              {canResolve && (
                <div className="text-center py-4">
                  <p className="text-xs text-slate-500 font-mono">
                    Tiempo agotado — el admin resolverá la ronda
                  </p>
                </div>
              )}
            </div>
          )}

          {/* ── RESOLVED ─────────────────────────────── */}
          {phase === RoundPhase.Resolved && round && (
            <div className="space-y-5">
              {/* Banner de resultado */}
              <div className={`rounded-xl border p-5 text-center
                ${round.upWon ? 'border-up/40 bg-up/5' : 'border-down/40 bg-down/5'}`}
              >
                <p className={`font-orbitron text-2xl font-black tracking-widest ${round.upWon ? 'text-up' : 'text-down'}`}>
                  {round.upWon ? '▲ UP WON 🏆' : '▼ DOWN WON 💀'}
                </p>
                <div className="flex justify-center gap-4 mt-3 text-xs font-mono text-slate-400">
                  <span>Ref: ${formatPrice(round.referencePrice)}</span>
                  <span>→</span>
                  <span className={round.upWon ? 'text-up' : 'text-down'}>
                    Final: ${formatPrice(round.finalPrice)}
                  </span>
                </div>
                <p className="text-xs text-slate-600 font-mono mt-1">
                  Pool total: {formatFlash(totalPool)} FLASH
                </p>
              </div>

              {/* Claim si ganó */}
              {userWon && round && (
                <ClaimBanner
                  roundId={round.id}
                  userBet={userBet?.amount ?? 0n}
                  totalPool={totalPool}
                  myPoolSide={round.upWon ? round.totalUp : round.totalDown}
                  onClaim={() => claimPayout(round.id)}
                  isLoading={isWritePending || isTxConfirming}
                />
              )}

              {/* Perdió */}
              {hasUserBet && !userWon && (
                <div className="rounded-lg border border-down/20 bg-down/5 px-4 py-3 text-sm font-mono text-slate-500 text-center">
                  Tu apuesta de {formatFlash(userBet?.amount ?? 0n)} FLASH{' '}
                  {userBetDir === BetDir.UP ? '▲ UP' : '▼ DOWN'} no ganó esta vez.
                </div>
              )}

              <TxStatus
                isPending={isWritePending} isConfirming={isTxConfirming}
                isSuccess={isTxSuccess} hash={txHash} error={writeError}
                label="Claim"
              />

            </div>
          )}
        </GlassCard>
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Página principal
// ─────────────────────────────────────────────────────────────────────────────
export function MarketsPage() {
  const { isConnected } = useAccount()
  const chainId         = useChainId()
  const { switchChain } = useSwitchChain()
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
        <div className="text-center mb-8">
          <h1
            className="font-orbitron text-3xl md:text-5xl font-black text-white tracking-widest mb-3"
            style={{ textShadow: '0 0 40px rgba(0,245,255,0.4)' }}
          >
            FLASH<span className="text-neon-cyan">BET</span>
          </h1>
          <p className="text-slate-500 font-mono text-sm">
            Apostá $FLASH en BTC o ETH
          </p>
        </div>

        {/* ── Tabs BTC / ETH ───────────────────────────── */}
        <div className="flex rounded-xl overflow-hidden border border-border bg-surface/50 mb-6 max-w-xs mx-auto">
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

        {/* ── Contenido del mercado ────────────────────── */}
        <MarketContent key={activeMarket} marketId={activeMarket} isConnected={isConnected} />

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
