// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";

import {FlashToken} from "../src/FlashToken.sol";
import {FlashVault} from "../src/FlashVault.sol";
import {FlashPredMarket} from "../src/FlashPredMarket.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockAToken} from "../src/mocks/MockAToken.sol";
import {MockAavePool} from "../src/mocks/MockAavePool.sol";
import {MockFlashOracle} from "../src/mocks/MockFlashOracle.sol";

// =============================================================================

/**
 * @title Deploy
 * @dev Deploys the complete FlashBet protocol on Sepolia in a single broadcast.
 *
 * CONTRACTS DEPLOYED (in order):
 *  1. MockAToken          - aUSDT substitute (Sepolia, no Aave supply cap)
 *  2. MockAavePool        - Aave V3 Pool substitute with 5% instant yield
 *  3. MockFlashOracle     - Chainlink BTC/USD + ETH/USD feed substitute
 *  4. Treasury            - Receives protocol fees and harvested yield
 *  5. FlashToken ($FLASH) - ERC20 protocol token (6 decimals)
 *  6. FlashVault          - Deposit USDT -> mint $FLASH, backed by MockAavePool
 *  7. FlashPredMarket     - Prediction market (BTC/USD + ETH/USD, UP/DOWN bets)
 *
 * POST-DEPLOY SETUP (done inside this script):
 *  - MINTER_ROLE + BURNER_ROLE granted to FlashVault on FlashToken
 *  - MINTER_ROLE for prediction market? No - FlashPredMarket uses its own $FLASH.
 *  - MockFlashOracle prices set to placeholders + simulation enabled
 *    (run protocol/keeper/update-prices.sh to sync with Binance)
 *  - MockAavePool yield reserve seeded: 20 USDT for demo deposits
 *
 * USAGE:
 *   set -a && source .env && set +a
 *
 *   forge script script/Deploy.s.sol \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY \
 *     -vvv
 *
 * OUTPUT:
 *   All contract addresses are logged. Copy them into the DApp .env.local file.
 *
 * PREREQUISITES:
 *   Wallet at mnemonic index 0 (deployer) needs:
 *   - Sepolia ETH for gas (~0.05 ETH)
 *   - 20 USDT (Sepolia) for yield reserve seed
 *     Get Sepolia USDT at: https://sepolia.etherscan.io/address/0x7169d38820dfd117c3fa1f22a697dba58d90ba06
 */
