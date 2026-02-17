#!/usr/bin/env bash
# blinko-status.sh — Check Blinko balance, HONEY, and play history
# Usage: blinko-status.sh --wallet 0x... [--mode balance|history|all] [--limit 10]
#
# Blinko by @bearish_af — https://blinko.gg
# On Abstract Chain (Chain ID: 2741)

set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────────
CONFIG_DIR="${HOME}/.config/blinko"
ABSTRACT_RPC="${ABSTRACT_RPC:-https://api.mainnet.abs.xyz}"
ABSTRACT_CHAIN_ID=2741
ABSTRACT_EXPLORER="https://explorer.abstract.money"

# ─── Defaults ──────────────────────────────────────────────────────────────────
WALLET=""
MODE="all"
LIMIT=10

# ─── Helpers ───────────────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --wallet <addr>   Your Abstract Global Wallet address"
  echo "  --mode <mode>     balance | history | all (default: all)"
  echo "  --limit <n>       Number of history entries to show (default: 10)"
  echo "  --rpc <url>       Abstract Chain RPC URL"
  echo "  -h, --help        Show this help"
  echo ""
  echo "Examples:"
  echo "  $0 --wallet 0xYourAddress"
  echo "  $0 --wallet 0xYourAddress --mode history --limit 5"
  exit 0
}

log()  { echo "[blinko-status] $*"; }
die()  { echo "[blinko-status] ✗ $*" >&2; exit 1; }

# ─── Parse Args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wallet)  WALLET="$2"; shift 2 ;;
    --mode)    MODE="$2"; shift 2 ;;
    --limit)   LIMIT="$2"; shift 2 ;;
    --rpc)     ABSTRACT_RPC="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1. Run with --help." ;;
  esac
done

# Try to load wallet from config if not provided
if [[ -z "$WALLET" && -f "${CONFIG_DIR}/config.json" ]]; then
  WALLET=$(jq -r '.wallet // ""' "${CONFIG_DIR}/config.json" 2>/dev/null || echo "")
fi
[[ -z "$WALLET" ]] && die "Missing --wallet. Example: --wallet 0xYourAddress"

# Basic address validation
if ! echo "$WALLET" | grep -qE '^0x[0-9a-fA-F]{40}$'; then
  die "Invalid wallet address: $WALLET"
fi

# ─── Balance Check ─────────────────────────────────────────────────────────────
show_balance() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "💰 WALLET BALANCE"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "  Wallet: $WALLET"
  log "  Network: Abstract Chain (ID: $ABSTRACT_CHAIN_ID)"
  log ""

  # ETH balance
  RESP=$(curl -sf -X POST "$ABSTRACT_RPC" \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$WALLET\",\"latest\"],\"id\":1}" \
    2>/dev/null || echo '{"result":"0x0"}')

  BALANCE_HEX=$(echo "$RESP" | jq -r '.result // "0x0"')
  BALANCE_WEI=$(printf "%d" "$BALANCE_HEX" 2>/dev/null || echo 0)
  BALANCE_ETH=$(awk "BEGIN { printf \"%.6f\", $BALANCE_WEI / 1e18 }")

  log "  ETH Balance: ${BALANCE_ETH} ETH"
  log ""

  # Transaction count (nonce = proxy for activity)
  NONCE_RESP=$(curl -sf -X POST "$ABSTRACT_RPC" \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionCount\",\"params\":[\"$WALLET\",\"latest\"],\"id\":2}" \
    2>/dev/null || echo '{"result":"0x0"}')
  NONCE_HEX=$(echo "$NONCE_RESP" | jq -r '.result // "0x0"')
  NONCE=$(printf "%d" "$NONCE_HEX" 2>/dev/null || echo 0)
  log "  Total Txs (nonce): $NONCE"
  log ""
  log "  Explorer: ${ABSTRACT_EXPLORER}/address/${WALLET}"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # HONEY balance note
  log ""
  log "  🍯 HONEY Balance: Check at https://blinko.gg (connect wallet)"
  log "     HONEY earns $BURR via Bearish ecosystem"
  log "     HONEY feeds XEET leaderboard on xeet.ai"
}

# ─── Local History ─────────────────────────────────────────────────────────────
show_history() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "📜 PLAY HISTORY (last $LIMIT)"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  HISTORY_FILE="${CONFIG_DIR}/history.jsonl"
  if [[ ! -f "$HISTORY_FILE" ]]; then
    log "  No local history found."
    log "  History is written by blinko-play.sh after each play."
    log "  Full history: ${ABSTRACT_EXPLORER}/address/${WALLET}"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    return
  fi

  local count=0
  while IFS= read -r line; do
    count=$((count + 1))
    TS=$(echo "$line" | jq -r '.ts // "unknown"')
    AMT=$(echo "$line" | jq -r '.amount // "?"')
    RISK=$(echo "$line" | jq -r '.risk // "?"')
    TX=$(echo "$line" | jq -r '.tx // "?"')
    log "  [$count] $TS — ${AMT} ETH — risk: $RISK"
    log "       TX: $TX"
    log "       → ${ABSTRACT_EXPLORER}/tx/${TX}"
  done < <(tail -n "$LIMIT" "$HISTORY_FILE")

  log ""
  log "  Total recorded plays: $(wc -l < "$HISTORY_FILE" | tr -d ' ')"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─── Global Stats ──────────────────────────────────────────────────────────────
show_global_stats() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🌐 BLINKO GLOBAL STATS"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "  Game: Blinko by @bearish_af"
  log "  URL: https://blinko.gg"
  log "  Network: Abstract Chain"
  log "  Total Games Played: 683,664+ (as of Feb 2026)"
  log "  Min Bet: 0.001 ETH"
  log "  Max Observed Multiplier: 11x+"
  log "  Rewards: HONEY → \$BURR tokens"
  log "  Abstract XP: Yes — earned on every play"
  log "  Recommended: 3 plays/day for XP farming"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─── Main ──────────────────────────────────────────────────────────────────────
case "$MODE" in
  balance)
    show_balance
    ;;
  history)
    show_history
    ;;
  all)
    show_balance
    echo ""
    show_history
    echo ""
    show_global_stats
    ;;
  *)
    die "Invalid mode: $MODE. Use: balance | history | all"
    ;;
esac
