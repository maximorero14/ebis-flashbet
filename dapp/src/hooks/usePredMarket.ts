/**
 * usePredMarket — hook principal para interactuar con FlashPredMarket.
 *
 * Encapsula toda la lógica de un mercado de predicción (BTC o ETH):
 *   - Estado de la ronda actual (fase, precios, pools, countdown)
 *   - Apuesta del usuario en la ronda actual
 *   - Allowance de $FLASH para FlashPredMarket
 *   - Escrituras: openRound, placeBetWithApprove, resolveRound, claimPayout
 *   - Watchers de eventos para auto-refresh en tiempo real
 *
 * @param marketId  0 = BTC/USD  |  1 = ETH/USD
 *
 * Reglas críticas:
 *   - placeBet() requiere approve(FlashPredMarket, amount) en FlashToken
 *   - Un usuario solo puede apostar en una dirección por ronda
 *   - $FLASH tiene 6 decimales
 *   - round.id === roundCount (contrato hace ++roundCount antes de asignar id)
 */
import {
  useReadContracts,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
  useAccount,
} from 'wagmi'
import { waitForTransactionReceipt } from '@wagmi/core'
import { sepolia }              from 'wagmi/chains'
import { useState, useCallback } from 'react'
import { CONTRACTS }            from '../config/contracts'
import { wagmiConfig }          from '../config/wagmi'
import { FlashPredMarketABI }   from '../abi/FlashPredMarket'
import { FlashTokenABI }        from '../abi/FlashToken'
import { parseFlash }           from '../utils/format'
import { useFlashBalance }      from './useFlashBalance'

const addr = CONTRACTS[sepolia.id]

/** 0 = BTC/USD  |  1 = ETH/USD */
export type MarketId = 0 | 1

/**
 * Fases de una ronda según el contrato (equivalente a enum Phase en Solidity).
 * Usamos const object en lugar de TypeScript enum para compatibilidad
 * con el modo erasableSyntaxOnly del compilador.
 */
export const RoundPhase = { Idle: 0, Open: 1, Resolved: 2 } as const
export type RoundPhase = typeof RoundPhase[keyof typeof RoundPhase]

/** Dirección de apuesta (equivalente a enum Dir en Solidity) */
export const BetDir = { UP: 0, DOWN: 1 } as const
export type BetDir = typeof BetDir[keyof typeof BetDir]

/**
 * Paso del flujo de transacción secuencial (approve → action).
 * Permite al componente mostrar mensajes contextuales al usuario.
 */
export type TxStep = 'idle' | 'approving' | 'placing'

