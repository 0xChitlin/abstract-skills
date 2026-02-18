#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# TokenLauncher — launch-token.sh
# Deploys a new ERC-20 token via ClawTokenLauncher on Abstract Mainnet.
#
# Usage:
#   ./launch-token.sh --name "My Token" --symbol "MTK" --supply 1000000000 --liquidity 0.05
#   ./launch-token.sh --config ~/.config/tokenlauncher/config.json
#
# Required env:
#   ABSTRACT_PRIVATE_KEY   — agent wallet private key (0x prefixed)
#   ABSTRACT_RPC_URL       — (optional) defaults to https://api.mainnet.abs.xyz
#
# Output:
#   Prints token address, tx link, LP address.
#   Appends entry to ~/.config/tokenlauncher/launch-history.json
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
CONTRACT_ADDRESS="0x89B974b6977157f1E7D743D70e28fCA1B5Ca84b5"
CHAIN_ID="2741"
DEFAULT_RPC="https://api.mainnet.abs.xyz"
HISTORY_FILE="${TOKENLAUNCHER_HISTORY:-$HOME/.config/tokenlauncher/launch-history.json}"
CONFIG_DIR="$(dirname "$HISTORY_FILE")"

# ClawTokenLauncher ABI — launchToken(string,string,uint256,uint256)
FUNCTION_SIG="launchToken(string,string,uint256,uint256)"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()    { echo -e "${CYAN}[tokenlauncher]${RESET} $*"; }
ok()     { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()   { echo -e "${YELLOW}[!]${RESET} $*"; }
die()    { echo -e "${RED}[✗] ERROR:${RESET} $*" >&2; exit 1; }

# ── Defaults ─────────────────────────────────────────────────────────────────
TOKEN_NAME=""
TOKEN_SYMBOL=""
TOTAL_SUPPLY=""
LIQUIDITY_ETH=""
CONFIG_FILE="${TOKENLAUNCHER_CONFIG:-$HOME/.config/tokenlauncher/config.json}"

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)       TOKEN_NAME="$2";     shift 2 ;;
    --symbol)     TOKEN_SYMBOL="$2";   shift 2 ;;
    --supply)     TOTAL_SUPPLY="$2";   shift 2 ;;
    --liquidity)  LIQUIDITY_ETH="$2";  shift 2 ;;
    --config)     CONFIG_FILE="$2";    shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ── Load from config if args missing ──────────────────────────────────────────
if [[ -z "$TOKEN_NAME" || -z "$TOKEN_SYMBOL" || -z "$TOTAL_SUPPLY" || -z "$LIQUIDITY_ETH" ]]; then
  if [[ -f "$CONFIG_FILE" ]]; then
    log "Loading config from $CONFIG_FILE"
    TOKEN_NAME="${TOKEN_NAME:-$(jq -r '.tokenName'    "$CONFIG_FILE")}"
    TOKEN_SYMBOL="${TOKEN_SYMBOL:-$(jq -r '.tokenSymbol'  "$CONFIG_FILE")}"
    TOTAL_SUPPLY="${TOTAL_SUPPLY:-$(jq -r '.totalSupply'  "$CONFIG_FILE")}"
    LIQUIDITY_ETH="${LIQUIDITY_ETH:-$(jq -r '.liquidityETH' "$CONFIG_FILE")}"
  fi
fi

# ── Validation ────────────────────────────────────────────────────────────────
[[ -z "$TOKEN_NAME"    ]] && die "Token name required (--name or config.tokenName)"
[[ -z "$TOKEN_SYMBOL"  ]] && die "Token symbol required (--symbol or config.tokenSymbol)"
[[ -z "$TOTAL_SUPPLY"  ]] && die "Total supply required (--supply or config.totalSupply)"
[[ -z "$LIQUIDITY_ETH" ]] && die "Liquidity ETH required (--liquidity or config.liquidityETH)"
[[ -z "${ABSTRACT_PRIVATE_KEY:-}" ]] && die "ABSTRACT_PRIVATE_KEY env var not set"

command -v cast  >/dev/null 2>&1 || die "Foundry 'cast' not found. Run: curl -L https://foundry.paradigm.xyz | bash && foundryup"
command -v jq    >/dev/null 2>&1 || die "'jq' not found. Install: brew install jq"
command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || die "python3 not found"

RPC_URL="${ABSTRACT_RPC_URL:-$DEFAULT_RPC}"

# ── Convert supply to wei (multiply by 10^18) ─────────────────────────────────
# totalSupply is in whole tokens; the contract expects wei (18 decimals)
SUPPLY_WEI=$(python3 -c "print(int(${TOTAL_SUPPLY} * 10**18))" 2>/dev/null || \
             python  -c "print(int(${TOTAL_SUPPLY} * 10**18))")

