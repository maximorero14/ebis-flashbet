/**
 * ClaimBanner — banner animado para cuando el usuario ganó una ronda.
 *
 * Se muestra cuando:
 *   - La ronda está en fase Resolved
 *   - El usuario apostó en el lado ganador
 *   - Todavía no reclamó el payout
 *
 * Muestra el payout estimado y el botón CLAIM.
 */
import { GlassCard }     from '../ui/GlassCard'
import { NeonButton }    from '../ui/NeonButton'
import { formatFlash, calcPayout } from '../../utils/format'

interface ClaimBannerProps {
  roundId:   bigint
  userBet:   bigint         // monto apostado (net)
  totalPool: bigint         // totalUp + totalDown
  myPoolSide: bigint        // el lado que ganó (si upWon → totalUp, si !upWon → totalDown)
  onClaim:   () => void
  isLoading: boolean
  isUpWin?:  boolean        // true si ganó apostando UP → color verde
}

export function ClaimBanner({
  roundId, userBet, totalPool, myPoolSide, onClaim, isLoading, isUpWin = false
}: ClaimBannerProps) {
  const payout = calcPayout(userBet, totalPool, myPoolSide)

  const borderCls  = isUpWin ? 'border-up/40'         : 'border-yellow-500/30'
  const bgCls      = isUpWin ? 'bg-up/5'              : 'bg-yellow-500/5'
  const titleCls   = isUpWin ? 'text-up'              : 'text-yellow-400'
  const amountCls  = isUpWin ? 'text-up'              : 'text-yellow-400'
  const btnVariant = isUpWin ? 'up' as const          : 'gold' as const

  return (
    <GlassCard glow className={`border ${borderCls} ${bgCls} animate-pulse-slow`}>
      <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
        <div className="text-center sm:text-left">
          <div className="flex items-center gap-2 justify-center sm:justify-start">
            <span className="text-2xl">🏆</span>
            <h3 className={`font-orbitron font-bold ${titleCls} tracking-wider`}>
              ¡GANASTE!
            </h3>
          </div>
          <p className="font-mono text-sm text-slate-300 mt-1">
            Ronda #{roundId.toString()} — Payout:{' '}
            <span className={`${amountCls} font-bold`}>
              {formatFlash(payout)} FLASH
            </span>
          </p>
        </div>

        <NeonButton
          variant={btnVariant}
          size="lg"
          loading={isLoading}
          onClick={onClaim}
        >
          ⚡ CLAIM PAYOUT
        </NeonButton>
      </div>
    </GlassCard>
  )
}
