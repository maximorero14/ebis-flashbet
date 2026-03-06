# FlashBet DApp

> Mercado de predicción DeFi en Sepolia Testnet — TFM Máster en Ingeniería y Desarrollo Blockchain (EBIS)

🌐 **DApp disponible en:** [https://ebis-flashbet.vercel.app/](https://ebis-flashbet.vercel.app/)

## ¿Qué es FlashBet?

FlashBet es un protocolo DeFi de dos capas desplegado en Ethereum Sepolia:

1. **FlashVault** — Los usuarios depositan USDT y reciben `$FLASH` tokens 1:1. El USDT se presta a Aave V3 para generar yield pasivo mientras el usuario apuesta.

2. **FlashPredMarket** — Mercado de predicción estilo Polymarket. Los usuarios apuestan `$FLASH` a si BTC/USD o ETH/USD subirá o bajará en los próximos 60 segundos. El precio de referencia se fija al abrir la ronda y se puede apostar hasta el último segundo.

**Flujo completo:**
```
USDT → FlashVault → $FLASH
$FLASH → FlashPredMarket → Apuesta UP o DOWN
→ Si ganás: cobrás tu parte proporcional del pool
→ Si querés salir: redimís $FLASH → recuperás USDT
```

---

## Stack Tecnológico

| Categoría | Tecnología | Versión |
|---|---|---|
| Framework UI | React + TypeScript | 18 / 5 |
| Bundler | Vite | 7 |
| Blockchain reads/writes | wagmi + viem | 2 |
| Wallet modal | RainbowKit | 2 |
| Cache async | TanStack Query | 5 |
| Estilos | TailwindCSS | 3 |
| Notificaciones | react-hot-toast | 2 |
| Routing | react-router-dom | 7 |
| Deploy | Vercel | — |

---

## Arquitectura

```
dapp/src/
├── abi/                  ← ABIs tipadas de los contratos
│   ├── ERC20.ts          ← ABI mínima ERC-20 (para USDT)
│   ├── FlashToken.ts     ← ABI de $FLASH token
│   ├── FlashVault.ts     ← ABI del vault (deposit/redeem/harvestYield)
│   └── FlashPredMarket.ts← ABI del mercado de predicción
│
├── config/
│   ├── contracts.ts      ← Addresses de contratos en Sepolia (tipadas por chainId)
│   └── wagmi.ts          ← Config de wagmi + RainbowKit
│
├── hooks/                ← Lógica de negocio encapsulada en hooks
│   ├── useFlashBalance.ts← Balance $FLASH del usuario
│   ├── useVault.ts       ← Depósito, redención, harvestYield + allowances
│   ├── usePredMarket.ts  ← Ronda activa, apuestas, claim + event watchers
│   └── useRoundTimer.ts  ← Countdown en tiempo real (setInterval)
│
├── components/
│   ├── layout/
│   │   ├── Navbar.tsx    ← Sticky navbar con blur, balance $FLASH, ConnectButton
│   │   └── Footer.tsx    ← Links a contratos en Etherscan
│   ├── ui/               ← Primitivos de UI reutilizables
│   │   ├── NeonButton.tsx   ← Botón con variantes: cyan|purple|up|down|ghost|gold
│   │   ├── GlassCard.tsx    ← Contenedor glassmorphism
│   │   ├── CountdownTimer.tsx← Reloj digital con barra de progreso
│   │   ├── PoolBar.tsx      ← Barra UP/DOWN proporcional
│   │   └── TxStatus.tsx     ← Estados de tx: pending → confirming → success|error
│   └── sections/
│       ├── VaultSection.tsx ← Interfaz de depósito y redención
│       ├── MarketCard.tsx   ← Card completa de un mercado de predicción
│       └── ClaimBanner.tsx  ← Banner de payout disponible para reclamar
│
├── pages/
│   ├── HomePage.tsx      ← Layout 2col: Vault (izq) + Markets (der)
│   └── HistoryPage.tsx   ← Historial paginado via getLogs on-chain
│
├── utils/
│   └── format.ts         ← formatFlash, formatPrice, calcPct, calcPayout, etc.
│
├── App.tsx               ← Router + layout (Navbar + Footer)
└── main.tsx              ← Entry point: WagmiProvider + QueryClient + RainbowKit
```

### Flujo de datos

```
Blockchain (Sepolia)
        │
        ▼
wagmi hooks (useReadContract, useWriteContract, useWatchContractEvent)
        │
        ▼
Custom hooks (useVault, usePredMarket, useFlashBalance)
        │  encapsulan: reads batch, writes, event watchers, allowance checks
        ▼
Components (VaultSection, MarketCard)
        │  presentan los datos, manejan inputs y estados de UI
        ▼
Pages (HomePage, HistoryPage)
```

---

## Contratos en Sepolia

Todos los contratos están verificados en Etherscan. Deploy: 2026-03-01.

| Contrato | Address |
|---|---|
| FlashToken ($FLASH) | `0xC7e23DB5aD763bE17d7327E62a402D66eCB5970C` |
| FlashVault | `0x4Ed1547b1D049E5aC4BF28aAc51228B49805A2AE` |
| FlashPredMarket | `0xfF7b0425cFf18969B03b36b2125eef13AC5Faa22` |
| Treasury | `0xdc2111EC6dc36F0D713baa3D4A8Cf803416E7721` |
| MockFlashOracle | `0xC455281F05e96853A8b1ad3869246ebb61AabA1c` |
| MockAavePool | `0x15c076D355fE3cE4C03bf193AA13f16806A7aEE1` |
| USDT (Sepolia) | `0x7169D38820dfd117C3FA1f22a697dBA58d90BA06` |

---

## Setup Local

### Requisitos previos
- Node.js >= 18
- MetaMask u otra wallet compatible con Ethereum
- Red Sepolia configurada en la wallet

### Instalación

```bash
# 1. Clonar el repositorio
git clone <repo-url>
cd ebis-flashbet/dapp

# 2. Instalar dependencias
npm install

# 3. Configurar variables de entorno
cp .env.local.example .env.local
# Editar .env.local con tu RPC de Sepolia

# 4. Iniciar servidor de desarrollo
npm run dev
```

### Variables de entorno

```bash
# .env.local
VITE_SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
VITE_WALLETCONNECT_PROJECT_ID=YOUR_WC_PROJECT_ID  # opcional
```

### Scripts disponibles

```bash
npm run dev      # servidor de desarrollo con HMR
npm run build    # build de producción en dist/
npm run preview  # sirve el build localmente
npm run lint     # linting con ESLint
```

---

## Deploy en Vercel

1. Importar el repositorio en [vercel.com](https://vercel.com)
2. Configurar **Root Directory** como `dapp`
3. Agregar las variables de entorno en el dashboard de Vercel
4. Deploy automático — `vercel.json` maneja el routing SPA

---

## Reglas del Protocolo (implementadas en la DApp)

| # | Regla |
|---|---|
| 1 | `$FLASH` y `USDT` tienen **6 decimales** — `formatUnits(x, 6)` / `parseUnits(str, 6)` |
| 2 | Precios del oracle: **8 decimales** (estándar Chainlink) — `Number(price) / 1e8` |
| 3 | `placeBet()` requiere `approve(FlashPredMarket, amount)` en FlashToken previo |
| 4 | `deposit()` requiere `approve(FlashVault, amount)` en USDT previo |
| 5 | Un usuario solo puede apostar en **una dirección por ronda** |
| 6 | Fee = **1%** → Treasury en cada apuesta |
| 7 | `claimPayout(marketId, roundId)` — roundId de la ronda ganada |

---

## Tests de Smart Contracts

Los tests unitarios están en `protocol/test/` y se ejecutan con Foundry:

```bash
cd ../protocol
forge test -v
```

---

## Diseño

UI estilo **terminal de trading de alta frecuencia** / cyberpunk:
- Glassmorphism cards con `backdrop-filter: blur`
- Neon glow cyan/purple en elementos activos
- Overlay scanlines en todo el viewport (efecto CRT)
- Fuente **Orbitron** para headings, **JetBrains Mono** para números
- Paleta: fondo `#030712`, neon cyan `#00f5ff`, neon purple `#a855f7`
- Animaciones pulsantes en botones UP (cyan) y DOWN (rojo)

---

*FlashBet — Sepolia Testnet — Solidity ^0.8.30 — Foundry — React 18 — wagmi v2*
