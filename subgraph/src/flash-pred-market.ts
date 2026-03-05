import { BigInt } from "@graphprotocol/graph-ts"
import {
  RoundOpened as RoundOpenedEvent,
  BetPlaced as BetPlacedEvent,
  RoundResolved as RoundResolvedEvent,
  PayoutClaimed as PayoutClaimedEvent,
} from "../generated/FlashPredMarket/FlashPredMarket"
import { Round, Bet } from "../generated/schema"

export function handleRoundOpened(event: RoundOpenedEvent): void {
  const marketId = event.params.marketId
  const roundId = event.params.roundId
  const id = marketId.toString() + "-" + roundId.toString()

  let round = new Round(id)
  round.marketId = marketId
  round.roundId = roundId
  round.openedAt = event.params.openedAt
  round.referencePrice = event.params.referencePrice
  round.resolved = false
  // closedAt, finalPrice, upWon, totalPool are nullable — default to null, no need to set
  round.save()
}

export function handleBetPlaced(event: BetPlacedEvent): void {
  const marketId = event.params.marketId
  const roundId = event.params.roundId
  const bettor = event.params.bettor
  const roundEntityId = marketId.toString() + "-" + roundId.toString()
  const betId = roundEntityId + "-" + bettor.toHexString()

  let bet = Bet.load(betId)
  if (bet == null) {
    bet = new Bet(betId)
    bet.round = roundEntityId
    bet.bettor = bettor
    bet.direction = event.params.dir
    bet.netAmount = event.params.netAmount
    bet.fee = event.params.fee
    bet.claimed = false
    // payout is nullable — defaults to null
  } else {
    // Accumulate for same-direction bets in the same round
    bet.netAmount = bet.netAmount.plus(event.params.netAmount)
    bet.fee = bet.fee.plus(event.params.fee)
  }
  bet.save()
}

export function handleRoundResolved(event: RoundResolvedEvent): void {
  const marketId = event.params.marketId
  const roundId = event.params.roundId
  const id = marketId.toString() + "-" + roundId.toString()

  let round = Round.load(id)
  if (round == null) {
    // Fallback: create Round if RoundOpened event was missed (e.g. startBlock too late)
    round = new Round(id)
    round.marketId = marketId
    round.roundId = roundId
    round.openedAt = BigInt.fromI32(0)
    round.referencePrice = event.params.referencePrice
    round.resolved = false
  }

  round.closedAt = event.block.timestamp
  round.finalPrice = event.params.finalPrice
  round.upWon = event.params.upWon
  round.totalPool = event.params.totalPool
  round.resolved = true
  round.save()
}

export function handlePayoutClaimed(event: PayoutClaimedEvent): void {
  const marketId = event.params.marketId
  const roundId = event.params.roundId
  const user = event.params.user
  const roundEntityId = marketId.toString() + "-" + roundId.toString()
  const betId = roundEntityId + "-" + user.toHexString()

  let bet = Bet.load(betId)
  if (bet == null) {
    // Fallback: create Bet if BetPlaced event was missed
    bet = new Bet(betId)
    bet.round = roundEntityId
    bet.bettor = user
    bet.direction = 0
    bet.netAmount = BigInt.fromI32(0)
    bet.fee = BigInt.fromI32(0)
    bet.claimed = false
  }

  bet.claimed = true
  bet.payout = event.params.amount
  bet.save()
}
