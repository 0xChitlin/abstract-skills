#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# MarketBot — post-content.sh
# Posts content to X/Twitter via goat-x CDP intercept
# TikTok/IG: saves to drafts with "Manual post required" note
# Respects rate limits: max 3 posts/day on X
#
# Usage:
#   post-content.sh                          # auto-picks next draft
#   post-content.sh --batch batch_20250217   # specific batch
#   post-content.sh --variant v1             # specific variant
#   post-content.sh --text "Custom tweet"    # direct text post
# ─────────────────────────────────────────────────────────────

set -euo pipefail

CONFIG_DIR="${HOME}/.config/marketbot"
CONFIG_FILE="${CONFIG_DIR}/config.json"
DRAFTS_DIR="${CONFIG_DIR}/drafts"
POST_HISTORY="${CONFIG_DIR}/post-history.json"
STATE_FILE="${CONFIG_DIR}/state.json"
LOG_FILE="${CONFIG_DIR}/post.log"
GOAT_X_DIR="/Users/algohussle/.openclaw/skills/goat-x"

# Parse args
BATCH_ID=""
VARIANT_ID=""
CUSTOM_TEXT=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch)   BATCH_ID="$2"; shift 2 ;;
    --variant) VARIANT_ID="$2"; shift 2 ;;
    --text)    CUSTOM_TEXT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) shift ;;
  esac
done

mkdir -p "${CONFIG_DIR}"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }

# ── Load config ───────────────────────────────────────────────
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "❌ No config. Copy config.example.json to ~/.config/marketbot/config.json"
  exit 1
fi

PLATFORMS=$(jq -r '.platforms | join(",")' "${CONFIG_FILE}")
MAX_POSTS_PER_DAY=$(jq -r '.posts_per_day // 2' "${CONFIG_FILE}")
X_HANDLE=$(jq -r '.x_handle // ""' "${CONFIG_FILE}")
PRODUCT_URL=$(jq -r '.product_url // ""' "${CONFIG_FILE}")

# ── Check rate limits ─────────────────────────────────────────
TODAY=$(date +"%Y-%m-%d")

# Initialize state file
if [[ ! -f "${STATE_FILE}" ]]; then
  echo "{\"posts_today\": {}, \"last_reset\": \"${TODAY}\"}" > "${STATE_FILE}"
fi

# Reset daily counter if new day
LAST_RESET=$(jq -r '.last_reset // ""' "${STATE_FILE}")
if [[ "${LAST_RESET}" != "${TODAY}" ]]; then
  log "📅 New day — resetting daily post counter"
  jq --arg today "${TODAY}" '.posts_today = {} | .last_reset = $today' "${STATE_FILE}" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "${STATE_FILE}"
fi

X_POSTS_TODAY=$(jq -r --arg date "${TODAY}" '.posts_today[$date] // 0' "${STATE_FILE}")
log "📊 Posts today: ${X_POSTS_TODAY}/${MAX_POSTS_PER_DAY}"

if (( X_POSTS_TODAY >= MAX_POSTS_PER_DAY )); then
  log "🚫 Daily limit reached (${MAX_POSTS_PER_DAY} posts). Skipping."
  log "   Next window: tomorrow. Use --dry-run to preview content anyway."
  if [[ "${DRY_RUN}" == "false" ]]; then
    exit 0
  fi
fi

# ── Check quiet hours ─────────────────────────────────────────
QUIET_START=$(jq -r '.quiet_hours.start // 23' "${CONFIG_FILE}" 2>/dev/null || echo 23)
QUIET_END=$(jq -r '.quiet_hours.end // 8' "${CONFIG_FILE}" 2>/dev/null || echo 8)
CURRENT_HOUR=$(date +"%H" | sed 's/^0//')

in_quiet_hours() {
  local h=$1 s=$2 e=$3
  if (( s > e )); then
    (( h >= s || h < e ))
  else
    (( h >= s && h < e ))
  fi
}

if in_quiet_hours "${CURRENT_HOUR}" "${QUIET_START}" "${QUIET_END}" && [[ "${DRY_RUN}" == "false" ]]; then
  log "🌙 Quiet hours (${QUIET_START}:00–${QUIET_END}:00). Skipping post."
  exit 0
fi

# ── Find content to post ──────────────────────────────────────
POST_TEXT=""
POST_SOURCE=""

if [[ -n "${CUSTOM_TEXT}" ]]; then
  POST_TEXT="${CUSTOM_TEXT}"
  POST_SOURCE="custom"
  log "📝 Using custom text (${#POST_TEXT} chars)"

