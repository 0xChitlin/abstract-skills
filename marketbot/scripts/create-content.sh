#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# MarketBot — create-content.sh
# Reads competitor research + strategy, generates 3–5 content
# variants using Claude via OpenClaw. Formats for each platform.
#
# Usage: create-content.sh [--count 5] [--style "educational"]
# ─────────────────────────────────────────────────────────────

set -euo pipefail

CONFIG_DIR="${HOME}/.config/marketbot"
CONFIG_FILE="${CONFIG_DIR}/config.json"
RESEARCH_FILE="${CONFIG_DIR}/competitor-research.json"
STRATEGY_FILE="${CONFIG_DIR}/strategy.json"
DRAFTS_DIR="${CONFIG_DIR}/drafts"
LOG_FILE="${CONFIG_DIR}/content.log"

COUNT="${VARIANTS:-5}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --count) COUNT="$2"; shift 2 ;;
    --style) STYLE_OVERRIDE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

mkdir -p "${DRAFTS_DIR}"

# ── Load config ───────────────────────────────────────────────
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "❌ No config found. Copy config.example.json to ~/.config/marketbot/config.json"
  exit 1
fi

PRODUCT_NAME=$(jq -r '.product_name // "ClawWallet"' "${CONFIG_FILE}")
PRODUCT_URL=$(jq -r '.product_url // "https://clawwallet.buzz"' "${CONFIG_FILE}")
NICHE=$(jq -r '.niche // "AI tools"' "${CONFIG_FILE}")
TARGET_AUDIENCE=$(jq -r '.target_audience // "builders"' "${CONFIG_FILE}")
CONTENT_STYLE="${STYLE_OVERRIDE:-$(jq -r '.content_style // "educational + builder"' "${CONFIG_FILE}")}"
PLATFORMS=$(jq -r '.platforms | join(",")' "${CONFIG_FILE}")
X_HANDLE=$(jq -r '.x_handle // ""' "${CONFIG_FILE}")

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }

log "🧠 MarketBot: Generating content for '${PRODUCT_NAME}'"
log "   Niche: ${NICHE} | Audience: ${TARGET_AUDIENCE}"
log "   Style: ${CONTENT_STYLE} | Variants: ${COUNT}"

# ── Build context for Claude ──────────────────────────────────
RESEARCH_SUMMARY="No competitor research yet. Generate general educational content."
STRATEGY_SUMMARY="No strategy yet. Focus on introducing the product."
WINNING_PATTERNS="Unknown. Vary formats: threads, questions, tips."

