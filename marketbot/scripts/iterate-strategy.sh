#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# MarketBot — iterate-strategy.sh
# Reads analytics, identifies winning content patterns,
# updates strategy.json, generates next content batch
# based on what's actually working.
#
# Usage: iterate-strategy.sh [--generate-content]
# ─────────────────────────────────────────────────────────────

set -euo pipefail

CONFIG_DIR="${HOME}/.config/marketbot"
CONFIG_FILE="${CONFIG_DIR}/config.json"
ANALYTICS_FILE="${CONFIG_DIR}/analytics.json"
STRATEGY_FILE="${CONFIG_DIR}/strategy.json"
DRAFTS_DIR="${CONFIG_DIR}/drafts"
LOG_FILE="${CONFIG_DIR}/strategy.log"

GENERATE_CONTENT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --generate-content) GENERATE_CONTENT=true; shift ;;
    *) shift ;;
  esac
done

mkdir -p "${CONFIG_DIR}" "${DRAFTS_DIR}"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE=$(date +"%Y-%m-%d")

log "🧠 MarketBot: Iterating strategy based on analytics"

if [[ ! -f "${ANALYTICS_FILE}" ]]; then
  log "❌ No analytics yet. Run read-analytics.sh first."
  exit 1
fi

# ── Analyze patterns in winners ───────────────────────────────
python3 - <<PYTHON_EOF
import json, os
from collections import Counter, defaultdict
from datetime import datetime

analytics_file = "${ANALYTICS_FILE}"
strategy_file = "${STRATEGY_FILE}"
config_file = "${CONFIG_FILE}"
timestamp = "${TIMESTAMP}"
date = "${DATE}"

with open(analytics_file) as f:
    analytics = json.load(f)

with open(config_file) as f:
    config = json.load(f)

winners = analytics.get("winners", [])
all_posts = analytics.get("posts", [])
summary = analytics.get("summary", {})

# Load existing strategy to preserve history
try:
    with open(strategy_file) as f:
        existing_strategy = json.load(f)
    strategy_history = existing_strategy.get("history", [])
    iteration = existing_strategy.get("iteration", 0) + 1
except:
    strategy_history = []
    iteration = 1

# Detect winning format patterns
format_counter = Counter()
keyword_counter = Counter()
length_buckets = {"short": [], "medium": [], "long": []}
emoji_posts = 0
question_posts = 0
thread_posts = 0

import re

for post in all_posts:
    text = post.get("text_preview", "")
    score = post.get("engagement_score", 0)

    # Format detection
    if "🧵" in text or re.search(r'\b1/', text):
        format_counter["thread"] += score
        thread_posts += 1
    elif "?" in text[-30:]:
        format_counter["question"] += score
        question_posts += 1
    elif any(e in text for e in ["✅", "❌", "💡", "🔥", "⚡", "🚀"]):
        format_counter["list_emojis"] += score
        emoji_posts += 1
    else:
        format_counter["plain"] += score

    # Length bucket
    n = len(text)
    if n < 100:
        length_buckets["short"].append(score)
    elif n < 200:
        length_buckets["medium"].append(score)
    else:
        length_buckets["long"].append(score)

    # Extract high-value keywords
    words = re.findall(r'\b[a-z]{4,}\b', text.lower())
    if score > summary.get("avg_engagement_score", 0):
        for w in words:
            if w not in ("this", "that", "with", "from", "your", "have", "been", "will", "they", "them"):
                keyword_counter[w] += 1

# Best length
avg_by_length = {}
for bucket, scores in length_buckets.items():
    avg_by_length[bucket] = sum(scores) / max(len(scores), 1)
best_length = max(avg_by_length, key=avg_by_length.get) if avg_by_length else "medium"

# Winning formats (sorted by engagement-weighted score)
winning_formats = []
formats_to_drop = []
for fmt, score in format_counter.most_common():
    if score > summary.get("avg_engagement_score", 0) * 2:
        winning_formats.append({"format": fmt, "score": round(score, 1)})
    elif score < summary.get("avg_engagement_score", 0) * 0.5:
        formats_to_drop.append(fmt)

