// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/FlashPredMarket.sol";
import "../src/FlashToken.sol";
import "../src/Treasury.sol";
import "../src/mocks/MockFlashOracle.sol";

/**
 * @title FlashPredMarketTest
 * @dev Unit tests for the Polymarket-style FlashPredMarket.
 *
 * Key design: reference price locked at openRound(), bets accepted until
 * the very last second of the round (no closeRound / Closed phase).
 * openRound() and resolveRound() are restricted to the owner (admin).
 *
 * Test categories:
 *  1. Deployment / initial state
 *  2. openRound()   — locks reference price immediately (onlyOwner)
 *  3. placeBet()    — open until ROUND_DURATION
 *  4. resolveRound() (onlyOwner)
 *  5. claimPayout() — UP wins, DOWN wins, one-sided refund, historical
 *  6. Fuzz: payout invariant
 *  7. Integration: BTC + ETH simultaneous cycle
 */
contract FlashPredMarketTest is Test {
    // ─────────────── Contracts ───────────────────────────────────────────
    FlashToken      public flash;
    MockFlashOracle public oracle;
    Treasury        public treasury;
    FlashPredMarket public market;

    // ─────────────── Actors ──────────────────────────────────────────────
    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob   = makeAddr("bob");
    address public carol = makeAddr("carol");

    // ─────────────── Roles ───────────────────────────────────────────────
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ─────────────── Markets ─────────────────────────────────────────────
    uint8 constant BTC = 0;
    uint8 constant ETH = 1;

    // ─────────────── Prices ──────────────────────────────────────────────
    int256 constant BTC_REF  = 30_000e8;
    int256 constant BTC_UP   = 31_000e8;  // UP wins
    int256 constant BTC_DOWN = 29_000e8;  // DOWN wins
    int256 constant ETH_REF  = 2_000e8;
    int256 constant ETH_UP   = 2_100e8;

    // ─────────────── Amounts ─────────────────────────────────────────────
    uint256 constant BET = 1_000e6;
    uint256 constant FEE = 10e6;    // 1% of 1000
    uint256 constant NET = 990e6;   // BET - FEE

    // ─────────────── Setup ───────────────────────────────────────────────
    function setUp() public {
        vm.startPrank(admin);

        flash    = new FlashToken();
        oracle   = new MockFlashOracle();
        treasury = new Treasury(admin);
        market   = new FlashPredMarket(
            address(flash),
            address(oracle),
            address(treasury),
            admin,
            0 // roundDuration: 0 = default 300s
        );

        flash.grantRole(MINTER_ROLE, admin);
        flash.mint(alice, BET * 100);
        flash.mint(bob,   BET * 100);
        flash.mint(carol, BET * 100);
        vm.stopPrank();

        oracle.setPrice("BTC", BTC_REF);
        oracle.setPrice("ETH", ETH_REF);

        vm.prank(alice);
        flash.approve(address(market), type(uint256).max);
        vm.prank(bob);
        flash.approve(address(market), type(uint256).max);
        vm.prank(carol);
        flash.approve(address(market), type(uint256).max);
    }

    // ─────────────── Helpers ─────────────────────────────────────────────

    /// @dev Open + resolve a round as admin. Returns roundId.
    function _fullCycle(
        uint8  mid,
        int256 openPrice,
        int256 closePrice
    ) internal returns (uint256 roundId) {
        oracle.setPrice(mid == BTC ? "BTC" : "ETH", openPrice);
        vm.prank(admin);
        market.openRound(mid);
        roundId = market.roundCount(mid);
        oracle.setPrice(mid == BTC ? "BTC" : "ETH", closePrice);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(mid);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 1. DEPLOYMENT / INITIAL STATE
    // ═════════════════════════════════════════════════════════════════════

    function test_ImmutableAddresses() public view {
        assertEq(address(market.flashToken()), address(flash));
        assertEq(address(market.oracle()),     address(oracle));
        assertEq(market.treasury(),            address(treasury));
    }

    function test_DefaultRoundDuration() public view {
        assertEq(market.ROUND_DURATION(), 300);
    }

    function test_CustomRoundDuration() public {
        FlashPredMarket m2 = new FlashPredMarket(
            address(flash),
            address(oracle),
            address(treasury),
            admin,
            60
        );
        assertEq(m2.ROUND_DURATION(), 60);
    }

    function test_InitialRoundsIdle() public view {
        assertEq(uint8(market.getRound(BTC).phase), uint8(FlashPredMarket.RoundPhase.Idle));
        assertEq(uint8(market.getRound(ETH).phase), uint8(FlashPredMarket.RoundPhase.Idle));
    }

    function test_RoundCountStartsZero() public view {
        assertEq(market.roundCount(BTC), 0);
        assertEq(market.roundCount(ETH), 0);
    }

    function test_MarketSymbols() public view {
        assertEq(market.marketSymbol(BTC), "BTC");
        assertEq(market.marketSymbol(ETH), "ETH");
    }

    function test_InvalidMarketReverts() public {
        vm.expectRevert(FlashPredMarket.FlashPredMarket__InvalidMarket.selector);
        market.getRound(2);
    }

    function test_ConstructorRevertsZeroAddress() public {
        vm.expectRevert(FlashPredMarket.FlashPredMarket__ZeroAddress.selector);
        new FlashPredMarket(address(0), address(oracle), address(treasury), admin, 0);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2. openRound() — reference price locked immediately, onlyOwner
    // ═════════════════════════════════════════════════════════════════════

    function test_OpenRoundLocksReferencePrice() public {
        oracle.setPrice("BTC", BTC_REF);
        vm.prank(admin);
        market.openRound(BTC);
        assertEq(market.getRound(BTC).referencePrice, BTC_REF);
    }

    function test_OpenRoundSetsPhaseOpen() public {
        vm.prank(admin);
        market.openRound(BTC);
        assertEq(uint8(market.getRound(BTC).phase), uint8(FlashPredMarket.RoundPhase.Open));
    }

    function test_OpenRoundIncrementsCounter() public {
        vm.prank(admin);
        market.openRound(BTC);
        assertEq(market.roundCount(BTC), 1);

        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);
        vm.prank(admin);
        market.openRound(BTC);
        assertEq(market.roundCount(BTC), 2);
    }

    function test_OpenRoundEmitsEventWithReferencePrice() public {
        oracle.setPrice("BTC", BTC_REF);
        vm.expectEmit(true, true, false, true);
        emit FlashPredMarket.RoundOpened(BTC, 1, block.timestamp, BTC_REF);
        vm.prank(admin);
        market.openRound(BTC);
    }

    function test_OpenRoundRevertsIfAlreadyOpen() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(admin);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__RoundNotIdle.selector);
        market.openRound(BTC);
    }

    function test_OpenRoundRevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        market.openRound(BTC);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3. placeBet() — open until the last second
    // ═════════════════════════════════════════════════════════════════════

    function test_PlaceBetDeductsFee() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        assertEq(flash.balanceOf(address(treasury)), FEE);
    }

    function test_PlaceBetAccumulatesPool() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        vm.prank(bob);
        market.placeBet(BTC, FlashPredMarket.Direction.DOWN, BET * 2);
        FlashPredMarket.Round memory r = market.getRound(BTC);
        assertEq(r.totalUp,   NET);
        assertEq(r.totalDown, NET * 2);
    }

    function test_PlaceBetMergesSameDirection() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.startPrank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        vm.stopPrank();
        assertEq(market.getBet(BTC, 1, alice).amount, NET * 2);
    }

    function test_PlaceBetAcceptedOnSecondBeforeEnd() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.warp(block.timestamp + market.ROUND_DURATION() - 1);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        assertEq(market.getBet(BTC, 1, alice).amount, NET);
    }

    function test_PlaceBetRevertsAtExactEnd() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(alice);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__BetWindowClosed.selector);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
    }

    function test_PlaceBetRevertsZeroAmount() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__AmountZero.selector);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, 0);
    }

    function test_PlaceBetRevertsWhenIdle() public {
        vm.prank(alice);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__RoundNotOpen.selector);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
    }

    function test_PlaceBetRevertsDirectionConflict() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.startPrank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__DirectionConflict.selector);
        market.placeBet(BTC, FlashPredMarket.Direction.DOWN, BET);
        vm.stopPrank();
    }

    function test_PlaceBetEmitsEvent() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.expectEmit(true, true, true, true);
        emit FlashPredMarket.BetPlaced(BTC, 1, alice, FlashPredMarket.Direction.UP, NET, FEE);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 4. resolveRound() — onlyOwner
    // ═════════════════════════════════════════════════════════════════════

    function test_ResolveRoundUpWins() public {
        oracle.setPrice("BTC", BTC_REF);
        vm.prank(admin);
        market.openRound(BTC);
        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        FlashPredMarket.Round memory r = market.getRound(BTC);
        assertTrue(r.upWon);
        assertEq(uint8(r.phase), uint8(FlashPredMarket.RoundPhase.Resolved));
        assertEq(r.finalPrice,     BTC_UP);
        assertEq(r.referencePrice, BTC_REF);
    }

    function test_ResolveRoundDownWins() public {
        oracle.setPrice("BTC", BTC_REF);
        vm.prank(admin);
        market.openRound(BTC);
        oracle.setPrice("BTC", BTC_DOWN);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        assertFalse(market.getRound(BTC).upWon);
    }

    function test_ResolveRoundSnapshotsResolvedRound() public {
        uint256 rid = _fullCycle(BTC, BTC_REF, BTC_UP);
        FlashPredMarket.ResolvedRound memory rr = market.getResolvedRound(BTC, rid);
        assertTrue(rr.resolved);
        assertTrue(rr.upWon);
    }

    function test_ResolveRoundRevertsIfStillOpen() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.warp(block.timestamp + market.ROUND_DURATION() - 1);
        vm.prank(admin);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__RoundStillOpen.selector);
        market.resolveRound(BTC);
    }

    function test_ResolveRoundRevertsIfNotOpen() public {
        vm.prank(admin);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__RoundNotOpen.selector);
        market.resolveRound(BTC);
    }

    function test_ResolveRoundRevertsIfNotOwner() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(alice);
        vm.expectRevert();
        market.resolveRound(BTC);
    }

    function test_ResolveRoundEmitsEvent() public {
        oracle.setPrice("BTC", BTC_REF);
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());

        vm.expectEmit(true, true, false, false);
        // checkData=false: only topics (marketId, roundId) are verified
        emit FlashPredMarket.RoundResolved(BTC, 1, true, BTC_REF, BTC_UP, NET, block.timestamp);
        vm.prank(admin);
        market.resolveRound(BTC);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 5. claimPayout()
    // ═════════════════════════════════════════════════════════════════════

    function test_ClaimPayoutUpWins() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        vm.prank(bob);
        market.placeBet(BTC, FlashPredMarket.Direction.DOWN, BET);
        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        uint256 before = flash.balanceOf(alice);
        vm.prank(alice);
        market.claimPayout(BTC, 1);
        assertEq(flash.balanceOf(alice), before + NET * 2);
    }

    function test_ClaimPayoutDownWins() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        vm.prank(bob);
        market.placeBet(BTC, FlashPredMarket.Direction.DOWN, BET);
        oracle.setPrice("BTC", BTC_DOWN);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        uint256 before = flash.balanceOf(bob);
        vm.prank(bob);
        market.claimPayout(BTC, 1);
        assertEq(flash.balanceOf(bob), before + NET * 2);
    }

    function test_ClaimPayoutProportional() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        vm.prank(bob);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET * 3);
        vm.prank(carol);
        market.placeBet(BTC, FlashPredMarket.Direction.DOWN, BET * 2);
        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        FlashPredMarket.ResolvedRound memory rr = market.getResolvedRound(BTC, 1);
        uint256 totalPool = rr.totalUp + rr.totalDown;

        uint256 aliceNet = market.getBet(BTC, 1, alice).amount;
        uint256 bobNet   = market.getBet(BTC, 1, bob).amount;

        uint256 aliceBefore = flash.balanceOf(alice);
        uint256 bobBefore   = flash.balanceOf(bob);

        vm.prank(alice);
        market.claimPayout(BTC, 1);
        vm.prank(bob);
        market.claimPayout(BTC, 1);

        assertEq(flash.balanceOf(alice), aliceBefore + (aliceNet * totalPool) / rr.totalUp);
        assertEq(flash.balanceOf(bob),   bobBefore   + (bobNet   * totalPool) / rr.totalUp);
    }

    function test_ClaimPayoutOneSidedRefund() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        uint256 before = flash.balanceOf(alice);
        vm.prank(alice);
        market.claimPayout(BTC, 1);
        assertEq(flash.balanceOf(alice), before + NET); // full refund
    }

    function test_ClaimPayoutRevertsAlreadyClaimed() public {
        _fullCycle(BTC, BTC_REF, BTC_UP); // round 1 — no bets, resolved
        oracle.setPrice("BTC", BTC_REF);
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        vm.prank(alice);
        market.claimPayout(BTC, 2);
        vm.prank(alice);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__AlreadyClaimed.selector);
        market.claimPayout(BTC, 2);
    }

    function test_ClaimPayoutRevertsNotWinner() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        vm.prank(bob);
        market.placeBet(BTC, FlashPredMarket.Direction.DOWN, BET);
        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        vm.prank(bob);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__NotWinner.selector);
        market.claimPayout(BTC, 1);
    }

    function test_ClaimPayoutRevertsNoBet() public {
        uint256 rid = _fullCycle(BTC, BTC_REF, BTC_UP);
        vm.prank(carol);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__NoBetFound.selector);
        market.claimPayout(BTC, rid);
    }

    function test_ClaimPayoutRevertsRoundNotResolved() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        vm.prank(alice);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__RoundNotResolved.selector);
        market.claimPayout(BTC, 1);
    }

    function test_ClaimFromHistoricalRoundAfterNewOpen() public {
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        vm.prank(bob);
        market.placeBet(BTC, FlashPredMarket.Direction.DOWN, BET);
        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        oracle.setPrice("BTC", BTC_UP);
        vm.prank(admin);
        market.openRound(BTC);

        uint256 before = flash.balanceOf(alice);
        vm.prank(alice);
        market.claimPayout(BTC, 1);
        assertEq(flash.balanceOf(alice), before + NET * 2);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 6. Fuzz: payout invariant
    // ═════════════════════════════════════════════════════════════════════

    function testFuzz_PayoutInvariant(uint256 amtAlice, uint256 amtBob) public {
        amtAlice = bound(amtAlice, 1e6, 1_000_000e6);
        amtBob   = bound(amtBob,   1e6, 1_000_000e6);

        vm.startPrank(admin);
        flash.mint(alice, amtAlice);
        flash.mint(bob,   amtBob);
        vm.stopPrank();

        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, amtAlice);
        vm.prank(bob);
        market.placeBet(BTC, FlashPredMarket.Direction.DOWN, amtBob);
        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        FlashPredMarket.ResolvedRound memory rr = market.getResolvedRound(BTC, 1);
        uint256 totalPool      = rr.totalUp + rr.totalDown;
        uint256 aliceNet       = market.getBet(BTC, 1, alice).amount;
        uint256 expectedPayout = (aliceNet * totalPool) / rr.totalUp;

        uint256 before = flash.balanceOf(alice);
        vm.prank(alice);
        market.claimPayout(BTC, 1);
        uint256 payout = flash.balanceOf(alice) - before;

        assertEq(payout, expectedPayout);
        assertLe(payout, totalPool);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 7. Integration: BTC + ETH simultaneous full cycle
    // ═════════════════════════════════════════════════════════════════════

    // ═════════════════════════════════════════════════════════════════════
    // 7. PAUSE / UNPAUSE
    // ═════════════════════════════════════════════════════════════════════

    /// @dev Owner can pause the market.
    function test_OwnerCanPause() public {
        vm.prank(admin);
        market.pause();
        assertTrue(market.paused());
    }

    /// @dev Owner can unpause the market.
    function test_OwnerCanUnpause() public {
        vm.prank(admin);
        market.pause();
        vm.prank(admin);
        market.unpause();
        assertFalse(market.paused());
    }

    /// @dev Non-owner cannot pause the market.
    function test_NonOwnerCannotPause() public {
        vm.prank(alice);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        market.pause();
    }

    /// @dev openRound() reverts when the market is paused.
    function test_OpenRoundRevertsWhenPaused() public {
        vm.prank(admin);
        market.pause();

        vm.prank(admin);
        vm.expectRevert(); // EnforcedPause
        market.openRound(BTC);
    }

    /// @dev placeBet() reverts when the market is paused.
    function test_PlaceBetRevertsWhenPaused() public {
        vm.prank(admin);
        market.openRound(BTC);

        vm.prank(admin);
        market.pause();

        vm.prank(alice);
        vm.expectRevert(); // EnforcedPause
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
    }

    /// @dev claimPayout() reverts when the market is paused.
    function test_ClaimPayoutRevertsWhenPaused() public {
        // Run a full cycle so Alice has a claimable payout
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        vm.prank(admin);
        market.pause();

        vm.prank(alice);
        vm.expectRevert(); // EnforcedPause
        market.claimPayout(BTC, 1);
    }

    /// @dev After unpause, all operations resume normally.
    function test_OperationsResumeAfterUnpause() public {
        vm.prank(admin);
        market.pause();
        vm.prank(admin);
        market.unpause();

        // Full cycle should work again
        vm.prank(admin);
        market.openRound(BTC);
        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        oracle.setPrice("BTC", BTC_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());
        vm.prank(admin);
        market.resolveRound(BTC);

        uint256 before = flash.balanceOf(alice);
        vm.prank(alice);
        market.claimPayout(BTC, 1);
        assertGt(flash.balanceOf(alice), before);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 8. Integration: BTC + ETH simultaneous full cycle
    // ═════════════════════════════════════════════════════════════════════

    function test_BothMarketsSimultaneous() public {
        oracle.setPrice("BTC", BTC_REF);
        oracle.setPrice("ETH", ETH_REF);
        vm.startPrank(admin);
        market.openRound(BTC);
        market.openRound(ETH);
        vm.stopPrank();

        vm.prank(alice);
        market.placeBet(BTC, FlashPredMarket.Direction.UP, BET);
        vm.prank(bob);
        market.placeBet(BTC, FlashPredMarket.Direction.DOWN, BET);
        vm.prank(alice);
        market.placeBet(ETH, FlashPredMarket.Direction.UP, BET);
        vm.prank(carol);
        market.placeBet(ETH, FlashPredMarket.Direction.DOWN, BET);

        oracle.setPrice("BTC", BTC_UP);
        oracle.setPrice("ETH", ETH_UP);
        vm.warp(block.timestamp + market.ROUND_DURATION());

        vm.startPrank(admin);
        market.resolveRound(BTC);
        market.resolveRound(ETH);
        vm.stopPrank();

        assertTrue(market.getRound(BTC).upWon);
        assertTrue(market.getRound(ETH).upWon);

        vm.startPrank(alice);
        market.claimPayout(BTC, 1);
        market.claimPayout(ETH, 1);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(FlashPredMarket.FlashPredMarket__NotWinner.selector);
        market.claimPayout(BTC, 1);
    }
}
