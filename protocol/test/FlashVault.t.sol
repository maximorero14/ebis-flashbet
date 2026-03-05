// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/FlashVault.sol";
import "../src/FlashToken.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockAToken.sol";
import "./mocks/MockAavePool.sol";

/**
 * @title FlashVaultTest
 * @dev Unit tests for FlashVault using lightweight mocks (no fork required).
 *
 * Test categories:
 *  1. Deployment / initial state
 *  2. deposit()
 *  3. redeem()
 *  4. harvestYield() / pendingYield()
 *  5. Access control & edge cases
 *  6. Fuzz tests
 */
contract FlashVaultTest is Test {
    // ─────────────── Contracts ───────────────────────────────────────────
    FlashToken public flash;
    MockERC20 public usdt;
    MockAToken public aToken;
    MockAavePool public pool;
    FlashVault public vault;

    // ─────────────── Actors ──────────────────────────────────────────────
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    // ─────────────── Roles ───────────────────────────────────────────────
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // ─────────────── Constants ───────────────────────────────────────────
    uint256 constant DEPOSIT = 1_000e6; // 1 000 USDT (6 dec)

    // ─────────────── Setup ───────────────────────────────────────────────
    function setUp() public {
        vm.startPrank(admin);

        // Deploy tokens
        flash = new FlashToken();
        usdt = new MockERC20("Tether USD", "USDT", 6);
        aToken = new MockAToken();

        // Deploy mock pool (holds USDT, mints/burns aToken)
        pool = new MockAavePool(address(usdt), address(aToken));

        // Deploy vault
        vault = new FlashVault(
            address(flash),
            address(usdt),
            address(pool),
            address(aToken),
            treasury
        );

        // Grant vault the MINTER and BURNER roles on FlashToken
        flash.grantRole(MINTER_ROLE, address(vault));
        flash.grantRole(BURNER_ROLE, address(vault));

        vm.stopPrank();

        // Fund alice and bob with USDT
        usdt.mint(alice, DEPOSIT * 10);
        usdt.mint(bob, DEPOSIT * 10);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 1. INITIAL STATE
    // ═════════════════════════════════════════════════════════════════════

    function test_InitialTotalDeposited() public view {
        assertEq(vault.totalDeposited(), 0);
    }

    function test_ImmutableAddresses() public view {
        assertEq(address(vault.flashToken()), address(flash));
        assertEq(address(vault.usdt()), address(usdt));
        assertEq(address(vault.aavePool()), address(pool));
        assertEq(address(vault.aToken()), address(aToken));
        assertEq(vault.treasury(), treasury);
    }

    function test_VaultHasMinterRole() public view {
        assertTrue(flash.hasRole(MINTER_ROLE, address(vault)));
    }

    function test_VaultHasBurnerRole() public view {
        assertTrue(flash.hasRole(BURNER_ROLE, address(vault)));
    }

    function test_ConstructorRevertsZeroAddress() public {
        vm.expectRevert(FlashVault.FlashVault__ZeroAddress.selector);
        new FlashVault(
            address(0),
            address(usdt),
            address(pool),
            address(aToken),
            treasury
        );
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2. DEPOSIT
    // ═════════════════════════════════════════════════════════════════════

    modifier withAliceDeposited(uint256 amount) {
        vm.startPrank(alice);
        usdt.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
        _;
    }

    function test_DepositMintsFlash() public withAliceDeposited(DEPOSIT) {
        assertEq(flash.balanceOf(alice), DEPOSIT);
    }

    function test_DepositUpdatesTotalDeposited()
        public
        withAliceDeposited(DEPOSIT)
    {
        assertEq(vault.totalDeposited(), DEPOSIT);
    }

    function test_DepositTransfersUsdtToPool()
        public
        withAliceDeposited(DEPOSIT)
    {
        // Pool should hold the USDT
        assertEq(usdt.balanceOf(address(pool)), DEPOSIT);
        // Vault should hold aTokens
        assertEq(aToken.balanceOf(address(vault)), DEPOSIT);
    }

    function test_DepositEmitsEvent() public {
        vm.startPrank(alice);
        usdt.approve(address(vault), DEPOSIT);

        vm.expectEmit(true, false, false, true);
        emit FlashVault.Deposited(alice, DEPOSIT);
        vault.deposit(DEPOSIT);
        vm.stopPrank();
    }

    function test_DepositRevertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(FlashVault.FlashVault__AmountZero.selector);
        vault.deposit(0);
    }

    function test_MultipleDepositsAccumulate() public {
        vm.startPrank(alice);
        usdt.approve(address(vault), DEPOSIT * 2);
        vault.deposit(DEPOSIT);
        vault.deposit(DEPOSIT);
        vm.stopPrank();

        assertEq(vault.totalDeposited(), DEPOSIT * 2);
        assertEq(flash.balanceOf(alice), DEPOSIT * 2);
    }

    function test_TwoUsersDeposit() public {
        vm.startPrank(alice);
        usdt.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT);
        vm.stopPrank();

        vm.startPrank(bob);
        usdt.approve(address(vault), DEPOSIT * 2);
        vault.deposit(DEPOSIT * 2);
        vm.stopPrank();

        assertEq(vault.totalDeposited(), DEPOSIT * 3);
        assertEq(flash.balanceOf(alice), DEPOSIT);
        assertEq(flash.balanceOf(bob), DEPOSIT * 2);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3. REDEEM
    // ═════════════════════════════════════════════════════════════════════

    function test_RedeemBurnsFlash() public withAliceDeposited(DEPOSIT) {
        vm.prank(alice);
        vault.redeem(DEPOSIT);
        assertEq(flash.balanceOf(alice), 0);
    }

    function test_RedeemReturnsUsdt() public withAliceDeposited(DEPOSIT) {
        uint256 balBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(DEPOSIT);
        assertEq(usdt.balanceOf(alice), balBefore + DEPOSIT);
    }

    function test_RedeemUpdatesTotalDeposited()
        public
        withAliceDeposited(DEPOSIT)
    {
        vm.prank(alice);
        vault.redeem(DEPOSIT);
        assertEq(vault.totalDeposited(), 0);
    }

    function test_RedeemEmitsEvent() public withAliceDeposited(DEPOSIT) {
        vm.expectEmit(true, false, false, true);
        emit FlashVault.Redeemed(alice, DEPOSIT);

        vm.prank(alice);
        vault.redeem(DEPOSIT);
    }

    function test_RedeemRevertsZeroAmount() public withAliceDeposited(DEPOSIT) {
        vm.prank(alice);
        vm.expectRevert(FlashVault.FlashVault__AmountZero.selector);
        vault.redeem(0);
    }

    function test_RedeemRevertsInsufficientFlash() public {
        vm.prank(alice);
        vm.expectRevert(
            FlashVault.FlashVault__InsufficientFlashBalance.selector
        );
        vault.redeem(DEPOSIT);
    }

    function test_PartialRedeem() public withAliceDeposited(DEPOSIT) {
        vm.prank(alice);
        vault.redeem(DEPOSIT / 2);

        assertEq(flash.balanceOf(alice), DEPOSIT / 2);
        assertEq(vault.totalDeposited(), DEPOSIT / 2);
    }

    function test_RoundTripDepositRedeem() public {
        uint256 startUsdt = usdt.balanceOf(alice);

        vm.startPrank(alice);
        usdt.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT);
        vault.redeem(DEPOSIT);
        vm.stopPrank();

        assertEq(usdt.balanceOf(alice), startUsdt);
        assertEq(flash.balanceOf(alice), 0);
        assertEq(vault.totalDeposited(), 0);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 4. HARVEST YIELD / PENDING YIELD
    // ═════════════════════════════════════════════════════════════════════

    function test_PendingYieldZeroWithNoYield()
        public
        withAliceDeposited(DEPOSIT)
    {
        assertEq(vault.pendingYield(), 0);
    }

    function test_PendingYieldAfterSimulatedYield()
        public
        withAliceDeposited(DEPOSIT)
    {
        uint256 yieldAmt = 50e6; // 50 USDT
        aToken.simulateYield(address(vault), yieldAmt);
        assertEq(vault.pendingYield(), yieldAmt);
    }

    function test_HarvestYieldSendsToTreasury()
        public
        withAliceDeposited(DEPOSIT)
    {
        uint256 yieldAmt = 100e6;
        // Simulate Aave interest + ensure pool holds enough USDT to pay it out
        aToken.simulateYield(address(vault), yieldAmt);
        usdt.mint(address(pool), yieldAmt); // pool needs USDT to release

        uint256 treasuryBefore = usdt.balanceOf(treasury);
        vault.harvestYield();

        assertEq(usdt.balanceOf(treasury), treasuryBefore + yieldAmt);
    }

    function test_HarvestYieldEmitsEvent() public withAliceDeposited(DEPOSIT) {
        uint256 yieldAmt = 75e6;
        aToken.simulateYield(address(vault), yieldAmt);
        usdt.mint(address(pool), yieldAmt);

        vm.expectEmit(false, true, false, true);
        emit FlashVault.YieldHarvested(yieldAmt, treasury);
        vault.harvestYield();
    }

    function test_HarvestYieldDoesNotTouchPrincipal()
        public
        withAliceDeposited(DEPOSIT)
    {
        uint256 yieldAmt = 60e6;
        aToken.simulateYield(address(vault), yieldAmt);
        usdt.mint(address(pool), yieldAmt);

        vault.harvestYield();

        // totalDeposited unchanged — only surplus harvested
        assertEq(vault.totalDeposited(), DEPOSIT);
        // Vault still holds aTokens for principal
        assertEq(aToken.balanceOf(address(vault)), DEPOSIT);
    }

    function test_HarvestYieldRevertsNoYield()
        public
        withAliceDeposited(DEPOSIT)
    {
        vm.expectRevert(FlashVault.FlashVault__NoYieldAvailable.selector);
        vault.harvestYield();
    }

    function test_HarvestYieldRevertsWhenEmpty() public {
        vm.expectRevert(FlashVault.FlashVault__NoYieldAvailable.selector);
        vault.harvestYield();
    }

    function test_AnyoneCanHarvestYield() public withAliceDeposited(DEPOSIT) {
        uint256 yieldAmt = 10e6;
        aToken.simulateYield(address(vault), yieldAmt);
        usdt.mint(address(pool), yieldAmt);

        // Bob (random address) can trigger harvest — funds go to treasury
        vm.prank(bob);
        vault.harvestYield();

        assertEq(usdt.balanceOf(treasury), yieldAmt);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 5. INTEGRATION SCENARIO
    // ═════════════════════════════════════════════════════════════════════

    function test_FullLifecycleTwoUsers() public {
        // Alice and Bob deposit
        vm.startPrank(alice);
        usdt.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT);
        vm.stopPrank();

        vm.startPrank(bob);
        usdt.approve(address(vault), DEPOSIT * 2);
        vault.deposit(DEPOSIT * 2);
        vm.stopPrank();

        assertEq(vault.totalDeposited(), DEPOSIT * 3);

        // Yield accrues
        uint256 yieldAmt = 300e6;
        aToken.simulateYield(address(vault), yieldAmt);
        usdt.mint(address(pool), yieldAmt);

        // Harvest
        vault.harvestYield();
        assertEq(usdt.balanceOf(treasury), yieldAmt);
        assertEq(vault.pendingYield(), 0);

        // Alice redeems all
        vm.prank(alice);
        vault.redeem(DEPOSIT);
        assertEq(vault.totalDeposited(), DEPOSIT * 2);

        // Bob redeems all
        vm.prank(bob);
        vault.redeem(DEPOSIT * 2);
        assertEq(vault.totalDeposited(), 0);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 6. FUZZ TESTS
    // ═════════════════════════════════════════════════════════════════════

    function testFuzz_DepositRedeem(uint256 amount) public {
        amount = bound(amount, 1, type(uint96).max);
        usdt.mint(alice, amount);

        vm.startPrank(alice);
        usdt.approve(address(vault), amount);
        vault.deposit(amount);

        assertEq(flash.balanceOf(alice), amount);
        assertEq(vault.totalDeposited(), amount);

        vault.redeem(amount);
        vm.stopPrank();

        assertEq(flash.balanceOf(alice), 0);
        assertEq(vault.totalDeposited(), 0);
    }

    function testFuzz_HarvestYield(
        uint256 depositAmt,
        uint256 yieldAmt
    ) public {
        depositAmt = bound(depositAmt, 1, type(uint96).max);
        yieldAmt = bound(yieldAmt, 1, type(uint96).max);

        usdt.mint(alice, depositAmt);

        vm.startPrank(alice);
        usdt.approve(address(vault), depositAmt);
        vault.deposit(depositAmt);
        vm.stopPrank();

        aToken.simulateYield(address(vault), yieldAmt);
        usdt.mint(address(pool), yieldAmt);

        vault.harvestYield();

        assertEq(usdt.balanceOf(treasury), yieldAmt);
        assertEq(vault.pendingYield(), 0);
        assertEq(vault.totalDeposited(), depositAmt); // principal intact
    }

    // ═════════════════════════════════════════════════════════════════════
    // 7. PAUSE / UNPAUSE
    // ═════════════════════════════════════════════════════════════════════

    /// @dev Owner can pause the vault.
    function test_OwnerCanPause() public {
        vm.prank(admin);
        vault.pause();
        assertTrue(vault.paused());
    }

    /// @dev Owner can unpause the vault.
    function test_OwnerCanUnpause() public {
        vm.prank(admin);
        vault.pause();
        vm.prank(admin);
        vault.unpause();
        assertFalse(vault.paused());
    }

    /// @dev Non-owner cannot pause the vault.
    function test_NonOwnerCannotPause() public {
        vm.prank(alice);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        vault.pause();
    }

    /// @dev deposit() reverts when the vault is paused.
    function test_DepositRevertsWhenPaused() public {
        vm.prank(admin);
        vault.pause();

        vm.startPrank(alice);
        usdt.approve(address(vault), DEPOSIT);
        vm.expectRevert(); // EnforcedPause
        vault.deposit(DEPOSIT);
        vm.stopPrank();
    }

    /// @dev redeem() reverts when the vault is paused.
    function test_RedeemRevertsWhenPaused() public withAliceDeposited(DEPOSIT) {
        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert(); // EnforcedPause
        vault.redeem(DEPOSIT);
    }

    /// @dev harvestYield() reverts when the vault is paused.
    function test_HarvestYieldRevertsWhenPaused()
        public
        withAliceDeposited(DEPOSIT)
    {
        uint256 yieldAmt = 50e6;
        aToken.simulateYield(address(vault), yieldAmt);
        usdt.mint(address(pool), yieldAmt);

        vm.prank(admin);
        vault.pause();

        vm.expectRevert(); // EnforcedPause
        vault.harvestYield();
    }

    /// @dev After unpause, deposit and redeem work normally again.
    function test_DepositAndRedeemWorkAfterUnpause() public {
        vm.prank(admin);
        vault.pause();
        vm.prank(admin);
        vault.unpause();

        vm.startPrank(alice);
        usdt.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT);
        vault.redeem(DEPOSIT);
        vm.stopPrank();

        assertEq(flash.balanceOf(alice), 0);
        assertEq(vault.totalDeposited(), 0);
    }
}
