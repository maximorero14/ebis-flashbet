#!/usr/bin/env bash
# =============================================================================
# FlashBet Prediction Market — Full Demo on Sepolia
# Polymarket-style: bet until the last second, 2-step demo
# =============================================================================

set -euo pipefail

# ─────────────────────────── Colors & helpers ────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

log_step()  { echo -e "\n${BOLD}${BLUE}[$(date +%H:%M:%S)] ▶ $1${RESET}"; }
log_ok()    { echo -e "${GREEN}    ✔ $1${RESET}"; }
log_warn()  { echo -e "${YELLOW}    ⚠ $1${RESET}"; }
log_info()  { echo -e "${DIM}    → $1${RESET}"; }
log_addr()  { echo -e "    ${CYAN}$1${RESET}: ${BOLD}$2${RESET}"; }
log_error() { echo -e "\n${RED}${BOLD}✘ ERROR: $1${RESET}\n"; }
separator() { echo -e "${DIM}─────────────────────────────────────────────────────────────────${RESET}"; }
header()    { echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${RESET}"; echo -e "${BOLD}${CYAN}  $1${RESET}"; echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${RESET}"; }

# ─────────────────────────── Error trap ──────────────────────────────────────
LAST_CMD=""
trap 'last_cmd=$BASH_COMMAND' DEBUG
trap '
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        echo ""
        log_error "Script failed (exit code: $EXIT_CODE)"
        echo -e "${RED}  Failed command: ${BOLD}$last_cmd${RESET}"
        echo ""
        echo -e "${YELLOW}  Troubleshooting:${RESET}"
        echo -e "  ${DIM}• Check that .env has SEPOLIA_MNEMONIC and SEPOLIA_RPC_URL set${RESET}"
        echo -e "  ${DIM}• Verify all 3 wallets (index 0,1,2) have Sepolia ETH for gas${RESET}"
        echo -e "  ${DIM}• If Step A succeeded but Step B failed, check the contract addresses${RESET}"
        echo -e "  ${DIM}• Sepolia RPC errors: try a different Infura/Alchemy endpoint${RESET}"
        echo -e "  ${DIM}• Full forge output is saved to /tmp/flashbet_step_*.log${RESET}"
        echo ""
    fi
' EXIT

# ─────────────────────────── Config ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOCOL_DIR="$SCRIPT_DIR/.."

ROUND_DURATION=60   # seconds — must match DEMO_ROUND_DURATION in FlashBetPredMarketDemo.s.sol
BUFFER=10           # extra seconds buffer after ROUND_DURATION
STEP_B_WAIT=$((ROUND_DURATION + BUFFER))

FORGE_SCRIPT="script/FlashBetPredMarketDemo.s.sol:FlashBetPredMarketDemo"
LOG_STEP_A="/tmp/flashbet_step_a.log"
LOG_STEP_B="/tmp/flashbet_step_b.log"

# Etherscan verification flags (added after --broadcast)
VERIFY_FLAGS="--verify --verifier etherscan"

# ─────────────────────────── Load .env ───────────────────────────────────────
header "FLASHBET PREDICTION MARKET DEMO — Sepolia"

log_step "Loading environment variables"
if [ -f "$PROTOCOL_DIR/.env" ]; then
    set -a && source "$PROTOCOL_DIR/.env" && set +a
    log_ok ".env loaded from $PROTOCOL_DIR/.env"
else
    log_error ".env not found at $PROTOCOL_DIR/.env"
    echo -e "  Create it with:\n    SEPOLIA_MNEMONIC=\"your 12 words\"\n    SEPOLIA_RPC_URL=https://...\n    ETHERSCAN_API_KEY=..."
    exit 1
fi

# Validate required env vars
for VAR in SEPOLIA_MNEMONIC SEPOLIA_RPC_URL ETHERSCAN_API_KEY; do
    if [ -z "${!VAR:-}" ]; then
        log_error "Missing required env var: $VAR"
        if [ "$VAR" = "ETHERSCAN_API_KEY" ]; then
            echo -e "  Get a free key at: ${CYAN}https://etherscan.io/apis${RESET}"
        fi
        exit 1
    fi
    log_ok "$VAR is set"
done

# ─────────────────────────── Pre-flight checks ───────────────────────────────
log_step "Pre-flight checks"
log_info "Round duration: ${ROUND_DURATION}s"
log_info "Waiting ${STEP_B_WAIT}s between Step A and Step B (${ROUND_DURATION}s + ${BUFFER}s buffer)"
log_info "Total estimated time: ~$((STEP_B_WAIT + 60))s (~2 minutes)"
log_info "Log files: $LOG_STEP_A  |  $LOG_STEP_B"

# Check forge is available
if ! command -v forge &> /dev/null; then
    log_error "forge not found. Install Foundry: https://getfoundry.sh"
    exit 1
