/**
 * ABI de FlashVault.
 *
 * Flujo de depósito:
 *   1. USDT.approve(FlashVault, amount)
 *   2. FlashVault.deposit(amount)  → mint de $FLASH 1:1
 *
 * Flujo de redención:
 *   1. FlashToken.approve(FlashVault, amount)
 *   2. FlashVault.redeem(amount)   → burn de $FLASH, retorno de USDT
 *
 * El USDT depositado se envía a Aave V3 para generar yield pasivo.
 * harvestYield() recolecta el interés acumulado y lo envía al Treasury.
 */
export const FlashVaultABI = [
  // ── Reads ──────────────────────────────────────────
  {
    name: 'totalDeposited',
    type: 'function',
    stateMutability: 'view',
    inputs:  [],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'owner',
    type: 'function',
    stateMutability: 'view',
    inputs:  [],
    outputs: [{ type: 'address' }],
  },
  {
    name: 'pendingYield',
    type: 'function',
    stateMutability: 'view',
    inputs:  [],
    outputs: [{ type: 'uint256' }],
  },
  // ── Writes ─────────────────────────────────────────
  {
    name: 'deposit',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs:  [{ name: 'amount', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'redeem',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs:  [{ name: 'amount', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'harvestYield',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs:  [],
    outputs: [],
  },
  // ── Events ─────────────────────────────────────────
  {
    name: 'Deposited',
    type: 'event',
    inputs: [
      { name: 'user',   type: 'address', indexed: true  },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'Redeemed',
    type: 'event',
    inputs: [
      { name: 'user',   type: 'address', indexed: true  },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'YieldHarvested',
    type: 'event',
    inputs: [
      { name: 'yieldAmount', type: 'uint256', indexed: false },
      { name: 'treasury',    type: 'address', indexed: true  },
    ],
  },
] as const
