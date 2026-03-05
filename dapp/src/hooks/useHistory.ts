/**
 * useHistory — historial de apuestas del usuario via The Graph.
 *
 * Reemplaza la lógica de getLogs/chunkedGetLogs de HistoryPage.tsx
 * con una query GraphQL limpia al subgraph de FlashBet.
 *
 * Requiere VITE_GRAPH_URL en .env.local apuntando al endpoint de Subgraph Studio.
 */
import { useQuery } from '@tanstack/react-query'
import { useAccount } from 'wagmi'

export const GRAPH_URL = import.meta.env.VITE_GRAPH_URL as string | undefined

export interface RoundHistoryRow {
  roundId: bigint
  marketId: number    // 0=BTC 1=ETH
  openedAt: bigint    // timestamp de apertura
  closedAt: bigint    // timestamp de cierre; 0n si no disponible
  refPrice: bigint    // precio de referencia
  finalPrice: bigint  // precio final; 0n si no disponible
  upWon: boolean
  totalPool: bigint
  myBetAmount: bigint // acumulado (la entidad Bet ya lo acumula en el subgraph)
  myBetDir: number    // 0=UP 1=DOWN
  myPayout: bigint    // 0 si no cobró o perdió
  claimed: boolean
  resolvedOnChain: boolean
}

const USER_HISTORY_QUERY = `
  query UserHistory($bettor: String!) {
    bets(
      where: { bettor: $bettor }
      orderBy: round__roundId
      orderDirection: desc
      first: 200
    ) {
      direction
      netAmount
      payout
      claimed
      round {
        marketId
        roundId
        openedAt
        closedAt
        referencePrice
        finalPrice
        upWon
        totalPool
        resolved
      }
    }
  }
`

interface GraphBet {
  direction: number
  netAmount: string
  payout: string | null
  claimed: boolean
  round: {
    marketId: number
    roundId: string
    openedAt: string
    closedAt: string | null
    referencePrice: string
    finalPrice: string | null
    upWon: boolean | null
    totalPool: string | null
    resolved: boolean
  }
}

async function fetchUserHistory(address: string): Promise<RoundHistoryRow[]> {
  if (!GRAPH_URL) return []

  const res = await fetch(GRAPH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query: USER_HISTORY_QUERY,
      variables: { bettor: address.toLowerCase() },
    }),
  })

  if (!res.ok) throw new Error(`Graph request failed: ${res.status}`)

  const json = await res.json()
  if (json.errors) throw new Error(json.errors[0].message)

  const bets: GraphBet[] = json.data?.bets ?? []

  return bets.map((bet): RoundHistoryRow => ({
    roundId: BigInt(bet.round.roundId),
    marketId: Number(bet.round.marketId),
    openedAt: BigInt(bet.round.openedAt),
    closedAt: bet.round.closedAt != null ? BigInt(bet.round.closedAt) : 0n,
    refPrice: BigInt(bet.round.referencePrice),
    finalPrice: bet.round.finalPrice != null ? BigInt(bet.round.finalPrice) : 0n,
    upWon: bet.round.upWon ?? false,
    totalPool: bet.round.totalPool != null ? BigInt(bet.round.totalPool) : 0n,
    myBetAmount: BigInt(bet.netAmount),
    myBetDir: Number(bet.direction),
    myPayout: bet.payout != null ? BigInt(bet.payout) : 0n,
    claimed: bet.claimed,
    resolvedOnChain: bet.round.resolved,
  }))
}

export function useHistory() {
  const { address } = useAccount()

  return useQuery({
    queryKey: ['history', address],
    queryFn: () => fetchUserHistory(address!),
    enabled: !!address && !!GRAPH_URL,
    staleTime: 30_000,
    retry: 2,
  })
}
