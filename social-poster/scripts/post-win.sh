#!/usr/bin/env bash
# post-win.sh — Post an agent win to X/Twitter via goat-x CDP pattern
#
# Usage:
#   ./post-win.sh <game_name> <result> <earnings_eth>
#
# Examples:
#   ./post-win.sh gigaverse "cleared floor 7" 0.025
#   ./post-win.sh blinko "hit 11x multiplier" 0.05
#
# Tweet format:
#   {agent_name}.claw just {result} on {game_name}. Earned {amount} ETH.
#   Powered by @ClawWalletBuzz 🤖⚡

set -euo pipefail

# ── Args ──────────────────────────────────────────────────────
GAME_NAME="${1:-}"
RESULT="${2:-}"
EARNINGS="${3:-0}"

if [[ -z "$GAME_NAME" || -z "$RESULT" ]]; then
  echo "Usage: $0 <game_name> <result> [earnings_eth]" >&2
  exit 1
fi

# ── Config ────────────────────────────────────────────────────
CONFIG_DIR="${HOME}/.config/social-poster"
CONFIG_FILE="${CONFIG_DIR}/config.json"
STATE_FILE="${CONFIG_DIR}/state.json"
GOAT_X_DIR="${GOAT_X_DIR:-/Users/algohussle/.openclaw/skills/goat-x}"

# Load config with defaults
if [[ -f "$CONFIG_FILE" ]]; then
  AGENT_NAME=$(jq -r '.agent_name // "agent"' "$CONFIG_FILE")
  MAX_POSTS_PER_DAY=$(jq -r '.max_posts_per_day // 3' "$CONFIG_FILE")
  COOLDOWN_HOURS=$(jq -r '.cooldown_hours // 4' "$CONFIG_FILE")
  CDP_PORT=$(jq -r '.twitter_cdp_port // 3012' "$CONFIG_FILE")
  MENTION=$(jq -r '.mention // "@ClawWalletBuzz"' "$CONFIG_FILE")
else
  AGENT_NAME="${AGENT_NAME:-agent}"
  MAX_POSTS_PER_DAY=3
  COOLDOWN_HOURS=4
  CDP_PORT=3012
  MENTION="@ClawWalletBuzz"
fi

# ── Rate Limit Check ──────────────────────────────────────────
mkdir -p "$CONFIG_DIR"

TODAY=$(date -u +%Y-%m-%d)
NOW_TS=$(date -u +%s)

if [[ -f "$STATE_FILE" ]]; then
  DAILY_RESET=$(jq -r '.dailyReset // ""' "$STATE_FILE")
  POSTS_TODAY=$(jq -r '.postsToday // 0' "$STATE_FILE")
  LAST_POST_TS=$(jq -r '.lastPostTimestamp // 0' "$STATE_FILE")
else
  DAILY_RESET=""
  POSTS_TODAY=0
  LAST_POST_TS=0
fi

# Reset daily counter if new day
if [[ "$DAILY_RESET" != "$TODAY" ]]; then
  POSTS_TODAY=0
  DAILY_RESET="$TODAY"
fi

# Check daily limit
if [[ $POSTS_TODAY -ge $MAX_POSTS_PER_DAY ]]; then
  echo "⏭️  Rate limit: already posted $POSTS_TODAY/$MAX_POSTS_PER_DAY times today. Skipping." >&2
  exit 2
fi

# Check cooldown
COOLDOWN_SECS=$((COOLDOWN_HOURS * 3600))
ELAPSED=$((NOW_TS - LAST_POST_TS))
if [[ $LAST_POST_TS -gt 0 && $ELAPSED -lt $COOLDOWN_SECS ]]; then
  WAIT_MINS=$(( (COOLDOWN_SECS - ELAPSED) / 60 ))
  echo "⏭️  Cooldown: ${WAIT_MINS}m remaining before next post. Skipping." >&2
  exit 2
fi

# ── Format Tweet ──────────────────────────────────────────────
# Format earnings
if [[ "$EARNINGS" == "0" || "$EARNINGS" == "0.0" ]]; then
  EARNINGS_STR=""
  TWEET="${AGENT_NAME}.claw just ${RESULT} on ${GAME_NAME}.
Powered by ${MENTION} 🤖⚡"
else
  TWEET="${AGENT_NAME}.claw just ${RESULT} on ${GAME_NAME}. Earned ${EARNINGS} ETH.
Powered by ${MENTION} 🤖⚡"
fi

# Enforce Twitter 280 char limit
if [[ ${#TWEET} -gt 280 ]]; then
  # Truncate result if too long
  MAX_RESULT_LEN=$(( 280 - ${#AGENT_NAME} - ${#GAME_NAME} - ${#MENTION} - 60 ))
  RESULT="${RESULT:0:$MAX_RESULT_LEN}..."
  TWEET="${AGENT_NAME}.claw just ${RESULT} on ${GAME_NAME}.
Powered by ${MENTION} 🤖⚡"
fi

echo "📝 Tweet: $TWEET"

# ── Post via goat-x ───────────────────────────────────────────
GOAT_X_BIN="${GOAT_X_DIR}/src/browser-x.ts"
POST_SUCCESS=false

if [[ -f "$GOAT_X_BIN" ]] && command -v npx &>/dev/null; then
  echo "🚀 Posting via goat-x CDP (port ${CDP_PORT})..."

  # Temporarily override CDP port if different from default
  if [[ "$CDP_PORT" != "3011" ]]; then
    # browser-x.ts reads CDP_URL from env or defaults to 3011
    export CDP_PORT_OVERRIDE="$CDP_PORT"
  fi

  # Run goat-x tweet command
  if GOAT_X_OUTPUT=$(cd "$GOAT_X_DIR" && CDP_URL="http://127.0.0.1:${CDP_PORT}" npx ts-node src/browser-x.ts tweet "$TWEET" 2>&1); then
    echo "✅ Posted: $GOAT_X_OUTPUT"
    POST_SUCCESS=true
  else
    echo "⚠️  goat-x failed: $GOAT_X_OUTPUT" >&2
    echo "💡 Falling back to manual tweet URL..." >&2
  fi
else
  echo "⚠️  goat-x not found at $GOAT_X_DIR" >&2
fi

# ── Fallback: Twitter Intent URL ──────────────────────────────
if [[ "$POST_SUCCESS" == "false" ]]; then
  ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$TWEET" 2>/dev/null || \
            node -e "process.stdout.write(encodeURIComponent(process.argv[1]))" "$TWEET" 2>/dev/null || \
            echo "$TWEET" | sed 's/ /%20/g; s/#/%23/g; s/@/%40/g; s/\n/%0A/g')
  INTENT_URL="https://x.com/intent/tweet?text=${ENCODED}"
  echo ""
  echo "📋 Manual tweet URL (open in browser):"
  echo "$INTENT_URL"
  echo ""
  # Still update state so we track the attempt
  POST_SUCCESS=true
fi

# ── Update State ──────────────────────────────────────────────
if [[ "$POST_SUCCESS" == "true" ]]; then
  POSTS_TODAY=$((POSTS_TODAY + 1))
  NOW_TS=$(date -u +%s)

  cat > "$STATE_FILE" <<EOF
{
  "postsToday": $POSTS_TODAY,
  "lastPostTimestamp": $NOW_TS,
  "lastPostContent": $(echo "$TWEET" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"$TWEET\""),
  "dailyReset": "$TODAY"
}
EOF

  echo "📊 Posts today: $POSTS_TODAY/$MAX_POSTS_PER_DAY"
fi

exit 0