# Convert liquidityETH to wei for the --value flag
LIQUIDITY_WEI=$(python3 -c "print(int(${LIQUIDITY_ETH} * 10**18))" 2>/dev/null || \
                python  -c "print(int(${LIQUIDITY_ETH} * 10**18))")

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  🚀 TokenLauncher — Abstract Chain (ID: $CHAIN_ID)${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
log "Token name:    $TOKEN_NAME"
log "Symbol:        $TOKEN_SYMBOL"
log "Total supply:  $TOTAL_SUPPLY tokens ($SUPPLY_WEI wei)"
log "Liquidity:     $LIQUIDITY_ETH ETH ($LIQUIDITY_WEI wei)"
log "Contract:      $CONTRACT_ADDRESS"
log "RPC:           $RPC_URL"
echo ""

# ── Send transaction via cast ─────────────────────────────────────────────────
log "Submitting transaction to ClawTokenLauncher..."

TX_OUTPUT=$(cast send \
  "$CONTRACT_ADDRESS" \
  "$FUNCTION_SIG" \
  "$TOKEN_NAME" \
  "$TOKEN_SYMBOL" \
  "$SUPPLY_WEI" \
  "$LIQUIDITY_WEI" \
  --private-key "$ABSTRACT_PRIVATE_KEY" \
  --rpc-url "$RPC_URL" \
  --chain "$CHAIN_ID" \
  --value "${LIQUIDITY_WEI}" \
  --json 2>&1) || die "Transaction failed:\n$TX_OUTPUT"

TX_HASH=$(echo "$TX_OUTPUT" | jq -r '.transactionHash // .hash // empty' 2>/dev/null)
[[ -z "$TX_HASH" ]] && die "Could not parse tx hash from cast output:\n$TX_OUTPUT"

ok "Transaction submitted: $TX_HASH"
log "Waiting for confirmation..."

# ── Get receipt ───────────────────────────────────────────────────────────────
RECEIPT=$(cast receipt "$TX_HASH" --rpc-url "$RPC_URL" --json 2>/dev/null) || \
  die "Could not fetch receipt for $TX_HASH"

STATUS=$(echo "$RECEIPT" | jq -r '.status // empty')
[[ "$STATUS" != "1" && "$STATUS" != "0x1" ]] && die "Transaction reverted (status: $STATUS). Check Abscan: https://abscan.org/tx/$TX_HASH"

ok "Transaction confirmed!"

# ── Parse token and LP addresses from logs ────────────────────────────────────
# The contract emits a TokenLaunched event with (tokenAddress, lpAddress, ...)
# Logs[0].topics[1] = tokenAddress (padded), Logs[0].topics[2] = lpAddress (padded)
# Extract from the first log entry
LOGS=$(echo "$RECEIPT" | jq -r '.logs // []')
LOG_COUNT=$(echo "$LOGS" | jq 'length')

TOKEN_ADDRESS=""
LP_ADDRESS=""

if [[ "$LOG_COUNT" -gt 0 ]]; then
  # Try to extract addresses from log topics (padded 32-byte addresses)
  RAW_TOKEN=$(echo "$LOGS" | jq -r '.[0].topics[1] // empty' 2>/dev/null)
  RAW_LP=$(echo    "$LOGS" | jq -r '.[0].topics[2] // empty' 2>/dev/null)

  # Strip leading zeros padding (32 bytes → 20 byte address)
  if [[ -n "$RAW_TOKEN" && ${#RAW_TOKEN} -ge 42 ]]; then
    TOKEN_ADDRESS="0x$(echo "$RAW_TOKEN" | sed 's/0x//' | tail -c 41)"
  fi
  if [[ -n "$RAW_LP" && ${#RAW_LP} -ge 42 ]]; then
    LP_ADDRESS="0x$(echo "$RAW_LP" | sed 's/0x//' | tail -c 41)"
  fi

  # Fallback: try contractAddress from receipt (for CREATE-style deployments)
  if [[ -z "$TOKEN_ADDRESS" ]]; then
    TOKEN_ADDRESS=$(echo "$RECEIPT" | jq -r '.contractAddress // empty' 2>/dev/null || true)
  fi
fi

# If still empty, note it (abscan will show the full details)
[[ -z "$TOKEN_ADDRESS" ]] && TOKEN_ADDRESS="(parse from tx: https://abscan.org/tx/$TX_HASH)"
[[ -z "$LP_ADDRESS"    ]] && LP_ADDRESS="(parse from tx: https://abscan.org/tx/$TX_HASH)"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Save to history ───────────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR"
HISTORY_ENTRY=$(jq -n \
  --arg name   "$TOKEN_NAME" \
  --arg symbol "$TOKEN_SYMBOL" \
  --arg supply "$TOTAL_SUPPLY" \
  --arg liqEth "$LIQUIDITY_ETH" \
  --arg addr   "$TOKEN_ADDRESS" \
  --arg tx     "$TX_HASH" \
  --arg lp     "$LP_ADDRESS" \
  --arg ts     "$TIMESTAMP" \
  '{
    tokenName:    $name,
    tokenSymbol:  $symbol,
    totalSupply:  $supply,
    liquidityETH: $liqEth,
    tokenAddress: $addr,
    txHash:       $tx,
    lpAddress:    $lp,
    timestamp:    $ts
  }')

# Append to history array (create if not exists)
if [[ -f "$HISTORY_FILE" ]]; then
  UPDATED=$(jq --argjson entry "$HISTORY_ENTRY" '. += [$entry]' "$HISTORY_FILE")
else
  UPDATED=$(jq -n --argjson entry "$HISTORY_ENTRY" '[$entry]')
fi

echo "$UPDATED" > "$HISTORY_FILE"
ok "Saved to launch history: $HISTORY_FILE"

# ── Print summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  ✅ LAUNCH COMPLETE${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Token Name:${RESET}    $TOKEN_NAME (\$$TOKEN_SYMBOL)"
echo -e "  ${BOLD}Token Address:${RESET} ${GREEN}$TOKEN_ADDRESS${RESET}"
echo -e "  ${BOLD}LP Address:${RESET}    ${GREEN}$LP_ADDRESS${RESET}"
echo -e "  ${BOLD}TX Hash:${RESET}       $TX_HASH"
echo -e "  ${BOLD}Abscan TX:${RESET}     ${CYAN}https://abscan.org/tx/$TX_HASH${RESET}"
echo -e "  ${BOLD}Abscan Token:${RESET}  ${CYAN}https://abscan.org/token/$TOKEN_ADDRESS${RESET}"
echo -e "  ${BOLD}LP seeded:${RESET}     $LIQUIDITY_ETH ETH"
echo ""
