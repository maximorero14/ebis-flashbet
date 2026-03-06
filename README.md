# FlashBet Protocol

> **Trabajo Final de Máster — Máster en Ingeniería y Desarrollo Blockchain (MDB)**
> Protocolo DeFi de dos capas desplegado en Ethereum Sepolia (testnet).

🌐 **DApp disponible en:** [https://ebis-flashbet.vercel.app/](https://ebis-flashbet.vercel.app/)

<div align="center">

[![Solidity](https://img.shields.io/badge/Solidity-0.8.30-363636.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-Contracts-FFDB1C.svg)](https://getfoundry.sh/)
[![React](https://img.shields.io/badge/React-19.2.0-61DAFB.svg)](https://react.dev/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.9-3178C6.svg)](https://www.typescriptlang.org/)
[![wagmi](https://img.shields.io/badge/wagmi-v2-1C1C1C.svg)](https://wagmi.sh/)
[![Vite](https://img.shields.io/badge/Vite-7.2.4-646CFF.svg)](https://vitejs.dev/)
[![Live on Sepolia](https://img.shields.io/badge/Live-Sepolia%20Testnet-success)](https://sepolia.etherscan.io/)
[![GitHub Repo](https://img.shields.io/badge/GitHub-Repository-181717?logo=github)](https://github.com/maximorero14/ebis-flashbet)
[![Vercel](https://img.shields.io/badge/Vercel-Deployment-black?logo=vercel)](https://ebis-flashbet.vercel.app/)

</div>

<p align="center">
  <a href="https://sepolia.etherscan.io/address/0xfF7b0425cFf18969B03b36b2125eef13AC5Faa22">
    <img src="https://img.shields.io/badge/FlashPredMarket-Etherscan-3C3C3D?style=flat-square&logo=ethereum&logoColor=white" />
  </a>
  <a href="https://sepolia.etherscan.io/address/0x4Ed1547b1D049E5aC4BF28aAc51228B49805A2AE">
    <img src="https://img.shields.io/badge/FlashVault-Etherscan-3C3C3D?style=flat-square&logo=ethereum&logoColor=white" />
  </a>
  <a href="https://sepolia.etherscan.io/address/0xC7e23DB5aD763bE17d7327E62a402D66eCB5970C">
    <img src="https://img.shields.io/badge/%24FLASH_Token-Etherscan-3C3C3D?style=flat-square&logo=ethereum&logoColor=white" />
  </a>
  <a href="https://sepolia.etherscan.io/address/0xdc2111EC6dc36F0D713baa3D4A8Cf803416E7721">
    <img src="https://img.shields.io/badge/Treasury-Etherscan-3C3C3D?style=flat-square&logo=ethereum&logoColor=white" />
  </a>
</p>

---

## Índice

1. [Resumen del protocolo](#1-resumen-del-protocolo)
2. [Problema que resuelve](#2-problema-que-resuelve)
3. [Arquitectura general](#3-arquitectura-general)
4. [Stack tecnológico](#4-stack-tecnológico)
5. [Smart Contracts — Descripción detallada](#5-smart-contracts--descripción-detallada)
   - 5.1 [FlashToken.sol](#51-flashtokensol)
   - 5.2 [FlashVault.sol](#52-flashvaultsol)
   - 5.3 [FlashPredMarket.sol](#53-flashpredmarketsol)
   - 5.4 [Oracle de precios (IFlashOracle)](#54-oracle-de-precios-iflashoracle)
   - 5.5 [Treasury.sol](#55-treasurysol)
   - 5.6 [Contratos Mock (Testnet)](#56-contratos-mock-testnet)
   - 5.7 [Interfaces](#57-interfaces)
6. [Flujos principales de usuario](#6-flujos-principales-de-usuario)
7. [Modelo económico](#7-modelo-económico)
8. [Seguridad y control de acceso](#8-seguridad-y-control-de-acceso)
9. [Tests unitarios](#9-tests-unitarios)
10. [Despliegue](#10-despliegue)
11. [Indexación con The Graph](#11-indexación-con-the-graph)
12. [Contratos desplegados en Sepolia](#12-contratos-desplegados-en-sepolia)
13. [Frontend (DApp)](#13-frontend-dapp)
14. [Estructura de carpetas](#14-estructura-de-carpetas)
15. [Alcance y entregables del proyecto](#15-alcance-y-entregables-del-proyecto)

---

## 1. Resumen del protocolo

**FlashBet** es un protocolo DeFi de dos capas que combina **yield farming pasivo** con un **mercado de predicción de precios** al estilo Polymarket. Los usuarios depositan USDT, obtienen el token nativo `$FLASH` 1:1, y pueden usar ese `$FLASH` para apostar sobre la dirección del precio de BTC/USD y ETH/USD en rondas de duración fija.

```
Usuario deposita USDT
        │
        ▼
  FlashVault (Capa 1)
  ┌──────────────────────────────────────────┐
  │  USDT → Aave V3 → genera ~5% APY        │
  │  Usuario recibe $FLASH 1:1               │
  │  Yield → Treasury                        │
  └──────────────────────────────────────────┘
        │
        │  Usuario usa $FLASH
        ▼
  FlashPredMarket (Capa 2)
  ┌──────────────────────────────────────────┐
  │  Rondas BTC/USD y ETH/USD               │
  │  Apuesta UP o DOWN con $FLASH           │
  │  Precio referencia: Chainlink Oracle    │
  │  1% fee → Treasury                      │
  │  Ganadores: payout proporcional         │
  └──────────────────────────────────────────┘
```

---

## 2. Problema que resuelve

Los mercados de predicción tradicionales (Polymarket, Augur) tienen varios problemas:

- **Capital ocioso**: el colateral bloqueado no genera rendimiento mientras espera el resultado.
- **Dependencia de liquidez externa**: necesitan market makers externos para que haya pools a ambos lados.
- **Tokens de gobernanza complejos**: muchos protocolos tienen tokens inflacionarios de gobernanza desvinculados del valor real.

**FlashBet resuelve esto con tres decisiones de diseño:**

1. **USDT en Aave**: el colateral siempre trabaja, no está ocioso. El usuario gana yield aunque no apueste.
2. **$FLASH como colateral nativo**: al estar respaldado 1:1 por USDT en Aave, `$FLASH` no es inflacionario — solo existe cuando hay USDT detrás.
3. **Simplicidad operativa**: sin Chainlink Automation, sin DAOs, sin vesting. El owner opera las rondas manualmente desde el Admin Panel — comprensible, auditable, demostrable en un TFM.

---

## 3. Arquitectura general

```
                      ┌─────────────────────────────────────┐
                      │         Ethereum Sepolia             │
                      │                                      │
  ┌──────────┐        │   ┌──────────────────────────┐      │
  │  Usuario │◄──────►│   │      FlashVault           │      │
  └──────────┘ USDT/  │   │  deposit() / redeem()    │      │
               $FLASH │   │  harvestYield()           │      │
                      │   └────────────┬─────────────┘      │
                      │                │ supply/withdraw     │
                      │   ┌────────────▼─────────────┐      │
                      │   │     Aave V3 Pool          │      │
                      │   │  (MockAavePool en Sepolia)│      │
                      │   └────────────┬─────────────┘      │
                      │                │ aUSDT               │
                      │   ┌────────────▼─────────────┐      │
                      │   │       FlashToken          │      │
                      │   │    ERC20 $FLASH (6 dec)  │      │
                      │   └────────────┬─────────────┘      │
                      │                │ approve + transfer  │
                      │   ┌────────────▼─────────────┐      │
                      │   │    FlashPredMarket        │      │
                      │   │  openRound() [owner]      │      │
                      │   │  placeBet()   [user]      │      │
                      │   │  resolveRound()[owner]    │      │
                      │   │  claimPayout()[winner]    │      │
                      │   └────────────┬─────────────┘      │
                      │                │ getPrice()          │
                      │   ┌────────────▼─────────────┐      │
                      │   │   MockFlashOracle         │      │
                      │   │  (IFlashOracle interface) │      │
                      │   │  simulación ±1.5% APY     │      │
                      │   └──────────────────────────┘      │
                      │                                      │
                      │   ┌──────────────────────────┐      │
                      │   │       Treasury            │      │
                      │   │   fees (1% $FLASH)        │      │
                      │   │   yield (USDT de Aave)    │      │
                      │   └──────────────────────────┘      │
                      └─────────────────────────────────────┘
```

### Flujo de valor

```
USDT (usuario)
  │
  ├──[deposit]──► FlashVault ──[supply]──► Aave V3 ──► aUSDT (rendimiento)
  │                   │                                      │
  │              mint $FLASH                       harvestYield() ──► Treasury (USDT)
  │
  └──[approve]──► FlashPredMarket
                      │
                 placeBet($FLASH)
                      │
                  1% ──► Treasury ($FLASH)
                 99% ──► Pool (UP o DOWN)
                      │
                resolveRound()
                (precio MockFlashOracle)
                      │
                 claimPayout() ──► Ganadores (payout proporcional en $FLASH)
```

---

## 4. Stack tecnológico

### Smart Contracts

| Componente | Tecnología | Versión |
|---|---|---|
| Lenguaje | Solidity | `^0.8.30` |
| Framework de desarrollo | Foundry | latest |
| Librería de contratos | OpenZeppelin | v5 |
| Compilador | `solc` | `0.8.30`, optimizer 200 runs |
| Oracle de precios | MockFlashOracle (IFlashOracle) | testnet (simulación ±1.5%) |
| Yield | Aave V3 | Pool supply/withdraw (MockAavePool en testnet) |
| Testing | Foundry Test (`forge test`) | 120 tests unitarios (4 archivos) |

### OpenZeppelin — Módulos utilizados

| Módulo OZ | Dónde se usa | Para qué |
|---|---|---|
| `ERC20` | FlashToken, MockAToken | Token estándar |
| `AccessControl` | FlashToken | Roles MINTER y BURNER granulares |
| `Ownable` | FlashVault, FlashPredMarket, Treasury | Funciones de admin |
| `Pausable` | FlashToken, FlashVault, FlashPredMarket | Pausa de emergencia |
| `ReentrancyGuard` | FlashVault, FlashPredMarket | Protección reentrancy |
| `SafeERC20` | FlashVault, FlashPredMarket, Treasury | Transferencias seguras (USDT quirk) |

---

## 5. Smart Contracts — Descripción detallada

### 5.1 `FlashToken.sol`

**Ruta:** `protocol/src/FlashToken.sol`

**Propósito:** Token nativo ERC-20 del protocolo. Símbolo: `$FLASH`. Actúa como "recibo de depósito" del vault y como "ficha de apuesta" en el mercado de predicción.

#### Decisiones de diseño clave

| Decisión | Justificación |
|---|---|
| **6 decimales** | Espeja USDC/USDT: `1 FLASH = 1 USDT` sin conversiones de decimales |
| **AccessControl** (no Ownable) | Permite asignar MINTER y BURNER a contratos distintos de forma granular |
| **BURNER_ROLE** para vault | El vault puede quemar tokens del usuario sin `approve` previo (atomicidad) |
| **Custom errors** | Ahorra gas vs `require(condition, "string")` |

#### Roles

```solidity
bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
```

- `DEFAULT_ADMIN_ROLE`: el deployer. Puede pause/unpause y asignar/revocar roles.
- `MINTER_ROLE`: asignado a **FlashVault** post-deploy. Permite mint.
- `BURNER_ROLE`: asignado a **FlashVault** post-deploy. Permite burn.

#### Funciones

---

**`constructor()`**

```solidity
constructor() ERC20("Flash Token", "FLASH")
```

Despliega el token. Otorga solo `DEFAULT_ADMIN_ROLE` al deployer — no se auto-asigna MINTER ni BURNER. El deployer otorgará esos roles a FlashVault en el script de deploy.

---

**`mint(address to, uint256 amount)`**

```solidity
function mint(address to, uint256 amount)
    external onlyRole(MINTER_ROLE) whenNotPaused
```

Acuña `amount` tokens FLASH hacia `to`. Solo puede llamarlo una cuenta con `MINTER_ROLE` (FlashVault).

- Reverts: `FlashToken__AmountZero` si amount == 0 | `FlashToken__InvalidRecipient` si to == address(0).
- Emite: `TokensMinted(to, amount)`.

**Flujo real:** El usuario llama `FlashVault.deposit(1000e6)` → vault llama `flash.mint(user, 1000e6)` → usuario recibe 1000 $FLASH.

---

**`burn(address from, uint256 amount)`**

```solidity
function burn(address from, uint256 amount)
    external onlyRole(BURNER_ROLE) whenNotPaused
```

Destruye `amount` tokens de la dirección `from`. No requiere `allowance` — el burner (vault) está en modo "confiado". Solo `BURNER_ROLE` puede llamarlo.

- Reverts: `FlashToken__AmountZero` si amount == 0.
- Emite: `TokensBurned(from, amount)`.

**Flujo real:** El usuario llama `FlashVault.redeem(500e6)` → vault llama `flash.burn(user, 500e6)` → esos tokens son destruidos → vault devuelve USDT al usuario.

---

**`pause()` / `unpause()`**

```solidity
function pause() external onlyRole(DEFAULT_ADMIN_ROLE)
function unpause() external onlyRole(DEFAULT_ADMIN_ROLE)
```

Suspenden / reanudan mint y burn. Solo `DEFAULT_ADMIN_ROLE`. Útil en caso de emergencia o bug crítico.

---

**`decimals()`**

```solidity
function decimals() public pure override returns (uint8) { return 6; }
```

Override del ERC20 para devolver 6 decimales en lugar de 18 (default de OpenZeppelin).

---

### 5.2 `FlashVault.sol`

**Ruta:** `protocol/src/FlashVault.sol`

**Propósito:** Vault de colateral que genera yield. Acepta USDT → lo suministra a Aave V3 → acumula intereses → emite `$FLASH` 1:1 al depositante. El yield acumulado puede enviarse al Treasury en cualquier momento.

#### Decisiones de diseño clave

| Decisión | Justificación |
|---|---|
| **1:1 USDT ↔ $FLASH** | Precio de $FLASH siempre respaldado. No hay riesgo de depegging. |
| **`forceApprove`** de SafeERC20 | USDT tiene un bug histórico: `approve(x)` revierte si hay allowance previo distinto de cero. `forceApprove` lo resuelve. |
| **`harvestYield` permisionless** | Cualquiera puede disparar la cosecha. Los fondos van al treasury hardcodeado → no hay vector de griefing. |
| **`totalDeposited` como referencia** | El saldo de `aUSDT` crece con el tiempo (Aave acumula interés). La diferencia `aBalance - totalDeposited` es el yield puro. |

#### State variables

```solidity
FlashToken public immutable flashToken;   // Token $FLASH
IERC20     public immutable usdt;         // Token USDT (Sepolia real o mainnet)
IAavePool  public immutable aavePool;     // Pool de Aave V3
IERC20     public immutable aToken;       // aUSDT (token de interés de Aave)
address    public immutable treasury;     // Destino del yield y fees

uint256 public totalDeposited;            // USDT en principal (sin yield)
```

#### Funciones

---

**`deposit(uint256 amount)`**

```solidity
function deposit(uint256 amount) external whenNotPaused nonReentrant
```

Acepta USDT del usuario y le entrega $FLASH 1:1.

**Pasos internos:**
1. `usdt.safeTransferFrom(msg.sender, address(this), amount)` — tira USDT del usuario al vault.
2. `usdt.forceApprove(aavePool, amount)` — aprueba al pool de Aave.
3. `aavePool.supply(usdt, amount, address(this), 0)` — suministra USDT a Aave, el vault recibe `aUSDT`.
4. `totalDeposited += amount` — registra el principal.
5. `flashToken.mint(msg.sender, amount)` — acuña $FLASH 1:1 al usuario.

**Pre-condición:** El usuario debe haber aprobado al vault con `USDT.approve(vault, amount)` antes.

- Reverts: `FlashVault__AmountZero` | `FlashVault__ZeroAddress`.
- Emite: `Deposited(user, amount)`.

---

**`redeem(uint256 amount)`**

```solidity
function redeem(uint256 amount) external whenNotPaused nonReentrant
```

Quema `$FLASH` del usuario y le devuelve `USDT` 1:1.

**Pasos internos:**
1. Verifica que el usuario tenga saldo suficiente de $FLASH.
2. `flashToken.burn(msg.sender, amount)` — destruye $FLASH (requiere BURNER_ROLE del vault).
3. `totalDeposited -= amount` — reduce el principal.
4. `aavePool.withdraw(usdt, amount, msg.sender)` — retira USDT de Aave directamente al usuario.

**No requiere** `$FLASH.approve()` previo al vault — el vault tiene BURNER_ROLE y puede quemar directamente.

- Reverts: `FlashVault__AmountZero` | `FlashVault__InsufficientFlashBalance`.
- Emite: `Redeemed(user, amount)`.

---

**`harvestYield()`**

```solidity
function harvestYield() external whenNotPaused nonReentrant
```

Envía el interés acumulado de Aave al Treasury. **Permissionless** — cualquier cuenta puede llamarla.

**Lógica:**
```
aBalance   = aToken.balanceOf(address(this))  // incluye principal + interés
yield      = aBalance - totalDeposited         // solo el interés puro
aavePool.withdraw(usdt, yield, treasury)       // retira interés al treasury
```

- Reverts: `FlashVault__NoYieldAvailable` si no hay interés acumulado aún.
- Emite: `YieldHarvested(yieldAmount, treasury)`.

---

**`pendingYield()` (view)**

```solidity
function pendingYield() external view returns (uint256 yield)
```

Retorna el yield pendiente sin gastar gas en una transacción. Útil para el frontend (Admin Panel).

---

**`pause()` / `unpause()`** — Solo owner. Pausa `deposit`, `redeem`, `harvestYield`.

---

### 5.3 `FlashPredMarket.sol`

**Ruta:** `protocol/src/FlashPredMarket.sol`

**Propósito:** Mercado de predicción de precio al estilo **Polymarket**. Los usuarios apuestan `$FLASH` a que BTC/USD o ETH/USD subirá (UP) o bajará (DOWN) en una ronda de duración fija. Al resolver, los ganadores reclaman un payout proporcional del pool total.

#### Modelo de negocio

- **Dos mercados**: BTC/USD (`marketId=0`) y ETH/USD (`marketId=1`).
- **Ronda**: período de tiempo fijo (`ROUND_DURATION`, default 300s). El owner la abre y resuelve manualmente.
- **Referencia**: el precio se fija al abrir la ronda (no al cerrar). Las apuestas se aceptan hasta el último segundo.
- **Fee**: 1% de cada apuesta va al Treasury en el momento de apostar.
- **Payout**: proporcional a la contribución al pool ganador.
- **Sin counterparty externo**: el contrato actúa de "clearing house".

#### Ciclo de vida de una ronda

```
   IDLE
    │
    │ openRound() [onlyOwner]
    │ → Lee precio oracle (referencePrice)
    │ → roundPhase = Open
    ▼
   OPEN  ◄─── placeBet() acepta apuestas de todos los usuarios
    │         hasta que: block.timestamp >= openedAt + ROUND_DURATION
    │
    │ resolveRound() [onlyOwner, solo cuando ROUND_DURATION ha pasado]
    │ → Lee precio oracle (finalPrice)
    │ → Determina upWon = (finalPrice > referencePrice)
    │ → Snapshot en _resolvedRounds[marketId][roundId]
    │ → roundPhase = Resolved
    ▼
  RESOLVED
    │
    │ claimPayout() [users, winners only]
    │ → payout = (bet.amount * totalPool) / winningSide
    ▼
   IDLE (nueva ronda puede abrirse)
```

#### Estructuras de datos

```solidity
// Estado activo de la ronda (se sobreescribe en cada openRound)
struct Round {
    uint256    id;             // Número incremental de ronda
    uint256    openedAt;       // Timestamp de apertura
    int256     referencePrice; // Precio al abrir (= precio de referencia)
    int256     finalPrice;     // Precio al resolver
    uint256    totalUp;        // $FLASH neto apostado UP (sin fee)
    uint256    totalDown;      // $FLASH neto apostado DOWN (sin fee)
    RoundPhase phase;          // Idle | Open | Resolved
    bool       upWon;          // True si finalPrice > referencePrice
}

// Snapshot inmutable para claimPayout (sobrevive al próximo openRound)
struct ResolvedRound {
    bool    resolved;
    bool    upWon;
    uint256 totalUp;
    uint256 totalDown;
}

// Apuesta de un usuario en una ronda específica
struct Bet {
    uint256   amount;  // Neto (fee ya deducido)
    Direction dir;     // UP o DOWN
    bool      claimed; // Si ya reclamó su payout
}
```

#### Mappings de estado

```solidity
mapping(uint8 => Round) public rounds;                                          // Ronda activa por mercado
mapping(uint8 => uint256) public roundCount;                                    // Contador de rondas por mercado
mapping(uint8 => mapping(uint256 => ResolvedRound)) private _resolvedRounds;   // Snapshots históricos
mapping(uint8 => mapping(uint256 => mapping(address => Bet))) public bets;     // Apuestas por mercado/ronda/usuario
```

#### Funciones

---

**`openRound(uint8 marketId)`**

```solidity
function openRound(uint8 marketId) external onlyOwner whenNotPaused
```

Abre una nueva ronda para un mercado. Solo el owner puede llamarla.

**Pasos internos:**
1. Valida que el mercado sea válido (0=BTC, 1=ETH).
2. Verifica que la fase actual sea `Idle` o `Resolved` (no se puede abrir una ronda si ya hay una abierta).
3. Consulta el oracle: `refPrice = oracle.getPrice("BTC")` — el precio queda fijado en este momento.
4. Incrementa `roundCount[marketId]` y crea el struct `Round` con `phase = Open`.

**Por qué el precio se fija al abrir:** En Polymarket, el precio de referencia es el estado "antes" de que ocurra el evento. Los apostadores saben desde el inicio contra qué precio se mide el resultado.

- Reverts: `FlashPredMarket__RoundNotIdle` | `FlashPredMarket__InvalidMarket`.
- Emite: `RoundOpened(marketId, roundId, openedAt, referencePrice)`.

---

**`placeBet(uint8 marketId, Direction dir, uint256 amount)`**

```solidity
function placeBet(uint8 marketId, Direction dir, uint256 amount)
    external whenNotPaused nonReentrant
```

Coloca una apuesta en la ronda activa. Cualquier usuario puede llamarla mientras la ronda esté `Open`.

**Pasos internos:**
1. Verifica que la ronda esté `Open` y que `block.timestamp < openedAt + ROUND_DURATION`.
2. Transfiere `amount` de $FLASH del usuario al contrato: `flashToken.safeTransferFrom(user, market, amount)`.
3. Calcula: `fee = amount * 1% / 100` y `netAmount = amount - fee`.
4. Envía el fee al treasury: `flashToken.safeTransfer(treasury, fee)`.
5. Acumula `netAmount` en `r.totalUp` o `r.totalDown` según `dir`.
6. Registra o actualiza la apuesta en `bets[marketId][roundId][msg.sender]`.

**Restricción clave:** Un usuario no puede apostar en ambas direcciones en la misma ronda (`DirectionConflict`). Puede apostar múltiples veces en la misma dirección — los montos se acumulan.

- Reverts: `FlashPredMarket__RoundNotOpen` | `FlashPredMarket__BetWindowClosed` | `FlashPredMarket__AmountZero` | `FlashPredMarket__DirectionConflict`.
- Emite: `BetPlaced(marketId, roundId, bettor, dir, netAmount, fee)`.

---

**`resolveRound(uint8 marketId)`**

```solidity
function resolveRound(uint8 marketId) external onlyOwner whenNotPaused
```

Cierra la ronda, determina el ganador y guarda un snapshot histórico. Solo el owner puede llamarla y solo cuando `ROUND_DURATION` ha transcurrido.

**Pasos internos:**
1. Verifica que la ronda esté `Open` y que `block.timestamp >= openedAt + ROUND_DURATION`.
2. Consulta el precio final del oracle: `finalP = oracle.getPrice("BTC")`.
3. Determina `upWon = (finalP > referencePrice)`.
4. Cambia la fase a `Resolved`.
5. Guarda `_resolvedRounds[marketId][roundId]` — este snapshot persiste aunque la próxima ronda sobreescriba `rounds[marketId]`.

**Por qué snapshot:** El mapping `rounds[marketId]` solo guarda UNA ronda activa. Cuando se abre la siguiente, los datos se sobreescriben. El snapshot en `_resolvedRounds` preserva los resultados históricos para que los usuarios puedan reclamar pagos de rondas anteriores.

- Reverts: `FlashPredMarket__RoundNotOpen` | `FlashPredMarket__RoundStillOpen`.
- Emite: `RoundResolved(marketId, roundId, upWon, refPrice, finalPrice, totalPool, closedAt)`.

---

**`claimPayout(uint8 marketId, uint256 roundId)`**

```solidity
function claimPayout(uint8 marketId, uint256 roundId)
    external whenNotPaused nonReentrant
```

Permite a un ganador retirar su payout proporcional. Puede llamarse en cualquier momento después de que la ronda esté resuelta (incluso cuando ya hay una nueva ronda abierta).

**Fórmula de payout:**
```
totalPool  = totalUp + totalDown
winningSide = upWon ? totalUp : totalDown
payout     = (bet.amount * totalPool) / winningSide
```

**Caso especial (ronda sin counterparty):**
Si `totalPool == winningSide` (solo un lado apostó), el ganador recibe su monto neto de vuelta sin ganancia — no hubo contraparte.

**Patrón Checks-Effects-Interactions:**
```solidity
bet.claimed = true;                                          // Effect (antes de transfer)
IERC20(flashToken).safeTransfer(msg.sender, payout);        // Interaction (al final)
```
Esto previene ataques de reentrancy donde el atacante llame `claimPayout` recursivamente.

- Reverts: `FlashPredMarket__RoundNotResolved` | `FlashPredMarket__NoBetFound` | `FlashPredMarket__AlreadyClaimed` | `FlashPredMarket__NotWinner`.
- Emite: `PayoutClaimed(marketId, roundId, user, payout)`.

---

**View helpers**

| Función | Descripción |
|---|---|
| `getRound(marketId)` | Retorna el struct `Round` activo (puede estar en cualquier fase) |
| `getResolvedRound(marketId, roundId)` | Retorna el snapshot histórico de una ronda resuelta |
| `getBet(marketId, roundId, bettor)` | Retorna el struct `Bet` de un usuario en una ronda específica |
| `marketSymbol(marketId)` | Retorna `"BTC"` o `"ETH"` según el marketId |

---

**Custom errors**

| Error | Cuándo se lanza |
|---|---|
| `FlashPredMarket__InvalidMarket` | marketId >= 2 (solo 0 y 1 son válidos) |
| `FlashPredMarket__RoundNotIdle` | `openRound` cuando ya hay una ronda Open |
| `FlashPredMarket__RoundNotOpen` | `placeBet`/`resolveRound` cuando fase != Open |
| `FlashPredMarket__RoundNotResolved` | `claimPayout` cuando la ronda no está resuelta aún |
| `FlashPredMarket__RoundStillOpen` | `resolveRound` antes de que venza el tiempo |
| `FlashPredMarket__AmountZero` | Apuesta con amount = 0 |
| `FlashPredMarket__BetWindowClosed` | Apuesta cuando el tiempo de la ronda ya venció |
| `FlashPredMarket__AlreadyClaimed` | `claimPayout` doble |
| `FlashPredMarket__NotWinner` | `claimPayout` desde el lado perdedor |
| `FlashPredMarket__NoBetFound` | `claimPayout` sin haber apostado |
| `FlashPredMarket__ZeroAddress` | Constructor con address(0) |
| `FlashPredMarket__DirectionConflict` | Apostar UP y DOWN en la misma ronda |
| `FlashPredMarket__AlreadyBet` | Segunda apuesta en ronda cerrada (edge case) |

---

### 5.4 Oracle de precios (`IFlashOracle`)

**Interfaz:** `protocol/src/interfaces/IFlashOracle.sol`

**Propósito:** El protocolo consume precios a través de la interfaz `IFlashOracle`. Esto desacopla completamente `FlashPredMarket` de la implementación concreta del oracle, permitiendo usar un mock en testnet y un wrapper de Chainlink en producción sin cambiar nada del contrato del mercado.

```solidity
interface IFlashOracle {
    function getPrice(string calldata symbol) external view returns (int256);
}
```

#### Implementación en testnet (Sepolia — este proyecto)

Se usa **`MockFlashOracle`** (ver §5.6). Los feeds de Chainlink en Sepolia son lentos e inconsistentes para demos: pueden quedar estáticos durante minutos, haciendo que `openRound()` y `resolveRound()` vean el mismo precio y la ronda no tenga resultado significativo.

La decisión de usar `MockFlashOracle` con simulación habilitada fue **intencional** para garantizar la demostrabilidad del protocolo sin depender de infraestructura externa.

---

### 5.5 `Treasury.sol`

**Ruta:** `protocol/src/Treasury.sol`

**Propósito:** Contrato receptor de todos los ingresos del protocolo. Acumula:

- **Trading fees** (1% de cada apuesta): recibidos en `$FLASH` desde `FlashPredMarket`.
- **Yield de Aave**: recibido en USDT desde `FlashVault.harvestYield()`.

El contrato es intencionalmente minimalista — no tiene vesting, no tiene splits automáticos, no tiene votación. Solo el owner puede retirar.

#### Funciones

---

**`withdraw(address token, address to, uint256 amount)`**

```solidity
function withdraw(address token, address to, uint256 amount) external onlyOwner
```

Retira `amount` de `token` (USDT o $FLASH) hacia `to`. Solo owner.

- Reverts: `Treasury__ZeroAddress` | `Treasury__AmountZero` | `Treasury__InsufficientBalance`.
- Emite: `Withdrawn(token, to, amount)`.

---

**`balance(address token)` (view)**

```solidity
function balance(address token) external view returns (uint256)
```

Retorna el saldo actual del treasury para un token dado. Útil para el Admin Panel del frontend.

---

### 5.6 Contratos Mock (Testnet)

Los mocks permiten correr el protocolo completo en Sepolia sin depender de infraestructura externa real (Aave V3 real, Chainlink feeds reales).

---

#### `MockFlashOracle.sol`

**Ruta:** `protocol/src/mocks/MockFlashOracle.sol`

Simula un feed de precios Chainlink con dos modos de operación:

**Modo determinístico** (`simulationEnabled = false`, default):
- `getPrice()` devuelve exactamente el precio configurado con `setPrice()`.
- Usado en tests unitarios para resultados exactos.

**Modo simulación** (`simulationEnabled = true`, activado en deploy a Sepolia):
- `getPrice()` agrega ruido pseudo-aleatorio al precio base, derivado del `block.timestamp` y `blockhash`.
- **Componente lento** (cada 30s): tendencia direccional ± `volatilityBps` (default 1.5%).
- **Componente rápido** (cada bloque): ruido micro ±0.02%.
- **Propósito**: garantizar que `openRound()` y `resolveRound()` siempre vean precios distintos en Sepolia, sin necesitar un keeper externo que actualice precios. Resuelve el problema de "siempre empata" en testnet.

```
Precio base BTC = $66,000
Slow dev  = 66_000 * (seed % 301 - 150) / 10_000 → máx ±$990
Fast dev  = 66_000 * (seed % 41 - 20) / 100_000  → máx ±$13.2
Precio final = 66_000 ± (slow + fast)
```

**Funciones:**

| Función | Descripción |
|---|---|
| `setPrice(symbol, price)` | Fija el precio base (cualquiera puede llamarlo — permisionless) |
| `getPrice(symbol)` | Retorna precio base ± ruido (si simulationEnabled) |
| `getBasePrice(symbol)` | Retorna siempre el precio base sin ruido |
| `enableSimulation()` | Activa el modo de simulación |
| `disableSimulation()` | Desactiva la simulación (vuelve a precio exacto) |
| `setVolatility(bps)` | Ajusta la volatilidad máxima. Default 150 (±1.5%). Máx 500 (±5%) |

---

#### `MockAavePool.sol`

**Ruta:** `protocol/src/mocks/MockAavePool.sol`

Simula el comportamiento del Pool de Aave V3. Implementa `supply()` y `withdraw()` con la misma firma que el pool real.

**Truco del yield:** En Aave real, el `aToken.balanceOf()` crece por segundo (interés compuesto continuo). En el mock, al hacer `supply(amount)`, el pool mintea `amount + 5%` aTokens inmediatamente. Así, desde el primer momento hay yield "pendiente" para poder demostrar `harvestYield()`.

```
supply(200 USDT) → mint(vault, 200 + 10) = 210 maUSDT
pendingYield = aBalance(210) - totalDeposited(200) = 10 USDT
```

**Pre-requisito:** El deployer debe llamar `seedYieldReserve(amount)` con USDT suficiente para respaldar los yield bonus. El script `Deploy.s.sol` lo hace con 20 USDT.

---

#### `MockAToken.sol`

**Ruta:** `protocol/src/mocks/MockAToken.sol`

ERC-20 simple de 6 decimales que actúa como `aUSDT`. Solo el pool puede mintear o quemar. El vault lo usa para medir cuánto USDT tiene en Aave (el balance de aUSDT es la "libreta" del vault).

---

### 5.7 Interfaces

#### `IFlashOracle`

```solidity
interface IFlashOracle {
    function getPrice(string calldata symbol) external view returns (int256);
}
```

Contrato abstracto compartido por `FlashOracle` (producción) y `MockFlashOracle` (testnet/tests). `FlashPredMarket` solo conoce esta interfaz — puede recibir cualquiera de las dos implementaciones en el constructor.

#### `IAavePool`

```solidity
interface IAavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}
```

Subconjunto mínimo del IPool de Aave V3. Solo se usan `supply` y `withdraw`. Implementado por `MockAavePool` en testnet y por el Pool proxy real de Aave V3 en producción.

---

## 6. Flujos principales de usuario

### Flujo 1: Depositar USDT y obtener $FLASH

```
1. Usuario aprueba USDT al vault:
   USDT.approve(FlashVault, 1000e6)

2. Usuario deposita:
   FlashVault.deposit(1000e6)
   └─ vault toma 1000 USDT
   └─ vault suministra 1000 USDT a Aave
   └─ vault recibe 1050 maUSDT (5% yield del mock)
   └─ vault mintea 1000 $FLASH al usuario

Resultado: usuario tiene 1000 $FLASH. Aave genera interés en background.
```

### Flujo 2: Apostar en el mercado de predicción

```
1. Usuario aprueba $FLASH al mercado:
   FlashToken.approve(FlashPredMarket, 100e6)

2. Admin abre una ronda:
   FlashPredMarket.openRound(0) // BTC
   └─ Oracle: BTC = $66,000 → referencePrice = 66_000e8
   └─ Ronda #1 en estado Open

3. Usuario apuesta 100 $FLASH a UP:
   FlashPredMarket.placeBet(0, Direction.UP, 100e6)
   └─ vault toma 100 $FLASH del usuario
   └─ fee = 1 $FLASH → Treasury
   └─ net = 99 $FLASH → pool UP

4. Pasan 300 segundos. Admin resuelve:
   FlashPredMarket.resolveRound(0)
   └─ Oracle: BTC = $66,500 → finalPrice = 66_500e8
   └─ finalPrice > referencePrice → upWon = true
   └─ Snapshot guardado en _resolvedRounds[0][1]

5. Usuario ganador reclama:
   FlashPredMarket.claimPayout(0, 1)
   └─ payout = (99 * totalPool) / totalUp
   └─ $FLASH transferidos al usuario
```

### Flujo 3: Cosechar yield de Aave

```
Cualquier cuenta puede llamar:
FlashVault.harvestYield()
└─ aUSDT balance > totalDeposited
└─ Diferencia = yield puro
└─ Aave withdraw(yield) → Treasury (en USDT)
```

### Flujo 4: Recuperar USDT (redención)

```
FlashVault.redeem(500e6)
└─ FlashToken.burn(usuario, 500 $FLASH)
└─ totalDeposited -= 500
└─ Aave withdraw(500 USDT) → usuario directamente
```

---

## 7. Modelo económico

### Flujos de ingresos del Treasury

```
Treasury recibe:
  ┌─ 1% de cada apuesta (en $FLASH)  ← FlashPredMarket.placeBet()
  └─ Yield de Aave (en USDT)         ← FlashVault.harvestYield()
```

### Fórmula de payout

```
Si UP gana:
  payout_i = (bet_i_up * (totalUp + totalDown)) / totalUp

Ejemplo:
  Alice apuesta 100 UP  → net = 99
  Bob   apuesta 200 DOWN → net = 198
  totalPool = 297, totalUp = 99

  Alice payout = (99 * 297) / 99 = 297 $FLASH
  Alice ganancia = 297 - 99 = 198 $FLASH (exactamente lo que perdió Bob)
```

### Invariante de solvencia

```
sum(payouts_ganadores) <= totalPool = totalUp + totalDown
```

El contrato siempre puede pagar a todos los ganadores porque el pool total está depositado en el contrato. No hay riesgo de insolvencia.

### Caso borde: ronda sin contraparte

```
Si solo UP apostó (totalDown = 0):
  totalPool == totalUp
  payout = (bet * totalPool) / totalPool = bet
  → Reembolso completo. Ningún ganador real.
```

---

## 8. Seguridad y control de acceso

### Matriz de permisos

| Función | Permiso requerido | Contrato |
|---|---|---|
| `FlashToken.pause()` | `DEFAULT_ADMIN_ROLE` | FlashToken |
| `FlashToken.mint()` | `MINTER_ROLE` (asignado a vault) | FlashToken |
| `FlashToken.burn()` | `BURNER_ROLE` (asignado a vault) | FlashToken |
| `FlashVault.pause()` | `onlyOwner` | FlashVault |
| `FlashVault.deposit()` | `whenNotPaused` + `nonReentrant` | FlashVault |
| `FlashVault.redeem()` | `whenNotPaused` + `nonReentrant` | FlashVault |
| `FlashVault.harvestYield()` | `whenNotPaused` + `nonReentrant` (permisionless) | FlashVault |
| `FlashPredMarket.openRound()` | `onlyOwner` + `whenNotPaused` | FlashPredMarket |
| `FlashPredMarket.placeBet()` | `whenNotPaused` + `nonReentrant` | FlashPredMarket |
| `FlashPredMarket.resolveRound()` | `onlyOwner` + `whenNotPaused` | FlashPredMarket |
| `FlashPredMarket.claimPayout()` | `whenNotPaused` + `nonReentrant` | FlashPredMarket |
| `Treasury.withdraw()` | `onlyOwner` | Treasury |

### Protecciones implementadas

#### Reentrancy Guard

`FlashVault` y `FlashPredMarket` heredan `ReentrancyGuard` de OpenZeppelin. Todas las funciones que transfieren tokens usan `nonReentrant`. Adicionalmente, `claimPayout` sigue el patrón **Checks-Effects-Interactions**:

```solidity
bet.claimed = true;                    // ← EFFECT primero
flashToken.safeTransfer(msg.sender, payout); // ← INTERACTION después
```

#### SafeERC20

Todas las transferencias de tokens usan `SafeERC20.safeTransfer` / `safeTransferFrom`. Esto envuelve las llamadas ERC-20 y revierte si el token retorna `false` en lugar de lanzar. Crítico para USDT, que tiene comportamiento no estándar en `approve`.

#### `forceApprove` para USDT

USDT tiene un bug conocido: `approve(x)` revierte si el allowance previo es distinto de cero. `SafeERC20.forceApprove` primero hace `approve(0)` y luego `approve(x)`, evitando el revert.

#### Custom errors (gas efficiency)

El protocolo usa custom errors en lugar de `require(condition, "string")`. Ahorra ~50 bytes de calldata por error, que a 16 gas/byte es un ahorro significativo en redes con gas caro.

#### Pausable (circuit breaker)

Los tres contratos principales heredan `Pausable`. El owner puede pausar en caso de bug crítico, exploit activo, o necesidad de migración. Cuando está pausado, todas las funciones de usuario revierten.

#### Immutables para infraestructura

Oracle, token, pool de Aave, treasury — todos son `immutable`. Se setean en el constructor y no pueden modificarse después. Elimina la posibilidad de un ataque "cambiar el oracle" por parte de un owner malicioso post-deploy.

---

## 9. Tests unitarios

**Framework:** Foundry (`forge test`)
**Resultado:** 120 tests unitarios — todos pasan. 4 archivos de test.

| Archivo | Tests | Qué cubre |
|---|---|---|
| `FlashToken.t.sol` | ~24 | Roles, mint, burn, pause/unpause, decimales, validaciones |
| `FlashVault.t.sol` | ~30 | Deposit, redeem, harvestYield, pendingYield, fuzz, pause/unpause |
| `FlashPredMarket.t.sol` | ~48 | openRound, placeBet, resolveRound, claimPayout, fuzz, integración |
| `Treasury.t.sol` | ~18 | Withdraw, balance, multi-token, validaciones de acceso |

### `FlashToken.t.sol`

Cubre:
- Roles: solo MINTER_ROLE puede mint, solo BURNER_ROLE puede burn
- Validaciones: amount=0, to=address(0)
- Pause/unpause: mint y burn revierten cuando pausado
- Decimales: 6
- AccessControl: reverts al intentar operaciones sin rol

### `FlashVault.t.sol`

Cubre:
- `deposit()`: flujo completo, totalDeposited, mint 1:1
- `redeem()`: burn + withdraw de Aave, balances
- `harvestYield()`: yield acumulado va al treasury
- `pendingYield()`: vista del yield pendiente
- Casos extremos: amount=0, balance insuficiente
- Fuzz: deposit y redeem con amounts aleatorios
- Pause/unpause: todas las funciones revierten cuando pausado

### `FlashPredMarket.t.sol`

Cubre:
- Estado inicial: Idle, roundCount=0, marketSymbols
- `openRound()`: bloqueo de referencePrice, phase=Open, solo owner, doble open revierte
- `placeBet()`: fee=1%, pool acumulado, apuesta hasta el último segundo, revierte al vencer, conflicto de dirección
- `resolveRound()`: UP wins, DOWN wins, snapshot, solo owner, revierte si aún abierto
- `claimPayout()`: UP wins, DOWN wins, proporcional (3 bettors), ronda sin contraparte (refund), doble claim, no ganador, sin apuesta, ronda sin resolver
- `claimPayout` de ronda histórica (nueva ronda ya abierta)
- **Fuzz**: invariante `payout <= totalPool` con amounts aleatorios
- **Integración**: BTC + ETH simultáneos en el mismo bloque
- Pause/unpause: todas las funciones de usuario revierten cuando pausado

### `Treasury.t.sol`

Cubre:
- `withdraw()`: retira USDT y $FLASH correctamente al owner
- `balance()`: refleja saldos correctos por token
- Multi-token: acumula USDT y $FLASH independientemente
- Control de acceso: solo owner puede retirar
- Validaciones: ZeroAddress, AmountZero, InsufficientBalance

---

## 10. Despliegue

### Script: `Deploy.s.sol`

Despliega el protocolo completo en una sola transacción broadcast. Secuencia:

```
1. MockAToken      ← aUSDT sustituto
2. MockAavePool    ← Aave V3 sustituto (necesita dirección de MockAToken)
3. MockFlashOracle ← Chainlink sustituto
4. Treasury        ← receptor de ingresos
5. FlashToken      ← token $FLASH
6. FlashVault      ← vault de colateral
7. FlashPredMarket ← mercado de predicción

Post-deploy:
  flash.grantRole(MINTER_ROLE, vault)
  flash.grantRole(BURNER_ROLE, vault)
  oracle.setPrice("BTC", 66_000e8)
  oracle.setPrice("ETH", 2_500e8)
  oracle.enableSimulation()
  USDT.approve(pool, 20e6)
  pool.seedYieldReserve(20e6)  // 20 USDT para cubrir yield demos
```

**Predicción de dirección:** `MockAToken` necesita la dirección de `MockAavePool` en su constructor. El script usa `vm.computeCreateAddress(deployer, nonce + 1)` para predecir la dirección antes de deployar.

### Script de automatización: `deploy.sh`

```bash
cd protocol && ./deploy.sh
```

Ejecuta en secuencia:
1. `forge script Deploy.s.sol --broadcast --verify` → despliega contratos y verifica en Etherscan.
2. Extrae el `startBlock` del primer receipt del broadcast (para el subgraph).
3. Actualiza `dapp/.env.local` con las nuevas direcciones de contratos.
4. Actualiza `subgraph/subgraph.yaml` con la nueva dirección de `FlashPredMarket` y el nuevo `startBlock`.
5. `graph codegen && graph build` → regenera código del subgraph.
6. `goldsky subgraph deploy flashbet/1.0.YYYYMMDDHHMM --path .` → despliega a Goldsky.

### Variables de entorno requeridas

```bash
# protocol/.env
SEPOLIA_MNEMONIC="word word word ..."   # 12 palabras BIP39
SEPOLIA_RPC_URL=https://...             # Infura / Alchemy Sepolia
ETHERSCAN_API_KEY=...                   # Para verificación automática
GOLDSKY_API_KEY=...                     # Para deploy del subgraph
```

### Requisitos previos

- ~0.05 ETH en Sepolia para gas
- 20 USDT en Sepolia para seed del yield reserve
  - Faucet: `https://sepolia.etherscan.io/address/0x7169d38820dfd117c3fa1f22a697dba58d90ba06`

### Demo del mercado de predicción (`demo_pred_market.sh`)

Script que ejecuta el ciclo completo del mercado de predicción en Sepolia en ~2 minutos:

```bash
cd protocol/script
./demo_pred_market.sh
```

**Qué hace en secuencia:**

- **Step A** — Despliega `FlashToken`, `MockFlashOracle`, `Treasury` y `FlashPredMarket`. Abre una ronda BTC/USD fijando el precio de referencia (`$30,000`) en ese instante. Player 1 apuesta 200 $FLASH a UP y Player 2 apuesta 300 $FLASH a DOWN. Verifica todos los contratos en Etherscan automáticamente.
- **Espera automática** — El script aguarda 70s (60s de ronda + 10s de buffer) con una barra de progreso en tiempo real.
- **Step B** — Actualiza el oracle a `$31,000`, llama `resolveRound()` (UP gana), y Player 1 reclama su payout proporcional.

**Resultado real en Sepolia (última ejecución):**

```
Player 1 (200 FLASH on UP)  → Payout: 495 FLASH  (+297 FLASH de profit)
Player 2 (300 FLASH on DOWN)→ Pierde 297 FLASH net
Treasury                    → Acumula 5 FLASH (1% fee de cada apuesta)
Market balance              → 0 FLASH (solvente, todo distribuido)
```

| Lo que demuestra | Mecanismo |
|---|---|
| Precio de referencia bloqueado al abrir | `openRound()` lee oracle en ese instante |
| Apuestas hasta el último segundo | Estilo Polymarket — sin fase de cierre |
| Fee automático al Treasury | 1% de cada apuesta en el mismo tx |
| Payout proporcional | `(bet * totalPool) / winningSide` |
| Snapshot histórico | `ResolvedRound` persiste para claims futuros |

---

## 11. Indexación con The Graph

El subgraph indexa los eventos de `FlashPredMarket` y expone una API GraphQL para consultas históricas eficientes.

### Por qué The Graph (en lugar de `getLogs`)

Los RPC providers (Infura, Alchemy) limitan las llamadas `eth_getLogs` con rangos de bloques amplios. En Sepolia, `fromBlock: 0` falla. The Graph indexa eventos on-chain en tiempo real y permite paginación eficiente.

### Entidades indexadas

```graphql
type Round {
  id: ID!              # "{marketId}-{roundId}"
  marketId: Int!
  roundId: BigInt!
  openedAt: BigInt!
  closedAt: BigInt
  referencePrice: BigInt!
  finalPrice: BigInt
  upWon: Boolean
  totalPool: BigInt
  resolved: Boolean!
  bets: [Bet!]! @derivedFrom(field: "round")
}

type Bet {
  id: ID!              # "{marketId}-{roundId}-{bettor}"
  round: Round!
  bettor: Bytes!
  direction: Int!      # 0=UP, 1=DOWN
  netAmount: BigInt!
  fee: BigInt!
  payout: BigInt
  claimed: Boolean!
}
```

### Eventos mapeados → handlers

| Evento del contrato | Handler del subgraph | Qué indexa |
|---|---|---|
| `RoundOpened` | `handleRoundOpened` | Crea entidad `Round` con estado inicial |
| `BetPlaced` | `handleBetPlaced` | Crea entidad `Bet` y actualiza pools de la ronda |
| `RoundResolved` | `handleRoundResolved` | Actualiza `Round` con `finalPrice`, `upWon`, `totalPool` |
| `PayoutClaimed` | `handlePayoutClaimed` | Actualiza `Bet.payout` y `Bet.claimed = true` |

### Deploy del subgraph

```bash
cd subgraph
npm install
graph codegen && graph build
goldsky subgraph deploy flashbet/1.0.YYYYMMDDHHMM --path .
```

---

## 12. Contratos desplegados en Sepolia

Todos verificados en Etherscan:

| Contrato | Dirección |
|---|---|
| FlashToken ($FLASH) | [`0xC7e23DB5aD763bE17d7327E62a402D66eCB5970C`](https://sepolia.etherscan.io/address/0xC7e23DB5aD763bE17d7327E62a402D66eCB5970C) |
| FlashVault | [`0x4Ed1547b1D049E5aC4BF28aAc51228B49805A2AE`](https://sepolia.etherscan.io/address/0x4Ed1547b1D049E5aC4BF28aAc51228B49805A2AE) |
| FlashPredMarket | [`0xfF7b0425cFf18969B03b36b2125eef13AC5Faa22`](https://sepolia.etherscan.io/address/0xfF7b0425cFf18969B03b36b2125eef13AC5Faa22) |
| Treasury | [`0xdc2111EC6dc36F0D713baa3D4A8Cf803416E7721`](https://sepolia.etherscan.io/address/0xdc2111EC6dc36F0D713baa3D4A8Cf803416E7721) |
| MockFlashOracle | [`0xC455281F05e96853A8b1ad3869246ebb61AabA1c`](https://sepolia.etherscan.io/address/0xC455281F05e96853A8b1ad3869246ebb61AabA1c) |
| MockAavePool | [`0x15c076D355fE3cE4C03bf193AA13f16806A7aEE1`](https://sepolia.etherscan.io/address/0x15c076D355fE3cE4C03bf193AA13f16806A7aEE1) |
| MockAToken (maUSDT) | [`0x96F88e150A5dFE2dbfa3c570eE4310E78477D3d0`](https://sepolia.etherscan.io/address/0x96F88e150A5dFE2dbfa3c570eE4310E78477D3d0) |
| USDT (Sepolia) | [`0x7169D38820dfd117C3FA1f22a697dBA58d90BA06`](https://sepolia.etherscan.io/address/0x7169D38820dfd117C3FA1f22a697dBA58d90BA06) |

---

## 13. Frontend (DApp)

La DApp es una aplicación **React 19 + TypeScript** con tema cyberpunk (Orbitron + JetBrains Mono, paleta cyan/purple). Está desplegada en Vercel y se comunica con los contratos vía `wagmi v2` + `viem v2` + `RainbowKit v2`.

> **Wallet soportada:** La DApp usa exclusivamente **MetaMask** (o cualquier extensión de wallet inyectada en el navegador). No se usa WalletConnect ni ningún SDK de conexión remota. Esto garantiza que el evento `accountsChanged` del navegador se propague correctamente tanto en local como en producción, de forma que cambiar de cuenta en MetaMask actualiza la DApp de forma inmediata.

### Stack frontend

| Tecnología | Versión | Rol |
|---|---|---|
| React | 19.2.0 | Framework UI |
| TypeScript | ~5.9.3 | Tipado estático |
| Vite | 7.3.1 | Bundler + HMR |
| wagmi | 2.19.5 | Hooks de blockchain |
| viem | 2.46.3 | Cliente Ethereum |
| RainbowKit | 2.2.10 | Conexión de wallets |
| TanStack Query | 5.90.21 | Estado asíncrono |
| TailwindCSS | 3.4.19 | Estilos |
| react-router-dom | 7.13.1 | Routing SPA |
| recharts | 3.7.0 | Gráficos de precio |
| react-hot-toast | 2.6.0 | Notificaciones |

### Páginas

| Página | Ruta | Descripción |
|---|---|---|
| `HomePage` | `/` | Selección de sección: vault o mercados |
| `VaultPage` | `/vault` | Depósito/redención USDT ↔ $FLASH |
| `MarketsPage` | `/markets` | MarketCard BTC y ETH con countdown, pools y apuestas |
| `HistoryPage` | `/history` | Historial de rondas paginado vía The Graph |
| `AdminPage` | `/admin` | Panel del owner: openRound/resolveRound, harvest yield, métricas, top wallets |

### Custom hooks

| Hook | Descripción |
|---|---|
| `usePredMarket` | Estado del mercado, placeBet, openRound, resolveRound, claimPayout |
| `useVault` | Deposit, redeem, harvestYield con flujo approve implícito |
| `useFlashBalance` | Balance $FLASH del usuario |
| `useHistory` | Historial de rondas via The Graph (GraphQL + paginación) |
| `useAdminStats` | Métricas globales + top 5 winners/losers via The Graph |
| `useLivePrice` | Precio on-chain desde MockFlashOracle (8 decimales → display) |
| `useCoinGeckoPrice` | Precio off-chain BTC/ETH desde CoinGecko API |
| `useRoundTimer` | Countdown MM:SS en tiempo real |
| `useIsAdmin` | Booleano: `address == FlashPredMarket.owner()` |

### Variables de entorno requeridas (`dapp/.env.local`)

```env
# RPC de Sepolia — Alchemy
VITE_SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/TU_KEY

# Contratos desplegados
VITE_FLASHTOKEN_ADDRESS=0x...
VITE_FLASHVAULT_ADDRESS=0x...
VITE_FLASHPREDMARKET_ADDRESS=0x...
VITE_TREASURY_ADDRESS=0x...
VITE_MOCKORACLE_ADDRESS=0x...
VITE_MOCKAAVEPOOL_ADDRESS=0x...
VITE_MOCKATOKEN_ADDRESS=0x...

# The Graph
VITE_GRAPH_URL=https://api.goldsky.com/...
```

> **Nota:** `VITE_WALLETCONNECT_PROJECT_ID` ha sido eliminada. La dapp usa el conector `injected` de wagmi directamente — no depende de WalletConnect.

Todas las direcciones tienen fallback hardcodeado en `dapp/src/config/contracts.ts` con los valores del último deploy.

---

## 14. Estructura de carpetas

```
ebis-flashbet/
│
├── protocol/                          # Smart contracts (Foundry)
│   ├── src/
│   │   ├── FlashToken.sol             # ERC20 nativo del protocolo ($FLASH, 6 dec)
│   │   ├── FlashVault.sol             # Vault: USDT → Aave → $FLASH
│   │   ├── FlashPredMarket.sol        # Mercado de predicción UP/DOWN
│   │   ├── Treasury.sol               # Receptor de fees ($FLASH) y yield (USDT)
│   │   ├── interfaces/
│   │   │   ├── IAavePool.sol          # Interfaz mínima del Pool de Aave V3
│   │   │   └── IFlashOracle.sol       # Interfaz del oracle de precios
│   │   └── mocks/
│   │       ├── MockFlashOracle.sol    # Oracle simulado (±1.5% por bloque)
│   │       ├── MockAavePool.sol       # Aave simulado (+5% yield instantáneo)
│   │       └── MockAToken.sol         # aUSDT simulado (6 decimales)
│   ├── script/
│   │   ├── Deploy.s.sol               # Script de despliegue completo
│   │   ├── FlashBetDemo.s.sol         # Script de demo vault
│   │   └── FlashBetPredMarketDemo.s.sol # Script de demo mercado
│   ├── test/
│   │   ├── FlashToken.t.sol           # ~24 tests del token
│   │   ├── FlashVault.t.sol           # ~30 tests del vault (con mocks)
│   │   ├── FlashPredMarket.t.sol      # ~48 tests del mercado
│   │   └── Treasury.t.sol             # ~18 tests del treasury
│   ├── foundry.toml                   # Configuración compilador (solc 0.8.30)
│   └── deploy.sh                      # Script bash: deploy + subgraph a Goldsky
│
├── subgraph/                          # The Graph subgraph (indexa FlashPredMarket)
│   ├── subgraph.yaml                  # Contrato, red Sepolia, startBlock, handlers
│   ├── schema.graphql                 # Entidades: Round, Bet
│   ├── abis/                          # ABI de FlashPredMarket
│   └── src/
│       └── flash-pred-market.ts       # Handlers: handleRoundOpened, handleBetPlaced,
│                                      #   handleRoundResolved, handlePayoutClaimed
│
├── dapp/                              # Frontend React 19 + TypeScript
│   ├── src/
│   │   ├── abi/                       # ABIs de los contratos
│   │   ├── config/
│   │   │   ├── contracts.ts           # Addresses por chainId (con fallback hardcodeado)
│   │   │   └── wagmi.ts               # Config wagmi con conector injected (Sepolia, MetaMask only)
│   │   ├── hooks/
│   │   │   ├── usePredMarket.ts       # Mercado: apuestas, rondas, payout
│   │   │   ├── useVault.ts            # Vault: depósito, redención, harvest
│   │   │   ├── useFlashBalance.ts     # Balance $FLASH del usuario
│   │   │   ├── useHistory.ts          # Historial de rondas via The Graph
│   │   │   ├── useAdminStats.ts       # Métricas globales + top wallets
│   │   │   ├── useLivePrice.ts        # Precio on-chain (MockFlashOracle)
│   │   │   ├── useCoinGeckoPrice.ts   # Precio off-chain (CoinGecko API)
│   │   │   ├── useRoundTimer.ts       # Countdown MM:SS en tiempo real
│   │   │   └── useIsAdmin.ts          # ¿Es el usuario el owner del contrato?
│   │   ├── components/
│   │   │   ├── layout/                # Navbar, Footer, AccountWatcher
│   │   │   ├── sections/              # VaultSection, MarketCard, ClaimBanner
│   │   │   └── ui/                    # NeonButton, GlassCard, CountdownTimer,
│   │   │                              #   PoolBar, TxStatus, PriceChart
│   │   ├── pages/
│   │   │   ├── HomePage.tsx           # Selección de sección
│   │   │   ├── VaultPage.tsx          # Depósito/redención
│   │   │   ├── MarketsPage.tsx        # Mercados BTC y ETH con MarketCard
│   │   │   ├── HistoryPage.tsx        # Historial paginado (The Graph)
│   │   │   └── AdminPage.tsx          # Panel admin: rondas, yield, métricas
│   │   └── utils/
│   │       ├── format.ts              # formatFlash, parseFlash, calcPayout, etc.
│   │       └── errors.ts              # parseContractError (errores en español)
│   ├── package.json
│   ├── vite.config.ts
│   ├── tailwind.config.js
│   ├── tsconfig.json
│   └── vercel.json                    # SPA routing en Vercel
│
├── README.md                          # Esta documentación
└── [MDB] TFM Parte I - Proyecto Ethereum.pdf  # Guía oficial del TFM (EBIS)
```

---

## 15. Alcance y entregables del proyecto

FlashBet es un protocolo DeFi completo desarrollado como Trabajo Final de Máster en el **Máster en Ingeniería y Desarrollo Blockchain (MDB)** de EBIS Business Techschool. El proyecto cubre el ciclo completo de una DApp: diseño del protocolo, implementación de contratos, tests, indexación on-chain y frontend desplegado.

### Smart Contracts y DApp

El núcleo del proyecto son cuatro contratos Solidity desplegados y verificados en Ethereum Sepolia: `FlashToken`, `FlashVault`, `FlashPredMarket` y `Treasury`. Cada uno tiene responsabilidad única y se comunica con los demás a través de interfaces bien definidas. La DApp está construida con React 19 + wagmi v2 y desplegada en Vercel, conectándose a los contratos en tiempo real sin intermediarios.

### DApp publicada

La aplicación está disponible públicamente en Vercel. El despliegue es continuo: cada push a `main` lanza un nuevo build automáticamente. El directorio raíz configurado en Vercel es `dapp/`.

### Tests unitarios

El protocolo cuenta con 120 tests unitarios escritos con Foundry, distribuidos en cuatro archivos (`FlashToken.t.sol`, `FlashVault.t.sol`, `FlashPredMarket.t.sol`, `Treasury.t.sol`). Cubren flujos normales, casos borde, fuzzing y comportamiento bajo pausa. Todos pasan con `forge test`.

### Documentación técnica

La documentación está integrada directamente en el repositorio: este README describe la arquitectura, los contratos, los flujos de usuario y las decisiones de diseño. Los contratos están verificados en Etherscan para que cualquiera pueda leer el código fuente on-chain. El archivo `CLAUDE.md` documenta las convenciones internas del proyecto.

### Integración con el ecosistema DeFi

FlashBet no opera en aislamiento — integra varios protocolos y herramientas del ecosistema:

- **Aave V3**: el vault suministra USDT al pool de Aave para generar yield pasivo.
- **The Graph / Goldsky**: un subgraph indexa los eventos de `FlashPredMarket` y expone una API GraphQL para datos históricos sin depender de `getLogs`.
- **RainbowKit + wagmi v2 + viem v2**: stack de conexión de wallets inyectadas (MetaMask). Se usa el conector `injected` nativo de wagmi — sin WalletConnect — para garantizar sincronización reactiva al cambiar de cuenta en producción.
- **MockFlashOracle con simulación**: oracle propio con ruido pseudo-aleatorio por bloque, garantizando precios distintos entre apertura y cierre de ronda sin ningún servicio externo.
- **`deploy.sh`**: script de automatización que despliega contratos, actualiza variables de entorno, regenera el subgraph y lo publica en Goldsky en un solo comando.

### Entregables

- **Código fuente**: este repositorio en GitHub
- **DApp**: desplegada en Vercel

---

*FlashBet Protocol — TFM Máster en Ingeniería y Desarrollo Blockchain (MDB)*

*Desarrollado por Maximiliano Morero*
