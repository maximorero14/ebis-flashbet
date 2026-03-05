// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {FlashToken} from "../src/FlashToken.sol";
import {FlashPredMarket} from "../src/FlashPredMarket.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockFlashOracle} from "../src/mocks/MockFlashOracle.sol";

// =============================================================================

/**
 * @title FlashBetPredMarketDemo
 * @dev End-to-end demo of the FlashBet prediction market on Sepolia.
 *
 * POLYMARKET-STYLE DESIGN:
 *   - Reference price locked at openRound() (start of round).
 *   - Bets accepted until the very last second of the round.
 *   - No closeRound() — just open -> resolve (2 phases instead of 3).
 *
 * WHY MOCK ORACLE (not real Chainlink)?
 *   Chainlink BTC/USD on Sepolia only updates every ~1 hour or when price
 *   moves >0.5%. MockFlashOracle lets the script control prices so the demo
 *   works reliably in Sepolia blocks without waiting an hour.
 *
 * ROUND STORY:
 *   BTC price at openRound():    $30,000 (reference, locked immediately)
 *   BTC price at resolveRound(): $31,000 (final — UP wins)
 *   Player 1 bets 200 FLASH on UP  -> winner, claims proportional payout
 *   Player 2 bets 300 FLASH on DOWN -> loses
 *
 * USAGE ON SEPOLIA (2 steps):
 *
 *   set -a && source .env && set +a
 *
 *   # Step A: deploy + open round + players bet
 *   forge script script/FlashBetPredMarketDemo.s.sol:FlashBetPredMarketDemo \
 *     --sig "stepA_DeployAndBet()" \
 *     --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv
 *   # Note MARKET_ADDRESS and ORACLE_ADDRESS from output.
 *
 *   # Wait ROUND_DURATION seconds (default demo: 60s)...
 *
 *   # Step B: resolve + winner claims
 *   forge script script/FlashBetPredMarketDemo.s.sol:FlashBetPredMarketDemo \
 *     --sig "stepB_ResolveAndClaim(address,address)" <MARKET> <ORACLE> \
 *     --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv
 *
 * OR use the shell wrapper (does both steps with auto-sleep):
 *   ./script/demo_pred_market.sh
 *
 * USAGE ON LOCAL ANVIL (single shot):
 *   forge script script/FlashBetPredMarketDemo.s.sol:FlashBetPredMarketDemo \
 *     --sig "run()" \
 *     --rpc-url http://localhost:8545 --broadcast -vvv
 */
