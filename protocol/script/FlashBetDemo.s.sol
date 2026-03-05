// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {FlashToken} from "../src/FlashToken.sol";
import {FlashVault} from "../src/FlashVault.sol";
import {MockAToken} from "../src/mocks/MockAToken.sol";
import {MockAavePool} from "../src/mocks/MockAavePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// =============================================================================

/**
 * @title FlashBetDemo
 * @dev Full deployment + happy-path demo for FlashToken + FlashVault on Sepolia.
 *
 * Uses MOCK Aave contracts (MockAToken, MockAavePool) with the REAL Sepolia USDT.
 * This bypasses Aave testnet supply cap issues while using real tokens.
 *
 * PREREQUISITES (before running this script):
 *   All 3 wallets derived from SEPOLIA_MNEMONIC must have:
 *   - Sepolia ETH (for gas)
 *   - USDT: https://sepolia.etherscan.io/address/0x7169d38820dfd117c3fa1f22a697dba58d90ba06
 *     Deployer: at least 20 USDT (for yield reserve seed)
 *     Player 1: at least 200 USDT
 *     Player 2: at least 150 USDT
 *
 * PHASES:
 *  Phase 1  - Deploy MockAToken, MockAavePool, FlashToken, FlashVault.
 *  Phase 2  - Grant MINTER_ROLE and BURNER_ROLE to the vault.
 *  Phase 3  - Deployer seeds 20 USDT yield reserve into MockAavePool.
 *  Phase 4  - Players deposit real USDT -> receive $FLASH 1:1.
 *  Phase 5  - Player 1 partially redeems $FLASH -> receives USDT back.
 *  Phase 6  - harvestYield() sends accrued yield to treasury.
 *  Summary  - Final balances and contract addresses for Etherscan.
 *
 * USAGE:
 *   set -a && source .env && set +a
 *   forge script script/FlashBetDemo.s.sol \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast \
 *     --verify \
 *     -vvv
 */
