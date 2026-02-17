#!/usr/bin/env bash
# badgelender-rent.sh — Rent or Return ABSOCKS NFT on BadgeLender
# Usage: badgelender-rent.sh --wallet 0x... --action rent|return
#
# BadgeLender by @BigHossbot — https://badgelender.com
# Featured by @AbstractChain — 301+ rentals served
#
# Flow:
#   rent   → Pay 0.205 ETH (0.2 collateral + 0.005 fee) → get ABSOCKS NFT
#   return → Send ABSOCKS back → get 0.2 ETH collateral refunded
#
# Abstract Chain:
#   RPC: https://api.mainnet.abs.xyz
#   Chain ID: 2741

set -euo pipefail

# ─── Constants ─────────────────────────────────────────────────────────────────
ABSTRACT_RPC="${ABSTRACT_RPC:-https://api.mainnet.abs.xyz}"
ABSTRACT_CHAIN_ID=2741
ABSTRACT_EXPLORER="https://explorer.abstract.money"
BADGELENDER_URL="https://badgelender.com"
ABSTRACT_REWARDS_URL="https://portal.abs.xyz/rewards"

# Pricing (as of Feb 17, 2026 — will fluctuate with ETH price)
COLLATERAL_ETH="0.2"        # Refundable
SERVICE_FEE_ETH="0.005"     # Non-refundable
TOTAL_ETH="0.205"           # Total to send
RENTAL_DURATION_SECS=3600   # 1 hour
LATE_PENALTY_PCT=5          # 5% per hour on collateral

# State file location
STATE_DIR="${HOME}/.config/badgelender"
STATE_FILE="${STATE_DIR}/rental-state.json"

# ─── Args ──────────────────────────────────────────────────────────────────────
WALLET=""
ACTION=""
DRY_RUN=false

usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --wallet <addr>    Your Abstract Global Wallet (AGW) address"
  echo "  --action <action>  rent | return"
  echo "  --rpc <url>        Abstract Chain RPC (default: https://api.mainnet.abs.xyz)"
  echo "  --dry-run          Simulate without sending transaction"
  echo "  -h, --help         Show this help"
  echo ""
  echo "Pricing:"
  echo "  Collateral (refundable): $COLLATERAL_ETH ETH"
  echo "  Service fee (kept):      $SERVICE_FEE_ETH ETH"
  echo "  Total to send:           $TOTAL_ETH ETH"
  echo "  Rental window:           1 hour"
  echo "  Late penalty:            ${LATE_PENALTY_PCT}%/hr on collateral"
  echo ""
  echo "Examples:"
  echo "  $0 --wallet 0xYourAddress --action rent"
  echo "  $0 --wallet 0xYourAddress --action return"
  echo "  $0 --wallet 0xYourAddress --action rent --dry-run"
  exit 0
}

log()  { echo "[badgelender-rent] $*"; }
warn() { echo "[badgelender-rent] ⚠️  $*" >&2; }
die()  { echo "[badgelender-rent] ✗ $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wallet)   WALLET="$2"; shift 2 ;;
    --action)   ACTION="$2"; shift 2 ;;
    --rpc)      ABSTRACT_RPC="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    -h|--help)  usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -z "$WALLET" ]]  && die "Missing --wallet"
[[ -z "$ACTION" ]]  && die "Missing --action (rent | return)"

if ! echo "$WALLET" | grep -qE '^0x[0-9a-fA-F]{40}$'; then
  die "Invalid wallet address: $WALLET"
fi

case "$ACTION" in
  rent|return) ;;
  *) die "Invalid action: $ACTION. Use: rent | return" ;;
esac

mkdir -p "$STATE_DIR"

# ─── Check Balance ─────────────────────────────────────────────────────────────
check_balance() {
  local min_required="$1"
  log "Checking ETH balance for $WALLET on Abstract Chain..."
  
  RESP=$(curl -sf -X POST "$ABSTRACT_RPC" \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$WALLET\",\"latest\"],\"id\":1}" \
    2>/dev/null || echo '{"result":"0x0"}')
  
  BALANCE_HEX=$(echo "$RESP" | jq -r '.result // "0x0"')
  BALANCE_WEI=$(printf "%d" "$BALANCE_HEX" 2>/dev/null || echo 0)
  BALANCE_ETH=$(awk "BEGIN { printf \"%.6f\", $BALANCE_WEI / 1e18 }")
  
  log "  Balance: ${BALANCE_ETH} ETH"
  
  ENOUGH=$(awk "BEGIN { print ($BALANCE_ETH >= $min_required) ? \"yes\" : \"no\" }")
  if [[ "$ENOUGH" != "yes" ]]; then
    warn "Balance ${BALANCE_ETH} ETH may be insufficient (need ~${min_required} ETH)"
  fi
}

