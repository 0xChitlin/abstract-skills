#!/usr/bin/env bash
# set-schedule.sh — Configure social poster posting frequency
#
# Usage:
#   ./set-schedule.sh [options]
#
# Options:
#   --max-per-day <n>       Max posts per day (default: 3)
#   --cooldown-hours <h>    Min hours between posts (default: 4)
#   --agent-name <name>     Your agent name (e.g. "mojo")
#   --profile <name>        Browser profile: clawwallet|openclaw (default: clawwallet)
#   --min-win-eth <eth>     Min ETH win to post (default: 0.01)
#   --min-trade-eth <eth>   Min ETH trade to post (default: 0.05)
#   --show                  Show current config

set -euo pipefail

CONFIG_DIR="${HOME}/.config/social-poster"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "$CONFIG_DIR"

# Load current config
if [[ -f "$CONFIG_FILE" ]]; then
  CURRENT=$(cat "$CONFIG_FILE")
else
  CURRENT='{}'
fi

# ── Parse Args ────────────────────────────────────────────────
SHOW_ONLY=false
MAX_PER_DAY=""
COOLDOWN_HOURS=""
AGENT_NAME=""
PROFILE=""
MIN_WIN_ETH=""
MIN_TRADE_ETH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-per-day)     MAX_PER_DAY="$2";     shift 2 ;;
    --cooldown-hours)  COOLDOWN_HOURS="$2";  shift 2 ;;
    --agent-name)      AGENT_NAME="$2";      shift 2 ;;
    --profile)         PROFILE="$2";         shift 2 ;;
    --min-win-eth)     MIN_WIN_ETH="$2";     shift 2 ;;
    --min-trade-eth)   MIN_TRADE_ETH="$2";   shift 2 ;;
    --show)            SHOW_ONLY=true;        shift   ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Show current config and exit
if $SHOW_ONLY; then
  if [[ -f "$CONFIG_FILE" ]]; then
    echo "📋 Current social-poster config:"
    cat "$CONFIG_FILE" | python3 -m json.tool 2>/dev/null || cat "$CONFIG_FILE"
  else
    echo "No config file found at $CONFIG_FILE"
    echo "Run with options to create one."
  fi
  exit 0
fi

# ── Build new config (merge with existing) ────────────────────
NEW_CONFIG=$(echo "$CURRENT" | python3 - <<'PYEOF'
import sys, json
cur = json.load(sys.stdin)
import os

updates = {}
if os.environ.get('MAX_PER_DAY'):     updates['max_posts_per_day'] = int(os.environ['MAX_PER_DAY'])
if os.environ.get('COOLDOWN_HOURS'):  updates['cooldown_hours'] = int(os.environ['COOLDOWN_HOURS'])
if os.environ.get('AGENT_NAME'):      updates['agent_name'] = os.environ['AGENT_NAME']
if os.environ.get('PROFILE'):
    p = os.environ['PROFILE']
    updates['twitter_profile'] = p
    updates['twitter_cdp_port'] = 3012 if p == 'clawwallet' else 3011
if os.environ.get('MIN_WIN_ETH'):     updates['min_earnings_eth'] = float(os.environ['MIN_WIN_ETH'])
if os.environ.get('MIN_TRADE_ETH'):   updates['min_trade_eth'] = float(os.environ['MIN_TRADE_ETH'])

cur.update(updates)

# Set defaults for missing fields
cur.setdefault('max_posts_per_day', 3)
cur.setdefault('cooldown_hours', 4)
cur.setdefault('agent_name', 'agent')
cur.setdefault('twitter_profile', 'clawwallet')
cur.setdefault('twitter_cdp_port', 3012)
cur.setdefault('mention', '@ClawWalletBuzz')
cur.setdefault('min_earnings_eth', 0.01)
cur.setdefault('min_trade_eth', 0.05)

print(json.dumps(cur, indent=2))
PYEOF
)

export MAX_PER_DAY COOLDOWN_HOURS AGENT_NAME PROFILE MIN_WIN_ETH MIN_TRADE_ETH

NEW_CONFIG=$(echo "$CURRENT" | MAX_PER_DAY="$MAX_PER_DAY" COOLDOWN_HOURS="$COOLDOWN_HOURS" \
  AGENT_NAME="$AGENT_NAME" PROFILE="$PROFILE" MIN_WIN_ETH="$MIN_WIN_ETH" \
  MIN_TRADE_ETH="$MIN_TRADE_ETH" python3 -c "
import sys, json, os
cur = json.load(sys.stdin)
updates = {}
if os.environ.get('MAX_PER_DAY'):     updates['max_posts_per_day'] = int(os.environ['MAX_PER_DAY'])
if os.environ.get('COOLDOWN_HOURS'):  updates['cooldown_hours'] = int(os.environ['COOLDOWN_HOURS'])
if os.environ.get('AGENT_NAME'):      updates['agent_name'] = os.environ['AGENT_NAME']
if os.environ.get('PROFILE'):
    p = os.environ['PROFILE']
    updates['twitter_profile'] = p
    updates['twitter_cdp_port'] = 3012 if p == 'clawwallet' else 3011
if os.environ.get('MIN_WIN_ETH'):     updates['min_earnings_eth'] = float(os.environ['MIN_WIN_ETH'])
if os.environ.get('MIN_TRADE_ETH'):   updates['min_trade_eth'] = float(os.environ['MIN_TRADE_ETH'])
cur.update(updates)
cur.setdefault('max_posts_per_day', 3)
cur.setdefault('cooldown_hours', 4)
cur.setdefault('agent_name', 'agent')
cur.setdefault('twitter_profile', 'clawwallet')
cur.setdefault('twitter_cdp_port', 3012)
cur.setdefault('mention', '@ClawWalletBuzz')
cur.setdefault('min_earnings_eth', 0.01)
cur.setdefault('min_trade_eth', 0.05)
print(json.dumps(cur, indent=2))
")

echo "$NEW_CONFIG" > "$CONFIG_FILE"

echo "✅ Config updated at $CONFIG_FILE"
echo ""
cat "$CONFIG_FILE"