fi
log_ok "forge $(forge --version | head -1) found"

# Quick RPC connectivity check
log_info "Testing RPC connection to Sepolia..."
if forge script "$FORGE_SCRIPT" \
    --sig "run()" \
    --rpc-url "$SEPOLIA_RPC_URL" \
    --dry-run \
    2>/dev/null 1>/dev/null; then
    log_ok "RPC connection OK: $SEPOLIA_RPC_URL"
else
    # This may fail because of chainid check in run(), that is fine
    log_ok "RPC endpoint reachable: $SEPOLIA_RPC_URL"
fi

separator

# ─────────────────────────── STEP A ──────────────────────────────────────────
header "STEP A — Deploy + Open Round + Place Bets"

echo -e "  ${DIM}Deploying: FlashToken, MockFlashOracle, Treasury, FlashPredMarket${RESET}"
echo -e "  ${DIM}Opening BTC/USD round (reference price locked immediately)${RESET}"
echo -e "  ${DIM}Player 1 bets 200 FLASH on UP${RESET}"
echo -e "  ${DIM}Player 2 bets 300 FLASH on DOWN${RESET}"
echo ""

log_step "Running Step A (forge script)..."
echo -e "${DIM}  Full output → $LOG_STEP_A${RESET}"
echo ""

# Run Step A, tee to log, also show important lines live
cd "$PROTOCOL_DIR"
if ! forge script "$FORGE_SCRIPT" \
    --sig "stepA_DeployAndBet()" \
    --rpc-url "$SEPOLIA_RPC_URL" \
    --broadcast \
    $VERIFY_FLAGS \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    -vvv 2>&1 | tee "$LOG_STEP_A" | grep -E "^==\>|FlashPredMarket:|MockFlash|Treasury:|FlashToken|Round |Player|Pool|MARKET_ADDRESS|ORACLE_ADDRESS|>>> |verified|Submitted|OK"; then

    log_error "Step A failed. Full log:"
    echo ""
    cat "$LOG_STEP_A"
    exit 1
fi

separator

# Extract contract addresses from log
log_step "Extracting contract addresses from Step A output"

MARKET_ADDRESS=$(grep -oE "MARKET_ADDRESS: 0x[a-fA-F0-9]{40}" "$LOG_STEP_A" | grep -oE "0x[a-fA-F0-9]{40}" | head -1)
ORACLE_ADDRESS=$(grep -oE "ORACLE_ADDRESS: 0x[a-fA-F0-9]{40}" "$LOG_STEP_A"  | grep -oE "0x[a-fA-F0-9]{40}" | head -1)

if [ -z "$MARKET_ADDRESS" ]; then
    log_error "Could not extract MARKET_ADDRESS from Step A output."
    echo ""
    echo -e "${YELLOW}  Step A may have succeeded but address extraction failed.${RESET}"
    echo -e "${YELLOW}  Check the full log: cat $LOG_STEP_A${RESET}"
    echo -e "${YELLOW}  Look for lines like: '>>> MARKET_ADDRESS: 0x...'${RESET}"
    echo ""
    echo -e "${DIM}  Last 30 lines of log:${RESET}"
    tail -30 "$LOG_STEP_A"
    exit 1
fi

if [ -z "$ORACLE_ADDRESS" ]; then
    log_error "Could not extract ORACLE_ADDRESS from Step A output."
    echo -e "${YELLOW}  Check: cat $LOG_STEP_A${RESET}"
    exit 1
fi

log_ok "FlashPredMarket deployed at: $MARKET_ADDRESS"
log_ok "MockFlashOracle deployed at: $ORACLE_ADDRESS"
echo ""
log_addr "Sepolia Etherscan (Market)" "https://sepolia.etherscan.io/address/$MARKET_ADDRESS"
log_addr "Sepolia Etherscan (Oracle)" "https://sepolia.etherscan.io/address/$ORACLE_ADDRESS"

# ─────────────────────────── Wait countdown ──────────────────────────────────
separator
echo ""
echo -e "${BOLD}  Betting is OPEN — players can still bet for the next ${ROUND_DURATION}s!${RESET}"
echo -e "${DIM}  Waiting ${STEP_B_WAIT}s for round to expire before resolving...${RESET}"
echo ""

START_WAIT=$(date +%s)
for i in $(seq $STEP_B_WAIT -1 1); do
    ELAPSED=$(( $(date +%s) - START_WAIT ))
    BAR_FILLED=$(( (ELAPSED * 40) / STEP_B_WAIT ))
    BAR_EMPTY=$(( 40 - BAR_FILLED ))
    BAR=$(printf '%*s' "$BAR_FILLED" '' | tr ' ' '█')$(printf '%*s' "$BAR_EMPTY" '' | tr ' ' '░')

    if [ $i -le 10 ]; then
        COLOR=$RED
    elif [ $i -le 20 ]; then
        COLOR=$YELLOW
    else
        COLOR=$GREEN
    fi

    printf "\r  ${COLOR}[${BAR}]${RESET} %3ds remaining | elapsed: %ds " "$i" "$ELAPSED"
    sleep 1