# ─── Save Rental State ─────────────────────────────────────────────────────────
save_rental_state() {
  local tx_hash="$1"
  local start_time
  start_time=$(date -u +%s)
  local deadline=$((start_time + RENTAL_DURATION_SECS))
  
  cat > "$STATE_FILE" <<EOF
{
  "wallet": "$WALLET",
  "action": "rented",
  "txHash": "$tx_hash",
  "startTime": $start_time,
  "deadline": $deadline,
  "deadlineHuman": "$(date -u -r "$deadline" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$deadline" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "unknown")",
  "collateralETH": "$COLLATERAL_ETH",
  "serviceFeeETH": "$SERVICE_FEE_ETH",
  "claimURL": "$ABSTRACT_REWARDS_URL"
}
EOF
  log "Rental state saved to: $STATE_FILE"
}

clear_rental_state() {
  if [[ -f "$STATE_FILE" ]]; then
    rm -f "$STATE_FILE"
    log "Rental state cleared"
  fi
}

# ─── RENT ──────────────────────────────────────────────────────────────────────
do_rent() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🧦 BADGELENDER — RENT ABSOCKS"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "  Wallet:        $WALLET"
  log "  Collateral:    $COLLATERAL_ETH ETH (refunded on return)"
  log "  Service fee:   $SERVICE_FEE_ETH ETH (kept by protocol)"
  log "  Total to send: $TOTAL_ETH ETH"
  log "  Duration:      1 hour (return within 1hr for full refund)"
  log "  Late penalty:  ${LATE_PENALTY_PCT}% per hour on collateral"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""
  log "After renting:"
  log "  1. ABSOCKS NFT arrives in your wallet instantly"
  log "  2. Go to: $ABSTRACT_REWARDS_URL"
  log "  3. Claim the 'Sock Master' badge"
  log "  4. Return ABSOCKS via: badgelender-rent.sh --action return"
  log ""

  check_balance "$(awk "BEGIN { print $TOTAL_ETH + 0.002 }")"

  if $DRY_RUN; then
    log "🔎 DRY RUN — would send $TOTAL_ETH ETH to BadgeLender contract"
    log "   Real run: remove --dry-run flag"
    exit 0
  fi

  # ── Contract Call ──────────────────────────────────────────────────────────
  # BadgeLender contract call: rent() payable with 0.205 ETH (0.2 collateral + 0.005 fee)
  # Requires BADGELENDER_CONTRACT env var and PRIVATE_KEY for direct cast call.
  # AGW (Abstract Global Wallet) users must use the web UI or session key automation.

  BADGELENDER_CONTRACT="${BADGELENDER_CONTRACT:-}"
  PRIVATE_KEY="${PRIVATE_KEY:-}"

  if [[ -n "$BADGELENDER_CONTRACT" && -n "$PRIVATE_KEY" ]]; then
    log "Submitting rent() call via cast..."
    
    TX_HASH=$(cast send "$BADGELENDER_CONTRACT" \
      "rent()" \
      --value "${TOTAL_ETH}ether" \
      --private-key "$PRIVATE_KEY" \
      --rpc-url "$ABSTRACT_RPC" \
      --chain-id "$ABSTRACT_CHAIN_ID" \
      --json 2>&1 | jq -r '.transactionHash // empty')
    
    if [[ -n "$TX_HASH" ]]; then
      log "✅ Rental submitted!"
      log "   TX: $TX_HASH"
      log "   Explorer: ${ABSTRACT_EXPLORER}/tx/${TX_HASH}"
      log ""
      log "⏰ 1-HOUR CLOCK STARTS NOW"
      log "   Claim badge at: $ABSTRACT_REWARDS_URL"
      log "   Return ABSOCKS before deadline to get ${COLLATERAL_ETH} ETH back!"
      save_rental_state "$TX_HASH"
    else
      die "Rent transaction failed"
    fi
  else
    log "⚠️  To automate: set BADGELENDER_CONTRACT and PRIVATE_KEY env vars"
    log "   Or use the web UI: $BADGELENDER_URL"
    log ""
    log "Manual steps:"
    log "  1. Visit $BADGELENDER_URL"
    log "  2. Connect Abstract Global Wallet"
    log "  3. Click 'Rent ABSOCKS' and approve $TOTAL_ETH ETH"
    log "  4. ABSOCKS NFT arrives instantly — claim badge within 1 hour!"
    exit 0
  fi
}

