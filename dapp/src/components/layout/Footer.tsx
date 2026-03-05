/**
 * Footer — pie de página con links a contratos en Etherscan.
 * Muestra las direcciones de los contratos deployados para transparencia.
 */
import { CONTRACTS } from '../../config/contracts'
import { sepolia }   from 'wagmi/chains'

const addr = CONTRACTS[sepolia.id]

const contracts = [
  { name: 'FlashToken',      address: addr.FlashToken      },
  { name: 'FlashVault',      address: addr.FlashVault      },
  { name: 'FlashPredMarket', address: addr.FlashPredMarket },
  { name: 'Treasury',        address: addr.Treasury        },
]

export function Footer() {
  return (
    <footer className="mt-16 border-t border-border/50 py-8 px-4">
      <div className="max-w-7xl mx-auto">
        <div className="flex flex-col md:flex-row justify-between items-start gap-6">

          {/* Branding */}
          <div>
            <p className="font-orbitron font-bold text-neon-cyan tracking-widest text-sm">
              ⚡ FLASHBET
            </p>
            <p className="text-xs text-slate-600 mt-1 font-mono">
              DeFi Prediction Market · Sepolia Testnet
            </p>
            <p className="text-xs text-slate-700 mt-1 font-mono">
              Solidity ^0.8.30 · Foundry · wagmi v2
            </p>
          </div>

          {/* Contratos */}
          <div>
            <p className="text-xs text-slate-500 font-mono uppercase tracking-widest mb-2">
              Contracts on Sepolia
            </p>
            <ul className="space-y-1">
              {contracts.map(c => (
                <li key={c.name} className="flex items-center gap-2 font-mono text-xs">
                  <span className="text-slate-600 w-28">{c.name}</span>
                  <a
                    href={`https://sepolia.etherscan.io/address/${c.address}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-slate-500 hover:text-neon-cyan transition-colors"
                    title={c.address}
                  >
                    {c.address.slice(0, 8)}...{c.address.slice(-6)} ↗
                  </a>
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="text-center font-mono mt-8 space-y-1">
          <p className="text-xs text-slate-700">
            TFM — Máster en Ingeniería y Desarrollo Blockchain (MDB) — EBIS Business Techschool
          </p>
          <p className="text-xs text-slate-600">
            Desarrollado por <span className="text-neon-cyan">Maximiliano Morero</span>
          </p>
        </div>
      </div>
    </footer>
  )
}
