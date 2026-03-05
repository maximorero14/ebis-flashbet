/**
 * Utilidades de formateo — FlashBet DApp
 *
 * Reglas críticas del protocolo:
 *   - $FLASH y USDT tienen 6 decimales → usar formatUnits(x, 6)
 *   - Precios del oracle tienen 8 decimales (estándar Chainlink)
 *   - Todos los números se muestran con separador de miles
 */
import { formatUnits, parseUnits } from 'viem'

/**
 * Formatea un valor en wei de $FLASH / USDT (6 decimales) para display.
 * Ejemplo: 1_000_000n → "1.00"
 *          495_500_000n → "495.50"
 */
export function formatFlash(value: bigint): string {
  return Number(formatUnits(value, 6)).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

/**
 * Parsea un string de input a bigint en unidades de 6 decimales.
 * Valida que el string sea un número válido antes de parsear.
 */
export function parseFlash(str: string): bigint {
  if (!str || isNaN(Number(str))) return 0n
  try {
    return parseUnits(str, 6)
  } catch {
    return 0n
  }
}

/**
 * Formatea un precio del oracle Chainlink (8 decimales) para display.
 * Ejemplo: 3_000_000_000_000n (int256) → "$30,000.00"
 */
export function formatPrice(value: bigint | number | string): string {
  const num = typeof value === 'bigint'
    ? Number(value) / 1e8
    : Number(value)
  return num.toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

/**
 * Calcula el porcentaje de `a` sobre el total `a + b`.
 * Retorna 50 si ambos son 0 (pool vacío → mostrar 50/50).
 */
export function calcPct(a: bigint, b: bigint): number {
  const total = a + b
  if (total === 0n) return 50
  return Math.round((Number(a) / Number(total)) * 100)
}

/**
 * Calcula el multiplicador de payout estimado para un lado.
 * Fórmula: totalPool / ladoApostado
 * Ejemplo: pool 500, lado UP 200 → multiplicador 2.5x
 */
export function calcMultiplier(myPoolSide: bigint, totalPool: bigint): string {
  if (myPoolSide === 0n || totalPool === 0n) return '—'
  const mult = Number(totalPool) / Number(myPoolSide)
  return `${mult.toFixed(2)}x`
}

/**
 * Calcula el payout estimado para el usuario.
 * Fórmula: (miApuestaNet * totalPool) / ladoGanador
 */
export function calcPayout(myBet: bigint, totalPool: bigint, myPoolSide: bigint): bigint {
  if (myPoolSide === 0n || totalPool === 0n) return 0n
  return (myBet * totalPool) / myPoolSide
}

/**
 * Formatea segundos en formato MM:SS para el countdown.
 * Ejemplo: 65 → "01:05"
 */
export function formatCountdown(seconds: number): string {
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}

/**
 * Abrevia un hash de transacción para display.
 * Ejemplo: "0x1234...abcd"
 */
export function shortHash(hash: string): string {
  if (!hash) return ''
  return `${hash.slice(0, 6)}...${hash.slice(-4)}`
}

/**
 * Abrevia una dirección Ethereum para display.
 * Ejemplo: "0x1234...abcd"
 */
export function shortAddress(address: string): string {
  if (!address) return ''
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}
