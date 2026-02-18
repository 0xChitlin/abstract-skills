#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# MarketBot — track-mrr.sh
# Tracks which posts drove signups/revenue via webhook
# Outputs weekly MRR attribution summary
#
# Usage:
#   track-mrr.sh                     # check recent attribution
#   track-mrr.sh --summary           # weekly summary
#   track-mrr.sh --record POST_URL   # manually record a conversion
#   track-mrr.sh --setup-webhook     # show webhook setup instructions
# ─────────────────────────────────────────────────────────────

set -euo pipefail

CONFIG_DIR="${HOME}/.config/marketbot"
CONFIG_FILE="${CONFIG_DIR}/config.json"
POST_HISTORY="${CONFIG_DIR}/post-history.json"
MRR_FILE="${CONFIG_DIR}/mrr.json"
LOG_FILE="${CONFIG_DIR}/mrr.log"

SHOW_SUMMARY=false
RECORD_POST_URL=""
SHOW_WEBHOOK_SETUP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary)       SHOW_SUMMARY=true; shift ;;
    --record)        RECORD_POST_URL="$2"; shift 2 ;;
    --setup-webhook) SHOW_WEBHOOK_SETUP=true; shift ;;
    *) shift ;;
  esac
done

mkdir -p "${CONFIG_DIR}"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE=$(date +"%Y-%m-%d")

# ── Webhook setup instructions ────────────────────────────────
if [[ "${SHOW_WEBHOOK_SETUP}" == "true" ]]; then
  cat <<'WEBHOOK_DOCS'
# MarketBot MRR Attribution — Webhook Setup

## How It Works
1. Post links to your product (clawwallet.buzz)
2. Use UTM parameters to tag posts: ?utm_source=marketbot&utm_medium=x&utm_campaign=BATCH_ID
3. Your product backend fires a webhook when a signup happens
4. MarketBot catches the webhook and attributes it to the right post

## UTM Link Format
https://clawwallet.buzz/?utm_source=marketbot&utm_medium=x&utm_campaign=batch_20250217&utm_content=v1

## Webhook Payload (your app sends this)
POST https://your-webhook-url.com/marketbot/conversion
{
  "event": "signup" | "purchase",
  "utm_campaign": "batch_20250217",
  "utm_content": "v1",
  "value_usd": 9.99,
  "product": "agent_registration"
}

## Set Webhook URL in config.json
{
  "mrr_webhook": "https://your-app.com/webhook/marketbot",
  ...
}

## Or Use Zapier / Make.com
1. Create a "New signup" trigger in your app
2. Add UTM parameter extraction
3. POST to: ~/.config/marketbot/mrr.json (via file append action)

## Manual Recording
If you don't have webhook setup, record manually:
  track-mrr.sh --record https://x.com/0xChitlin/status/123456
WEBHOOK_DOCS
  exit 0
fi

