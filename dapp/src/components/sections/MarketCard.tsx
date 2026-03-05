/**
 * MarketCard — card principal del mercado de predicción.
 *
 * Una card por mercado (BTC/USD o ETH/USD). Maneja:
 *   - Display de la ronda actual (fase, precio referencia, countdown)
 *   - Pool bar UP/DOWN
 *   - Formulario de apuesta con flujo de un solo botón (approve → bet)
 *   - Resultado de ronda resuelta + claim payout
 *   - Botón "Open New Round" cuando la ronda está Idle/Resolved
 *
 * Reglas críticas aplicadas:
 *   - 6 decimales para $FLASH
 *   - 8 decimales para precios del oracle
 *   - Un usuario solo apuesta en una dirección por ronda
 *   - Approve automático antes de bet si el allowance es insuficiente
 *   - Mostrar fee 1% y payout estimado antes de confirmar
 */
import { useEffect, useState }  from 'react'
import { useAccount }           from 'wagmi'
import { GlassCard }            from '../ui/GlassCard'
import { NeonButton }           from '../ui/NeonButton'
import { CountdownTimer }       from '../ui/CountdownTimer'
import { PoolBar }              from '../ui/PoolBar'
import { TxStatus }             from '../ui/TxStatus'
import { PriceChart }           from '../ui/PriceChart'
import { ClaimBanner }          from './ClaimBanner'
import { usePredMarket, RoundPhase, BetDir } from '../../hooks/usePredMarket'
import type { MarketId } from '../../hooks/usePredMarket'
import { useRoundTimer }        from '../../hooks/useRoundTimer'
import { formatFlash, formatPrice, calcPayout, calcMultiplier } from '../../utils/format'

/** Configuración visual por mercado */
const MARKET_META: Record<MarketId, { symbol: string; icon: string; label: string }> = {
  0: { symbol: 'BTC',  icon: '₿', label: 'BTC/USD' },
  1: { symbol: 'ETH',  icon: 'Ξ', label: 'ETH/USD' },
}

/** Fee del protocolo: 1% (100 bps) */
const FEE_BPS = 100n

interface MarketCardProps {
  marketId: MarketId
}

