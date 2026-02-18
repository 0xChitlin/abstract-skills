#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# TokenLauncher — promote-launch.sh
# Posts a launch announcement to X/Twitter via goat-x CDP pattern.
#
# Usage:
#   ./promote-launch.sh               # Promotes latest launch from history
#   ./promote-launch.sh 0xTokenAddress  # Promotes specific token
#
# Requires:
#   - goat-x skill installed at ~/.openclaw/skills/goat-x
#   - OpenClaw browser running with X logged in (clawwallet or openclaw profile)
#   - launch-history.json with at least one entry
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
HISTORY_FILE="${TOKENLAUNCHER_HISTORY:-$HOME/.config/tokenlauncher/launch-history.json}"
STATE_FILE="${TOKENLAUNCHER_STATE:-$HOME/.config/tokenlauncher/state.json}"
CONFIG_FILE="${TOKENLAUNCHER_CONFIG:-$HOME/.config/tokenlauncher/config.json}"
RATE_LIMIT_SECONDS=900   # 15 minutes between promotes

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[tokenlauncher/promote]${RESET} $*"; }
ok()   { echo -e "${GREEN}[✓]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
die()  { echo -e "${RED}[✗] ERROR:${RESET} $*" >&2; exit 1; }

TARGET_ADDRESS="${1:-}"

# ── Rate limit check ──────────────────────────────────────────────────────────
NOW=$(date +%s)
if [[ -f "$STATE_FILE" ]]; then
  LAST_PROMOTE=$(jq -r '.lastPromoteTimestamp // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  ELAPSED=$(( NOW - LAST_PROMOTE ))
  if [[ "$ELAPSED" -lt "$RATE_LIMIT_SECONDS" ]]; then
    WAIT=$(( RATE_LIMIT_SECONDS - ELAPSED ))
    warn "Rate limit: last promote was ${ELAPSED}s ago. Wait ${WAIT}s more (or delete $STATE_FILE to reset)."
    exit 0
  fi
fi

# ── Load launch history ───────────────────────────────────────────────────────
[[ -f "$HISTORY_FILE" ]] || die "No launch history found at $HISTORY_FILE. Run launch-token.sh first."

ENTRY=""
if [[ -n "$TARGET_ADDRESS" ]]; then
  ENTRY=$(jq --arg addr "$TARGET_ADDRESS" '.[] | select(.tokenAddress == $addr) | . ' "$HISTORY_FILE" | jq -s '.[0]' 2>/dev/null)
  [[ "$ENTRY" == "null" || -z "$ENTRY" ]] && die "Token $TARGET_ADDRESS not found in launch history."
else
  ENTRY=$(jq '.[-1]' "$HISTORY_FILE")
  [[ "$ENTRY" == "null" || -z "$ENTRY" ]] && die "Launch history is empty."
fi

TOKEN_SYMBOL=$(echo  "$ENTRY" | jq -r '.tokenSymbol')
TOKEN_ADDRESS=$(echo "$ENTRY" | jq -r '.tokenAddress')
LIQUIDITY_ETH=$(echo "$ENTRY" | jq -r '.liquidityETH')
TX_HASH=$(echo       "$ENTRY" | jq -r '.txHash')

# ── Load twitter handle from config ──────────────────────────────────────────
TWITTER_HANDLE="@ClawWalletHQ"
if [[ -f "$CONFIG_FILE" ]]; then
  HANDLE_FROM_CONFIG=$(jq -r '.twitterHandle // empty' "$CONFIG_FILE" 2>/dev/null || true)
  [[ -n "$HANDLE_FROM_CONFIG" ]] && TWITTER_HANDLE="$HANDLE_FROM_CONFIG"
fi

# ── Build tweet text ──────────────────────────────────────────────────────────
TWEET="🚀 Just launched \$${TOKEN_SYMBOL} on Abstract Chain via @ClawWalletHQ!

Token: ${TOKEN_ADDRESS}
LP seeded with ${LIQUIDITY_ETH} ETH
abscan.org/token/${TOKEN_ADDRESS}

#AbstractChain #DeFi #ClawWallet"

log "Preparing promotion tweet for \$$TOKEN_SYMBOL..."
echo ""
echo -e "${BOLD}─── Tweet Preview ───────────────────────────────────${RESET}"
echo "$TWEET"
echo -e "${BOLD}─────────────────────────────────────────────────────${RESET}"
echo ""

# ── Check goat-x availability ─────────────────────────────────────────────────
GOAT_X_PATH="${HOME}/.openclaw/skills/goat-x"
GOAT_X_SCRIPT=""

# Try common goat-x script locations
for candidate in \
  "$GOAT_X_PATH/scripts/post-tweet.sh" \
  "$GOAT_X_PATH/scripts/tweet.sh" \
  "$GOAT_X_PATH/post.sh"; do
  if [[ -f "$candidate" ]]; then
    GOAT_X_SCRIPT="$candidate"
    break
  fi
done

# ── Post via goat-x CDP ───────────────────────────────────────────────────────
if [[ -n "$GOAT_X_SCRIPT" ]]; then
  log "Posting via goat-x CDP ($GOAT_X_SCRIPT)..."
  if bash "$GOAT_X_SCRIPT" "$TWEET"; then
    ok "Tweet posted successfully!"
  else
    warn "goat-x script returned non-zero. Check browser session."
    warn "Tweet text saved to state for manual posting."
  fi
else
  # goat-x not installed — try openclaw browser CDP direct
  log "goat-x script not found at $GOAT_X_PATH — attempting OpenClaw browser CDP..."

  # Check if openclaw CLI is available
  if command -v openclaw >/dev/null 2>&1; then
    log "Using openclaw browser to post tweet..."
    # Use OpenClaw's exec to drive the browser
    # This mirrors the goat-x CDP pattern used by @ClawWallet51335
    TWEET_ESCAPED=$(echo "$TWEET" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || \
                    echo "\"$TWEET\"")
    warn "goat-x skill not installed. Install it from abstract-skills/social-poster for full X automation."
    warn "Manual post required. Copy this tweet:"
    echo ""
    echo "$TWEET"
    echo ""
  else
    warn "Neither goat-x nor openclaw CLI found."
    warn "Manual post required. Copy this tweet:"
    echo ""
    echo "$TWEET"
    echo ""
  fi
fi

# ── Update state file ─────────────────────────────────────────────────────────
mkdir -p "$(dirname "$STATE_FILE")"
STATE_JSON=$(jq -n \
  --argjson ts "$NOW" \
  --arg sym "$TOKEN_SYMBOL" \
  --arg addr "$TOKEN_ADDRESS" \
  --arg tweet "$TWEET" \
  '{
    lastPromoteTimestamp: $ts,
    lastPromotedSymbol:   $sym,
    lastPromotedAddress:  $addr,
    lastTweetText:        $tweet
  }')
echo "$STATE_JSON" > "$STATE_FILE"
ok "Promote state saved to $STATE_FILE"

echo ""
ok "Promotion complete for \$$TOKEN_SYMBOL"
echo -e "  ${BOLD}Abscan:${RESET} ${CYAN}https://abscan.org/token/$TOKEN_ADDRESS${RESET}"
echo -e "  ${BOLD}TX:${RESET}     ${CYAN}https://abscan.org/tx/$TX_HASH${RESET}"
echo ""
