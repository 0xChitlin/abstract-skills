#!/usr/bin/env bash
# blinko-play.sh — Make a play on Blinko (blinko.gg) via Abstract Chain
# Usage: blinko-play.sh --amount 0.001 --risk medium --wallet 0x...
# 
# Blinko is an on-chain plinko game by @bearish_af on Abstract Chain.
# Each play earns HONEY points → redeemable for $BURR tokens + Abstract XP.
#
# Abstract Chain:
#   RPC: https://api.mainnet.abs.xyz
#   Chain ID: 2741
#   Explorer: https://explorer.abstract.money

set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────────
CONFIG_DIR="${HOME}/.config/blinko"
CONFIG_FILE="${CONFIG_DIR}/config.json"
ABSTRACT_RPC="${ABSTRACT_RPC:-https://api.mainnet.abs.xyz}"
ABSTRACT_CHAIN_ID=2741
BLINKO_URL="https://blinko.gg"

# ─── Defaults ──────────────────────────────────────────────────────────────────
AMOUNT=""
RISK=""
WALLET=""
SET_RISK_ONLY=false

# ─── Helpers ───────────────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --amount <ETH>      Wager amount in ETH (min 0.001)"
  echo "  --risk <level>      Risk level: low | medium | high (default: from config)"
  echo "  --wallet <addr>     Your Abstract Global Wallet (AGW) address"
  echo "  --rpc <url>         Abstract Chain RPC URL (default: https://api.mainnet.abs.xyz)"
  echo "  --set-risk <level>  Save default risk level and exit"
  echo "  --dry-run           Simulate without sending transaction"
  echo "  -h, --help          Show this help"
  echo ""
  echo "Examples:"
  echo "  $0 --amount 0.001 --risk medium --wallet 0xYourAddress"
  echo "  $0 --set-risk high"
  echo "  $0 --amount 0.005 --risk high --wallet 0xYourAddress --dry-run"
  exit 0
}

log()  { echo "[blinko-play] $*"; }
warn() { echo "[blinko-play] ⚠️  $*" >&2; }
die()  { echo "[blinko-play] ✗ $*" >&2; exit 1; }

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    SAVED_RISK=$(jq -r '.defaultRisk // "medium"' "$CONFIG_FILE" 2>/dev/null || echo "medium")
    SAVED_WALLET=$(jq -r '.wallet // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
  else
    SAVED_RISK="medium"
    SAVED_WALLET=""
  fi
}

save_config() {
  mkdir -p "$CONFIG_DIR"
  local risk_level="$1"
  echo "{\"defaultRisk\": \"$risk_level\", \"wallet\": \"${WALLET:-}\"}" > "$CONFIG_FILE"
  log "Default risk level saved: $risk_level"
}

validate_amount() {
  local amt="$1"
  # Check it's a valid number >= 0.001
  if ! echo "$amt" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    die "Invalid amount: $amt. Must be a number (e.g. 0.001)"
  fi
  # Convert to wei-like comparison using awk
  local min_ok
  min_ok=$(awk "BEGIN { print ($amt >= 0.001) ? \"yes\" : \"no\" }")
  if [[ "$min_ok" != "yes" ]]; then
    die "Amount $amt ETH is below minimum (0.001 ETH)"
  fi
}

validate_risk() {
  case "$1" in
    low|medium|high) return 0 ;;
    *) die "Invalid risk level: $1. Must be: low | medium | high" ;;
  esac
}

# ─── Parse Args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --amount)    AMOUNT="$2"; shift 2 ;;
    --risk)      RISK="$2"; shift 2 ;;
    --wallet)    WALLET="$2"; shift 2 ;;
    --rpc)       ABSTRACT_RPC="$2"; shift 2 ;;
    --set-risk)  RISK="$2"; SET_RISK_ONLY=true; shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    -h|--help)   usage ;;
    *) die "Unknown option: $1. Run with --help for usage." ;;
  esac
done
DRY_RUN="${DRY_RUN:-false}"

load_config

# Handle --set-risk-only mode
if $SET_RISK_ONLY; then
  validate_risk "$RISK"
  save_config "$RISK"
  exit 0
fi

# Fill defaults from config
RISK="${RISK:-$SAVED_RISK}"
WALLET="${WALLET:-$SAVED_WALLET}"

# ─── Validation ────────────────────────────────────────────────────────────────
[[ -z "$AMOUNT" ]] && die "Missing --amount. Example: --amount 0.001"
[[ -z "$WALLET" ]] && die "Missing --wallet. Example: --wallet 0xYourAddress"
validate_amount "$AMOUNT"
validate_risk "$RISK"

# Wallet address basic sanity
if ! echo "$WALLET" | grep -qE '^0x[0-9a-fA-F]{40}$'; then
  die "Invalid wallet address: $WALLET (must be 0x + 40 hex chars)"
