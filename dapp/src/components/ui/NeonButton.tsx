/**
 * NeonButton — botón reutilizable con variantes de estilo neon.
 *
 * Variantes:
 *   cyan    → acción primaria (connect, confirm)
 *   purple  → acción secundaria
 *   up      → apostar UP (cyan pulsante)
 *   down    → apostar DOWN (rojo pulsante)
 *   ghost   → acción terciaria (borde solo)
 *   gold    → claim payout (amarillo)
 */
import React from 'react'

type Variant = 'cyan' | 'purple' | 'up' | 'down' | 'ghost' | 'gold'
type Size    = 'sm' | 'md' | 'lg'

interface NeonButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant
  size?:    Size
  loading?: boolean
  fullWidth?: boolean
}

const variantClasses: Record<Variant, string> = {
  cyan:   'bg-neon-cyan/10 border border-neon-cyan text-neon-cyan hover:bg-neon-cyan/20 hover:shadow-[0_0_20px_rgba(0,245,255,0.4)] transition-all duration-200',
  purple: 'bg-neon-purple/10 border border-neon-purple text-neon-purple hover:bg-neon-purple/20 hover:shadow-[0_0_20px_rgba(168,85,247,0.4)] transition-all duration-200',
  up:     'bg-up/10 border border-up text-up btn-pulse-up hover:bg-up/20 transition-all duration-200',
  down:   'bg-down/10 border border-down text-down btn-pulse-down hover:bg-down/20 transition-all duration-200',
  ghost:  'bg-transparent border border-border text-slate-400 hover:border-neon-cyan/50 hover:text-neon-cyan transition-all duration-200',
  gold:   'bg-yellow-500/10 border border-yellow-500 text-yellow-400 hover:bg-yellow-500/20 hover:shadow-[0_0_20px_rgba(234,179,8,0.4)] transition-all duration-200',
}

const sizeClasses: Record<Size, string> = {
  sm: 'px-3 py-1.5 text-xs',
  md: 'px-4 py-2 text-sm',
  lg: 'px-6 py-3 text-base',
}

export function NeonButton({
  variant   = 'cyan',
  size      = 'md',
  loading   = false,
  fullWidth = false,
  disabled,
  children,
  className = '',
  ...props
}: NeonButtonProps) {
  const isDisabled = disabled || loading

  return (
    <button
      disabled={isDisabled}
      className={[
        'font-mono font-medium rounded-lg tracking-wider uppercase',
        'disabled:opacity-40 disabled:cursor-not-allowed disabled:pointer-events-none',
        variantClasses[variant],
        sizeClasses[size],
        fullWidth ? 'w-full' : '',
        className,
      ].join(' ')}
      {...props}
    >
      {loading ? (
        <span className="flex items-center justify-center gap-2">
          <span className="inline-block w-3 h-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
          {children}
        </span>
      ) : children}
    </button>
  )
}