top_keywords = [kw for kw, _ in keyword_counter.most_common(15)]

# Build strategy insights
insights = []
if thread_posts > 0 and format_counter.get("thread", 0) > format_counter.get("plain", 0):
    insights.append("Threads outperform single posts — prioritize threads")
if question_posts > 0 and format_counter.get("question", 0) > 0:
    insights.append("Questions drive replies — use them to build conversations")
if best_length == "short":
    insights.append("Short posts (<100 chars) getting more engagement than long ones")
elif best_length == "long":
    insights.append("Longer, detailed posts perform better in this niche")
if top_keywords:
    insights.append(f"High-performing keywords: {', '.join(top_keywords[:5])}")

# Current focus decision
current_focus = "educational content"
if winning_formats:
    top_fmt = winning_formats[0]["format"]
    if top_fmt == "thread":
        current_focus = "educational threads with step-by-step content"
    elif top_fmt == "question":
        current_focus = "engagement questions + community building"
    elif top_fmt == "list_emojis":
        current_focus = "quick-hit lists with emojis"

# Content directives for next batch
next_batch_directives = []
if winning_formats:
    next_batch_directives.append(f"Lead with {winning_formats[0]['format']} format")
if top_keywords:
    next_batch_directives.append(f"Include keywords: {', '.join(top_keywords[:3])}")
if best_length == "short":
    next_batch_directives.append("Keep posts under 120 chars")
elif best_length == "long":
    next_batch_directives.append("Write detailed posts >180 chars")
next_batch_directives.append(f"Content focus: {current_focus}")

# Archive current strategy to history
strategy_snapshot = {
    "iteration": iteration - 1,
    "date": date,
    "posts_analyzed": summary.get("posts_analyzed", 0),
    "winners": len(winners),
    "top_format": winning_formats[0]["format"] if winning_formats else "unknown"
}
strategy_history.append(strategy_snapshot)
strategy_history = strategy_history[-20:]  # keep last 20

strategy = {
    "version": "1.0",
    "iteration": iteration,
    "updated_at": timestamp,
    "date": date,
    "product": config.get("product_name", ""),
    "niche": config.get("niche", ""),
    "current_focus": current_focus,
    "winning_formats": winning_formats,
    "formats_to_drop": formats_to_drop,
    "best_post_length": best_length,
    "top_keywords": top_keywords,
    "insights": insights,
    "next_batch_directives": next_batch_directives,
    "recent_winners": [
        {
            "text_preview": w.get("text_preview", "")[:80],
            "score": w.get("engagement_score", 0),
            "url": w.get("url", ""),
            "summary": w.get("text_preview", "")[:40]
        }
        for w in winners[:5]
    ],
    "performance_trend": {
        "avg_likes": summary.get("avg_likes", 0),
        "avg_replies": summary.get("avg_replies", 0),
        "avg_score": summary.get("avg_engagement_score", 0),
        "winners": len(winners),
        "total_posts": summary.get("posts_analyzed", 0)
    },
    "history": strategy_history
}

with open(strategy_file, "w") as f:
    json.dump(strategy, f, indent=2)

print(f"✅ Strategy updated (iteration {iteration})")
print(f"   Current focus: {current_focus}")
print(f"   Winning formats: {[f['format'] for f in winning_formats]}")
print(f"   Drop: {formats_to_drop}")
print(f"   Best length: {best_length}")
if top_keywords:
    print(f"   Power keywords: {', '.join(top_keywords[:5])}")
print(f"")
print(f"📋 Next batch directives:")
for d in next_batch_directives:
    print(f"   • {d}")
PYTHON_EOF

log ""
log "💾 Strategy saved to ${STRATEGY_FILE}"

# ── Optionally trigger content generation ─────────────────────
if [[ "${GENERATE_CONTENT}" == "true" ]]; then
  log ""
  log "🧠 Strategy updated → generating new content batch…"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  bash "${SCRIPT_DIR}/create-content.sh"
else
  log "💡 Run create-content.sh to generate next batch based on new strategy"
  log "   Or: iterate-strategy.sh --generate-content"
fi
