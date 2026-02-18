#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# TokenLauncher — check-status.sh
# Checks on-chain stats for a launched token: supply, LP reserves, Abscan link.
#
# Usage:
#   ./check-status.sh                    # Checks latest launch from history
#   ./check-status.sh 0xTokenAddress     # Checks specific token address
#
# Required env:
#   ABSTRACT_RPC_URL  — (optional) defaults to https://api.mainnet.abs.xyz
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
DEFAULT_RPC="https://api.mainnet.abs.xyz"
HISTORY_FILE="${TOKENLAUNCHER_HISTORY:-$HOME/.config/tokenlauncher/launch-history.json}"
RPC_URL="${ABSTRACT_RPC_URL:-$DEFAULT_RPC}"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[tokenlauncher/status]${RESET} $*"; }
ok()   { echo -e "${GREEN}[✓]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
die()  { echo -e "${RED}[✗] ERROR:${RESET} $*" >&2; exit 1; }

TARGET_ADDRESS="${1:-}"

# ── Load token from history if address not provided ───────────────────────────
ENTRY=""
if [[ -n "$TARGET_ADDRESS" ]]; then
  TOKEN_ADDRESS="$TARGET_ADDRESS"
  TOKEN_SYMBOL="UNKNOWN"
  TOKEN_NAME="Unknown"
  LIQUIDITY_ETH="?"
  LP_ADDRESS=""
  TX_HASH=""
  LAUNCHED_AT=""

  # Try to find in history
  if [[ -f "$HISTORY_FILE" ]]; then
    ENTRY=$(jq --arg addr "$TARGET_ADDRESS" '.[] | select(.tokenAddress == $addr)' "$HISTORY_FILE" | jq -s '.[0]' 2>/dev/null || echo "null")
    if [[ "$ENTRY" != "null" && -n "$ENTRY" ]]; then
      TOKEN_SYMBOL=$(echo  "$ENTRY" | jq -r '.tokenSymbol  // "UNKNOWN"')
      TOKEN_NAME=$(echo    "$ENTRY" | jq -r '.tokenName    // "Unknown"')
      LIQUIDITY_ETH=$(echo "$ENTRY" | jq -r '.liquidityETH // "?"')
      LP_ADDRESS=$(echo    "$ENTRY" | jq -r '.lpAddress    // ""')
      TX_HASH=$(echo       "$ENTRY" | jq -r '.txHash       // ""')
      LAUNCHED_AT=$(echo   "$ENTRY" | jq -r '.timestamp    // ""')
    fi
  fi
else
  [[ -f "$HISTORY_FILE" ]] || die "No launch history found. Run launch-token.sh first."
  ENTRY=$(jq '.[-1]' "$HISTORY_FILE")
  [[ "$ENTRY" == "null" || -z "$ENTRY" ]] && die "Launch history is empty."

  TOKEN_ADDRESS=$(echo "$ENTRY" | jq -r '.tokenAddress')
  TOKEN_SYMBOL=$(echo  "$ENTRY" | jq -r '.tokenSymbol')
  TOKEN_NAME=$(echo    "$ENTRY" | jq -r '.tokenName')
  LIQUIDITY_ETH=$(echo "$ENTRY" | jq -r '.liquidityETH')
  LP_ADDRESS=$(echo    "$ENTRY" | jq -r '.lpAddress')
  TX_HASH=$(echo       "$ENTRY" | jq -r '.txHash')
  LAUNCHED_AT=$(echo   "$ENTRY" | jq -r '.timestamp')
fi

command -v cast >/dev/null 2>&1 || die "Foundry 'cast' not found. Install: curl -L https://foundry.paradigm.xyz | bash && foundryup"
command -v jq   >/dev/null 2>&1 || die "'jq' not found. Install: brew install jq"

# ── ERC-20 ABI calls ──────────────────────────────────────────────────────────
ERC20_NAME_SIG="name()(string)"
ERC20_SYMBOL_SIG="symbol()(string)"
ERC20_SUPPLY_SIG="totalSupply()(uint256)"
ERC20_DECIMALS_SIG="decimals()(uint8)"

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  📊 Token Status — Abstract Chain (ID: 2741)${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""

log "Checking token: $TOKEN_ADDRESS"
echo ""

# ── On-chain token metadata ───────────────────────────────────────────────────
ONCHAIN_NAME=""
ONCHAIN_SYMBOL=""
ONCHAIN_SUPPLY=""
ONCHAIN_DECIMALS="18"

ONCHAIN_NAME=$(cast call "$TOKEN_ADDRESS" "$ERC20_NAME_SIG" --rpc-url "$RPC_URL" 2>/dev/null | \
  cast --to-ascii 2>/dev/null | tr -d '\0' || echo "$TOKEN_NAME")

ONCHAIN_SYMBOL=$(cast call "$TOKEN_ADDRESS" "$ERC20_SYMBOL_SIG" --rpc-url "$RPC_URL" 2>/dev/null | \
  cast --to-ascii 2>/dev/null | tr -d '\0' || echo "$TOKEN_SYMBOL")

ONCHAIN_SUPPLY_RAW=$(cast call "$TOKEN_ADDRESS" "$ERC20_SUPPLY_SIG" --rpc-url "$RPC_URL" 2>/dev/null | \
  cast --to-dec 2>/dev/null || echo "0")

ONCHAIN_DECIMALS=$(cast call "$TOKEN_ADDRESS" "$ERC20_DECIMALS_SIG" --rpc-url "$RPC_URL" 2>/dev/null | \
  cast --to-dec 2>/dev/null || echo "18")

# Convert supply from wei to whole tokens
if command -v python3 >/dev/null 2>&1; then
  SUPPLY_TOKENS=$(python3 -c "
supply = int('${ONCHAIN_SUPPLY_RAW}' or '0')
dec = int('${ONCHAIN_DECIMALS}' or '18')
whole = supply / (10 ** dec)
if whole >= 1_000_000_000:
    print(f'{whole/1_000_000_000:.2f}B')
elif whole >= 1_000_000:
    print(f'{whole/1_000_000:.2f}M')
elif whole >= 1_000:
    print(f'{whole/1_000:.2f}K')
else:
    print(f'{whole:.2f}')
" 2>/dev/null || echo "$ONCHAIN_SUPPLY_RAW")
else
  SUPPLY_TOKENS="$ONCHAIN_SUPPLY_RAW (raw wei)"
fi

# ── LP reserves ───────────────────────────────────────────────────────────────
LP_STATUS="unknown"
LP_ETH_RESERVE=""
LP_TOKEN_RESERVE=""

if [[ -n "$LP_ADDRESS" && "$LP_ADDRESS" != "(parse"* ]]; then
  # Uniswap V2-style LP: getReserves()(uint112,uint112,uint32)
  RESERVES=$(cast call "$LP_ADDRESS" "getReserves()(uint112,uint112,uint32)" \
    --rpc-url "$RPC_URL" 2>/dev/null || echo "")

  if [[ -n "$RESERVES" ]]; then
    LP_STATUS="active"
    # Parse reserve0 and reserve1 (may be ETH/WETH and token, order depends on address sort)
    RESERVE0=$(echo "$RESERVES" | awk 'NR==1{print $1}' | cast --to-dec 2>/dev/null || echo "0")
    RESERVE1=$(echo "$RESERVES" | awk 'NR==2{print $1}' | cast --to-dec 2>/dev/null || echo "0")

    if command -v python3 >/dev/null 2>&1; then
      LP_ETH_RESERVE=$(python3 -c "print(f'{int(\"$RESERVE0\") / 10**18:.6f} ETH')" 2>/dev/null || echo "$RESERVE0 wei")
      LP_TOKEN_RESERVE=$(python3 -c "
r = int('$RESERVE1')
dec = int('${ONCHAIN_DECIMALS}')
v = r / (10 ** dec)
if v >= 1_000_000: print(f'{v/1_000_000:.2f}M tokens')
elif v >= 1_000:   print(f'{v/1_000:.2f}K tokens')
else:              print(f'{v:.2f} tokens')
" 2>/dev/null || echo "$RESERVE1 wei")
    else
      LP_ETH_RESERVE="$RESERVE0 wei"
      LP_TOKEN_RESERVE="$RESERVE1 wei"
    fi
  else
    LP_STATUS="no reserves (LP may not be active yet)"
  fi
fi

# ── Get ETH balance of contract (sanity check) ────────────────────────────────
CONTRACT_ETH=""
if [[ -n "$LP_ADDRESS" && "$LP_ADDRESS" != "(parse"* ]]; then
  CONTRACT_ETH=$(cast balance "$LP_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null | \
    python3 -c "import sys; v=int(sys.stdin.read().strip()); print(f'{v/10**18:.6f} ETH')" 2>/dev/null || echo "?")
fi

# ── Print results ─────────────────────────────────────────────────────────────
echo -e "  ${BOLD}Token Name:${RESET}      ${ONCHAIN_NAME:-$TOKEN_NAME}"
echo -e "  ${BOLD}Symbol:${RESET}          \$${ONCHAIN_SYMBOL:-$TOKEN_SYMBOL}"
echo -e "  ${BOLD}Total Supply:${RESET}    $SUPPLY_TOKENS"
echo -e "  ${BOLD}Token Address:${RESET}   ${GREEN}$TOKEN_ADDRESS${RESET}"
echo ""

if [[ -n "$LP_ADDRESS" && "$LP_ADDRESS" != "(parse"* ]]; then
  echo -e "  ${BOLD}LP Address:${RESET}      ${GREEN}$LP_ADDRESS${RESET}"
  echo -e "  ${BOLD}LP Status:${RESET}       $LP_STATUS"
  [[ -n "$LP_ETH_RESERVE"   ]] && echo -e "  ${BOLD}Reserve 0:${RESET}       $LP_ETH_RESERVE"
  [[ -n "$LP_TOKEN_RESERVE" ]] && echo -e "  ${BOLD}Reserve 1:${RESET}       $LP_TOKEN_RESERVE"
  [[ -n "$CONTRACT_ETH"     ]] && echo -e "  ${BOLD}LP ETH balance:${RESET}  $CONTRACT_ETH"
fi

echo ""
echo -e "  ${BOLD}Launch TX:${RESET}       ${CYAN}https://abscan.org/tx/$TX_HASH${RESET}"
echo -e "  ${BOLD}Abscan Token:${RESET}    ${CYAN}https://abscan.org/token/$TOKEN_ADDRESS${RESET}"
[[ -n "$LP_ADDRESS" && "$LP_ADDRESS" != "(parse"* ]] && \
  echo -e "  ${BOLD}Abscan LP:${RESET}       ${CYAN}https://abscan.org/address/$LP_ADDRESS${RESET}"
[[ -n "$LAUNCHED_AT" ]] && echo -e "  ${BOLD}Launched at:${RESET}     $LAUNCHED_AT"
echo ""

# ── Health assessment ─────────────────────────────────────────────────────────
if [[ "$LP_STATUS" == "active" ]]; then
  ok "LP is active and holding reserves. Token is tradeable."
elif [[ "$LP_STATUS" == "unknown" ]]; then
  warn "Could not verify LP status. Check Abscan manually."
else
  warn "LP status: $LP_STATUS"
fi

echo ""
