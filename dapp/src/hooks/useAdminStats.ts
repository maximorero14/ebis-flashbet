/**
 * useAdminStats — hook para el dashboard de administrador.
 *
 * Comprueba si la wallet conectada es el owner del FlashVault (deployer).
 * Si lo es, obtiene estadísticas globales via The Graph (misma fuente que
 * useHistory), evitando las limitaciones de getLogs en nodos RPC públicos.
 *
 * Estadísticas que calcula:
 *   - Total de apuestas realizadas
 *   - Apostadores únicos
 *   - Ganadores únicos (bettors que cobraron al menos una ronda)
 *   - Volumen total apostado ($FLASH)
 *   - Fees totales cobrados al Treasury
 *   - Top 5 wallets ganadoras (por FLASH cobrado)
 *   - Top 5 wallets perdedoras (por FLASH neto perdido)
 *   - Yield pendiente (pendingYield() on-chain)
 */
import { useState, useEffect, useCallback } from 'react'
import {
  useAccount,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from 'wagmi'
import { sepolia }              from 'wagmi/chains'
import { CONTRACTS }            from '../config/contracts'
import { FlashVaultABI }        from '../abi/FlashVault'
import { FlashTokenABI }        from '../abi/FlashToken'
import { ERC20ABI }             from '../abi/ERC20'
import { GRAPH_URL }            from './useHistory'

const addr = CONTRACTS[sepolia.id]

export interface WalletStats {
  address:      string
  totalBet:     bigint   // FLASH apostado en total
  totalClaimed: bigint   // FLASH cobrado en total
  totalLost:    bigint   // FLASH perdido en rondas resueltas (dirección perdedora)
  betCount:     number
}

export interface AdminStats {
  totalBets:            number
  uniqueBettors:        number
  totalWinners:         number
  totalVolume:          bigint  // suma de netAmount de todos los Bet
  totalFees:            bigint  // suma de fee de todos los Bet
  topWinners:           WalletStats[]
  topLosers:            WalletStats[]
  totalYieldHarvested:  bigint  // siempre 0n (no indexado en el subgraph)
  pendingYield:         bigint
  treasuryFlashBalance: bigint  // saldo $FLASH del Treasury
  treasuryUsdtBalance:  bigint  // saldo USDT del Treasury
  totalDeposited:       bigint  // USDT actualmente en Aave via FlashVault
}

// ── GraphQL query: todos los bets (sin filtro de bettor) ──────────────────
const ADMIN_STATS_QUERY = `
  query AdminStats($skip: Int!) {
    bets(
      first: 1000
      skip: $skip
      orderBy: id
      orderDirection: asc
    ) {
      bettor
      direction
      netAmount
      fee
      payout
      claimed
      round {
        resolved
        upWon
      }
    }
  }
`

interface GraphAdminBet {
  bettor:    string
  direction: number   // 0=UP 1=DOWN
  netAmount: string
  fee:       string
  payout:    string | null
  claimed:   boolean
  round: {
    resolved: boolean
    upWon:    boolean | null
  }
}

/** Obtiene todos los bets del subgraph con paginación automática */
async function fetchAllBets(): Promise<GraphAdminBet[]> {
  if (!GRAPH_URL) throw new Error('VITE_GRAPH_URL no configurado')

  const all: GraphAdminBet[] = []
  let skip = 0

  while (true) {
    const res = await fetch(GRAPH_URL, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        query:     ADMIN_STATS_QUERY,
        variables: { skip },
      }),
    })

    if (!res.ok) throw new Error(`Graph request failed: ${res.status}`)

    const json = await res.json()
    if (json.errors) throw new Error(json.errors[0].message)

    const bets: GraphAdminBet[] = json.data?.bets ?? []
    all.push(...bets)

    if (bets.length < 1000) break  // última página
    skip += 1000
  }

  return all
}

/** Computa AdminStats a partir de los bets del subgraph */
function computeStats(bets: GraphAdminBet[], pendingYield: bigint): AdminStats {
  const walletMap = new Map<string, WalletStats>()
  let totalVolume = 0n
  let totalFees   = 0n

  for (const bet of bets) {
    const bettor = bet.bettor.toLowerCase()
    const net    = BigInt(bet.netAmount)
    const fee    = BigInt(bet.fee)
    totalVolume += net
    totalFees   += fee

    const existing = walletMap.get(bettor)
    if (existing) {
      existing.totalBet += net
      existing.betCount += 1
    } else {
      walletMap.set(bettor, {
        address:      bettor,
        totalBet:     net,
        totalClaimed: 0n,
        totalLost:    0n,
        betCount:     1,
      })
    }

    // Acumular payouts cobrados
    if (bet.claimed && bet.payout != null) {
      const w = walletMap.get(bettor)
      if (w) w.totalClaimed += BigInt(bet.payout)
    }

    // Acumular pérdidas confirmadas: solo en rondas resueltas, dirección perdedora
    if (bet.round.resolved && bet.round.upWon != null) {
      const userLost =
        (bet.round.upWon && bet.direction === 1) ||   // UP ganó pero apostó DOWN
        (!bet.round.upWon && bet.direction === 0)      // DOWN ganó pero apostó UP
      if (userLost) {
        const w = walletMap.get(bettor)
        if (w) w.totalLost += net
      }
    }
  }

  const allWallets = Array.from(walletMap.values())

  const topWinners = [...allWallets]
    .filter(w => w.totalClaimed > 0n)
    .sort((a, b) => (b.totalClaimed > a.totalClaimed ? 1 : -1))
    .slice(0, 5)

  const topLosers = [...allWallets]
    .filter(w => w.totalLost > 0n)
    .sort((a, b) => (b.totalLost > a.totalLost ? 1 : -1))
    .slice(0, 5)

  const uniqueWinners = new Set(
    bets.filter(b => b.claimed).map(b => b.bettor.toLowerCase())
  )

  return {
    totalBets:            bets.length,
    uniqueBettors:        walletMap.size,
    totalWinners:         uniqueWinners.size,
    totalVolume,
    totalFees,
    topWinners,
    topLosers,
    totalYieldHarvested:  0n,  // no indexado en el subgraph
    pendingYield,
    treasuryFlashBalance: 0n,  // se sobreescribe en el return del hook
    treasuryUsdtBalance:  0n,  // se sobreescribe en el return del hook
    totalDeposited:       0n,  // se sobreescribe en el return del hook
  }
}

