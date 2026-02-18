#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# MarketBot — read-analytics.sh
# Checks engagement on recent posts via goat-x search
# Identifies "winners" (posts with >2x average engagement)
# Saves analytics to ~/.config/marketbot/analytics.json
#
# Usage: read-analytics.sh [--handle @0xChitlin] [--days 7]
# ─────────────────────────────────────────────────────────────

set -euo pipefail

CONFIG_DIR="${HOME}/.config/marketbot"
CONFIG_FILE="${CONFIG_DIR}/config.json"
POST_HISTORY="${CONFIG_DIR}/post-history.json"
ANALYTICS_FILE="${CONFIG_DIR}/analytics.json"
LOG_FILE="${CONFIG_DIR}/analytics.log"
GOAT_X_DIR="/Users/algohussle/.openclaw/skills/goat-x"

HANDLE_OVERRIDE=""
DAYS_BACK=7

while [[ $# -gt 0 ]]; do
  case "$1" in
    --handle) HANDLE_OVERRIDE="$2"; shift 2 ;;
    --days)   DAYS_BACK="$2"; shift 2 ;;
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

X_HANDLE="${HANDLE_OVERRIDE:-$(jq -r '.x_handle // ""' "${CONFIG_FILE}")}"
X_HANDLE="${X_HANDLE#@}"  # strip @ if present

if [[ -z "${X_HANDLE}" ]]; then
  log "❌ No X handle configured. Set 'x_handle' in config.json"
  exit 1
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE=$(date +"%Y-%m-%d")

log "📊 MarketBot: Reading analytics for @${X_HANDLE}"
log "   Looking back ${DAYS_BACK} days…"

# ── Fetch own recent tweets via goat-x ───────────────────────
SEARCH_RESULTS_FILE="${CONFIG_DIR}/.analytics_search_$$.json"

cd "${GOAT_X_DIR}" || { log "❌ goat-x not found at ${GOAT_X_DIR}"; exit 1; }

log "📡 Searching X for @${X_HANDLE} recent posts…"

node src/cli.ts search \
  --query "from:${X_HANDLE}" \
  --limit 20 \
  --output "${SEARCH_RESULTS_FILE}" \
  2>>"${LOG_FILE}" || {
    log "⚠️  goat-x search failed. Will use post history for estimates."
    echo '{"results":[]}' > "${SEARCH_RESULTS_FILE}"
  }

# ── Process analytics ─────────────────────────────────────────
python3 - <<PYTHON_EOF
import json, os, sys
from datetime import datetime, timedelta

search_file = "${SEARCH_RESULTS_FILE}"
history_file = "${POST_HISTORY}"
analytics_file = "${ANALYTICS_FILE}"
handle = "${X_HANDLE}"
days_back = int("${DAYS_BACK}")
timestamp = "${TIMESTAMP}"
date = "${DATE}"

# Load search results
try:
    with open(search_file) as f:
        search_data = json.load(f)
    live_posts = search_data.get("results", [])
except:
    live_posts = []

# Load post history
try:
    with open(history_file) as f:
        history = json.load(f)
except:
    history = []

# Merge: update history engagement from live data
tweet_map = {}
for post in live_posts:
    tweet_id = str(post.get("id", post.get("tweet_id", "")))
    if tweet_id:
        tweet_map[tweet_id] = {
            "likes": post.get("likes", post.get("favorite_count", 0)),
            "replies": post.get("replies", post.get("reply_count", 0)),
            "reposts": post.get("reposts", post.get("retweet_count", 0)),
            "views": post.get("views", post.get("view_count", 0)),
            "text": post.get("text", post.get("content", ""))[:280]
        }

# Build analytics records from history
cutoff = datetime.utcnow() - timedelta(days=days_back)
analyzed_posts = []
total_likes = 0
total_replies = 0
total_reposts = 0
total_views = 0

