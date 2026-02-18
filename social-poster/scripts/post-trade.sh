#!/usr/bin/env bash
# post-trade.sh — Post a DeFi trade to X/Twitter via goat-x CDP pattern
#
# Usage:
#   ./post-trade.sh <protocol> <action> [amount_eth]
#
# Examples:
#   ./post-trade.sh clawdex "swapped ETH→USDC" 0.1
#   ./post-trade.sh clankerzone "launched \$MOJO token" 0

set -euo pipefail

PROTOCOL="${1:-}"
ACTION="${2:-}"
AMOUNT="${3:-0}"

if [[ -z "$PROTOCOL" || -z "$ACTION" ]]; then
  echo "Usage: $0 <protocol> <action> [amount_eth]" >&2
  exit 1
fi

CONFIG_FILE="${HOME}/.config/social-poster/config.json"
AGENT_NAME=$(jq -r '.agent_name // "agent"' "$CONFIG_FILE" 2>/dev/null || echo "agent")
MENTION=$(jq -r '.mention // "@ClawWalletBuzz"' "$CONFIG_FILE" 2>/dev/null || echo "@ClawWalletBuzz")

# Format tweet
if [[ "$AMOUNT" == "0" || "$AMOUNT" == "0.0" ]]; then
  RESULT="${ACTION} on ${PROTOCOL}. Running on Abstract Chain."
else
  RESULT="${ACTION} on ${PROTOCOL} (${AMOUNT} ETH). Running on Abstract Chain."
fi

# Reuse post-win.sh for rate limiting + posting (earnings=0 suppresses ETH line)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# We build a custom tweet and bypass post-win's template by calling goat-x directly
# while still respecting the rate limit state.

# ── Rate Limit Check (shared with post-win.sh) ────────────────
CONFIG_DIR="${HOME}/.config/social-poster"
STATE_FILE="${CONFIG_DIR}/state.json"
MAX_POSTS_PER_DAY=$(jq -r '.max_posts_per_day // 3' "$CONFIG_FILE" 2>/dev/null || echo 3)
COOLDOWN_HOURS=$(jq -r '.cooldown_hours // 4' "$CONFIG_FILE" 2>/dev/null || echo 4)
CDP_PORT=$(jq -r '.twitter_cdp_port // 3012' "$CONFIG_FILE" 2>/dev/null || echo 3012)
GOAT_X_DIR="${GOAT_X_DIR:-/Users/algohussle/.openclaw/skills/goat-x}"

mkdir -p "$CONFIG_DIR"
TODAY=$(date -u +%Y-%m-%d)
NOW_TS=$(date -u +%s)

if [[ -f "$STATE_FILE" ]]; then
  DAILY_RESET=$(jq -r '.dailyReset // ""' "$STATE_FILE")
  POSTS_TODAY=$(jq -r '.postsToday // 0' "$STATE_FILE")
  LAST_POST_TS=$(jq -r '.lastPostTimestamp // 0' "$STATE_FILE")
else
  DAILY_RESET=""; POSTS_TODAY=0; LAST_POST_TS=0
fi

[[ "$DAILY_RESET" != "$TODAY" ]] && POSTS_TODAY=0 && DAILY_RESET="$TODAY"

if [[ $POSTS_TODAY -ge $MAX_POSTS_PER_DAY ]]; then
  echo "⏭️  Rate limit: $POSTS_TODAY/$MAX_POSTS_PER_DAY posts today. Skipping." >&2
  exit 2
fi

COOLDOWN_SECS=$((COOLDOWN_HOURS * 3600))
ELAPSED=$((NOW_TS - LAST_POST_TS))
if [[ $LAST_POST_TS -gt 0 && $ELAPSED -lt $COOLDOWN_SECS ]]; then
  WAIT_MINS=$(( (COOLDOWN_SECS - ELAPSED) / 60 ))
  echo "⏭️  Cooldown: ${WAIT_MINS}m remaining. Skipping." >&2
  exit 2
fi

# ── Format & Post ─────────────────────────────────────────────
TWEET="${AGENT_NAME}.claw just ${RESULT}
Powered by ${MENTION} 🤖⚡"

echo "📝 Tweet: $TWEET"

POST_SUCCESS=false
GOAT_X_BIN="${GOAT_X_DIR}/src/browser-x.ts"

if [[ -f "$GOAT_X_BIN" ]] && command -v npx &>/dev/null; then
  echo "🚀 Posting via goat-x CDP (port ${CDP_PORT})..."
  if GOAT_X_OUTPUT=$(cd "$GOAT_X_DIR" && CDP_URL="http://127.0.0.1:${CDP_PORT}" npx ts-node src/browser-x.ts tweet "$TWEET" 2>&1); then
    echo "✅ Posted: $GOAT_X_OUTPUT"
    POST_SUCCESS=true
  else
    echo "⚠️  goat-x failed: $GOAT_X_OUTPUT" >&2
  fi
fi

if [[ "$POST_SUCCESS" == "false" ]]; then
  ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$TWEET" 2>/dev/null || echo "$TWEET")
  echo "📋 Manual: https://x.com/intent/tweet?text=${ENCODED}"
  POST_SUCCESS=true
fi

# Update state
POSTS_TODAY=$((POSTS_TODAY + 1))
NOW_TS=$(date -u +%s)
cat > "$STATE_FILE" <<EOF
{
  "postsToday": $POSTS_TODAY,
  "lastPostTimestamp": $NOW_TS,
  "lastPostContent": $(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$TWEET" 2>/dev/null || echo "\"$TWEET\""),
  "dailyReset": "$TODAY"
}
EOF

echo "📊 Posts today: $POSTS_TODAY/$MAX_POSTS_PER_DAY"
exit 0
