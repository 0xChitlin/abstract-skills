#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# MarketBot — research-competitors.sh
# Finds top-performing accounts in your niche on X/Twitter
# Uses goat-x CDP intercept to search without API keys
#
# Usage: research-competitors.sh [niche_keyword]
#        research-competitors.sh "AI tools"
#        research-competitors.sh "crypto wallet"
# ─────────────────────────────────────────────────────────────

set -euo pipefail

NICHE="${1:-}"
CONFIG_DIR="${HOME}/.config/marketbot"
CONFIG_FILE="${CONFIG_DIR}/config.json"
OUTPUT_FILE="${CONFIG_DIR}/competitor-research.json"
LOG_FILE="${CONFIG_DIR}/research.log"
GOAT_X_DIR="/Users/algohussle/.openclaw/skills/goat-x"

# ── Load config ───────────────────────────────────────────────
mkdir -p "${CONFIG_DIR}"

if [[ -f "${CONFIG_FILE}" ]]; then
  if [[ -z "${NICHE}" ]]; then
    NICHE=$(jq -r '.niche // "AI tools"' "${CONFIG_FILE}")
  fi
  COMPETITOR_COUNT=$(jq -r '.competitor_count // 10' "${CONFIG_FILE}")
  TARGET_AUDIENCE=$(jq -r '.target_audience // ""' "${CONFIG_FILE}")
else
  NICHE="${NICHE:-AI tools}"
  COMPETITOR_COUNT=10
  TARGET_AUDIENCE=""
fi

if [[ -z "${NICHE}" ]]; then
  echo "❌ No niche provided. Usage: research-competitors.sh \"AI tools\""
  echo "   Or set 'niche' in ~/.config/marketbot/config.json"
  exit 1
fi

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }

log "🔍 MarketBot: Researching competitors in niche: '${NICHE}'"
log "   Target audience: ${TARGET_AUDIENCE:-not set}"
log "   Looking for top ${COMPETITOR_COUNT} accounts…"

# ── Run goat-x search for top accounts ───────────────────────
SEARCH_QUERY="${NICHE} -is:retweet min_faves:100 lang:en"
SEARCH_RESULTS_FILE="${CONFIG_DIR}/.search_results_$$.json"

log "📡 Running goat-x search: '${SEARCH_QUERY}'"

# Use goat-x to search X/Twitter via CDP (no API key needed)
# The goat-x browser-x.ts script handles the CDP intercept
cd "${GOAT_X_DIR}" || { log "❌ goat-x not found at ${GOAT_X_DIR}"; exit 1; }

# Search for top posts in the niche
node src/cli.ts search \
  --query "${SEARCH_QUERY}" \
  --limit 50 \
  --output "${SEARCH_RESULTS_FILE}" \
  2>>"${LOG_FILE}" || {
    log "⚠️  goat-x search failed. Creating mock research for testing."
    echo '{"results":[]}' > "${SEARCH_RESULTS_FILE}"
  }

log "✅ Search complete. Analyzing results…"

# ── Process results + build competitor profile ────────────────
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE=$(date +"%Y-%m-%d")

# Build competitor research JSON from search results
python3 - <<PYTHON_EOF
import json, os, sys, re
from collections import defaultdict, Counter
from datetime import datetime

results_file = "${SEARCH_RESULTS_FILE}"
output_file = "${OUTPUT_FILE}"
niche = "${NICHE}"
timestamp = "${TIMESTAMP}"
date = "${DATE}"

try:
    with open(results_file) as f:
        data = json.load(f)
    results = data.get("results", [])
except Exception as e:
    results = []

# Extract author stats
author_stats = defaultdict(lambda: {
    "handle": "", "name": "", "posts": 0,
    "total_likes": 0, "total_replies": 0, "total_reposts": 0,
    "formats_used": Counter(), "sample_posts": []
})