fi

# ─── Check balance ─────────────────────────────────────────────────────────────
log "Checking ETH balance on Abstract Chain for $WALLET..."
BALANCE_HEX=$(curl -sf -X POST "$ABSTRACT_RPC" \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$WALLET\",\"latest\"],\"id\":1}" \
  | jq -r '.result' 2>/dev/null || echo "0x0")

# Convert hex balance to ETH (rough)
BALANCE_WEI=$(printf "%d" "$BALANCE_HEX" 2>/dev/null || echo 0)
BALANCE_ETH=$(awk "BEGIN { printf \"%.6f\", $BALANCE_WEI / 1e18 }")
log "Balance: ${BALANCE_ETH} ETH"

# Rough check — need amount + some gas
ENOUGH=$(awk "BEGIN { print ($BALANCE_ETH >= ($AMOUNT + 0.001)) ? \"yes\" : \"no\" }")
if [[ "$ENOUGH" != "yes" ]]; then
  warn "Balance ${BALANCE_ETH} ETH may be insufficient for ${AMOUNT} ETH bet + gas"
fi

# ─── Build Play Info ───────────────────────────────────────────────────────────
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
AMOUNT_WEI=$(awk "BEGIN { printf \"%.0f\", $AMOUNT * 1e18 }")
AMOUNT_HEX=$(printf "0x%x" "$AMOUNT_WEI")

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "🎯 BLINKO PLAY"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Wallet:     $WALLET"
log "  Amount:     $AMOUNT ETH ($AMOUNT_WEI wei)"
log "  Risk:       $RISK"
log "  Network:    Abstract Chain (ID: $ABSTRACT_CHAIN_ID)"
log "  RPC:        $ABSTRACT_RPC"
log "  Timestamp:  $TIMESTAMP"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if $DRY_RUN; then
  log "🔎 DRY RUN — transaction not submitted"
  log "Would send: $AMOUNT ETH from $WALLET on Abstract Chain"
  log "Play URL: $BLINKO_URL"
  exit 0
fi

# ─── Submit Play ──────────────────────────────────────────────────────────────
# NOTE: Blinko uses a frontend-rendered React app. The actual contract call
# requires wallet signing via AGW (Abstract Global Wallet). Full automation
# requires either:
#   1. cast (Foundry) with a private key: cast send <BLINKO_CONTRACT> <SIG> --value <AMT> --private-key $PK --rpc-url $ABSTRACT_RPC
#   2. ethers.js/viem script using AGW session keys
#   3. OpenClaw browser automation via blinko.gg
#
# The contract address and ABI must be resolved from blinko.gg frontend.
# Run: `cast etherscan-source <CONTRACT>` or inspect blinko.gg network tab.

log "⚠️  Full automation requires wallet signing."
log "   Option 1: Use OpenClaw browser automation → blinko.gg"
log "   Option 2: Set BLINKO_CONTRACT and PRIVATE_KEY env vars for cast-based play"
log ""

BLINKO_CONTRACT="${BLINKO_CONTRACT:-}"
PRIVATE_KEY="${PRIVATE_KEY:-}"

if [[ -n "$BLINKO_CONTRACT" && -n "$PRIVATE_KEY" ]]; then
  log "Submitting via cast..."
  # Risk level encoding: low=0, medium=1, high=2
  case "$RISK" in
    low)    RISK_INT=0 ;;
    medium) RISK_INT=1 ;;
    high)   RISK_INT=2 ;;
  esac

  # Typical Blinko call: play(uint8 risk) payable
  TX_HASH=$(cast send "$BLINKO_CONTRACT" \
    "play(uint8)" "$RISK_INT" \
    --value "${AMOUNT}ether" \
    --private-key "$PRIVATE_KEY" \
    --rpc-url "$ABSTRACT_RPC" \
    --chain-id "$ABSTRACT_CHAIN_ID" \
    --json 2>&1 | jq -r '.transactionHash // empty')

  if [[ -n "$TX_HASH" ]]; then
    log "✅ Play submitted!"
    log "   TX: $TX_HASH"
    log "   Explorer: https://explorer.abstract.money/tx/$TX_HASH"
    
    # Save to history
    mkdir -p "$CONFIG_DIR"
    echo "{\"ts\":\"$TIMESTAMP\",\"amount\":\"$AMOUNT\",\"risk\":\"$RISK\",\"tx\":\"$TX_HASH\"}" \
      >> "${CONFIG_DIR}/history.jsonl"
    log "   Saved to history"
  else
    die "Transaction submission failed"
  fi
else
  log "Set BLINKO_CONTRACT and PRIVATE_KEY to enable direct on-chain play."
  log "Or use: openclaw browser open https://blinko.gg"
  exit 0
fi
