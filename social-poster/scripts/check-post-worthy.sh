#!/usr/bin/env bash
# check-post-worthy.sh — Decides if an agent action is worth posting to X/Twitter
#
# Usage:
#   ./check-post-worthy.sh --type <type> [--earnings <eth>] [--level <n>] [--amount <eth>]
#
# Types:
#   win         -- Game win (use --earnings to specify ETH earned)
#   levelup     -- Level up event (use --level for the new level)
#   first-game  -- First time playing a game
#   trade       -- DeFi trade (use --amount for ETH value)
#   loss        -- Loss (never post)
#   other       -- Generic (never post)
#
# Exit codes:
#   0 = worth posting (go ahead)
#   1 = not worth posting (skip)
#   2 = rate limited (handled by post-win.sh)
#
# Examples:
#   ./check-post-worthy.sh --type win --earnings 0.025   → exit 0 (post it)
#   ./check-post-worthy.sh --type win --earnings 0.003   → exit 1 (skip)
#   ./check-post-worthy.sh --type levelup --level 5      → exit 0 (post it)
#   ./check-post-worthy.sh --type first-game             → exit 0 (post it)
#   ./check-post-worthy.sh --type trade --amount 0.003   → exit 1 (skip)
#   ./check-post-worthy.sh --type trade --amount 0.1     → exit 0 (post it)

set -euo pipefail

# ── Parse Args ────────────────────────────────────────────────
EVENT_TYPE=""
EARNINGS="0"
LEVEL="0"
AMOUNT="0"
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)      EVENT_TYPE="$2"; shift 2 ;;
    --earnings)  EARNINGS="$2";   shift 2 ;;
    --level)     LEVEL="$2";      shift 2 ;;
    --amount)    AMOUNT="$2";     shift 2 ;;
    --verbose|-v) VERBOSE=true;  shift   ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$EVENT_TYPE" ]]; then
  echo "Usage: $0 --type <win|levelup|first-game|trade|loss|other> [options]" >&2
  exit 1
fi

# ── Config ────────────────────────────────────────────────────
CONFIG_FILE="${HOME}/.config/social-poster/config.json"
STATE_FILE="${HOME}/.config/social-poster/state.json"

# Thresholds (overridable via config)
MIN_WIN_ETH="0.01"
MIN_TRADE_ETH="0.05"
MIN_LEVELUP=1  # any level up is worth posting

if [[ -f "$CONFIG_FILE" ]]; then
  CFG_MIN_WIN=$(jq -r '.min_earnings_eth // ""' "$CONFIG_FILE")
  CFG_MIN_TRADE=$(jq -r '.min_trade_eth // ""' "$CONFIG_FILE")
  [[ -n "$CFG_MIN_WIN" ]]   && MIN_WIN_ETH="$CFG_MIN_WIN"
  [[ -n "$CFG_MIN_TRADE" ]] && MIN_TRADE_ETH="$CFG_MIN_TRADE"
fi

# ── Helper: float comparison ──────────────────────────────────
# Returns 0 if $1 >= $2, 1 otherwise
float_gte() {
  python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)" "$1" "$2" 2>/dev/null || \
  node -e "process.exit(parseFloat(process.argv[1]) >= parseFloat(process.argv[2]) ? 0 : 1)" "$1" "$2" 2>/dev/null || \
  awk -v a="$1" -v b="$2" 'BEGIN { exit (a >= b ? 0 : 1) }'
}

# ── Decision Logic ────────────────────────────────────────────
log() {
  $VERBOSE && echo "$*" >&2 || true
}

case "$EVENT_TYPE" in

  win)
    # Win > MIN_WIN_ETH → post
    if float_gte "$EARNINGS" "$MIN_WIN_ETH"; then
      log "✅ Win of ${EARNINGS} ETH >= threshold ${MIN_WIN_ETH} ETH → post it"
      exit 0
    else
      log "⏭️  Win of ${EARNINGS} ETH < threshold ${MIN_WIN_ETH} ETH → skip"
      exit 1
    fi
    ;;

  levelup)
    # Any level up is post-worthy (especially milestone levels)
    if [[ "$LEVEL" -ge "$MIN_LEVELUP" ]] 2>/dev/null; then
      # Extra emphasis on milestone levels (5, 10, 25, 50, 100)
      if [[ "$LEVEL" -eq 5 || "$LEVEL" -eq 10 || "$LEVEL" -eq 25 || \
            "$LEVEL" -eq 50 || "$LEVEL" -eq 100 ]]; then
        log "✅ Milestone level ${LEVEL} → definitely post it"
      else
        log "✅ Level up to ${LEVEL} → post it"
      fi
      exit 0
    else
      log "⏭️  Level $LEVEL not worth posting → skip"
      exit 1
    fi
    ;;

  first-game)
    # First game ever played → always post
    FIRST_GAME_FLAG="${HOME}/.config/social-poster/.first-game-posted"
    if [[ -f "$FIRST_GAME_FLAG" ]]; then
      log "⏭️  First game already posted → skip"
      exit 1
    else
      log "✅ First game played → post it (creating flag file)"
      touch "$FIRST_GAME_FLAG"
      exit 0
    fi
    ;;

  trade)
    # Trade > MIN_TRADE_ETH → post
    if float_gte "$AMOUNT" "$MIN_TRADE_ETH"; then
      log "✅ Trade of ${AMOUNT} ETH >= threshold ${MIN_TRADE_ETH} ETH → post it"
      exit 0
    else
      log "⏭️  Trade of ${AMOUNT} ETH < threshold ${MIN_TRADE_ETH} ETH → skip"
      exit 1
    fi
    ;;

  loss | other | *)
    log "⏭️  Event type '${EVENT_TYPE}' → skip"
    exit 1
    ;;

esac
