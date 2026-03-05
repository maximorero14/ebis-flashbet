// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/Treasury.sol";
import "./mocks/MockERC20.sol";

/**
 * @title TreasuryTest
 * @dev Unit tests for the Treasury contract.
 *
 * The Treasury accumulates two types of revenue:
 *  - $FLASH tokens: 1% trading fee from FlashPredMarket.placeBet()
 *  - USDT tokens:   Aave yield forwarded by FlashVault.harvestYield()
 *
 * Test categories:
 *  1. Deployment / initial state
 *  2. withdraw() — success paths
 *  3. withdraw() — revert paths
 *  4. balance() view helper
 *  5. Multi-token accounting ($FLASH + USDT simultaneously)
 *  6. Fuzz tests
 */
contract TreasuryTest is Test {
    // ─────────────── Contracts ───────────────────────────────────────────
    Treasury   public treasury;
    MockERC20  public flash;   // Simulates $FLASH (6 dec)
    MockERC20  public usdt;    // Simulates USDT  (6 dec)

    // ─────────────── Actors ──────────────────────────────────────────────
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob   = makeAddr("bob");

    // ─────────────── Constants ───────────────────────────────────────────
    uint256 constant AMOUNT = 500e6; // 500 tokens (6 dec)

    // ─────────────── Setup ───────────────────────────────────────────────
    function setUp() public {
        // Deploy mock tokens to stand-in for $FLASH and USDT
        flash = new MockERC20("Flash Token", "FLASH", 6);
        usdt  = new MockERC20("Tether USD",  "USDT",  6);

        // Deploy treasury with `owner` as admin
        vm.prank(owner);
        treasury = new Treasury(owner);
    }

    // ─────────────── Helper: fund the treasury ────────────────────────────

    /// @dev Transfers `amount` of `token` directly into the treasury.
    function _fundTreasury(MockERC20 token, uint256 amount) internal {
        token.mint(address(treasury), amount);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 1. DEPLOYMENT / INITIAL STATE
    // ═════════════════════════════════════════════════════════════════════

    /// @dev Owner is set correctly in the constructor.
    function test_OwnerIsSetCorrectly() public view {
        assertEq(treasury.owner(), owner);
    }

    /// @dev Treasury starts with zero balance for any token.
    function test_InitialBalanceIsZero() public view {
        assertEq(treasury.balance(address(flash)), 0);
        assertEq(treasury.balance(address(usdt)),  0);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2. withdraw() — SUCCESS PATHS
    // ═════════════════════════════════════════════════════════════════════

    /// @dev Owner can withdraw FLASH tokens that were sent to the treasury.
    function test_OwnerCanWithdrawFlash() public {
        _fundTreasury(flash, AMOUNT);

        vm.prank(owner);
        treasury.withdraw(address(flash), alice, AMOUNT);

        assertEq(flash.balanceOf(alice),            AMOUNT);
        assertEq(treasury.balance(address(flash)),  0);
    }

    /// @dev Owner can withdraw USDT (simulating harvested Aave yield).
    function test_OwnerCanWithdrawUsdt() public {
        _fundTreasury(usdt, AMOUNT);

        vm.prank(owner);
        treasury.withdraw(address(usdt), bob, AMOUNT);

        assertEq(usdt.balanceOf(bob),            AMOUNT);
        assertEq(treasury.balance(address(usdt)), 0);
    }

    /// @dev Partial withdrawal leaves the remainder in the treasury.
    function test_PartialWithdraw() public {
        _fundTreasury(flash, AMOUNT);

        vm.prank(owner);
        treasury.withdraw(address(flash), alice, AMOUNT / 2);

        assertEq(flash.balanceOf(alice),           AMOUNT / 2);
        assertEq(treasury.balance(address(flash)), AMOUNT / 2);
    }

    /// @dev Withdraw emits the Withdrawn event with correct parameters.
    function test_WithdrawEmitsEvent() public {
        _fundTreasury(flash, AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit Treasury.Withdrawn(address(flash), alice, AMOUNT);

        vm.prank(owner);
        treasury.withdraw(address(flash), alice, AMOUNT);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3. withdraw() — REVERT PATHS
    // ═════════════════════════════════════════════════════════════════════

    /// @dev Non-owner cannot withdraw funds.
    function test_NonOwnerCannotWithdraw() public {
        _fundTreasury(flash, AMOUNT);

        vm.prank(alice);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        treasury.withdraw(address(flash), alice, AMOUNT);
    }

    /// @dev Withdraw with token = address(0) reverts with ZeroAddress.
    function test_WithdrawRevertsZeroToken() public {
        vm.prank(owner);
        vm.expectRevert(Treasury.Treasury__ZeroAddress.selector);
        treasury.withdraw(address(0), alice, AMOUNT);
    }

    /// @dev Withdraw with recipient = address(0) reverts with ZeroAddress.
    function test_WithdrawRevertsZeroRecipient() public {
        _fundTreasury(flash, AMOUNT);

        vm.prank(owner);
        vm.expectRevert(Treasury.Treasury__ZeroAddress.selector);
        treasury.withdraw(address(flash), address(0), AMOUNT);
    }

    /// @dev Withdraw with amount = 0 reverts with AmountZero.
    function test_WithdrawRevertsZeroAmount() public {
        _fundTreasury(flash, AMOUNT);

        vm.prank(owner);
        vm.expectRevert(Treasury.Treasury__AmountZero.selector);
        treasury.withdraw(address(flash), alice, 0);
    }

    /// @dev Withdraw more than available balance reverts with InsufficientBalance.
    function test_WithdrawRevertsInsufficientBalance() public {
        _fundTreasury(flash, AMOUNT);

        vm.prank(owner);
        vm.expectRevert(Treasury.Treasury__InsufficientBalance.selector);
        treasury.withdraw(address(flash), alice, AMOUNT + 1);
    }

    /// @dev Withdraw from an empty treasury reverts with InsufficientBalance.
    function test_WithdrawRevertsWhenEmpty() public {
        vm.prank(owner);
        vm.expectRevert(Treasury.Treasury__InsufficientBalance.selector);
        treasury.withdraw(address(flash), alice, AMOUNT);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 4. balance() VIEW HELPER
    // ═════════════════════════════════════════════════════════════════════

    /// @dev balance() correctly reflects tokens minted directly to treasury.
    function test_BalanceReflectsReceivedTokens() public {
        _fundTreasury(flash, AMOUNT);
        _fundTreasury(usdt,  AMOUNT * 2);

        assertEq(treasury.balance(address(flash)), AMOUNT);
        assertEq(treasury.balance(address(usdt)),  AMOUNT * 2);
    }

    /// @dev balance() decreases correctly after a withdrawal.
    function test_BalanceDecreasesAfterWithdraw() public {
        _fundTreasury(flash, AMOUNT);

        vm.prank(owner);
        treasury.withdraw(address(flash), alice, AMOUNT / 4);

        assertEq(treasury.balance(address(flash)), AMOUNT * 3 / 4);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 5. MULTI-TOKEN ACCOUNTING ($FLASH + USDT simultaneously)
    // ═════════════════════════════════════════════════════════════════════

    /**
     * @dev Simulates the real protocol flow:
     *  - $FLASH accumulates from trading fees (FlashPredMarket.placeBet)
     *  - USDT accumulates from Aave yield (FlashVault.harvestYield)
     *  Balances are independent and do not interfere with each other.
     */
    function test_IndependentTokenBalances() public {
        uint256 flashFees  = 150e6;  // Fees acumulados en $FLASH
        uint256 usdtYield  = 75e6;   // Yield cosechado en USDT

        _fundTreasury(flash, flashFees);
        _fundTreasury(usdt,  usdtYield);

        assertEq(treasury.balance(address(flash)), flashFees);
        assertEq(treasury.balance(address(usdt)),  usdtYield);

        // Owner withdraws both independently
        vm.startPrank(owner);
        treasury.withdraw(address(flash), alice, flashFees);
        treasury.withdraw(address(usdt),  bob,   usdtYield);
        vm.stopPrank();

        assertEq(flash.balanceOf(alice),           flashFees);
        assertEq(usdt.balanceOf(bob),              usdtYield);
        assertEq(treasury.balance(address(flash)), 0);
        assertEq(treasury.balance(address(usdt)),  0);
    }

    /**
     * @dev Multiple deposits of the same token accumulate correctly
     *      (mirrors multiple bet fees arriving in the same round).
     */
    function test_AccumulatesMultipleDeposits() public {
        uint256 fee1 = 10e6;
        uint256 fee2 = 25e6;
        uint256 fee3 = 8e6;

        _fundTreasury(flash, fee1);
        _fundTreasury(flash, fee2);
        _fundTreasury(flash, fee3);

        assertEq(treasury.balance(address(flash)), fee1 + fee2 + fee3);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 6. FUZZ TESTS
    // ═════════════════════════════════════════════════════════════════════

    /**
     * @dev Fuzz: any valid amount can be deposited and fully withdrawn.
     *      Ensures no off-by-one or overflow issues in accounting.
     */
    function testFuzz_DepositAndWithdraw(uint256 amount) public {
        amount = bound(amount, 1, type(uint96).max);

        _fundTreasury(flash, amount);
        assertEq(treasury.balance(address(flash)), amount);

        vm.prank(owner);
        treasury.withdraw(address(flash), alice, amount);

        assertEq(flash.balanceOf(alice),           amount);
        assertEq(treasury.balance(address(flash)), 0);
    }

    /**
     * @dev Fuzz: partial withdrawal leaves the correct remainder.
     *      withdraw + remainder == original amount (conservation law).
     */
    function testFuzz_PartialWithdrawConservation(
        uint256 total,
        uint256 withdrawAmt
    ) public {
        total       = bound(total,       1, type(uint96).max);
        withdrawAmt = bound(withdrawAmt, 1, total);

        _fundTreasury(usdt, total);

        vm.prank(owner);
        treasury.withdraw(address(usdt), alice, withdrawAmt);

        assertEq(usdt.balanceOf(alice),           withdrawAmt);
        assertEq(treasury.balance(address(usdt)), total - withdrawAmt);
    }
}
