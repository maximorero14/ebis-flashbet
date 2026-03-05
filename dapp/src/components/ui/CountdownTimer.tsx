/**
 * CountdownTimer — reloj digital grande para el countdown de ronda.
 *
 * Muestra MM:SS en formato digital con fuente JetBrains Mono.
 * Cambia de color según el tiempo restante:
 *   - > 30s: cyan neon
 *   - 10-30s: amarillo (urgencia)
 *   - < 10s: rojo pulsante (crítico)
 */
import { formatCountdown } from '../../utils/format'

interface CountdownTimerProps {
  seconds: number
  /** Duración total de la ronda para calcular el porcentaje */
  totalSeconds?: number
}

export function CountdownTimer({ seconds, totalSeconds = 60 }: CountdownTimerProps) {
  const display = formatCountdown(seconds)

  // Color dinámico según urgencia
  const colorClass =
    seconds > 30 ? 'text-neon-cyan' :
    seconds > 10 ? 'text-yellow-400' :
    'text-down animate-pulse'

  // Porcentaje de tiempo restante para la barra de progreso
  const pct = totalSeconds > 0 ? (seconds / totalSeconds) * 100 : 0

  const barColor =
    seconds > 30 ? 'bg-neon-cyan' :
    seconds > 10 ? 'bg-yellow-400' :
    'bg-down'

  return (
    <div className="flex flex-col items-center gap-2">
      {/* Display digital */}
      <div className={`font-mono font-bold text-5xl tracking-widest tabular-nums ${colorClass}`}
           style={{ textShadow: `0 0 20px currentColor, 0 0 40px currentColor` }}>
        {display}
      </div>

      {/* Barra de progreso */}
      <div className="w-full h-1 bg-border rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-1000 ${barColor}`}
          style={{ width: `${pct}%` }}
        />
      </div>

      <p className="text-xs text-slate-500 tracking-widest uppercase">Time Left</p>
    </div>
  )
}