for post in history:
    try:
        posted_at = datetime.fromisoformat(post["posted_at"].replace("Z", "+00:00")).replace(tzinfo=None)
    except:
        continue

    if posted_at < cutoff:
        continue

    tweet_id = str(post.get("tweet_id", ""))
    engagement = post.get("engagement", {})

    # Update from live data if available
    if tweet_id in tweet_map:
        live = tweet_map[tweet_id]
        engagement = {
            "likes": max(engagement.get("likes", 0), live["likes"]),
            "replies": max(engagement.get("replies", 0), live["replies"]),
            "reposts": max(engagement.get("reposts", 0), live["reposts"]),
            "views": max(engagement.get("views", 0), live["views"])
        }

    likes = engagement.get("likes", 0)
    replies = engagement.get("replies", 0)
    reposts = engagement.get("reposts", 0)
    views = engagement.get("views", 0)
    engagement_score = likes + (replies * 3) + (reposts * 2)

    total_likes += likes
    total_replies += replies
    total_reposts += reposts
    total_views += views

    analyzed_posts.append({
        "post_id": post.get("post_id", ""),
        "tweet_id": tweet_id,
        "batch_id": post.get("batch_id", ""),
        "variant_id": post.get("variant_id", ""),
        "text_preview": post.get("text", "")[:100],
        "url": post.get("url", ""),
        "posted_at": post["posted_at"],
        "platform": "x",
        "engagement": engagement,
        "engagement_score": engagement_score,
        "is_winner": False  # set after calculating avg
    })

# Calculate averages and identify winners
n = max(len(analyzed_posts), 1)
avg_score = sum(p["engagement_score"] for p in analyzed_posts) / n
avg_likes = total_likes / n
avg_replies = total_replies / n

winner_threshold = avg_score * 2
winners = []

for post in analyzed_posts:
    if post["engagement_score"] >= winner_threshold:
        post["is_winner"] = True
        winners.append(post)

# Sort by engagement
analyzed_posts.sort(key=lambda x: x["engagement_score"], reverse=True)

# Add some live-only posts (not in history)
for tweet_id, live in tweet_map.items():
    if not any(str(p.get("tweet_id", "")) == tweet_id for p in analyzed_posts):
        score = live["likes"] + (live["replies"] * 3) + (live["reposts"] * 2)
        analyzed_posts.append({
            "post_id": tweet_id,
            "tweet_id": tweet_id,
            "batch_id": "live_only",
            "text_preview": live["text"][:100],
            "url": f"https://x.com/{handle}/status/{tweet_id}",
            "posted_at": timestamp,
            "platform": "x",
            "engagement": {
                "likes": live["likes"],
                "replies": live["replies"],
                "reposts": live["reposts"],
                "views": live["views"]
            },
            "engagement_score": score,
            "is_winner": score >= winner_threshold
        })

output = {
    "handle": f"@{handle}",
    "analyzed_at": timestamp,
    "date": date,
    "period_days": days_back,
    "summary": {
        "posts_analyzed": len(analyzed_posts),
        "total_likes": total_likes,
        "total_replies": total_replies,
        "total_reposts": total_reposts,
        "total_views": total_views,
        "avg_likes": round(avg_likes, 1),
        "avg_replies": round(avg_replies, 1),
        "avg_engagement_score": round(avg_score, 1),
        "winner_threshold": round(winner_threshold, 1),
        "winners_count": len(winners)
    },
    "posts": analyzed_posts,
    "winners": [p for p in analyzed_posts if p["is_winner"]],
    "top_post": analyzed_posts[0] if analyzed_posts else None
}

with open(analytics_file, "w") as f:
    json.dump(output, f, indent=2)

print(f"✅ Analytics saved for {len(analyzed_posts)} posts")
print(f"   Avg engagement score: {round(avg_score, 1)}")
print(f"   Winner threshold (2x avg): {round(winner_threshold, 1)}")
print(f"   Winners found: {len(winners)}")
if analyzed_posts:
    top = analyzed_posts[0]
    print(f"   🏆 Top post: [{top['engagement_score']} score] {top['text_preview'][:60]}...")
for w in winners[:3]:
    print(f"   ⭐ Winner: {w['text_preview'][:60]}... ({w['engagement_score']} score)")
PYTHON_EOF

# ── Cleanup ───────────────────────────────────────────────────
rm -f "${SEARCH_RESULTS_FILE}"

WINNERS=$(jq '.summary.winners_count' "${ANALYTICS_FILE}" 2>/dev/null || echo 0)
log ""
log "💾 Analytics saved to ${ANALYTICS_FILE}"

if (( WINNERS > 0 )); then
  log "⭐ ${WINNERS} winner(s) found! Run iterate-strategy.sh to update strategy."
else
  log "📈 No clear winners yet. Keep posting — more data needed."
fi

log "   Next: ./iterate-strategy.sh"
