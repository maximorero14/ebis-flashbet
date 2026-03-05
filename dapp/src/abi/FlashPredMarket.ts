/**
 * ABI de FlashPredMarket — Mercado de predicción estilo Polymarket.
 *
 * Mercados disponibles:
 *   MARKET_BTC = 0  (BTC/USD)
 *   MARKET_ETH = 1  (ETH/USD)
 *
 * Fases de una ronda (enum Phase):
 *   0 = Idle      → ronda no iniciada
 *   1 = Open      → aceptando apuestas (hasta ROUND_DURATION segundos)
 *   2 = Resolved  → resultado determinado, pagos habilitados
 *
 * Dirección de apuesta (enum Dir):
 *   0 = UP    → el precio sube respecto al referencePrice
 *   1 = DOWN  → el precio baja respecto al referencePrice
 *
 * Fee: 1% (FEE_BPS = 100) → va al Treasury en cada apuesta.
 * Payout: proporcional al monto neto apostado en el lado ganador.
 */
export const FlashPredMarketABI = [
  // ── Constantes ─────────────────────────────────────
  {
    name: 'MARKET_BTC',
    type: 'function',
    stateMutability: 'view',
    inputs:  [],
    outputs: [{ type: 'uint8' }],   // retorna 0
  },
  {
    name: 'MARKET_ETH',
    type: 'function',
    stateMutability: 'view',
    inputs:  [],
    outputs: [{ type: 'uint8' }],   // retorna 1
  },
  {
    name: 'ROUND_DURATION',
    type: 'function',
    stateMutability: 'view',
    inputs:  [],
    outputs: [{ type: 'uint256' }], // segundos (60 en demo)
  },
  {
    name: 'FEE_BPS',
    type: 'function',
    stateMutability: 'view',
    inputs:  [],
    outputs: [{ type: 'uint256' }], // 100 = 1%
  },

  // ── Reads de estado ────────────────────────────────
  {
    name: 'roundCount',
    type: 'function',
    stateMutability: 'view',
    inputs:  [{ name: 'marketId', type: 'uint8' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'rounds',
    type: 'function',
    stateMutability: 'view',
    inputs:  [{ name: 'marketId', type: 'uint8' }],
    outputs: [
      { name: 'id',             type: 'uint256' },
      { name: 'openedAt',       type: 'uint256' },
      { name: 'referencePrice', type: 'int256'  },
      { name: 'finalPrice',     type: 'int256'  },
      { name: 'totalUp',        type: 'uint256' },
      { name: 'totalDown',      type: 'uint256' },
      { name: 'phase',          type: 'uint8'   }, // 0=Idle 1=Open 2=Resolved
      { name: 'upWon',          type: 'bool'    },
    ],
  },
  {
    name: 'bets',
    type: 'function',
    stateMutability: 'view',
    inputs:  [
      { name: 'marketId', type: 'uint8'   },
      { name: 'roundId',  type: 'uint256' },
      { name: 'bettor',   type: 'address' },
    ],
    outputs: [
      { name: 'amount',  type: 'uint256' },
      { name: 'dir',     type: 'uint8'   }, // 0=UP 1=DOWN
      { name: 'claimed', type: 'bool'    },
    ],
  },
  {
    name: 'getResolvedRound',
    type: 'function',
    stateMutability: 'view',
    inputs:  [
      { name: 'marketId', type: 'uint8'   },
      { name: 'roundId',  type: 'uint256' },
    ],
    outputs: [
      { name: 'resolved',  type: 'bool'    },
      { name: 'upWon',     type: 'bool'    },
      { name: 'totalUp',   type: 'uint256' },
      { name: 'totalDown', type: 'uint256' },
    ],
  },

  // ── Writes ─────────────────────────────────────────
  {
    name: 'openRound',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs:  [{ name: 'marketId', type: 'uint8' }],
    outputs: [],
  },
  {
    name: 'placeBet',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs:  [
      { name: 'marketId', type: 'uint8'   },
      { name: 'dir',      type: 'uint8'   }, // 0=UP 1=DOWN
      { name: 'amount',   type: 'uint256' },
    ],
    outputs: [],
  },
  {
    name: 'resolveRound',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs:  [{ name: 'marketId', type: 'uint8' }],
    outputs: [],
  },
  {
    name: 'claimPayout',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs:  [
      { name: 'marketId', type: 'uint8'   },
      { name: 'roundId',  type: 'uint256' },
    ],
    outputs: [],
  },

  // ── Events ─────────────────────────────────────────
  {
    name: 'RoundOpened',
    type: 'event',
    inputs: [
      { name: 'marketId',       type: 'uint8',   indexed: true  },
      { name: 'roundId',        type: 'uint256', indexed: true  },
      { name: 'openedAt',       type: 'uint256', indexed: false },
      { name: 'referencePrice', type: 'int256',  indexed: false },
    ],
  },
  {
    name: 'BetPlaced',
    type: 'event',
    inputs: [
      { name: 'marketId',  type: 'uint8',   indexed: true  },
      { name: 'roundId',   type: 'uint256', indexed: true  },
      { name: 'bettor',    type: 'address', indexed: true  },
      { name: 'dir',       type: 'uint8',   indexed: false },
      { name: 'netAmount', type: 'uint256', indexed: false },
      { name: 'fee',       type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'RoundResolved',
    type: 'event',
    inputs: [
      { name: 'marketId',       type: 'uint8',   indexed: true  },
      { name: 'roundId',        type: 'uint256', indexed: true  },
      { name: 'upWon',          type: 'bool',    indexed: false },
      { name: 'referencePrice', type: 'int256',  indexed: false },
      { name: 'finalPrice',     type: 'int256',  indexed: false },
      { name: 'totalPool',      type: 'uint256', indexed: false },
      { name: 'closedAt',       type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'PayoutClaimed',
    type: 'event',
    inputs: [
      { name: 'marketId', type: 'uint8',   indexed: true  },
      { name: 'roundId',  type: 'uint256', indexed: true  },
      { name: 'user',     type: 'address', indexed: true  },
      { name: 'amount',   type: 'uint256', indexed: false },
    ],
  },
] as const