if [[ -f "${RESEARCH_FILE}" ]]; then
  RESEARCH_SUMMARY=$(jq -r '
    "Niche: \(.niche)\n" +
    "Top competitors: \([.competitors[:3] | .[] | "\(.handle) (\(.engagement_score) score, \(.top_format))"] | join(", "))\n" +
    "Top format: \(.winning_patterns.top_format)\n" +
    "Avg likes on winners: \(.winning_patterns.avg_likes_across_top)\n" +
    "Insights: \([.winning_patterns.insights[] ] | join("; "))"
  ' "${RESEARCH_FILE}" 2>/dev/null || echo "Research available but parse failed.")
  WINNING_PATTERNS=$(jq -r '.winning_patterns.top_format // "threads"' "${RESEARCH_FILE}" 2>/dev/null || echo "threads")
fi

if [[ -f "${STRATEGY_FILE}" ]]; then
  STRATEGY_SUMMARY=$(jq -r '
    "Winning formats: \([.winning_formats[] | .format] | join(", "))\n" +
    "Drop: \([.formats_to_drop[] ] | join(", "))\n" +
    "Focus: \(.current_focus // "educational content")\n" +
    "Recent winners: \([.recent_winners[:2][] | .summary] | join("; "))"
  ' "${STRATEGY_FILE}" 2>/dev/null || echo "Strategy: early stage, build audience with educational content.")
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE=$(date +"%Y-%m-%d")
BATCH_ID="batch_${DATE//-/}_$(date +%H%M)"

log "📝 Calling Claude for content generation…"

# ── Call Claude via OpenClaw CLI ──────────────────────────────
CLAUDE_PROMPT="You are MarketBot, a social media content strategist for ${PRODUCT_NAME}.

PRODUCT INFO:
- Name: ${PRODUCT_NAME}
- URL: ${PRODUCT_URL}
- Niche: ${NICHE}
- Target audience: ${TARGET_AUDIENCE}
- X/Twitter handle: @${X_HANDLE}

COMPETITOR RESEARCH:
${RESEARCH_SUMMARY}

CURRENT STRATEGY:
${STRATEGY_SUMMARY}
Top winning format: ${WINNING_PATTERNS}

TASK: Generate exactly ${COUNT} social media content variants. Each must be distinct, high-quality, and data-driven based on what's performing.

Content style: ${CONTENT_STYLE}

For each variant, output valid JSON with this structure:
{
  \"id\": \"v1\",
  \"format\": \"thread|single_post|question|list|announcement\",
  \"platform_content\": {
    \"x\": \"X/Twitter version (max 280 chars for single, or '🧵 thread:\\n1/ ...\\n2/ ...\\n3/ ...' for threads)\",
    \"tiktok_script\": \"TikTok video script (hook + body + CTA, 30-60 seconds)\",
    \"instagram_caption\": \"Instagram caption with hashtags\"
  },
  \"estimated_engagement\": \"high|medium|low\",
  \"reasoning\": \"Why this format/angle was chosen\"
}

Output a JSON array of ${COUNT} variants. No markdown. Pure JSON only."

# Run via openclaw agent CLI
CONTENT_JSON=$(openclaw run --model anthropic/claude-opus-4-5 --prompt "${CLAUDE_PROMPT}" --json 2>>"${LOG_FILE}" || echo "[]")

# ── Save drafts ───────────────────────────────────────────────
if [[ "${CONTENT_JSON}" == "[]" ]] || [[ -z "${CONTENT_JSON}" ]]; then
  log "⚠️  Claude call failed or returned empty. Generating fallback content."

  # Fallback: generate minimal draft
  CONTENT_JSON=$(cat <<FALLBACK_EOF
[
  {
    "id": "v1",
    "format": "single_post",
    "platform_content": {
      "x": "Building with AI in ${NICHE}? ${PRODUCT_NAME} lets your agent handle it autonomously. No babysitting required. ${PRODUCT_URL} 🤖",
      "tiktok_script": "Hook: What if your AI agent could do your ${NICHE} work 24/7? Body: ${PRODUCT_NAME} is an autonomous agent that... CTA: Link in bio to try it free.",
      "instagram_caption": "Your agent is working while you sleep. 🤖 ${PRODUCT_NAME} automates ${NICHE} for crypto builders. Try it: ${PRODUCT_URL} #${NICHE// /} #AItools #crypto #builders"
    },
    "estimated_engagement": "medium",
    "reasoning": "Fallback content - Claude unavailable"
  }
]
FALLBACK_EOF
)
fi

# Write batch draft file
DRAFT_FILE="${DRAFTS_DIR}/${BATCH_ID}.json"

python3 - <<PYTHON_EOF
import json, sys
from datetime import datetime

try:
    variants = json.loads('''${CONTENT_JSON}''')
    if not isinstance(variants, list):
        variants = [variants]
except Exception as e:
    variants = []

batch = {
    "batch_id": "${BATCH_ID}",
    "created_at": "${TIMESTAMP}",
    "date": "${DATE}",
    "product": "${PRODUCT_NAME}",
    "niche": "${NICHE}",
    "content_style": "${CONTENT_STYLE}",
    "platforms": "${PLATFORMS}".split(","),
    "status": "draft",
    "variants": variants,
    "stats": {
        "total": len(variants),
        "high_engagement": sum(1 for v in variants if v.get("estimated_engagement") == "high"),
        "formats": list(set(v.get("format", "unknown") for v in variants))
    }
}

with open("${DRAFT_FILE}", "w") as f:
    json.dump(batch, f, indent=2)

print(f"✅ Saved {len(variants)} content variants to ${DRAFT_FILE}")
for i, v in enumerate(variants, 1):
    x_preview = v.get("platform_content", {}).get("x", "")[:60]
    print(f"   v{i} [{v.get('format','?')}] [{v.get('estimated_engagement','?')}]: {x_preview}...")
PYTHON_EOF

# ── Also write per-platform flat files for easy review ────────
log "📄 Writing platform-specific drafts…"

python3 - <<PYTHON_EOF2
import json, os

with open("${DRAFT_FILE}") as f:
    batch = json.load(f)

# X/Twitter drafts
x_file = "${DRAFTS_DIR}/${BATCH_ID}_x_drafts.txt"
with open(x_file, "w") as f:
    f.write(f"# X/Twitter Drafts — {batch['date']}\n")
    f.write(f"# Batch: {batch['batch_id']}\n\n")
    for v in batch["variants"]:
        f.write(f"--- [{v.get('format','?')}] [{v.get('estimated_engagement','?')} engagement] ---\n")
        f.write(v.get("platform_content", {}).get("x", "") + "\n\n")

# TikTok/IG script
tiktok_file = "${DRAFTS_DIR}/${BATCH_ID}_tiktok_scripts.txt"
with open(tiktok_file, "w") as f:
    f.write(f"# TikTok/Instagram Scripts — {batch['date']}\n")
    f.write(f"# Manual post required for these platforms\n\n")
    for i, v in enumerate(batch["variants"], 1):
        f.write(f"=== Script {i}: [{v.get('format','?')}] ===\n")
        f.write("[ TikTok ]\n")
        f.write(v.get("platform_content", {}).get("tiktok_script", "") + "\n\n")
        f.write("[ Instagram Caption ]\n")
        f.write(v.get("platform_content", {}).get("instagram_caption", "") + "\n\n")

print(f"📱 X/Twitter drafts: {x_file}")
print(f"📱 TikTok/IG scripts: {tiktok_file}")
PYTHON_EOF2

log ""
log "✅ Content generation complete! Batch: ${BATCH_ID}"
log "   Review drafts: ls ${DRAFTS_DIR}/"
log "   Post best variant: ./post-content.sh --batch ${BATCH_ID} --variant v1"