# ─── RETURN ────────────────────────────────────────────────────────────────────
do_return() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🧦 BADGELENDER — RETURN ABSOCKS"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Check if we have saved rental state
  if [[ -f "$STATE_FILE" ]]; then
    DEADLINE=$(jq -r '.deadline // 0' "$STATE_FILE")
    DEADLINE_HUMAN=$(jq -r '.deadlineHuman // "unknown"' "$STATE_FILE")
    RENT_TX=$(jq -r '.txHash // "unknown"' "$STATE_FILE")
    NOW=$(date -u +%s)
    TIME_LEFT=$((DEADLINE - NOW))
    
    log "  Rental TX:    $RENT_TX"
    log "  Deadline:     $DEADLINE_HUMAN"
    
    if [[ $TIME_LEFT -gt 0 ]]; then
      MINS_LEFT=$((TIME_LEFT / 60))
      log "  Time left:    ${MINS_LEFT} minutes ✓"
      log "  Status:       ON TIME — full collateral refund"
    elif [[ $TIME_LEFT -gt -300 ]]; then
      log "  Status:       GRACE PERIOD (0-5 min late) — still full refund"
    else
      OVERDUE_MINS=$(( (-TIME_LEFT) / 60 ))
      OVERDUE_HRS=$(awk "BEGIN { printf \"%.1f\", $OVERDUE_MINS / 60 }")
      PENALTY=$(awk "BEGIN { printf \"%.4f\", $overdue_hrs * $LATE_PENALTY_PCT / 100 * $COLLATERAL_ETH }")
      log "  Time left:    OVERDUE by ${OVERDUE_MINS} minutes"
      log "  Status:       LATE — penalty applies"
    fi
    log ""
  fi

  log "  Wallet: $WALLET"
  log ""

  if $DRY_RUN; then
    log "🔎 DRY RUN — would return ABSOCKS to BadgeLender contract"
    exit 0
  fi

  BADGELENDER_CONTRACT="${BADGELENDER_CONTRACT:-}"
  PRIVATE_KEY="${PRIVATE_KEY:-}"

  if [[ -n "$BADGELENDER_CONTRACT" && -n "$PRIVATE_KEY" ]]; then
    log "Submitting return() call via cast..."
    
    TX_HASH=$(cast send "$BADGELENDER_CONTRACT" \
      "returnNFT()" \
      --private-key "$PRIVATE_KEY" \
      --rpc-url "$ABSTRACT_RPC" \
      --chain-id "$ABSTRACT_CHAIN_ID" \
      --json 2>&1 | jq -r '.transactionHash // empty')
    
    if [[ -n "$TX_HASH" ]]; then
      log "✅ ABSOCKS returned!"
      log "   TX: $TX_HASH"
      log "   Explorer: ${ABSTRACT_EXPLORER}/tx/${TX_HASH}"
      log "   Collateral refund: ${COLLATERAL_ETH} ETH → $WALLET"
      log "   Badge kept: Sock Master 🧦"
      clear_rental_state
    else
      die "Return transaction failed"
    fi
  else
    log "⚠️  To automate: set BADGELENDER_CONTRACT and PRIVATE_KEY env vars"
    log "   Or use the web UI: $BADGELENDER_URL"
    log ""
    log "Manual steps:"
    log "  1. Visit $BADGELENDER_URL"
    log "  2. Connect Abstract Global Wallet"
    log "  3. Click 'Return ABSOCKS'"
    log "  4. Collateral (${COLLATERAL_ETH} ETH) refunded immediately"
    exit 0
  fi
}

# ─── Main ──────────────────────────────────────────────────────────────────────
case "$ACTION" in
  rent)   do_rent ;;
  return) do_return ;;
esac
