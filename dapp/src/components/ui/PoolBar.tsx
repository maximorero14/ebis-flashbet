/**
 * PoolBar — barra visual proporcional del pool UP vs DOWN.
 *
 * Muestra la distribución del capital apostado en cada dirección.
 * UP (cyan) a la izquierda, DOWN (rojo) a la derecha.
 * Si el pool está vacío, muestra 50/50.
 */
import { formatFlash, calcPct } from '../../utils/format'

interface PoolBarProps {
  totalUp:   bigint
  totalDown: bigint
}

export function PoolBar({ totalUp, totalDown }: PoolBarProps) {
  const upPct   = calcPct(totalUp, totalDown)
  const downPct = 100 - upPct

  const total = totalUp + totalDown

  return (
    <div className="space-y-2">
      {/* Barra proporcional */}
      <div className="flex rounded-full overflow-hidden h-3 bg-border">
        <div
          className="bg-up transition-all duration-500"
          style={{ width: `${upPct}%` }}
        />
        <div
          className="bg-down transition-all duration-500 flex-1"
        />
      </div>

      {/* Leyenda */}
      <div className="flex justify-between text-xs font-mono">
        <div className="flex items-center gap-1.5">
          <span className="w-2 h-2 rounded-full bg-up inline-block" />
          <span className="text-up">
            UP: {formatFlash(totalUp)} FLASH ({upPct}%)
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          <span className="text-down">
            DOWN: {formatFlash(totalDown)} FLASH ({downPct}%)
          </span>
          <span className="w-2 h-2 rounded-full bg-down inline-block" />
        </div>
      </div>

      {total === 0n && (
        <p className="text-center text-xs text-slate-600 italic">
          Pool vacío — sé el primero en apostar
        </p>
      )}
    </div>
  )
}
