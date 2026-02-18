#!/usr/bin/env bash
# post-update.sh — Post a general agent update to X/Twitter
#
# Usage:
#   ./post-update.sh "<message>"
#
# The @ClawWalletBuzz mention is appended automatically unless already present.

set -euo pipefail

MESSAGE="${1:-}"
if [[ -z "$MESSAGE" ]]; then
  echo "Usage: $0 \"<message>\"" >&2
  exit 1
fi

CONFIG_FILE="${HOME}/.config/social-poster/config.json"
MENTION=$(jq -r '.mention // "@ClawWalletBuzz"' "$CONFIG_FILE" 2>/dev/null || echo "@ClawWalletBuzz")

# Append mention if not already present
if [[ "$MESSAGE" != *"$MENTION"* ]]; then
  TWEET="${MESSAGE}
Powered by ${MENTION} 🤖⚡"
else
  TWEET="$MESSAGE"
fi

# ── Rate Limit + Post (shared logic) ─────────────────────────
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
  echo "⏭️  Rate limit: $POSTS_TODAY/$MAX_POSTS_PER_DAY posts today." >&2; exit 2
fi

COOLDOWN_SECS=$((COOLDOWN_HOURS * 3600))
ELAPSED=$((NOW_TS - LAST_POST_TS))
if [[ $LAST_POST_TS -gt 0 && $ELAPSED -lt $COOLDOWN_SECS ]]; then
  echo "⏭️  Cooldown active." >&2; exit 2
fi

echo "📝 Tweet: $TWEET"
POST_SUCCESS=false

if [[ -f "${GOAT_X_DIR}/src/browser-x.ts" ]] && command -v npx &>/dev/null; then
  echo "🚀 Posting via goat-x CDP (port ${CDP_PORT})..."
  if OUTPUT=$(cd "$GOAT_X_DIR" && CDP_URL="http://127.0.0.1:${CDP_PORT}" npx ts-node src/browser-x.ts tweet "$TWEET" 2>&1); then
    echo "✅ Posted: $OUTPUT"; POST_SUCCESS=true
  else
    echo "⚠️  goat-x failed: $OUTPUT" >&2
  fi
fi

if [[ "$POST_SUCCESS" == "false" ]]; then
  ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$TWEET" 2>/dev/null || echo "$TWEET")
  echo "📋 Manual: https://x.com/intent/tweet?text=${ENCODED}"
  POST_SUCCESS=true
fi

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