# ── Manual conversion recording ───────────────────────────────
if [[ -n "${RECORD_POST_URL}" ]]; then
  log "📝 Recording manual conversion for post: ${RECORD_POST_URL}"

  # Find matching post in history
  MATCHED_POST=""
  if [[ -f "${POST_HISTORY}" ]]; then
    MATCHED_POST=$(jq -r --arg url "${RECORD_POST_URL}" '
      .[] | select(.url == $url or (.tweet_id != "" and ($url | contains(.tweet_id))))
    ' "${POST_HISTORY}" 2>/dev/null | head -1 || echo "")
  fi

  CONVERSION=$(cat <<JSON
{
  "conversion_id": "manual_$(date +%s)",
  "post_url": "${RECORD_POST_URL}",
  "matched_post": ${MATCHED_POST:-null},
  "event": "signup",
  "value_usd": 0,
  "recorded_at": "${TIMESTAMP}",
  "source": "manual",
  "notes": "Manually recorded conversion"
}
JSON
)

  if [[ -f "${MRR_FILE}" ]]; then
    jq --argjson conv "${CONVERSION}" '.conversions += [$conv]' "${MRR_FILE}" > "${MRR_FILE}.tmp"
    mv "${MRR_FILE}.tmp" "${MRR_FILE}"
  else
    echo "{\"conversions\": [${CONVERSION}], \"updated_at\": \"${TIMESTAMP}\"}" > "${MRR_FILE}"
  fi

  log "✅ Conversion recorded"
  exit 0
fi

# ── Check webhook for new conversions ────────────────────────
MRR_WEBHOOK=$(jq -r '.mrr_webhook // ""' "${CONFIG_FILE}" 2>/dev/null || echo "")

if [[ -n "${MRR_WEBHOOK}" ]]; then
  log "🔗 Checking webhook for new conversions…"

  RESPONSE=$(curl -s -X GET "${MRR_WEBHOOK}/events?since=$(date -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)" \
    -H "Authorization: Bearer $(jq -r '.mrr_webhook_token // ""' "${CONFIG_FILE}")" \
    2>>"${LOG_FILE}" || echo "")

  if [[ -n "${RESPONSE}" ]]; then
    log "📥 Webhook response received"
    # Process webhook events
    python3 - <<PYTHON_EOF
import json, sys

try:
    events = json.loads('''${RESPONSE}''')
    if isinstance(events, dict):
        events = events.get("events", [events])
except:
    events = []
    print("⚠️  Could not parse webhook response")
    sys.exit(0)

print(f"📊 {len(events)} conversion events received")
for e in events[:5]:
    print(f"   → {e.get('event', '?')}: {e.get('utm_campaign', '?')} / {e.get('utm_content', '?')} — \${e.get('value_usd', 0):.2f}")
PYTHON_EOF
  fi
fi

# ── Build MRR attribution report ──────────────────────────────
log "📊 Building MRR attribution report…"

python3 - <<PYTHON_EOF
import json, os
from datetime import datetime, timedelta
from collections import defaultdict

mrr_file = "${MRR_FILE}"
history_file = "${POST_HISTORY}"
config_file = "${CONFIG_FILE}"
timestamp = "${TIMESTAMP}"
date = "${DATE}"

# Load data
try:
    with open(mrr_file) as f:
        mrr_data = json.load(f)
    conversions = mrr_data.get("conversions", [])
except:
    conversions = []

try:
    with open(history_file) as f:
        posts = json.load(f)
except:
    posts = []

try:
    with open(config_file) as f:
        config = json.load(f)
except:
    config = {}

# Build post lookup
post_map = {}
for p in posts:
    url = p.get("url", "")
    batch = p.get("batch_id", "")
    vid = p.get("variant_id", "")
    key = f"{batch}_{vid}"
    post_map[url] = p
    post_map[key] = p

# Attribution summary
attribution = defaultdict(lambda: {"conversions": 0, "revenue": 0.0, "posts": []})
week_cutoff = datetime.utcnow() - timedelta(days=7)
month_cutoff = datetime.utcnow() - timedelta(days=30)

weekly_revenue = 0.0
monthly_revenue = 0.0
total_conversions = len(conversions)
total_revenue = sum(c.get("value_usd", 0) for c in conversions)

for conv in conversions:
    try:
        recorded_at = datetime.fromisoformat(conv.get("recorded_at", timestamp).replace("Z", "+00:00")).replace(tzinfo=None)
    except:
        recorded_at = datetime.utcnow()

    value = conv.get("value_usd", 0)
    batch = conv.get("utm_campaign", conv.get("batch_id", "unknown"))
    vid = conv.get("utm_content", conv.get("variant_id", ""))
    key = f"{batch}_{vid}"

    attribution[key]["conversions"] += 1
    attribution[key]["revenue"] += value

    if recorded_at > week_cutoff:
        weekly_revenue += value
    if recorded_at > month_cutoff:
        monthly_revenue += value

# Top converting posts
top_posts = sorted(attribution.items(), key=lambda x: x[1]["revenue"], reverse=True)[:5]

output = {
    "updated_at": timestamp,
    "date": date,
    "product": config.get("product_name", ""),
    "revenue_goal": config.get("revenue_goal", ""),
    "summary": {
        "total_conversions": total_conversions,
        "total_revenue_usd": round(total_revenue, 2),
        "weekly_revenue_usd": round(weekly_revenue, 2),
        "monthly_revenue_usd": round(monthly_revenue, 2),
        "mrr_estimate_usd": round(monthly_revenue, 2)
    },
    "top_converting_posts": [
        {
            "post_key": k,
            "conversions": v["conversions"],
            "revenue": round(v["revenue"], 2)
        }
        for k, v in top_posts if v["conversions"] > 0
    ],
    "conversions": conversions[-100:]  # keep last 100
}

with open(mrr_file, "w") as f:
    json.dump(output, f, indent=2)

print(f"✅ MRR attribution updated")
print(f"   Total conversions: {total_conversions}")
print(f"   Total revenue: \${round(total_revenue, 2)}")
print(f"   Weekly revenue: \${round(weekly_revenue, 2)}")
print(f"   Monthly (MRR estimate): \${round(monthly_revenue, 2)}")
if not conversions:
    print("")
    print("📌 No conversions yet. Setup steps:")
    print("   1. Add UTM params to your product links in posts")
    print("   2. Set mrr_webhook in config.json, OR")
    print("   3. Record manually: track-mrr.sh --record POST_URL")
    print("   4. Run: track-mrr.sh --setup-webhook for full instructions")
PYTHON_EOF

# ── Weekly summary output ─────────────────────────────────────
if [[ "${SHOW_SUMMARY}" == "true" ]]; then
  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "           MARKETBOT WEEKLY MRR SUMMARY"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ -f "${MRR_FILE}" ]]; then
    MRR=$(jq -r '.summary.mrr_estimate_usd' "${MRR_FILE}")
    CONVS=$(jq -r '.summary.total_conversions' "${MRR_FILE}")
    WEEKLY=$(jq -r '.summary.weekly_revenue_usd' "${MRR_FILE}")
    PRODUCT=$(jq -r '.product' "${MRR_FILE}")
    GOAL=$(jq -r '.revenue_goal' "${MRR_FILE}")

    log ""
    log "  Product: ${PRODUCT}"
    log "  Goal: ${GOAL}"
    log ""
    log "  MRR (30-day): \$${MRR}"
    log "  This week:    \$${WEEKLY}"
    log "  Conversions:  ${CONVS} total"
    log ""
    log "  Top converting posts:"
    jq -r '.top_converting_posts[:3][] | "    • \(.post_key): \(.conversions) conv / $\(.revenue)"' "${MRR_FILE}" 2>/dev/null || true
  fi

  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

log ""
log "💾 MRR data saved to ${MRR_FILE}"
