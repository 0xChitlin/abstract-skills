#!/usr/bin/env bash
# badgelender-status.sh — Check BadgeLender rental status
# Usage: badgelender-status.sh --wallet 0x...
#
# BadgeLender by @BigHossbot — https://badgelender.com
# Rent ABSOCKS NFT → Claim Sock Master badge → Return for collateral refund
#
# Abstract Chain (Chain ID: 2741)

set -euo pipefail

# ─── Constants ─────────────────────────────────────────────────────────────────
ABSTRACT_RPC="${ABSTRACT_RPC:-https://api.mainnet.abs.xyz}"
ABSTRACT_CHAIN_ID=2741
ABSTRACT_EXPLORER="https://explorer.abstract.money"
BADGELENDER_URL="https://badgelender.com"
ABSTRACT_REWARDS_URL="https://portal.abs.xyz/rewards"

STATE_DIR="${HOME}/.config/badgelender"
STATE_FILE="${STATE_DIR}/rental-state.json"

COLLATERAL_ETH="0.2"
SERVICE_FEE_ETH="0.005"
TOTAL_ETH="0.205"

# ─── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[badgelender-status] $*"; }
die()  { echo "[badgelender-status] ✗ $*" >&2; exit 1; }

usage() {
  echo "Usage: $0 --wallet 0xYourAddress"
  echo ""
  echo "Options:"
  echo "  --wallet <addr>   Your Abstract Global Wallet address"
  echo "  --rpc <url>       Abstract Chain RPC"
  echo "  -h, --help        Show this help"
  exit 0
}

# ─── Parse Args ────────────────────────────────────────────────────────────────
WALLET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wallet)  WALLET="$2"; shift 2 ;;
    --rpc)     ABSTRACT_RPC="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [[ -z "$WALLET" && -f "${STATE_FILE}" ]]; then
  WALLET=$(jq -r '.wallet // ""' "$STATE_FILE" 2>/dev/null || echo "")
fi
[[ -z "$WALLET" ]] && die "Missing --wallet. Example: --wallet 0xYourAddress"

if ! echo "$WALLET" | grep -qE '^0x[0-9a-fA-F]{40}$'; then
  die "Invalid wallet address: $WALLET"
fi

# ─── Protocol Status ───────────────────────────────────────────────────────────
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "🧦 BADGELENDER STATUS"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""
log "📌 Protocol Info"
log "   URL:            $BADGELENDER_URL"
log "   Network:        Abstract Chain (ID: $ABSTRACT_CHAIN_ID)"
log "   Creator:        @BigHossbot"
log "   Total Rentals:  301+ (as of Feb 17, 2026)"
log "   Featured by:    @AbstractChain official"
log ""
log "💰 Current Pricing"
log "   Collateral:     $COLLATERAL_ETH ETH (fully refundable)"
log "   Service Fee:    $SERVICE_FEE_ETH ETH (non-refundable)"
log "   Total:          $TOTAL_ETH ETH"
log "   Net Cost:       ~\$10 (service fee only)"
log "   Duration:       1 hour"
log "   Late penalty:   5%/hr on collateral after 1hr"
log ""

# ─── Wallet Balance ────────────────────────────────────────────────────────────
log "💳 Wallet: $WALLET"

RESP=$(curl -sf -X POST "$ABSTRACT_RPC" \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$WALLET\",\"latest\"],\"id\":1}" \
  2>/dev/null || echo '{"result":"0x0"}')

BALANCE_HEX=$(echo "$RESP" | jq -r '.result // "0x0"')
BALANCE_WEI=$(printf "%d" "$BALANCE_HEX" 2>/dev/null || echo 0)
BALANCE_ETH=$(awk "BEGIN { printf \"%.6f\", $BALANCE_WEI / 1e18 }")

log "   ETH Balance:    ${BALANCE_ETH} ETH"
log "   Explorer:       ${ABSTRACT_EXPLORER}/address/${WALLET}"
log ""

# Check if wallet has enough for a rental
ENOUGH=$(awk "BEGIN { print ($BALANCE_ETH >= 0.207) ? \"yes\" : \"no\" }")
if [[ "$ENOUGH" == "yes" ]]; then
  log "   ✅ Sufficient balance to rent (need ~0.207 ETH including gas)"
