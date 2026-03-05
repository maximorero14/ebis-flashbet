/**
 * parseContractError — traduce errores de contratos y wagmi a mensajes amigables en español.
 *
 * Estrategia de detección (en orden de confiabilidad):
 *   1. error.cause.data.errorName  → viem decodifica el error custom si está en el ABI
 *   2. búsqueda de nombres de error en el shortMessage/message → fallback si no está en ABI
 *   3. detección de rechazo de wallet
 *   4. shortMessage como texto de respaldo (más legible que el hex raw)
 */

const ERROR_MESSAGES: Record<string, string> = {
  // ── FlashPredMarket ────────────────────────────────────────────────
  FlashPredMarket__AmountZero:
    'El monto debe ser mayor a 0',
  FlashPredMarket__RoundNotIdle:
    'Ya hay una ronda activa en este mercado',
  FlashPredMarket__RoundNotOpen:
    'La ronda no está activa — puede que haya cambiado de estado',
  FlashPredMarket__RoundNotResolved:
    'La ronda todavía no fue resuelta',
  FlashPredMarket__RoundStillOpen:
    'La ronda todavía está en curso, esperá que termine',
  FlashPredMarket__BetWindowClosed:
    'El tiempo de apuestas cerró — esperá la próxima ronda',
  FlashPredMarket__DirectionConflict:
    'Ya apostaste en la dirección opuesta en esta ronda',
  FlashPredMarket__AlreadyBet:
    'Ya realizaste una apuesta en esta ronda — solo se permite una por wallet',
  FlashPredMarket__AlreadyClaimed:
    'El payout de esta ronda ya fue reclamado',
  FlashPredMarket__NotWinner:
    'Tu apuesta no ganó esta ronda',
  FlashPredMarket__NoBetFound:
    'No se encontró apuesta para reclamar en esta ronda',

  // ── FlashVault ─────────────────────────────────────────────────────
  FlashVault__AmountZero:
    'El monto debe ser mayor a 0',
  FlashVault__InsufficientFlashBalance:
    'Saldo FLASH insuficiente para redimir',
  FlashVault__NoYieldAvailable:
    'No hay yield acumulado para cosechar todavía',

  // ── FlashOracle ────────────────────────────────────────────────────
  FlashOracle__StalePrice:
    'El precio del oracle está desactualizado — intentá de nuevo en unos minutos',
  FlashOracle__InvalidPrice:
    'El oracle no devolvió un precio válido en este momento',
  FlashOracle__UnknownSymbol:
    'Símbolo de mercado inválido',

  // ── ERC20 estándar (OpenZeppelin v5) ──────────────────────────────
  ERC20InsufficientBalance:
    'Saldo insuficiente para esta operación',
  ERC20InsufficientAllowance:
    'Allowance insuficiente — el approve no se completó',
}

export function parseContractError(error: unknown): string | null {
  if (!error) return null

  const err = error as {
    shortMessage?: string
    message?: string
    cause?: {
      data?: { errorName?: string }
      reason?: string
      cause?: {
        data?: { errorName?: string }
        reason?: string
      }
    }
    data?: { errorName?: string }
  }

  // 1. Decodificación estructurada de viem (cuando el error está en el ABI)
  const errorName =
    err.cause?.data?.errorName ??
    err.cause?.cause?.data?.errorName ??
    err.data?.errorName

  if (errorName && ERROR_MESSAGES[errorName]) {
    return ERROR_MESSAGES[errorName]
  }

  // 2. Búsqueda por nombre en el mensaje (cuando el error NO está en el ABI
  //    pero viem lo incluye como string en el shortMessage/reason)
  const fullMsg = [
    err.shortMessage,
    err.message,
    err.cause?.reason,
    err.cause?.cause?.reason,
  ]
    .filter(Boolean)
    .join(' ')

  for (const [key, friendly] of Object.entries(ERROR_MESSAGES)) {
    if (fullMsg.includes(key)) return friendly
  }

  // 3. Rechazo en la wallet
  if (/user rejected|denied transaction|user denied/i.test(fullMsg)) {
    return 'Transacción cancelada en la wallet'
  }

  // 4. Fallback al shortMessage de wagmi (más legible que el error raw)
  return err.shortMessage ?? null
}