contract FlashBetDemo is Script {
    using SafeERC20 for IERC20;
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    uint256 constant USDT_UNIT = 1e6; // 1 token (6 decimals)

    // Real Sepolia USDT (standard, not Aave's version)
    address constant USDT_ADDR = 0x7169D38820dfd117C3FA1f22a697dBA58d90BA06;

    // -------------------------------------------------------------------------
    // Deployed contracts
    // -------------------------------------------------------------------------
    MockAToken public mockAToken;
    MockAavePool public mockPool;
    FlashToken public flashToken;
    FlashVault public flashVault;
    IERC20 public usdt = IERC20(USDT_ADDR);

    // -------------------------------------------------------------------------
    // Actors
    // -------------------------------------------------------------------------
    address public deployer;
    address public player1;
    address public player2;

    uint256 public deployerPk;
    uint256 public player1Pk;
    uint256 public player2Pk;

    // -------------------------------------------------------------------------
    // Entry point
    // -------------------------------------------------------------------------
    function run() external {
        console.log(
            "\n======================================================================"
        );
        console.log(
            "FLASHBET SYSTEM DEMO - Happy Path (Mock Aave + Real USDT)"
        );
        console.log("FlashToken + FlashVault + MockAavePool on Sepolia");
        console.log(
            "======================================================================\n"
        );

        setupAccounts();
        checkPrerequisites();
        phase1_DeployAll();
        phase2_GrantRoles();
        phase3_SeedYieldReserve();
        phase4_PlayersDeposit();
        phase5_Player1Redeems();
        phase6_HarvestYield();
        finalSummary();
    }

    // =========================================================================
    // SETUP
    // =========================================================================
    function setupAccounts() internal {
        string memory mnemonic = vm.envString("SEPOLIA_MNEMONIC");
        string memory path = "m/44'/60'/0'/0/";

        deployerPk = vm.deriveKey(mnemonic, path, 0);
        player1Pk = vm.deriveKey(mnemonic, path, 1);
        player2Pk = vm.deriveKey(mnemonic, path, 2);

        deployer = vm.addr(deployerPk);
        player1 = vm.addr(player1Pk);
        player2 = vm.addr(player2Pk);

        console.log("==> Participants:");
        console.log("   Deployer / Treasury:", deployer);
        console.log("   Player 1 (BTC-UP):  ", player1);
        console.log("   Player 2 (BTC-DOWN):", player2);
    }

    function checkPrerequisites() internal view {
        console.log("\n==> Pre-flight USDT balances (real Sepolia USDT):");
        console.log(
            "   Deployer:",
            usdt.balanceOf(deployer) / USDT_UNIT,
            "USDT"
        );
        console.log(
            "   Player 1:",
            usdt.balanceOf(player1) / USDT_UNIT,
            "USDT"
        );
        console.log(
            "   Player 2:",
            usdt.balanceOf(player2) / USDT_UNIT,
            "USDT"
        );

        require(
            usdt.balanceOf(deployer) >= 20 * USDT_UNIT,
            "Deployer needs at least 20 USDT for yield reserve seed"
        );
        require(
            usdt.balanceOf(player1) >= 200 * USDT_UNIT,
            "Player 1 needs at least 200 USDT"
        );
        require(
            usdt.balanceOf(player2) >= 150 * USDT_UNIT,
            "Player 2 needs at least 150 USDT"
        );
        console.log("   All balances OK.\n");
    }

    // =========================================================================
    // PHASE 1 - DEPLOY ALL CONTRACTS
    // =========================================================================
    function phase1_DeployAll() internal {
        console.log(
            "======================================================================"
        );
        console.log("PHASE 1: DEPLOYMENT");
        console.log(
            "======================================================================\n"
        );

        vm.startBroadcast(deployerPk);

        // Predict MockAavePool address so MockAToken can reference it at deploy
        uint64 nonce = vm.getNonce(deployer);
        address predictedPool = vm.computeCreateAddress(deployer, nonce + 1);

        mockAToken = new MockAToken(USDT_ADDR, predictedPool);
        console.log("==> MockAToken deployed:  ", address(mockAToken));

        mockPool = new MockAavePool(USDT_ADDR, address(mockAToken));
        console.log("==> MockAavePool deployed: ", address(mockPool));
        require(
            address(mockPool) == predictedPool,
            "Pool address prediction failed"
        );

        flashToken = new FlashToken();
        console.log("==> FlashToken ($FLASH):  ", address(flashToken));

        flashVault = new FlashVault(
            address(flashToken),
            USDT_ADDR,
            address(mockPool),
            address(mockAToken),
            deployer
        );
        console.log("==> FlashVault deployed:  ", address(flashVault));
        console.log("   Underlying USDT:", USDT_ADDR);
        console.log("   Treasury:       ", deployer);

        vm.stopBroadcast();
    }

    // =========================================================================
    // PHASE 2 - GRANT ROLES
    // =========================================================================
    function phase2_GrantRoles() internal {
        console.log(
            "\n======================================================================"
        );
        console.log("PHASE 2: ROLE CONFIGURATION");
        console.log(
            "======================================================================\n"
        );

        vm.startBroadcast(deployerPk);
        flashToken.grantRole(flashToken.MINTER_ROLE(), address(flashVault));
        flashToken.grantRole(flashToken.BURNER_ROLE(), address(flashVault));
        vm.stopBroadcast();

        console.log("==> MINTER_ROLE + BURNER_ROLE granted to FlashVault");
        console.log("   Only the Vault can mint or burn $FLASH.");
    }

    // =========================================================================
    // PHASE 3 - SEED YIELD RESERVE
    // =========================================================================
    function phase3_SeedYieldReserve() internal {
        console.log(
            "\n======================================================================"
        );
        console.log("PHASE 3: SEED YIELD RESERVE INTO MOCK POOL");
        console.log(
            "======================================================================\n"
        );

        // 5% of (200 + 150) = 17.5 USDT expected yield. Seed 20 USDT to be safe.
        uint256 seed = 20 * USDT_UNIT;

        vm.startBroadcast(deployerPk);
        usdt.forceApprove(address(mockPool), seed);
        mockPool.seedYieldReserve(seed);
        vm.stopBroadcast();

        console.log(
            "==> Deployer seeded",
            seed / USDT_UNIT,
            "USDT into MockAavePool"
        );
        console.log("   This backs the 5% yield credited on each deposit.");
        console.log(
            "   In production Aave, this comes from borrower interest."
        );
        console.log(
            "   Pool USDT reserve:",
            usdt.balanceOf(address(mockPool)) / USDT_UNIT,
            "USDT"
        );
    }

    // =========================================================================
    // PHASE 4 - PLAYERS DEPOSIT USDT -> $FLASH
    // =========================================================================
    function phase4_PlayersDeposit() internal {
        console.log(
            "\n======================================================================"
        );
        console.log("PHASE 4: PLAYERS DEPOSIT USDT -> RECEIVE $FLASH");
        console.log(
            "======================================================================\n"
        );

        // Player 1 deposits 200 USDT
        console.log("==> Player 1: Depositing 200 USDT...");
        vm.startBroadcast(player1Pk);
        usdt.forceApprove(address(flashVault), 200 * USDT_UNIT);
        flashVault.deposit(200 * USDT_UNIT);
        vm.stopBroadcast();

        console.log("   -> 200 USDT pulled from Player 1");
        console.log("   -> FlashVault supplied 200 USDT to MockAavePool");
        console.log(
            "   -> MockAavePool minted 210 maUSDT to Vault (+5% yield bonus)"
        );
        console.log(
            "   -> $FLASH minted 1:1 to Player 1:",
            flashToken.balanceOf(player1) / USDT_UNIT
        );

        // Player 2 deposits 150 USDT
        console.log("\n==> Player 2: Depositing 150 USDT...");
        vm.startBroadcast(player2Pk);
        usdt.forceApprove(address(flashVault), 150 * USDT_UNIT);
        flashVault.deposit(150 * USDT_UNIT);
        vm.stopBroadcast();

        console.log("   -> 150 USDT pulled from Player 2");
        console.log(
            "   -> MockAavePool minted 157.5 maUSDT to Vault (+5% yield bonus)"
        );
        console.log(
            "   -> $FLASH minted 1:1 to Player 2:",
            flashToken.balanceOf(player2) / USDT_UNIT
        );

        console.log("\n==> Protocol state after deposits:");
        console.log(
            "   maUSDT in Vault: ",
            mockAToken.balanceOf(address(flashVault)) / USDT_UNIT
        );
        console.log(
            "   totalDeposited:  ",
            flashVault.totalDeposited() / USDT_UNIT,
            "USDT"
        );
        console.log(
            "   pendingYield():  ",
            flashVault.pendingYield() / USDT_UNIT,
            "USDT"
        );
        console.log(
            "   $FLASH supply:   ",
            flashToken.totalSupply() / USDT_UNIT
        );
    }

    // =========================================================================
    // PHASE 5 - PLAYER 1 REDEEMS
    // =========================================================================
    function phase5_Player1Redeems() internal {
        console.log(
            "\n======================================================================"
        );
        console.log("PHASE 5: PLAYER 1 REDEEMS 100 $FLASH -> USDT");
        console.log(
            "======================================================================\n"
        );

        uint256 usdtBefore = usdt.balanceOf(player1);
        uint256 flashBefore = flashToken.balanceOf(player1);

        vm.startBroadcast(player1Pk);
        flashVault.redeem(100 * USDT_UNIT);
        vm.stopBroadcast();

        console.log("==> Player 1 redeemed 100 $FLASH:");
        console.log(
            "   $FLASH burned:    ",
            (flashBefore - flashToken.balanceOf(player1)) / USDT_UNIT
        );
        console.log(
            "   USDT received:    ",
            (usdt.balanceOf(player1) - usdtBefore) / USDT_UNIT
        );
        console.log(
            "   Remaining $FLASH: ",
            flashToken.balanceOf(player1) / USDT_UNIT
        );
        console.log(
            "   totalDeposited:   ",
            flashVault.totalDeposited() / USDT_UNIT,
            "USDT"
        );
        console.log(
            "   pendingYield():   ",
            flashVault.pendingYield() / USDT_UNIT,
            "USDT (unchanged)"
        );
    }

    // =========================================================================
    // PHASE 6 - HARVEST YIELD
    // =========================================================================
    function phase6_HarvestYield() internal {
        console.log(
            "\n======================================================================"
        );
        console.log("PHASE 6: YIELD HARVEST -> TREASURY");
        console.log(
            "======================================================================\n"
        );

        console.log(
            "==> Yield accrued automatically (5% credited at each deposit):"
        );
        console.log(
            "   maUSDT balance:  ",
            mockAToken.balanceOf(address(flashVault)) / USDT_UNIT
        );
        console.log(
            "   totalDeposited:  ",
            flashVault.totalDeposited() / USDT_UNIT
        );
        console.log(
            "   pendingYield():  ",
            flashVault.pendingYield() / USDT_UNIT,
            "USDT"
        );

        uint256 treasuryBefore = usdt.balanceOf(deployer);

        vm.startBroadcast(deployerPk);
        flashVault.harvestYield();
        vm.stopBroadcast();

        uint256 harvested = usdt.balanceOf(deployer) - treasuryBefore;
        console.log("\n==> harvestYield() executed!");
        console.log("   Treasury received:", harvested / USDT_UNIT, "USDT");
        console.log(
            "   Principal intact: ",
            flashVault.totalDeposited() / USDT_UNIT,
            "USDT"
        );
        console.log(
            "   pendingYield():   ",
            flashVault.pendingYield() / USDT_UNIT,
            "USDT (now 0)"
        );
    }

    // =========================================================================
    // FINAL SUMMARY
    // =========================================================================
    function finalSummary() internal view {
        console.log(
            "\n======================================================================"
        );
        console.log("FINAL STATE");
        console.log(
            "======================================================================\n"
        );

        console.log(
            "   Player 1 USDT:   ",
            usdt.balanceOf(player1) / USDT_UNIT
        );
        console.log(
            "   Player 1 $FLASH: ",
            flashToken.balanceOf(player1) / USDT_UNIT
        );
        console.log(
            "   Player 2 USDT:   ",
            usdt.balanceOf(player2) / USDT_UNIT
        );
        console.log(
            "   Player 2 $FLASH: ",
            flashToken.balanceOf(player2) / USDT_UNIT
        );
        console.log(
            "   Treasury USDT:   ",
            usdt.balanceOf(deployer) / USDT_UNIT
        );
        console.log(
            "   $FLASH supply:   ",
            flashToken.totalSupply() / USDT_UNIT
        );
        console.log(
            "   USDT in Pool:    ",
            flashVault.totalDeposited() / USDT_UNIT
        );

        console.log(
            "\n======================================================================"
        );
        console.log("DEPLOYED CONTRACTS (verify on Sepolia Etherscan)");
        console.log(
            "======================================================================\n"
        );
        console.log("   MockAToken:  ", address(mockAToken));
        console.log("   MockAavePool:", address(mockPool));
        console.log("   FlashToken:  ", address(flashToken));
        console.log("   FlashVault:  ", address(flashVault));
        console.log("   Real USDT:   ", USDT_ADDR);
        console.log("\n   https://sepolia.etherscan.io");
        console.log(
            "======================================================================"
        );

        console.log("\nFEATURES DEMONSTRATED:");
        console.log("   [1:1 peg]    Deposit USDT -> mint $FLASH 1:1");
        console.log(
            "   [Yield]      MockAavePool credits 5% yield per deposit"
        );
        console.log("   [Redeem]     Burn $FLASH -> withdraw USDT 1:1");
        console.log(
            "   [Harvest]    Yield sent to Treasury, principal untouched"
        );
        console.log("   [Roles]      Only FlashVault can mint/burn $FLASH");
        console.log(
            "======================================================================\n"
        );
    }
}