export function usePredMarket(marketId: MarketId) {
  const { address, isConnected } = useAccount()

  // ── Estado del input de apuesta ────────────────────
  const [betInput, setBetInput] = useState('')
  const parsedBet = parseFlash(betInput)

  /** Paso actual del flujo de tx (idle → approving → placing) */
  const [txStep, setTxStep] = useState<TxStep>('idle')

  // ── Reads principales (ronda, contadores, allowance) ──
  const {
    data: reads,
    refetch: refetchReads,
  } = useReadContracts({
    contracts: [
      // [0] Datos de la ronda actual
      {
        address:      addr.FlashPredMarket,
        abi:          FlashPredMarketABI,
        functionName: 'rounds',
        args:         [marketId],
      },
      // [1] Contador de rondas
      {
        address:      addr.FlashPredMarket,
        abi:          FlashPredMarketABI,
        functionName: 'roundCount',
        args:         [marketId],
      },
      // [2] Duración de ronda
      {
        address:      addr.FlashPredMarket,
        abi:          FlashPredMarketABI,
        functionName: 'ROUND_DURATION',
      },
      // [3] Allowance $FLASH → FlashPredMarket
      {
        address:      addr.FlashToken,
        abi:          FlashTokenABI,
        functionName: 'allowance',
        args:         address
          ? [address, addr.FlashPredMarket]
          : ['0x0000000000000000000000000000000000000000', addr.FlashPredMarket],
      },
    ],
    query: {
      enabled:         isConnected && !!address,
      // Heartbeat de 60s solo para detectar rondas abiertas por otros usuarios.
      // El refetch real ocurre instantáneamente después de cada tx propia (isTxSuccess).
      // Multicall3: 4 reads = 1 eth_call → 4 calls/min × 2 markets = 8 calls/min total.
      refetchInterval: 60_000,
      staleTime:            0,   // siempre refetch en window focus (útil en presentación)
    },
  })

  /**
   * activeRoundId — ID de la ronda activa para leer bets del usuario.
   *
   * FIX: el contrato hace `uint256 newId = ++roundCount[marketId]` antes de asignar
   * el id al struct, por lo que round.id === roundCount (NO roundCount - 1).
   * Usar roundRaw[0] (round.id del struct) es el valor correcto.
   */
  const activeRoundId = (reads?.[0]?.result as readonly [bigint, ...unknown[]] | undefined)?.[0] ?? 0n

  // ── Read separado para la apuesta del usuario ──────
  // Requiere activeRoundId, por eso se hace en un hook aparte
  const { data: betResult, refetch: refetchBet } = useReadContract({
    address:      addr.FlashPredMarket,
    abi:          FlashPredMarketABI,
    functionName: 'bets',
    args:         [marketId, activeRoundId, address ?? '0x0000000000000000000000000000000000000000'],
    query: {
      enabled:         isConnected && !!address && activeRoundId > 0n,
      refetchInterval: 60_000,
      staleTime:            0,
    },
  })

  // ── Extracción de datos tipados ────────────────────
  type RoundData = {
    id: bigint; openedAt: bigint; referencePrice: bigint;
    finalPrice: bigint; totalUp: bigint; totalDown: bigint;
    phase: number; upWon: boolean;
  }
  type BetData = { amount: bigint; dir: number; claimed: boolean }

  const roundRaw       = reads?.[0]?.result as readonly [bigint,bigint,bigint,bigint,bigint,bigint,number,boolean] | undefined
  const roundCount     = (reads?.[1]?.result as bigint | undefined) ?? 0n
  const roundDuration  = (reads?.[2]?.result as bigint | undefined) ?? 60n
  const flashAllowance = (reads?.[3]?.result as bigint | undefined) ?? 0n
  const betRaw         = betResult as readonly [bigint, number, boolean] | undefined

  // Mapear array a objeto tipado
  const round: RoundData | undefined = roundRaw
    ? {
        id:             roundRaw[0],
        openedAt:       roundRaw[1],
        referencePrice: roundRaw[2],
        finalPrice:     roundRaw[3],
        totalUp:        roundRaw[4],
        totalDown:      roundRaw[5],
        phase:          roundRaw[6],
        upWon:          roundRaw[7],
      }
    : undefined

  const userBet: BetData | undefined = betRaw
    ? { amount: betRaw[0], dir: betRaw[1], claimed: betRaw[2] }
    : undefined

  const phase = (round?.phase ?? RoundPhase.Idle) as RoundPhase

  /** Refresca todos los reads (ronda + apuesta del usuario) */
  const refetch = useCallback(() => {
    refetchReads()
    refetchBet()
  }, [refetchReads, refetchBet])

  /** Indica si el usuario ya apostó en esta ronda */
  const hasUserBet = userBet ? userBet.amount > 0n : false
  /** Dirección en la que apostó el usuario (si apostó) */
  const userBetDir: BetDir | null = hasUserBet ? (userBet!.dir as BetDir) : null

  // ── Balance $FLASH del usuario ─────────────────────
  const { data: flashBalanceData } = useFlashBalance()
  const flashBalance = flashBalanceData ?? 0n

  /** El usuario necesita aprobar $FLASH antes de apostar */
  const needsApproval = parsedBet > 0n && flashAllowance < parsedBet

  /** El usuario no tiene suficiente $FLASH para cubrir la apuesta */
  const insufficientBalance = parsedBet > 0n && flashBalance < parsedBet

  // ── Writes ─────────────────────────────────────────
  const {
    writeContract,
    writeContractAsync,
    data: txHash,
    isPending: isWritePending,
    reset: resetWrite,
    error: writeError,
  } = useWriteContract()

  const { isLoading: isTxConfirming, isSuccess: isTxSuccess } =
    useWaitForTransactionReceipt({ hash: txHash })

  /** Iniciar una nueva ronda — puede llamarlo cualquier usuario */
  const openRound = useCallback(() =>
    writeContract({
      address:      addr.FlashPredMarket,
      abi:          FlashPredMarketABI,
      functionName: 'openRound',
      args:         [marketId],
    }), [marketId, writeContract])

  /**
   * Apostar con flujo de un solo botón: approve → placeBet.
   *
   * Si el allowance ya es suficiente, saltea el approve y va directo al bet.
   * El usuario verá 1 o 2 popups en su wallet según corresponda.
   *
   * @param dir  BetDir.UP (0) o BetDir.DOWN (1)
   */
  const placeBetWithApprove = useCallback(async (dir: BetDir) => {
    if (parsedBet === 0n) return
    // Verificar balance antes de intentar la transacción
    if (insufficientBalance) return
    // Una sola apuesta por wallet por ronda
    if (hasUserBet) return
    try {
      // Solo aprobar si el allowance es insuficiente
      if (flashAllowance < parsedBet) {
        setTxStep('approving')
        const approveHash = await writeContractAsync({
          address:      addr.FlashToken,
          abi:          FlashTokenABI,
          functionName: 'approve',
          args:         [addr.FlashPredMarket, parsedBet],
        })
        // Esperar confirmación on-chain antes de apostar
        await waitForTransactionReceipt(wagmiConfig, { hash: approveHash })
      }

      setTxStep('placing')
      await writeContractAsync({
        address:      addr.FlashPredMarket,
        abi:          FlashPredMarketABI,
        functionName: 'placeBet',
        args:         [marketId, dir, parsedBet],
      })
    } catch {
      // No llamar resetWrite() — dejar que writeError quede visible al usuario
    } finally {
      setTxStep('idle')
    }
  }, [marketId, parsedBet, flashAllowance, insufficientBalance, hasUserBet, writeContractAsync])

  /** Resolver la ronda — llama al oracle para obtener precio final */
  const resolveRound = useCallback(() =>
    writeContract({
      address:      addr.FlashPredMarket,
      abi:          FlashPredMarketABI,
      functionName: 'resolveRound',
      args:         [marketId],
    }), [marketId, writeContract])

  /**
   * Reclamar el payout de una ronda ganada.
   * @param roundId  ID de la ronda en la que se apostó
   */
  const claimPayout = useCallback((roundId: bigint) =>
    writeContract({
      address:      addr.FlashPredMarket,
      abi:          FlashPredMarketABI,
      functionName: 'claimPayout',
      args:         [marketId, roundId],
    }), [marketId, writeContract])

  return {
    // Datos de la ronda
    round,
    roundCount,
    roundDuration,
    phase,

    // Apuesta del usuario
    userBet,
    hasUserBet,
    userBetDir,

    // Balance y aprobación
    flashBalance,
    flashAllowance,
    needsApproval,
    insufficientBalance,

    // Input controlado
    betInput,
    setBetInput,
    parsedBet,

    // Acciones
    openRound,
    placeBetWithApprove,
    resolveRound,
    claimPayout,

    // Estado de transacción
    txHash,
    txStep,
    isWritePending,
    isTxConfirming,
    isTxSuccess,
    writeError,
    resetWrite,

    // Refrescar
    refetch,
  }
}
