// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/FlashToken.sol";

/**
 * @title FlashTokenTest
 * @dev Comprehensive unit tests for FlashToken.
 *
 * Test categories:
 *  1. Deployment / initial state
 *  2. Role management (grant / revoke)
 *  3. mint()
 *  4. burn()
 *  5. decimals()
 *  6. Standard ERC-20 behavior (transfer, approve, transferFrom)
 */
contract FlashTokenTest is Test {
    // ─────────────────── State ───────────────────────────────────────────
    FlashToken public token;

    address public admin = makeAddr("admin");
    address public minter = makeAddr("minter");
    address public burner = makeAddr("burner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant AMOUNT = 1_000e6; // 1 000 FLASH (6 dec)

    // ─────────────────── Roles (cached for readability) ──────────────────
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 constant ADMIN_ROLE = 0x00; // DEFAULT_ADMIN_ROLE

    // ─────────────────── Setup ───────────────────────────────────────────
    function setUp() public {
        // Deploy as `admin`
        vm.prank(admin);
        token = new FlashToken();

        // Grant roles explicitly (deployer holds only DEFAULT_ADMIN_ROLE)
        vm.startPrank(admin);
        token.grantRole(MINTER_ROLE, minter);
        token.grantRole(BURNER_ROLE, burner);
        vm.stopPrank();
    }

    // ═════════════════════════════════════════════════════════════════════
    // 1. DEPLOYMENT / INITIAL STATE
    // ═════════════════════════════════════════════════════════════════════

    function test_InitialName() public view {
        assertEq(token.name(), "Flash Token");
    }

    function test_InitialSymbol() public view {
        assertEq(token.symbol(), "FLASH");
    }

    function test_InitialTotalSupply() public view {
        assertEq(token.totalSupply(), 0);
    }

    function test_AdminHasDefaultAdminRole() public view {
        assertTrue(token.hasRole(ADMIN_ROLE, admin));
    }

    /// @dev Deployer must NOT have MINTER_ROLE by default.
    function test_DeployerDoesNotHaveMinterRole() public view {
        assertFalse(token.hasRole(MINTER_ROLE, admin));
    }

    /// @dev Deployer must NOT have BURNER_ROLE by default.
    function test_DeployerDoesNotHaveBurnerRole() public view {
        assertFalse(token.hasRole(BURNER_ROLE, admin));
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2. ROLE MANAGEMENT
    // ═════════════════════════════════════════════════════════════════════

    function test_AdminCanGrantMinterRole() public view {
        assertTrue(token.hasRole(MINTER_ROLE, minter));
    }

    function test_AdminCanGrantBurnerRole() public view {
        assertTrue(token.hasRole(BURNER_ROLE, burner));
    }

    function test_AdminCanRevokeMinterRole() public {
        vm.prank(admin);
        token.revokeRole(MINTER_ROLE, minter);
        assertFalse(token.hasRole(MINTER_ROLE, minter));
    }

    function test_NonAdminCannotGrantRole() public {
        vm.prank(alice);
        vm.expectRevert(); // AccessControl reverts without specific selector
        token.grantRole(MINTER_ROLE, alice);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3. MINT
    // ═════════════════════════════════════════════════════════════════════

    function test_MinterCanMint() public {
        vm.prank(minter);
        token.mint(alice, AMOUNT);
        assertEq(token.balanceOf(alice), AMOUNT);
        assertEq(token.totalSupply(), AMOUNT);
    }

    function test_MintEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit FlashToken.TokensMinted(alice, AMOUNT);

        vm.prank(minter);
        token.mint(alice, AMOUNT);
    }

    function test_MintRevertsZeroAmount() public {
        vm.prank(minter);
        vm.expectRevert(FlashToken.FlashToken__AmountZero.selector);
        token.mint(alice, 0);
    }

    function test_MintRevertsZeroAddress() public {
        vm.prank(minter);
        vm.expectRevert(FlashToken.FlashToken__InvalidRecipient.selector);
        token.mint(address(0), AMOUNT);
    }

    function test_NonMinterCannotMint() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, AMOUNT);
    }

    function test_AdminCannotMintWithoutRole() public {
        vm.prank(admin);
        vm.expectRevert();
        token.mint(alice, AMOUNT);
    }

    /// @dev Fuzz: any valid amount should mint correctly.
    function testFuzz_MintAnyAmount(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        vm.prank(minter);
        token.mint(alice, amount);
        assertEq(token.balanceOf(alice), amount);
    }

    /// @dev Mint to multiple recipients accumulates supply correctly.
    function test_MintAccumulatesSupply() public {
        vm.startPrank(minter);
        token.mint(alice, AMOUNT);
        token.mint(bob, AMOUNT * 2);
        vm.stopPrank();

        assertEq(token.totalSupply(), AMOUNT * 3);
        assertEq(token.balanceOf(alice), AMOUNT);
        assertEq(token.balanceOf(bob), AMOUNT * 2);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 4. BURN
    // ═════════════════════════════════════════════════════════════════════

    modifier withAliceMinted(uint256 amount) {
        vm.prank(minter);
        token.mint(alice, amount);
        _;
    }

    function test_BurnerCanBurn() public withAliceMinted(AMOUNT) {
        vm.prank(burner);
        token.burn(alice, AMOUNT);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_BurnEmitsEvent() public withAliceMinted(AMOUNT) {
        vm.expectEmit(true, false, false, true);
        emit FlashToken.TokensBurned(alice, AMOUNT);

        vm.prank(burner);
        token.burn(alice, AMOUNT);
    }

    function test_BurnRevertsZeroAmount() public withAliceMinted(AMOUNT) {
        vm.prank(burner);
        vm.expectRevert(FlashToken.FlashToken__AmountZero.selector);
        token.burn(alice, 0);
    }

    function test_BurnRevertsInsufficientBalance()
        public
        withAliceMinted(AMOUNT)
    {
        vm.prank(burner);
        vm.expectRevert(); // ERC20InsufficientBalance
        token.burn(alice, AMOUNT + 1);
    }

    function test_NonBurnerCannotBurn() public withAliceMinted(AMOUNT) {
        vm.prank(alice);
        vm.expectRevert();
        token.burn(alice, AMOUNT);
    }

    /// @dev Fuzz: partial burns reduce balance by exactly the burned amount.
    function testFuzz_PartialBurn(uint256 mintAmt, uint256 burnAmt) public {
        mintAmt = bound(mintAmt, 1, type(uint128).max);
        burnAmt = bound(burnAmt, 1, mintAmt);

        vm.prank(minter);
        token.mint(alice, mintAmt);

        vm.prank(burner);
        token.burn(alice, burnAmt);

        assertEq(token.balanceOf(alice), mintAmt - burnAmt);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 5. DECIMALS
    // ═════════════════════════════════════════════════════════════════════

    function test_Decimals() public view {
        assertEq(token.decimals(), 6);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 6. STANDARD ERC-20 BEHAVIOUR
    // ═════════════════════════════════════════════════════════════════════

    function test_Transfer() public withAliceMinted(AMOUNT) {
        vm.prank(alice);
        token.transfer(bob, AMOUNT / 2);

        assertEq(token.balanceOf(alice), AMOUNT / 2);
        assertEq(token.balanceOf(bob), AMOUNT / 2);
    }

    function test_TransferRevertsInsufficientBalance()
        public
        withAliceMinted(AMOUNT)
    {
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, AMOUNT + 1);
    }

    function test_ApproveAndTransferFrom() public withAliceMinted(AMOUNT) {
        vm.prank(alice);
        token.approve(bob, AMOUNT);

        vm.prank(bob);
        token.transferFrom(alice, bob, AMOUNT);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), AMOUNT);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_TransferFromRevertsInsufficientAllowance()
        public
        withAliceMinted(AMOUNT)
    {
        vm.prank(alice);
        token.approve(bob, AMOUNT - 1);

        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, bob, AMOUNT);
    }

    function test_RoundTrip_MintBurnBalance() public {
        uint256 amt = 500e6;

        vm.prank(minter);
        token.mint(alice, amt);
        assertEq(token.totalSupply(), amt);

        vm.prank(burner);
        token.burn(alice, amt);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 7. PAUSE / UNPAUSE
    // ═════════════════════════════════════════════════════════════════════

    /// @dev DEFAULT_ADMIN_ROLE can pause the contract.
    function test_AdminCanPause() public {
        vm.prank(admin);
        token.pause();
        assertTrue(token.paused());
    }

    /// @dev DEFAULT_ADMIN_ROLE can unpause the contract.
    function test_AdminCanUnpause() public {
        vm.prank(admin);
        token.pause();
        vm.prank(admin);
        token.unpause();
        assertFalse(token.paused());
    }

    /// @dev Non-admin cannot pause the contract.
    function test_NonAdminCannotPause() public {
        vm.prank(alice);
        vm.expectRevert();
        token.pause();
    }

    /// @dev mint() reverts when the contract is paused.
    function test_MintRevertsWhenPaused() public {
        vm.prank(admin);
        token.pause();

        vm.prank(minter);
        vm.expectRevert(); // EnforcedPause
        token.mint(alice, AMOUNT);
    }

    /// @dev burn() reverts when the contract is paused.
    function test_BurnRevertsWhenPaused() public withAliceMinted(AMOUNT) {
        vm.prank(admin);
        token.pause();

        vm.prank(burner);
        vm.expectRevert(); // EnforcedPause
        token.burn(alice, AMOUNT);
    }

    /// @dev After unpause, mint and burn work again normally.
    function test_MintAndBurnWorkAfterUnpause() public {
        vm.prank(admin);
        token.pause();
        vm.prank(admin);
        token.unpause();

        // mint should succeed
        vm.prank(minter);
        token.mint(alice, AMOUNT);
        assertEq(token.balanceOf(alice), AMOUNT);

        // burn should succeed
        vm.prank(burner);
        token.burn(alice, AMOUNT);
        assertEq(token.balanceOf(alice), 0);
    }
}