export function MarketCard({ marketId }: MarketCardProps) {
  const { isConnected }    = useAccount()
  const meta               = MARKET_META[marketId]

  const {
    round, roundCount, roundDuration, phase,
    userBet, hasUserBet, userBetDir,
    flashBalance,
    needsApproval,
    insufficientBalance,
    betInput, setBetInput, parsedBet,
    openRound, placeBetWithApprove, claimPayout,
    txHash, txStep, isWritePending, isTxConfirming, isTxSuccess, writeError,
    refetch,
  } = usePredMarket(marketId)

  const timeLeft    = useRoundTimer(round?.openedAt, roundDuration)
  const [showChart, setShowChart] = useState(true)

  // Auto-refrescar al confirmar tx
  useEffect(() => {
    if (isTxSuccess) {
      setBetInput('')
      refetch()
    }
  }, [isTxSuccess])

  // ── Cálculos derivados ─────────────────────────────
  /** Monto neto que entra al pool (descontado el 1% de fee) */
  const netAmount = parsedBet > 0n
    ? parsedBet - (parsedBet * FEE_BPS / 10_000n)
    : 0n

  const feeAmount = parsedBet > 0n
    ? parsedBet * FEE_BPS / 10_000n
    : 0n

  /** Payout estimado si gana UP */
  const totalPool  = (round?.totalUp ?? 0n) + (round?.totalDown ?? 0n)
  const estPayoutUp   = calcPayout(netAmount, totalPool + netAmount, (round?.totalUp ?? 0n) + netAmount)
  const estPayoutDown = calcPayout(netAmount, totalPool + netAmount, (round?.totalDown ?? 0n) + netAmount)

  const multUp   = calcMultiplier((round?.totalUp ?? 0n) + netAmount, totalPool + netAmount)
  const multDown = calcMultiplier((round?.totalDown ?? 0n) + netAmount, totalPool + netAmount)

  /** Determina si la ronda tiene que ser resuelta (tiempo agotado + fase Open) */
  const canResolve = phase === RoundPhase.Open && timeLeft === 0

  /** El usuario ganó esta ronda y todavía no reclamó */
  const userWon =
    phase === RoundPhase.Resolved &&
    hasUserBet &&
    !userBet?.claimed &&
    userBet?.amount !== undefined && userBet.amount > 0n &&
    ((round?.upWon && userBetDir === BetDir.UP) ||
     (!round?.upWon && userBetDir === BetDir.DOWN))

  // ── Indicador de fase ──────────────────────────────
  const phaseLabel =
    phase === RoundPhase.Open     ? { text: '● OPEN',     cls: 'text-green-400' } :
    phase === RoundPhase.Resolved ? { text: '■ RESOLVED', cls: 'text-yellow-400' } :
                                    { text: '○ IDLE',     cls: 'text-slate-500' }

  const isBetLoading = isWritePending || isTxConfirming || txStep !== 'idle'

  /** Etiqueta del botón de apuesta según el paso del flujo */
  const betStepLabel =
    txStep === 'approving' ? 'Aprobando FLASH...' :
    txStep === 'placing'   ? 'Apostando...' :
    null

  return (
    <GlassCard>
      {/* ── Header ──────────────────────────────────── */}
      <div className="flex items-start justify-between mb-4">
        <div>
          <h2 className="font-orbitron text-lg font-bold text-white tracking-wider">
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

      {/* ── Gráfico de precio en vivo ─────────────── */}
      <div className="mb-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-xs text-slate-600 font-mono uppercase tracking-wider">
            Live Price
          </span>
          <button
            onClick={() => setShowChart(v => !v)}
            className="text-xs text-slate-600 hover:text-neon-cyan font-mono transition-colors"
          >
            {showChart ? '▲ ocultar' : '▼ mostrar'}
          </button>
        </div>
        {showChart && (
          <PriceChart
            marketId={marketId}
            referencePrice={phase === RoundPhase.Open ? round?.referencePrice : undefined}
            showRefLine={phase === RoundPhase.Open}
          />
        )}
      </div>

      <div className="border-t border-border/30 mb-4" />

      {/* ── Estado: IDLE — sin ronda activa ─────────── */}
      {phase === RoundPhase.Idle && (
        <div className="text-center py-6 space-y-4">
          <p className="text-slate-500 font-mono text-sm">
            No hay ronda activa — ¡sé el primero en abrir una!
          </p>
          {isConnected && (
            <NeonButton
              variant="cyan"
              loading={isWritePending || isTxConfirming}
              onClick={openRound}
            >
              ⚡ Open New Round
            </NeonButton>
          )}
          <TxStatus
            isPending={isWritePending} isConfirming={isTxConfirming}
            isSuccess={isTxSuccess} hash={txHash} error={writeError}
            label="Apertura de ronda"
          />
        </div>
      )}

      {/* ── Estado: OPEN — ronda activa ─────────────── */}
      {phase === RoundPhase.Open && (
        <div className="space-y-4">
          {/* Countdown */}
          <CountdownTimer seconds={timeLeft} totalSeconds={Number(roundDuration)} />

          {/* Pool bar */}
          <PoolBar totalUp={round?.totalUp ?? 0n} totalDown={round?.totalDown ?? 0n} />

          {/* Apuesta del usuario (si ya apostó) — bloquea el form */}
          {hasUserBet && userBetDir !== null && (
            <div className={`rounded-lg px-4 py-3 border text-sm font-mono space-y-1
              ${userBetDir === BetDir.UP
                ? 'border-up/30 bg-up/5 text-up'
                : 'border-down/30 bg-down/5 text-down'}`}>
              <p className="font-bold">
                {userBetDir === BetDir.UP ? '▲ UP' : '▼ DOWN'} — {formatFlash(userBet?.amount ?? 0n)} FLASH apostado
              </p>
              <p className="text-xs text-slate-500">
                Solo se permite una apuesta por wallet por ronda.
              </p>
            </div>
          )}

          {/* Formulario de apuesta — solo visible si el usuario no apostó aún */}
          {isConnected && !hasUserBet && (
            <div className="space-y-3">
              {/* Input */}
              <div>
                <label className="text-xs text-slate-500 font-mono uppercase tracking-wider mb-1.5 block">
                  Amount ($FLASH)
                </label>
                <input
                  type="number"
                  min="0"
                  step="0.000001"
                  value={betInput}
                  onChange={e => setBetInput(e.target.value)}
                  placeholder="0.00"
                  disabled={canResolve}
                  className="w-full bg-surface border border-border rounded-lg px-3 py-2.5 font-mono text-sm text-white placeholder-slate-600 focus:outline-none focus:border-neon-cyan/50 transition-colors disabled:opacity-40"
                />
              </div>

              {/* Aviso de saldo insuficiente */}
              {insufficientBalance && !canResolve && (
                <div className="flex items-center gap-2 px-3 py-2 rounded-lg border border-down/40 bg-down/10 text-down text-xs font-mono">
                  <span>✗</span>
                  <span>
                    Saldo insuficiente — tenés <span className="font-bold text-white">{formatFlash(flashBalance)} FLASH</span> disponible
                  </span>
                </div>
              )}

              {/* Info de fee y payout estimado */}
              {parsedBet > 0n && !insufficientBalance && !canResolve && (
                <div className="text-xs font-mono text-slate-600 space-y-0.5 px-1">
                  <p>Fee 1%: <span className="text-slate-500">−{formatFlash(feeAmount)} FLASH → Treasury</span></p>
                  <p>Net al pool: <span className="text-white">{formatFlash(netAmount)} FLASH</span></p>
                  {needsApproval && (
                    <p className="text-neon-purple">⚡ Se enviará un approve automático primero</p>
                  )}
                </div>
              )}

              {/* Botones UP / DOWN */}
              {!canResolve && (
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

              {/* Tiempo agotado — esperando al admin */}
              {canResolve && (
                <div className="pt-1 border-t border-border/30 text-center">
                  <p className="text-xs text-slate-500 font-mono">
                    Tiempo agotado — el admin resolverá la ronda
                  </p>
                </div>
              )}

              <TxStatus
                isPending={isWritePending} isConfirming={isTxConfirming}
                isSuccess={isTxSuccess} hash={txHash} error={writeError}
                label={txStep === 'approving' ? 'Aprobando FLASH' : 'Apuesta'}
              />
            </div>
          )}

          {/* Sin wallet */}
          {!isConnected && (
            <p className="text-center text-sm text-slate-500 font-mono py-2">
              Conectá tu wallet para apostar
            </p>
          )}
        </div>
      )}

      {/* ── Estado: RESOLVED ────────────────────────── */}
      {phase === RoundPhase.Resolved && round && (
        <div className="space-y-4">
          {/* Banner resultado */}
          <div className={`rounded-xl border p-4 text-center
            ${round.upWon
              ? 'border-up/40 bg-up/5'
              : 'border-down/40 bg-down/5'}`}
          >
            <p className={`font-orbitron text-xl font-black tracking-widest ${round.upWon ? 'text-up' : 'text-down'}`}>
              {round.upWon ? '▲ UP WON 🏆' : '▼ DOWN WON 💀'}
            </p>
            <div className="flex justify-center gap-4 mt-2 text-xs font-mono text-slate-400">
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

          {/* Pool bar final */}
          <PoolBar totalUp={round.totalUp} totalDown={round.totalDown} />

          {/* Claim banner si el usuario ganó */}
          {userWon && round && (
            <ClaimBanner
              roundId={round.id}
              userBet={userBet?.amount ?? 0n}
              totalPool={totalPool}
              myPoolSide={round.upWon ? round.totalUp : round.totalDown}
              onClaim={() => claimPayout(round.id)}
              isLoading={isWritePending || isTxConfirming}
              isUpWin={round.upWon && userBetDir === BetDir.UP}
            />
          )}

          {/* El usuario perdió */}
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

          {/* Abrir nueva ronda */}
          {isConnected && (
            <div className="pt-2 border-t border-border/50">
              <NeonButton
                variant="ghost"
                fullWidth
                loading={isWritePending || isTxConfirming}
                onClick={openRound}
              >
                ⚡ Open New Round
              </NeonButton>
            </div>
          )}
        </div>
      )}
    </GlassCard>
  )
}