contract Deploy is Script {
    // -- Real Sepolia USDT -----------------------------------------------------
    address constant USDT = 0x7169D38820dfd117C3FA1f22a697dBA58d90BA06;

    // ─── PRECIOS INICIALES DEL ORACLE ─────────────────────────────────────
    // ÚNICO LUGAR donde cambiar los precios antes de un redeploy.
    // Formato: precio_en_usd * 1e8  (ej: $66,000 → 66_000e8)
    int256 constant BTC_PRICE = 66_000e8; // BTC/USD
    int256 constant ETH_PRICE = 2_500e8;  // ETH/USD
    // ──────────────────────────────────────────────────────────────────────

    // -- Yield reserve to seed into MockAavePool -------------------------------
    uint256 constant YIELD_SEED = 20 * 1e6; // 20 USDT (covers ~5% on 400 USDT deposits)

    // -- FlashPredMarket timing (0 = use defaults: 300s round) ----------------
    uint256 constant ROUND_DURATION = 0; // 0 -> defaults to 300s in production

    function run() external {
        string memory mnemonic = vm.envString("SEPOLIA_MNEMONIC");
        uint256 deployerPk = vm.deriveKey(mnemonic, "m/44'/60'/0'/0/", 0);
        address deployer = vm.addr(deployerPk);

        _header("FlashBet Full Protocol Deployment - Sepolia");
        console.log("  Deployer:", deployer);
        console.log("  Network: Sepolia (chainId 11155111)");
        console.log("  USDT:   ", USDT);
        console.log("");

        // -- Step 1: Predict MockAavePool address for MockAToken constructor --
        // MockAToken needs to know the pool address at deploy time (onlyPool guard).
        uint64 nonce = vm.getNonce(deployer);
        address predictedPool = vm.computeCreateAddress(deployer, nonce + 1);

        // -- Deploy all contracts ----------------------------------------------
        vm.startBroadcast(deployerPk);

        // 1. Mock Aave infrastructure
        MockAToken mockAToken = new MockAToken(USDT, predictedPool);
        MockAavePool mockPool = new MockAavePool(USDT, address(mockAToken));
        require(
            address(mockPool) == predictedPool,
            "Pool address prediction failed"
        );

        // 2. MockFlashOracle (replaces Chainlink on Sepolia)
        // Simulation enabled: getPrice() returns BTC_PRICE/ETH_PRICE ± ruido de bloque
        // (±1.5%), cambiando cada ~30s. Así openRound() y resolveRound() siempre
        // ven precios distintos sin necesitar ningún keeper externo.
        MockFlashOracle oracle = new MockFlashOracle();
        oracle.setPrice("BTC", BTC_PRICE);
        oracle.setPrice("ETH", ETH_PRICE);
        oracle.enableSimulation();

        // 3. Treasury
        Treasury treasury = new Treasury(deployer);

        // 4. FlashToken
        FlashToken flash = new FlashToken();

        // 5. FlashVault (USDT -> $FLASH, backed by MockAavePool)
        FlashVault vault = new FlashVault(
            address(flash),
            USDT,
            address(mockPool),
            address(mockAToken),
            address(treasury)
        );

        // 6. FlashPredMarket (BTC/USD + ETH/USD, $FLASH bets)
        FlashPredMarket market = new FlashPredMarket(
            address(flash),
            address(oracle),
            address(treasury),
            deployer,
            ROUND_DURATION // 0 -> 300s default
        );

        // -- Post-deploy setup -------------------------------------------------

        // Grant FlashVault the right to mint/burn $FLASH
        flash.grantRole(flash.MINTER_ROLE(), address(vault));
        flash.grantRole(flash.BURNER_ROLE(), address(vault));

        // Grant FlashPredMarket the right to mint $FLASH for demo (if needed)
        // Note: FlashPredMarket does NOT mint $FLASH - it only transfers $FLASH
        // that bettors send. So no MINTER_ROLE is needed here.

        // Seed MockAavePool yield reserve so harvestYield() works from day 1
        // Requires deployer to have approved USDT first (done inside broadcast)
        {
            // We need to approve the pool to pull USDT from the deployer
            // Use low-level call since USDT's approve is non-standard
            (bool ok, ) = USDT.call(
                abi.encodeWithSignature(
                    "approve(address,uint256)",
                    address(mockPool),
                    YIELD_SEED
                )
            );
            require(ok, "USDT approve failed");
            mockPool.seedYieldReserve(YIELD_SEED);
        }

        vm.stopBroadcast();

        // -- Print deployment summary ------------------------------------------
        _header("DEPLOYMENT COMPLETE");

        console.log("  Core Protocol:");
        console.log("    FlashToken ($FLASH):", address(flash));
        console.log("    FlashVault:         ", address(vault));
        console.log("    FlashPredMarket:    ", address(market));
        console.log("    Treasury:           ", address(treasury));
        console.log("");
        console.log("  Sepolia Mocks:");
        console.log("    MockFlashOracle:    ", address(oracle));
        console.log("    MockAavePool:       ", address(mockPool));
        console.log("    MockAToken (aUSDT): ", address(mockAToken));
        console.log("    Real USDT:          ", USDT);
        console.log("");
        console.log("  Configuration:");
        console.log("    BTC base price: $66,000 (modifica BTC_PRICE en Deploy.s.sol para cambiar)");
        console.log("    ETH base price: $2,500  (modifica ETH_PRICE en Deploy.s.sol para cambiar)");
        console.log("    Oracle simulation: ENABLED (precios fluctuan +-1.5% cada ~30s)");
        console.log("    FLASH decimals: 6");
        console.log("    USDT decimals:  6");
        console.log("    Round duration:", market.ROUND_DURATION(), "seconds");
        console.log("    Fee BPS:       ", market.FEE_BPS(), "(1%)");
        console.log("    Yield seed:    ", YIELD_SEED / 1e6, "USDT in pool");
        console.log("");
        console.log("  Roles:");
        console.log("    FlashVault has MINTER_ROLE on FlashToken: true");
        console.log("    FlashVault has BURNER_ROLE on FlashToken: true");
        console.log("");
        console.log("  Etherscan:");
        console.log(
            "    https://sepolia.etherscan.io/address/",
            address(flash)
        );
        console.log(
            "    https://sepolia.etherscan.io/address/",
            address(vault)
        );
        console.log(
            "    https://sepolia.etherscan.io/address/",
            address(market)
        );
        console.log(
            "    https://sepolia.etherscan.io/address/",
            address(treasury)
        );
        console.log("");
        _header("COPY THESE TO YOUR DAPP .env.local");
        console.log("  VITE_FLASHTOKEN_ADDRESS=", address(flash));
        console.log("  VITE_FLASHVAULT_ADDRESS=", address(vault));
        console.log("  VITE_FLASHPREDMARKET_ADDRESS=", address(market));
        console.log("  VITE_TREASURY_ADDRESS=", address(treasury));
        console.log("  VITE_MOCKORACLE_ADDRESS=", address(oracle));
        console.log("");
    }

    function _header(string memory title) internal pure {
        console.log(
            "\n================================================================="
        );
        console.log(title);
        console.log(
            "================================================================="
        );
    }
}