elif [[ -n "${BATCH_ID}" ]]; then
  BATCH_FILE="${DRAFTS_DIR}/${BATCH_ID}.json"
  if [[ ! -f "${BATCH_FILE}" ]]; then
    log "❌ Batch not found: ${BATCH_FILE}"
    exit 1
  fi
  VARIANT="${VARIANT_ID:-v1}"
  POST_TEXT=$(jq -r --arg vid "${VARIANT}" '
    .variants[] | select(.id == $vid) | .platform_content.x
  ' "${BATCH_FILE}" 2>/dev/null || echo "")
  POST_SOURCE="${BATCH_ID}:${VARIANT}"
  log "📦 Using batch ${BATCH_ID}, variant ${VARIANT}"

else
  # Auto-pick: find latest unposted draft
  log "🔍 Finding next unposted draft…"
  LATEST_BATCH=$(ls -t "${DRAFTS_DIR}"/*.json 2>/dev/null | grep -v "_x_drafts\|_tiktok" | head -1 || echo "")

  if [[ -z "${LATEST_BATCH}" ]]; then
    log "❌ No drafts found. Run create-content.sh first."
    exit 1
  fi

  # Find first unposted variant
  BATCH_ID=$(jq -r '.batch_id' "${LATEST_BATCH}")
  POSTED_IDS=$(jq -r --arg bid "${BATCH_ID}" '
    [.[] | select(.batch_id == $bid) | .variant_id] | join(",")
  ' "${POST_HISTORY}" 2>/dev/null || echo "")

  POST_TEXT=$(jq -r --arg posted "${POSTED_IDS}" '
    .variants[] |
    select((.id | IN(($posted | split(","))[])) | not) |
    .platform_content.x
  ' "${LATEST_BATCH}" 2>/dev/null | head -1 || echo "")

  VARIANT_ID=$(jq -r --arg posted "${POSTED_IDS}" '
    [.variants[] | select((.id | IN(($posted | split(","))[])) | not) | .id][0]
  ' "${LATEST_BATCH}" 2>/dev/null || echo "v1")

  POST_SOURCE="${BATCH_ID}:${VARIANT_ID}"
  log "📦 Auto-selected: ${POST_SOURCE}"
fi

if [[ -z "${POST_TEXT}" ]]; then
  log "❌ No post text found. Check your drafts."
  exit 1
fi

# Truncate if > 280 chars (safety)
if (( ${#POST_TEXT} > 280 )); then
  POST_TEXT="${POST_TEXT:0:277}..."
  log "✂️  Text truncated to 280 chars"
fi

log "📤 Content to post (${#POST_TEXT} chars):"
log "   ${POST_TEXT:0:100}…"

if [[ "${DRY_RUN}" == "true" ]]; then
  log ""
  log "🔍 DRY RUN — not posting. Full text:"
  echo ""
  echo "${POST_TEXT}"
  echo ""
  log "✅ Dry run complete."
  exit 0
fi

# ── Post to X via goat-x ──────────────────────────────────────
log "🐦 Posting to X/Twitter via goat-x CDP…"
cd "${GOAT_X_DIR}" || { log "❌ goat-x not found"; exit 1; }

POST_RESULT=$(node src/cli.ts tweet \
  --text "${POST_TEXT}" \
  --profile clawwallet \
  2>>"${LOG_FILE}" || echo "ERROR")

if echo "${POST_RESULT}" | grep -qi "error\|failed\|exception"; then
  log "❌ Post failed: ${POST_RESULT}"
  exit 1
fi

POST_URL=$(echo "${POST_RESULT}" | grep -oE 'https://x\.com/[^ ]+' | head -1 || echo "")
TWEET_ID=$(echo "${POST_URL}" | grep -oE '/status/[0-9]+' | tr -d '/status/' || echo "")

log "✅ Posted successfully!"
[[ -n "${POST_URL}" ]] && log "   URL: ${POST_URL}"

# ── Update state + history ────────────────────────────────────
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Increment daily counter
NEW_COUNT=$(( X_POSTS_TODAY + 1 ))
jq --arg today "${TODAY}" --argjson count "${NEW_COUNT}" \
  '.posts_today[$today] = $count' "${STATE_FILE}" > "${STATE_FILE}.tmp"
mv "${STATE_FILE}.tmp" "${STATE_FILE}"

# Append to post history
POST_ENTRY=$(cat <<JSON
{
  "post_id": "$(date +%s)",
  "tweet_id": "${TWEET_ID}",
  "batch_id": "${BATCH_ID}",
  "variant_id": "${VARIANT_ID}",
  "source": "${POST_SOURCE}",
  "platform": "x",
  "text": $(echo "${POST_TEXT}" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"),
  "url": "${POST_URL}",
  "posted_at": "${TIMESTAMP}",
  "handle": "@${X_HANDLE}",
  "engagement": {
    "likes": 0, "replies": 0, "reposts": 0, "views": 0
  },
  "is_winner": false
}
JSON
)

if [[ -f "${POST_HISTORY}" ]]; then
  jq --argjson entry "${POST_ENTRY}" '. + [$entry]' "${POST_HISTORY}" > "${POST_HISTORY}.tmp"
  mv "${POST_HISTORY}.tmp" "${POST_HISTORY}"
else
  echo "[${POST_ENTRY}]" > "${POST_HISTORY}"
fi

log ""
log "📈 ${NEW_COUNT}/${MAX_POSTS_PER_DAY} posts today"
log "📊 Run read-analytics.sh in 2-4 hours to check engagement"

# ── TikTok/IG reminder ────────────────────────────────────────
if echo "${PLATFORMS}" | grep -qE "tiktok|instagram"; then
  log ""
  log "📱 TikTok/Instagram: Manual post required"
  log "   Scripts saved at: ${DRAFTS_DIR}/"
  log "   Look for: *_tiktok_scripts.txt"
fi