for post in results:
    author = post.get("author", {})
    handle = author.get("handle", post.get("username", "unknown"))
    stats = author_stats[handle]
    stats["handle"] = f"@{handle}"
    stats["name"] = author.get("name", handle)
    stats["posts"] += 1
    stats["total_likes"] += post.get("likes", post.get("favorite_count", 0))
    stats["total_replies"] += post.get("replies", post.get("reply_count", 0))
    stats["total_reposts"] += post.get("reposts", post.get("retweet_count", 0))

    # Detect content format
    text = post.get("text", post.get("content", ""))
    if any(c in text for c in ["🧵", "1/", "1."]):
        stats["formats_used"]["thread"] += 1
    elif "http" in text and len(text) < 100:
        stats["formats_used"]["link_post"] += 1
    elif "?" in text[-20:]:
        stats["formats_used"]["question"] += 1
    elif any(c in text for c in ["✅", "❌", "🔥", "💡"]):
        stats["formats_used"]["list_with_emojis"] += 1
    else:
        stats["formats_used"]["plain_text"] += 1

    if len(stats["sample_posts"]) < 3:
        stats["sample_posts"].append({
            "text": text[:280],
            "likes": post.get("likes", 0),
            "replies": post.get("replies", 0),
            "url": post.get("url", "")
        })

# Rank competitors by engagement
competitors = []
for handle, stats in author_stats.items():
    if stats["posts"] > 0:
        avg_likes = stats["total_likes"] / stats["posts"]
        avg_replies = stats["total_replies"] / stats["posts"]
        engagement_score = avg_likes + (avg_replies * 3)
        top_format = stats["formats_used"].most_common(1)
        competitors.append({
            "handle": stats["handle"],
            "name": stats["name"],
            "posts_analyzed": stats["posts"],
            "avg_likes": round(avg_likes, 1),
            "avg_replies": round(avg_replies, 1),
            "total_reposts": stats["total_reposts"],
            "engagement_score": round(engagement_score, 1),
            "top_format": top_format[0][0] if top_format else "unknown",
            "format_breakdown": dict(stats["formats_used"]),
            "sample_posts": stats["sample_posts"]
        })

# Sort by engagement score
competitors.sort(key=lambda x: x["engagement_score"], reverse=True)
competitors = competitors[:${COMPETITOR_COUNT}]

# Extract winning patterns
all_formats = Counter()
for c in competitors:
    for fmt, count in c.get("format_breakdown", {}).items():
        all_formats[fmt] += count

patterns = {
    "top_format": all_formats.most_common(1)[0][0] if all_formats else "unknown",
    "format_distribution": dict(all_formats),
    "avg_likes_across_top": round(sum(c["avg_likes"] for c in competitors) / max(len(competitors), 1), 1),
    "avg_replies_across_top": round(sum(c["avg_replies"] for c in competitors) / max(len(competitors), 1), 1),
    "insights": []
}

# Generate insights
if all_formats.get("thread", 0) > all_formats.get("plain_text", 0):
    patterns["insights"].append("Threads drive more engagement than single posts in this niche")
if all_formats.get("question", 0) > 2:
    patterns["insights"].append("Questions get disproportionate replies — great for engagement")
if patterns["avg_likes_across_top"] > 100:
    patterns["insights"].append(f"High-engagement niche: avg {patterns['avg_likes_across_top']} likes on top posts")

output = {
    "niche": niche,
    "researched_at": timestamp,
    "date": date,
    "query_used": "${SEARCH_QUERY}",
    "total_posts_analyzed": len(results),
    "competitors": competitors,
    "winning_patterns": patterns,
    "next_action": "Run create-content.sh to generate content based on these patterns"
}

with open(output_file, "w") as f:
    json.dump(output, f, indent=2)

print(f"✅ Analyzed {len(results)} posts, found {len(competitors)} competitors")
print(f"   Top format: {patterns['top_format']}")
print(f"   Avg likes (top accounts): {patterns['avg_likes_across_top']}")
if competitors:
    print(f"   #1 competitor: {competitors[0]['handle']} ({competitors[0]['engagement_score']} score)")
for insight in patterns["insights"]:
    print(f"   💡 {insight}")
PYTHON_EOF

# ── Cleanup temp files ────────────────────────────────────────
rm -f "${SEARCH_RESULTS_FILE}"

log "💾 Research saved to ${OUTPUT_FILE}"
log ""
log "📋 Next step: run create-content.sh to generate content"
log "   ~/.openclaw/skills/marketbot/scripts/create-content.sh"
