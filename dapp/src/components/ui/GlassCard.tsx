/**
 * GlassCard — contenedor con efecto glassmorphism.
 * Aplica las variables CSS definidas en index.css (.glass-card).
 * Acepta className adicional para personalización.
 */
import React from 'react'

interface GlassCardProps {
  children:   React.ReactNode
  className?: string
  /** Si true, aplica neon-glow cyan en los bordes */
  glow?:      boolean
  padding?:   'sm' | 'md' | 'lg' | 'none'
}

const paddingClasses = {
  none: '',
  sm:   'p-3',
  md:   'p-4 md:p-6',
  lg:   'p-6 md:p-8',
}

export function GlassCard({
  children,
  className = '',
  glow      = false,
  padding   = 'md',
}: GlassCardProps) {
  return (
    <div
      className={[
        'glass-card',
        glow ? 'neon-glow' : '',
        paddingClasses[padding],
        className,
      ].join(' ')}
    >
      {children}
    </div>
  )
}