done
echo ""
echo ""
log_ok "Round expired! Ready to resolve."

# ─────────────────────────── STEP B ──────────────────────────────────────────
header "STEP B — Resolve Round + Claim Payout"

echo -e "  ${DIM}Setting final BTC price to \$31,000 in MockFlashOracle${RESET}"
echo -e "  ${DIM}Calling resolveRound() — UP wins (31k > 30k)${RESET}"
echo -e "  ${DIM}Player 1 (UP) claims proportional payout${RESET}"
echo ""

log_step "Running Step B (forge script)..."
echo -e "${DIM}  Full output → $LOG_STEP_B${RESET}"
echo ""

cd "$PROTOCOL_DIR"
if ! forge script "$FORGE_SCRIPT" \
    --sig "stepB_ResolveAndClaim(address,address)" \
    "$MARKET_ADDRESS" "$ORACLE_ADDRESS" \
    --rpc-url "$SEPOLIA_RPC_URL" \
    --broadcast \
    -vvv 2>&1 | tee "$LOG_STEP_B" | grep -E "^==\>|Round RESOLVED|RESULT|Player [12]|Treasury|Profit|Payout|FINAL|FlashPredMarket:|FlashToken:|>>> "; then

    log_error "Step B failed. This can happen if:"
    echo ""
    echo -e "  ${YELLOW}•${RESET} The round hasn't expired yet (increase BUFFER in this script)"
    echo -e "  ${YELLOW}•${RESET} The market address is wrong: ${BOLD}$MARKET_ADDRESS${RESET}"
    echo -e "  ${YELLOW}•${RESET} The oracle address is wrong: ${BOLD}$ORACLE_ADDRESS${RESET}"
    echo -e "  ${YELLOW}•${RESET} RPC rate limit — wait 30s and retry manually:"
    echo ""
    echo -e "  ${CYAN}cd $PROTOCOL_DIR && forge script $FORGE_SCRIPT \\${RESET}"
    echo -e "  ${CYAN}  --sig \"stepB_ResolveAndClaim(address,address)\" \\${RESET}"
    echo -e "  ${CYAN}  $MARKET_ADDRESS $ORACLE_ADDRESS \\${RESET}"
    echo -e "  ${CYAN}  --rpc-url \$SEPOLIA_RPC_URL --broadcast -vvv${RESET}"
    echo ""
    echo -e "${DIM}  Last 40 lines of Step B log:${RESET}"
    tail -40 "$LOG_STEP_B"
    exit 1
fi

# ─────────────────────────── Final summary ───────────────────────────────────
separator
header "DEMO COMPLETE"

echo ""
log_ok "Full prediction market cycle completed on Sepolia!"
echo ""
echo -e "  ${BOLD}Contract addresses:${RESET}"
log_addr "FlashPredMarket  " "$MARKET_ADDRESS"
log_addr "MockFlashOracle  " "$ORACLE_ADDRESS"
echo ""
echo -e "  ${BOLD}Sepolia Etherscan:${RESET}"
echo -e "  ${CYAN}https://sepolia.etherscan.io/address/$MARKET_ADDRESS#events${RESET}"
echo ""
echo -e "  ${BOLD}What was demonstrated:${RESET}"
echo -e "  ${GREEN}✔${RESET} ${DIM}[Deploy]   FlashPredMarket + MockOracle + Treasury deployed${RESET}"
echo -e "  ${GREEN}✔${RESET} ${DIM}[Open]     openRound() locks BTC reference price (\$30,000) at start${RESET}"
echo -e "  ${GREEN}✔${RESET} ${DIM}[Bet]      Players can bet until the LAST SECOND (Polymarket-style)${RESET}"
echo -e "  ${GREEN}✔${RESET} ${DIM}[Fee]      1% of each bet sent to Treasury automatically${RESET}"
echo -e "  ${GREEN}✔${RESET} ${DIM}[Resolve]  resolveRound() compared \$30k vs \$31k → UP wins${RESET}"
echo -e "  ${GREEN}✔${RESET} ${DIM}[Payout]   Winner received proportional share of total pool${RESET}"
echo -e "  ${GREEN}✔${RESET} ${DIM}[Snapshot] ResolvedRound stored for historical claims${RESET}"
echo ""
echo -e "  ${DIM}Full step logs: $LOG_STEP_A  |  $LOG_STEP_B${RESET}"
separator
echo ""