// ── Hook principal ─────────────────────────────────────────────────────────
export function useAdminStats() {
  const { address, isConnected } = useAccount()

  const [stats, setStats]     = useState<AdminStats>({
    totalBets:            0,
    uniqueBettors:        0,
    totalWinners:         0,
    totalVolume:          0n,
    totalFees:            0n,
    topWinners:           [],
    topLosers:            [],
    totalYieldHarvested:  0n,
    pendingYield:         0n,
    treasuryFlashBalance: 0n,
    treasuryUsdtBalance:  0n,
    totalDeposited:       0n,
  })
  const [loading, setLoading] = useState(false)
  const [error, setError]     = useState<string | null>(null)

  // ── Reads on-chain: owner + pendingYield + treasury balances ─────────────
  const { data: contractReads, refetch: refetchReads } = useReadContracts({
    contracts: [
      // [0] Owner del vault
      {
        address:      addr.FlashVault,
        abi:          FlashVaultABI,
        functionName: 'owner',
      },
      // [1] Yield pendiente en el vault
      {
        address:      addr.FlashVault,
        abi:          FlashVaultABI,
        functionName: 'pendingYield',
      },
      // [2] Balance $FLASH del Treasury
      {
        address:      addr.FlashToken,
        abi:          FlashTokenABI,
        functionName: 'balanceOf',
        args:         [addr.Treasury],
      },
      // [3] Balance USDT del Treasury
      {
        address:      addr.USDT,
        abi:          ERC20ABI,
        functionName: 'balanceOf',
        args:         [addr.Treasury],
      },
      // [4] Total USDT depositado en Aave via FlashVault
      {
        address:      addr.FlashVault,
        abi:          FlashVaultABI,
        functionName: 'totalDeposited',
      },
    ],
    query: {
      enabled:         isConnected && !!address,
      refetchInterval: 5_000,
    },
  })

  const vaultOwner           = (contractReads?.[0]?.result as string | undefined) ?? null
  const pendingYield         = (contractReads?.[1]?.result as bigint | undefined) ?? 0n
  const treasuryFlashBalance = (contractReads?.[2]?.result as bigint | undefined) ?? 0n
  const treasuryUsdtBalance  = (contractReads?.[3]?.result as bigint | undefined) ?? 0n
  const totalDeposited       = (contractReads?.[4]?.result as bigint | undefined) ?? 0n

  const isAdmin =
    !!address &&
    !!vaultOwner &&
    address.toLowerCase() === vaultOwner.toLowerCase()

  // ── Fetch de estadísticas via The Graph ──────────────────────────────────
  const fetchStats = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      const bets = await fetchAllBets()
      setStats(computeStats(bets, pendingYield))
    } catch (err) {
      console.error('Error fetching admin stats:', err)
      setError('Error al cargar estadísticas. Intentá de nuevo.')
    } finally {
      setLoading(false)
    }
  }, [pendingYield])

  useEffect(() => {
    if (isAdmin) {
      fetchStats()
    }
  }, [isAdmin, fetchStats])

  // ── Harvest yield ────────────────────────────────────────────────────────
  const {
    writeContract,
    data:      harvestTxHash,
    isPending: isHarvestPending,
    error:     harvestError,
    reset:     resetHarvest,
  } = useWriteContract()

  const { isLoading: isHarvestConfirming, isSuccess: isHarvestSuccess } =
    useWaitForTransactionReceipt({ hash: harvestTxHash })

  const harvestYield = () =>
    writeContract({
      address:      addr.FlashVault,
      abi:          FlashVaultABI,
      functionName: 'harvestYield',
      args:         [],
    })

  useEffect(() => {
    if (isHarvestSuccess) {
      refetchReads()
      fetchStats()
    }
  }, [isHarvestSuccess])

  return {
    vaultOwner,
    isAdmin,
    stats: { ...stats, pendingYield, treasuryFlashBalance, treasuryUsdtBalance, totalDeposited },
    loading,
    error,
    fetchStats,
    harvestYield,
    harvestTxHash,
    isHarvestPending,
    isHarvestConfirming,
    isHarvestSuccess,
    harvestError,
    resetHarvest,
  }
}
