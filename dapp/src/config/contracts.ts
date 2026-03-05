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
    FlashToken:      e('VITE_FLASHTOKEN_ADDRESS',      '0xC7e23DB5aD763bE17d7327E62a402D66eCB5970C'),
    FlashVault:      e('VITE_FLASHVAULT_ADDRESS',      '0x4Ed1547b1D049E5aC4BF28aAc51228B49805A2AE'),
    FlashPredMarket: e('VITE_FLASHPREDMARKET_ADDRESS', '0xfF7b0425cFf18969B03b36b2125eef13AC5Faa22'),
    Treasury:        e('VITE_TREASURY_ADDRESS',        '0xdc2111EC6dc36F0D713baa3D4A8Cf803416E7721'),

    // ── Mocks Sepolia (reemplazan Aave + Chainlink en testnet) ──
    MockFlashOracle: e('VITE_MOCKORACLE_ADDRESS',   '0xC455281F05e96853A8b1ad3869246ebb61AabA1c'),
    MockAavePool:    e('VITE_MOCKAAVEPOOL_ADDRESS', '0x15c076D355fE3cE4C03bf193AA13f16806A7aEE1'),
    MockAToken:      e('VITE_MOCKATOKEN_ADDRESS',   '0x96F88e150A5dFE2dbfa3c570eE4310E78477D3d0'),

    // ── USDT real en Sepolia (dirección fija, no cambia entre deploys) ──
    USDT:            e('VITE_USDT_ADDRESS', '0x7169D38820dfd117C3FA1f22a697dBA58d90BA06'),
  },
}

/** Tipo utilitario para obtener las direcciones del contrato activo */
export type ContractAddresses = typeof CONTRACTS[typeof sepolia.id]