contract FlashBetPredMarketDemo is Script {
    uint256 constant FLASH_UNIT = 1e6;

    // Demo: 60s round so the whole demo finishes in ~1 minute on Sepolia
    uint256 constant DEMO_ROUND_DURATION = 60;

    // Prices set by the script (mock oracle, no real Chainlink needed)
    int256 constant BTC_REF_PRICE = 30_000e8; // $30,000 at open (reference)
    int256 constant BTC_FINAL_PRICE = 31_000e8; // $31,000 at resolve (UP wins)

    uint256 constant BET_PLAYER1 = 200 * 1e6; // 200 FLASH on UP
    uint256 constant BET_PLAYER2 = 300 * 1e6; // 300 FLASH on DOWN

    address deployer;
    address player1;
    address player2;
    uint256 deployerPk;
    uint256 player1Pk;
    uint256 player2Pk;

    function _loadAccounts() internal {
        string memory mnemonic = vm.envString("SEPOLIA_MNEMONIC");
        string memory path = "m/44'/60'/0'/0/";
        deployerPk = vm.deriveKey(mnemonic, path, 0);
        player1Pk = vm.deriveKey(mnemonic, path, 1);
        player2Pk = vm.deriveKey(mnemonic, path, 2);
        deployer = vm.addr(deployerPk);
        player1 = vm.addr(player1Pk);
        player2 = vm.addr(player2Pk);
    }

    // =========================================================================
    // STEP A: Deploy + open round + both players bet
    // =========================================================================
    function stepA_DeployAndBet() external {
        _loadAccounts();
        _header("STEP A: DEPLOY + OPEN ROUND + PLACE BETS");

        console.log("Participants:");
        console.log("  Deployer / Treasury:", deployer);
        console.log("  Player 1 (UP  side):", player1);
        console.log("  Player 2 (DOWN side):", player2);

        vm.startBroadcast(deployerPk);

        FlashToken flash = new FlashToken();
        console.log("\nFlashToken ($FLASH):     ", address(flash));

        // MockFlashOracle: initial price = $30,000 (locked at openRound)
        MockFlashOracle oracle = new MockFlashOracle();
        oracle.setPrice("BTC", BTC_REF_PRICE);
        console.log("MockFlashOracle:          ", address(oracle));
        console.log("  BTC reference price: $30,000 (locked at round open)");

        Treasury treasury = new Treasury(deployer);
        console.log("Treasury:                 ", address(treasury));

        // 5 args: flash, oracle, treasury, owner, roundDuration
        FlashPredMarket market = new FlashPredMarket(
            address(flash),
            address(oracle),
            address(treasury),
            deployer,
            DEMO_ROUND_DURATION // 60 seconds for demo
        );
        console.log("FlashPredMarket:          ", address(market));
        console.log("  Round duration:", market.ROUND_DURATION(), "seconds");
        console.log(
            "  Bets accepted: from open until the LAST SECOND (Polymarket-style)"
        );

        flash.grantRole(flash.MINTER_ROLE(), deployer);
        flash.mint(player1, 500 * FLASH_UNIT);
        flash.mint(player2, 500 * FLASH_UNIT);

        // openRound locks reference price IMMEDIATELY from oracle
        market.openRound(market.MARKET_BTC());
        uint256 roundId = market.roundCount(market.MARKET_BTC());
        console.log(
            "\nRound",
            roundId,
            "opened. BTC reference price LOCKED at $30,000."
        );
        console.log(
            "Betting window: NOW until",
            market.ROUND_DURATION(),
            "seconds from now."
        );

        vm.stopBroadcast();

        // Player 1 bets UP
        vm.startBroadcast(player1Pk);
        flash.approve(address(market), BET_PLAYER1);
        market.placeBet(
            market.MARKET_BTC(),
            FlashPredMarket.Direction.UP,
            BET_PLAYER1
        );
        vm.stopBroadcast();

        uint256 fee1 = (BET_PLAYER1 * market.FEE_BPS()) / 10_000;
        console.log("\nPlayer 1 bet", BET_PLAYER1 / FLASH_UNIT, "FLASH on UP");
        console.log("  Fee (1%):", fee1 / FLASH_UNIT, "FLASH -> Treasury");
        console.log("  Net pool:", (BET_PLAYER1 - fee1) / FLASH_UNIT, "FLASH");

        // Player 2 bets DOWN
        vm.startBroadcast(player2Pk);
        flash.approve(address(market), BET_PLAYER2);
        market.placeBet(
            market.MARKET_BTC(),
            FlashPredMarket.Direction.DOWN,
            BET_PLAYER2
        );
        vm.stopBroadcast();

        uint256 fee2 = (BET_PLAYER2 * market.FEE_BPS()) / 10_000;
        console.log(
            "\nPlayer 2 bet",
            BET_PLAYER2 / FLASH_UNIT,
            "FLASH on DOWN"
        );
        console.log("  Fee (1%):", fee2 / FLASH_UNIT, "FLASH -> Treasury");
        console.log("  Net pool:", (BET_PLAYER2 - fee2) / FLASH_UNIT, "FLASH");

        FlashPredMarket.Round memory r = market.getRound(market.MARKET_BTC());
        console.log("\nPool state:");
        console.log("  UP:    ", r.totalUp / FLASH_UNIT, "FLASH");
        console.log("  DOWN:  ", r.totalDown / FLASH_UNIT, "FLASH");
        console.log(
            "  Total: ",
            (r.totalUp + r.totalDown) / FLASH_UNIT,
            "FLASH"
        );
        console.log(
            "  Treasury fees:",
            flash.balanceOf(address(treasury)) / FLASH_UNIT,
            "FLASH"
        );

        console.log("\n>>> STEP A DONE.");
        console.log(
            ">>> Bets still open for",
            market.ROUND_DURATION(),
            "seconds from openRound tx."
        );
        console.log(">>> MARKET_ADDRESS:", address(market));
        console.log(">>> ORACLE_ADDRESS:", address(oracle));
    }

    // =========================================================================
    // STEP B: Resolve round + winner claims payout
    // (callable after ROUND_DURATION seconds from openRound)
    // =========================================================================
    function stepB_ResolveAndClaim(
        address marketAddr,
        address oracleAddr
    ) external {
        _loadAccounts();
        _header("STEP B: RESOLVE ROUND + CLAIM PAYOUT");

        FlashPredMarket market = FlashPredMarket(marketAddr);
        MockFlashOracle oracle = MockFlashOracle(oracleAddr);
        FlashToken flash = FlashToken(address(market.flashToken()));

        // Update oracle to final price before resolving
        vm.startBroadcast(deployerPk);
        oracle.setPrice("BTC", BTC_FINAL_PRICE); // $31,000 -> UP wins
        market.resolveRound(market.MARKET_BTC());
        vm.stopBroadcast();

        FlashPredMarket.Round memory r = market.getRound(market.MARKET_BTC());
        console.log("Round RESOLVED!");
        console.log("  Reference price (at open):    $30,000");
        console.log("  Final price (at resolution):  $31,000 (+3.33%)");
        if (r.upWon) {
            console.log("  RESULT: UP wins! BTC rose above reference price.");
        } else {
            console.log("  RESULT: DOWN wins! BTC fell below reference price.");
        }

        uint256 roundId = market.roundCount(market.MARKET_BTC());
        FlashPredMarket.ResolvedRound memory rr = market.getResolvedRound(
            market.MARKET_BTC(),
            roundId
        );
        uint256 totalPool = rr.totalUp + rr.totalDown;

        if (rr.upWon) {
            FlashPredMarket.Bet memory winBet = market.getBet(
                market.MARKET_BTC(),
                roundId,
                player1
            );
            uint256 p1Before = flash.balanceOf(player1);
            vm.startBroadcast(player1Pk);
            market.claimPayout(market.MARKET_BTC(), roundId);
            vm.stopBroadcast();
            uint256 payout = flash.balanceOf(player1) - p1Before;

            console.log("\nPlayer 1 (UP) claims payout:");
            console.log("  Gross bet:      200 FLASH");
            console.log(
                "  Net contributed:",
                winBet.amount / FLASH_UNIT,
                "FLASH (after 1% fee)"
            );
            console.log("  Payout received:", payout / FLASH_UNIT, "FLASH");
            console.log(
                "  Profit:         ",
                payout > winBet.amount
                    ? (payout - winBet.amount) / FLASH_UNIT
                    : 0,
                "FLASH"
            );
            console.log(
                "\nPlayer 2 (DOWN) lost",
                rr.totalDown / FLASH_UNIT,
                "FLASH. Goes to Player 1."
            );
        } else {
            FlashPredMarket.Bet memory winBet = market.getBet(
                market.MARKET_BTC(),
                roundId,
                player2
            );
            uint256 p2Before = flash.balanceOf(player2);
            vm.startBroadcast(player2Pk);
            market.claimPayout(market.MARKET_BTC(), roundId);
            vm.stopBroadcast();
            uint256 payout = flash.balanceOf(player2) - p2Before;
            console.log(
                "\nPlayer 2 (DOWN) claims payout:",
                payout / FLASH_UNIT,
                "FLASH"
            );
            console.log("Player 1 (UP) lost.");
        }

        _header("FINAL STATE");
        console.log("Player 1 $FLASH:", flash.balanceOf(player1) / FLASH_UNIT);
        console.log("Player 2 $FLASH:", flash.balanceOf(player2) / FLASH_UNIT);
        console.log(
            "Treasury $FLASH:",
            flash.balanceOf(address(market.treasury())) / FLASH_UNIT,
            "(fees)"
        );
        console.log(
            "Market   $FLASH:",
            flash.balanceOf(marketAddr) / FLASH_UNIT,
            "(should be 0)"
        );
        console.log("\nContracts on Sepolia:");
        console.log("  FlashPredMarket:", marketAddr);
        console.log("  MockFlashOracle:", oracleAddr);
        console.log("  FlashToken:     ", address(flash));
        console.log("  Treasury:       ", address(market.treasury()));
        console.log("\nhttps://sepolia.etherscan.io");
        console.log("\nFEATURES DEMONSTRATED:");
        console.log(
            "  [Open]    openRound() locks reference price immediately"
        );
        console.log(
            "  [Bet]     Bets accepted until the LAST SECOND (Polymarket-style)"
        );
        console.log("  [Fee]     1% of each bet -> Treasury automatically");
        console.log(
            "  [Resolve] resolveRound() reads final price, picks winner"
        );
        console.log("  [Payout]  Winner gets proportional share of total pool");
        console.log(
            "  [Snap]    ResolvedRound snapshot survives for historical claims"
        );
    }

    // =========================================================================
    // run() — LOCAL ANVIL ONLY (uses vm.warp, single shot)
    // =========================================================================
    function run() external {
        _loadAccounts();

        require(
            block.chainid == 31337,
            "run() is Anvil only. Use stepA/stepB on Sepolia."
        );

        _header("FLASHBET PREDICTION MARKET - Anvil Local Demo");

        vm.startBroadcast(deployerPk);
        FlashToken flash = new FlashToken();
        MockFlashOracle oracle = new MockFlashOracle();
        Treasury treasury = new Treasury(deployer);
        FlashPredMarket market = new FlashPredMarket(
            address(flash),
            address(oracle),
            address(treasury),
            deployer,
            DEMO_ROUND_DURATION
        );
        oracle.setPrice("BTC", BTC_REF_PRICE);
        flash.grantRole(flash.MINTER_ROLE(), deployer);
        flash.mint(player1, 500 * FLASH_UNIT);
        flash.mint(player2, 500 * FLASH_UNIT);
        market.openRound(market.MARKET_BTC());
        vm.stopBroadcast();

        console.log("Round opened. Reference price: $30,000");

        vm.startBroadcast(player1Pk);
        flash.approve(address(market), BET_PLAYER1);
        market.placeBet(
            market.MARKET_BTC(),
            FlashPredMarket.Direction.UP,
            BET_PLAYER1
        );
        vm.stopBroadcast();

        vm.startBroadcast(player2Pk);
        flash.approve(address(market), BET_PLAYER2);
        market.placeBet(
            market.MARKET_BTC(),
            FlashPredMarket.Direction.DOWN,
            BET_PLAYER2
        );
        vm.stopBroadcast();

        console.log("Bets placed. Warping to round end...");
        vm.warp(block.timestamp + DEMO_ROUND_DURATION);

        vm.startBroadcast(deployerPk);
        oracle.setPrice("BTC", BTC_FINAL_PRICE); // $31,000
        market.resolveRound(market.MARKET_BTC());
        vm.stopBroadcast();

        console.log(
            "Round resolved. UP won:",
            market.getRound(market.MARKET_BTC()).upWon
        );

        uint256 roundId = market.roundCount(market.MARKET_BTC());
        uint256 p1Before = flash.balanceOf(player1);
        vm.startBroadcast(player1Pk);
        market.claimPayout(market.MARKET_BTC(), roundId);
        vm.stopBroadcast();

        console.log("\n=== FINAL BALANCES ===");
        console.log(
            "Player 1:",
            (flash.balanceOf(player1) - p1Before) / FLASH_UNIT,
            "FLASH payout"
        );
        console.log(
            "Player 2:",
            flash.balanceOf(player2) / FLASH_UNIT,
            "FLASH remaining (lost)"
        );
        console.log(
            "Treasury:",
            flash.balanceOf(address(treasury)) / FLASH_UNIT,
            "FLASH fees"
        );
        console.log(
            "Market:  ",
            flash.balanceOf(address(market)) / FLASH_UNIT,
            "FLASH (must be 0)"
        );
    }

    function _header(string memory title) internal pure {
        console.log(
            "\n================================================================="
        );
        console.log(title);
        console.log(
            "=================================================================\n"
        );
    }
}