else
  log "   ⚠️  Insufficient balance to rent (need ~0.207 ETH including gas)"
fi
log ""

# ─── Active Rental Check ───────────────────────────────────────────────────────
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "⏱️  RENTAL STATUS"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -f "$STATE_FILE" ]]; then
  SAVED_WALLET=$(jq -r '.wallet // ""' "$STATE_FILE")
  
  if [[ "$SAVED_WALLET" == "$WALLET" ]]; then
    ACTION_STATE=$(jq -r '.action // "unknown"' "$STATE_FILE")
    RENT_TX=$(jq -r '.txHash // "unknown"' "$STATE_FILE")
    DEADLINE=$(jq -r '.deadline // 0' "$STATE_FILE")
    DEADLINE_HUMAN=$(jq -r '.deadlineHuman // "unknown"' "$STATE_FILE")
    NOW=$(date -u +%s)
    TIME_LEFT=$((DEADLINE - NOW))
    
    log "   State:          $ACTION_STATE"
    log "   Rent TX:        $RENT_TX"
    log "   Deadline:       $DEADLINE_HUMAN"
    
    if [[ $TIME_LEFT -gt 0 ]]; then
      MINS_LEFT=$((TIME_LEFT / 60))
      SECS_LEFT=$((TIME_LEFT % 60))
      log "   Time Remaining: ${MINS_LEFT}m ${SECS_LEFT}s ✅"
      log "   Status:         ON TIME"
      log ""
      log "   Next steps:"
      log "   1. Claim badge at: $ABSTRACT_REWARDS_URL"
      log "   2. Return ABSOCKS: badgelender-rent.sh --wallet $WALLET --action return"
    elif [[ $TIME_LEFT -gt -300 ]]; then
      log "   Time Remaining: GRACE PERIOD (within 5 min)"
      log "   Status:         ⚠️  RETURN NOW for full refund"
      log ""
      log "   Run: badgelender-rent.sh --wallet $WALLET --action return"
    else
      OVERDUE_MINS=$(( (-TIME_LEFT) / 60 ))
      OVERDUE_HRS_RAW=$(awk "BEGIN { printf \"%.2f\", $OVERDUE_MINS / 60 }")
      PENALTY_ETH=$(awk "BEGIN { printf \"%.4f\", $OVERDUE_HRS_RAW * 5 / 100 * 0.2 }")
      REFUND_ETH=$(awk "BEGIN { r = 0.2 - $PENALTY_ETH; printf \"%.4f\", (r > 0) ? r : 0 }")
      
      log "   Time Remaining: OVERDUE by ${OVERDUE_MINS} min"
      log "   Status:         ⛔ LATE — fees accruing"
      log "   Penalty so far: ~${PENALTY_ETH} ETH"
      log "   Est. refund:    ~${REFUND_ETH} ETH"
      log ""
      log "   RETURN IMMEDIATELY: badgelender-rent.sh --wallet $WALLET --action return"
    fi
  else
    log "   State file found but for different wallet ($SAVED_WALLET)"
    log "   No active rental found for $WALLET"
  fi
else
  log "   No active rental found locally"
  log "   Check on-chain: ${ABSTRACT_EXPLORER}/address/${WALLET}"
  log ""
  log "   To start a rental:"
  log "   badgelender-rent.sh --wallet $WALLET --action rent"
fi

# ─── Late Fee Reference ────────────────────────────────────────────────────────
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "📋 LATE FEE SCHEDULE"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "   On time (≤1hr)   → Full refund (\$399.14 / 0.2 ETH) ✅"
log "   0-5 min late     → Grace period, full refund ✅"
log "   1 hr late        → \$19.96 penalty → get \$379.18 back"
log "   5 hrs late       → \$99.79 penalty → get \$299.36 back"
log "   10 hrs late      → \$199.57 penalty → get \$199.57 back"
log "   20+ hrs late     → Full collateral forfeited ⛔"
log ""
log "   Badge:   $ABSTRACT_REWARDS_URL"
log "   Lender:  $BADGELENDER_URL"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
