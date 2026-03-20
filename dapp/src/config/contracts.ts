/**
 * Direcciones de los contratos desplegados en Sepolia.
 * Se leen de variables de entorno (VITE_*) con fallback a las últimas
 * direcciones conocidas. Para actualizar tras un nuevo deploy, ejecutar:
 *
 *   cd protocol && ./deploy.sh
 *
 * que actualiza automáticamente ../dapp/.env.local con las nuevas addresses.
 */
import { sepolia } from 'wagmi/chains'

const e = (key: string, fallback: string) =>
  (import.meta.env[key] || fallback) as `0x${string}`

export const CONTRACTS = {
  [sepolia.id]: {
    // ── Protocolo principal ──────────────────────────
    FlashToken:      e('VITE_FLASHTOKEN_ADDRESS',      '0x783d48813d0568c20ac92f12899943eff33d9016'),
    FlashVault:      e('VITE_FLASHVAULT_ADDRESS',      '0x6953c33a913f53500e882c32361f72472c521166'),
    FlashPredMarket: e('VITE_FLASHPREDMARKET_ADDRESS', '0x1a009c8059217446b739d6647c683613ccfc7e91'),
    Treasury:        e('VITE_TREASURY_ADDRESS',        '0xfd602e71ea5058aea8a0f501167828e5ff923f1d'),

    // ── Mocks Sepolia (reemplazan Aave + Chainlink en testnet) ──
    MockFlashOracle: e('VITE_MOCKORACLE_ADDRESS',   '0x07a8084eeaae1b7769d291efe98d556aa255064a'),
    MockAavePool:    e('VITE_MOCKAAVEPOOL_ADDRESS', '0xd484ddc9bf2dc06ce37a7a2a7dae7641561e7fb6'),
    MockAToken:      e('VITE_MOCKATOKEN_ADDRESS',   '0xad3a61726a2bbbc20b8ad889548f419c6e402940'),

    // ── USDT real en Sepolia (dirección fija, no cambia entre deploys) ──
    USDT:            e('VITE_USDT_ADDRESS', '0x7169D38820dfd117C3FA1f22a697dBA58d90BA06'),
  },
}

/** Tipo utilitario para obtener las direcciones del contrato activo */
export type ContractAddresses = typeof CONTRACTS[typeof sepolia.id]
