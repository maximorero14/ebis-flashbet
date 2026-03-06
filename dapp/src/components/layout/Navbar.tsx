/**
 * Navbar — barra de navegación sticky con blur en scroll.
 *
 * Vault  → /vault   (ruta dedicada)
 * Markets → /markets (ruta dedicada)
 * History → /history (ruta separada)
 */
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { useAccount } from 'wagmi'
import { Link, useLocation } from 'react-router-dom'
import { useState } from 'react'
import { useFlashBalance } from '../../hooks/useFlashBalance'
import { useIsAdmin } from '../../hooks/useIsAdmin'
import { formatFlash } from '../../utils/format'

export function Navbar() {
  const { isConnected } = useAccount()
  const { data: balance } = useFlashBalance()
  const location = useLocation()
  const isAdmin = useIsAdmin()
  const [mobileOpen, setMobileOpen] = useState(false)

  const closeMobile = () => setMobileOpen(false)

  const navLink = (to: string, label: string) => {
    const active = location.pathname === to
    return (
      <Link
        to={to}
        className={[
          'font-mono text-sm tracking-widest uppercase transition-colors duration-200',
          active ? 'text-neon-cyan' : 'text-slate-400 hover:text-neon-cyan',
        ].join(' ')}
      >
        {label}
      </Link>
    )
  }

  return (
    <header className="sticky top-0 z-50 border-b border-border/50 bg-[#030712]/80 backdrop-blur-md">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">

          {/* Logo */}
          <Link to="/vault" className="flex items-center gap-2" aria-label="FlashBet home">
            <span
              className="text-xl font-black tracking-widest text-neon-cyan font-orbitron"
              style={{ textShadow: '0 0 20px rgba(0,245,255,0.6)' }}
            >
              ⚡ FLASHBET
            </span>
          </Link>

          {/* Nav — desktop */}
          <nav className="hidden md:flex items-center gap-6">
            {navLink('/vault', 'Vault')}
            {navLink('/markets', 'Markets')}
            {navLink('/history', 'History')}
            {isAdmin && (
              <Link
                to="/admin"
                className={[
                  'font-mono text-sm tracking-widest uppercase transition-colors duration-200',
                  'flex items-center gap-1',
                  location.pathname === '/admin'
                    ? 'text-purple-400'
                    : 'text-slate-400 hover:text-purple-400',
                ].join(' ')}
              >
                <span className="text-xs">⚙</span> Admin
              </Link>
            )}
          </nav>

          {/* Wallet area */}
          <div className="flex items-center gap-3">
            {isConnected && balance !== undefined && (
              <div className="hidden sm:flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-surface border border-border">
                <span className="text-neon-cyan text-xs font-mono">⚡</span>
                <span className="font-mono text-sm text-white tabular-nums">
                  {formatFlash(balance)}
                </span>
                <span className="text-xs text-slate-500 font-mono">FLASH</span>
              </div>
            )}

            <ConnectButton showBalance={false} chainStatus="icon" accountStatus="avatar" />

            {/* Hamburger mobile */}
            <button
              className="md:hidden p-2 text-slate-400 hover:text-neon-cyan transition-colors"
              onClick={() => setMobileOpen(v => !v)}
              aria-label="Toggle menu"
            >
              <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor">
                {mobileOpen ? (
                  <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
                ) : (
                  <path fillRule="evenodd" d="M3 5a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zM3 10a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zM3 15a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z" clipRule="evenodd" />
                )}
              </svg>
            </button>
          </div>
        </div>
      </div>

      {/* Mobile menu */}
      {mobileOpen && (
        <div className="md:hidden border-t border-border/50 bg-surface/90 backdrop-blur-md">
          <nav className="px-4 py-3 flex flex-col gap-1">
            <Link
              to="/vault"
              onClick={closeMobile}
              className={[
                'font-mono text-sm tracking-widest uppercase transition-colors py-2',
                location.pathname === '/vault' ? 'text-neon-cyan' : 'text-slate-400 hover:text-neon-cyan',
              ].join(' ')}
            >
              Vault
            </Link>
            <Link
              to="/markets"
              onClick={closeMobile}
              className={[
                'font-mono text-sm tracking-widest uppercase transition-colors py-2',
                location.pathname === '/markets' ? 'text-neon-cyan' : 'text-slate-400 hover:text-neon-cyan',
              ].join(' ')}
            >
              Markets
            </Link>
            <Link
              to="/history"
              onClick={closeMobile}
              className={[
                'font-mono text-sm tracking-widest uppercase transition-colors py-2',
                location.pathname === '/history' ? 'text-neon-cyan' : 'text-slate-400 hover:text-neon-cyan',
              ].join(' ')}
            >
              History
            </Link>
            {isAdmin && (
              <Link
                to="/admin"
                onClick={closeMobile}
                className={[
                  'font-mono text-sm tracking-widest uppercase transition-colors py-2 flex items-center gap-1',
                  location.pathname === '/admin' ? 'text-purple-400' : 'text-slate-400 hover:text-purple-400',
                ].join(' ')}
              >
                <span className="text-xs">⚙</span> Admin
              </Link>
            )}
            {isConnected && balance !== undefined && (
              <div className="flex items-center gap-1.5 py-2 border-t border-border mt-1">
                <span className="text-neon-cyan text-xs font-mono">⚡</span>
                <span className="font-mono text-sm text-white">{formatFlash(balance)} FLASH</span>
              </div>
            )}
          </nav>
        </div>
      )}
    </header>
  )
}