#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# MarketBot — run-campaign.sh
# FULL AUTOPILOT: research → create → post → analytics → iterate
# Designed to run on OpenClaw heartbeat/cron (2x/day)
# Respects quiet hours, rate limits, and state machine logic
#
# Usage:
#   run-campaign.sh                  # auto mode (follows state machine)
#   run-campaign.sh --force-research # re-research even if fresh
#   run-campaign.sh --force-post     # post even if limit reached
#   run-campaign.sh --dry-run        # simulate all steps
#   run-campaign.sh --status         # show current state
# ─────────────────────────────────────────────────────────────

set -euo pipefail

CONFIG_DIR="${HOME}/.config/marketbot"
CONFIG_FILE="${CONFIG_DIR}/config.json"
STATE_FILE="${CONFIG_DIR}/state.json"
LOG_FILE="${CONFIG_DIR}/campaign.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORCE_RESEARCH=false
FORCE_POST=false
DRY_RUN=false
SHOW_STATUS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-research) FORCE_RESEARCH=true; shift ;;
    --force-post)     FORCE_POST=true; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --status)         SHOW_STATUS=true; shift ;;
    *) shift ;;
  esac
done

mkdir -p "${CONFIG_DIR}"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "${msg}" | tee -a "${LOG_FILE}"
}

banner() {
  echo "" | tee -a "${LOG_FILE}"
  echo "══════════════════════════════════════════════" | tee -a "${LOG_FILE}"
  echo "  $*" | tee -a "${LOG_FILE}"
  echo "══════════════════════════════════════════════" | tee -a "${LOG_FILE}"
  echo "" | tee -a "${LOG_FILE}"
}

step() {
  echo "" | tee -a "${LOG_FILE}"
  echo "── $* ──────────────────────────────────────" | tee -a "${LOG_FILE}"
}

# ── Check config ──────────────────────────────────────────────
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "❌ MarketBot not configured."
  echo "   Copy: cp ~/.openclaw/skills/marketbot/config.example.json ~/.config/marketbot/config.json"
  echo "   Then edit with your niche, product, and X handle."
  exit 1
fi

PRODUCT_NAME=$(jq -r '.product_name // "Product"' "${CONFIG_FILE}")
NICHE=$(jq -r '.niche // "tech"' "${CONFIG_FILE}")
POSTS_PER_DAY=$(jq -r '.posts_per_day // 2' "${CONFIG_FILE}")
QUIET_START=$(jq -r '.quiet_hours.start // 23' "${CONFIG_FILE}" 2>/dev/null || echo 23)
QUIET_END=$(jq -r '.quiet_hours.end // 8' "${CONFIG_FILE}" 2>/dev/null || echo 8)
CURRENT_HOUR=$(date +%-H)
TODAY=$(date +"%Y-%m-%d")
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Check quiet hours ─────────────────────────────────────────
in_quiet_hours() {
  local h=$1 s=$2 e=$3
  if (( s > e )); then
    (( h >= s || h < e ))
  else
    (( h >= s && h < e ))
  fi
}

QUIET=false
if in_quiet_hours "${CURRENT_HOUR}" "${QUIET_START}" "${QUIET_END}"; then
  QUIET=true
fi

# ── Status display ────────────────────────────────────────────
if [[ "${SHOW_STATUS}" == "true" ]]; then
  banner "MARKETBOT STATUS — ${TODAY}"

  echo "📦 Product: ${PRODUCT_NAME}"
  echo "🎯 Niche: ${NICHE}"
  echo "🌙 Quiet hours: ${QUIET_START}:00–${QUIET_END}:00 (currently: $(${QUIET} && echo 'YES — QUIET' || echo 'NO — ACTIVE'))"
  echo ""

  # Posts today
  POSTS_TODAY=$(jq -r --arg d "${TODAY}" '.posts_today[$d] // 0' "${STATE_FILE}" 2>/dev/null || echo 0)
  echo "📊 Posts today: ${POSTS_TODAY}/${POSTS_PER_DAY}"

  # Last research
  if [[ -f "${CONFIG_DIR}/competitor-research.json" ]]; then
    RESEARCH_DATE=$(jq -r '.date // "unknown"' "${CONFIG_DIR}/competitor-research.json")
    echo "🔍 Last research: ${RESEARCH_DATE}"
  else
    echo "🔍 Research: not yet run"
  fi

  # Last analytics
  if [[ -f "${CONFIG_DIR}/analytics.json" ]]; then
    ANALYTICS_DATE=$(jq -r '.date // "unknown"' "${CONFIG_DIR}/analytics.json")
    AVG_SCORE=$(jq -r '.summary.avg_engagement_score // 0' "${CONFIG_DIR}/analytics.json")
    WINNERS=$(jq -r '.summary.winners_count // 0' "${CONFIG_DIR}/analytics.json")
    echo "📈 Last analytics: ${ANALYTICS_DATE} (avg score: ${AVG_SCORE}, winners: ${WINNERS})"
  else
    echo "📈 Analytics: not yet run"
  fi

  # MRR
  if [[ -f "${CONFIG_DIR}/mrr.json" ]]; then
    MRR=$(jq -r '.summary.mrr_estimate_usd // 0' "${CONFIG_DIR}/mrr.json")
    CONVS=$(jq -r '.summary.total_conversions // 0' "${CONFIG_DIR}/mrr.json")
    echo "💰 MRR: \$${MRR} (${CONVS} conversions)"
  else
    echo "💰 MRR: tracking not configured"
  fi

  echo ""

  # Draft count
  DRAFT_COUNT=$(ls "${CONFIG_DIR}/drafts/"*.json 2>/dev/null | grep -v "_x_drafts\|_tiktok" | wc -l || echo 0)
  echo "📝 Drafts available: ${DRAFT_COUNT} batches"
  echo ""
  exit 0
fi

# ── Main campaign logic ───────────────────────────────────────
banner "MARKETBOT RUN — ${NOW}"
log "Product: ${PRODUCT_NAME} | Niche: ${NICHE}"
log "Quiet: ${QUIET} | Dry run: ${DRY_RUN}"

# ── STEP 1: Research (once per week or forced) ────────────────
step "STEP 1: Competitor Research"

RESEARCH_FILE="${CONFIG_DIR}/competitor-research.json"
SHOULD_RESEARCH=false

if [[ "${FORCE_RESEARCH}" == "true" ]]; then
  SHOULD_RESEARCH=true
  log "🔄 Force research requested"
elif [[ ! -f "${RESEARCH_FILE}" ]]; then
  SHOULD_RESEARCH=true
  log "📋 No research file — running initial research"
else
  RESEARCH_DATE=$(jq -r '.date // "1970-01-01"' "${RESEARCH_FILE}")
  DAYS_AGO=$(python3 -c "
from datetime import date
d = date.fromisoformat('${RESEARCH_DATE}')
print((date.today() - d).days)
" 2>/dev/null || echo 99)

  if (( DAYS_AGO >= 7 )); then
    SHOULD_RESEARCH=true
    log "📅 Research is ${DAYS_AGO} days old — refreshing"
  else
    log "✅ Research is fresh (${DAYS_AGO} days old) — skipping"
  fi
fi

if [[ "${SHOULD_RESEARCH}" == "true" ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "🔍 [DRY RUN] Would run: research-competitors.sh '${NICHE}'"
  else
    log "🔍 Running competitor research for '${NICHE}'…"
    bash "${SCRIPT_DIR}/research-competitors.sh" "${NICHE}" || log "⚠️  Research failed — continuing"
  fi
fi

# ── STEP 2: Check if we need new content ─────────────────────
step "STEP 2: Content Check"

DRAFTS_DIR="${CONFIG_DIR}/drafts"
mkdir -p "${DRAFTS_DIR}"

# Count unposted variants
UNPOSTED=$(python3 - <<CHECK_PYTHON 2>/dev/null || echo 0
import json, os, glob

drafts_dir = "${DRAFTS_DIR}"
history_file = "${CONFIG_DIR}/post-history.json"

posted = set()
try:
    with open(history_file) as f:
        history = json.load(f)
    for p in history:
        posted.add(f"{p.get('batch_id', '')}_{p.get('variant_id', '')}")
except:
    pass

unposted = 0
for f in glob.glob(f"{drafts_dir}/*.json"):
    if "_x_drafts" in f or "_tiktok" in f:
        continue
    try:
        with open(f) as fh:
            batch = json.load(fh)
        for v in batch.get("variants", []):
            key = f"{batch['batch_id']}_{v['id']}"
            if key not in posted:
                unposted += 1
    except:
        pass

print(unposted)
CHECK_PYTHON
)

log "📝 Unposted variants available: ${UNPOSTED}"

if (( UNPOSTED < 2 )); then
  log "🧠 Low on content — generating new batch…"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "   [DRY RUN] Would run: create-content.sh"
  else
    bash "${SCRIPT_DIR}/create-content.sh" || log "⚠️  Content generation failed — continuing"
  fi
else
  log "✅ Enough content available — skipping generation"
fi

# ── STEP 3: Post content ──────────────────────────────────────
step "STEP 3: Post Content"

POSTS_TODAY=$(jq -r --arg d "${TODAY}" '.posts_today[$d] // 0' "${STATE_FILE}" 2>/dev/null || echo 0)

if [[ "${QUIET}" == "true" ]] && [[ "${FORCE_POST}" == "false" ]]; then
  log "🌙 Quiet hours — skipping post"
elif (( POSTS_TODAY >= POSTS_PER_DAY )) && [[ "${FORCE_POST}" == "false" ]]; then
  log "🚫 Daily limit reached (${POSTS_TODAY}/${POSTS_PER_DAY}) — skipping post"
else
  log "📤 Posting content…"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "   [DRY RUN] Would run: post-content.sh"
    bash "${SCRIPT_DIR}/post-content.sh" --dry-run || true
  else
    bash "${SCRIPT_DIR}/post-content.sh" || log "⚠️  Post failed — continuing"
  fi
fi

# ── STEP 4: Read analytics (if we have posts) ─────────────────
step "STEP 4: Analytics"

POST_COUNT=$(jq 'length' "${CONFIG_DIR}/post-history.json" 2>/dev/null || echo 0)

if (( POST_COUNT > 0 )); then
  LAST_ANALYTICS=$(jq -r '.date // "1970-01-01"' "${CONFIG_DIR}/analytics.json" 2>/dev/null || echo "1970-01-01")
  ANALYTICS_AGO=$(python3 -c "
from datetime import date
d = date.fromisoformat('${LAST_ANALYTICS}')
print((date.today() - d).days)
" 2>/dev/null || echo 99)

  if (( ANALYTICS_AGO >= 1 )); then
    log "📊 Reading analytics…"
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "   [DRY RUN] Would run: read-analytics.sh"
    else
      bash "${SCRIPT_DIR}/read-analytics.sh" || log "⚠️  Analytics failed — continuing"
    fi
  else
    log "✅ Analytics already run today — skipping"
  fi
else
  log "⏭️  No posts yet — skipping analytics"
fi

# ── STEP 5: Iterate strategy (evening run) ────────────────────
step "STEP 5: Strategy Iteration"

IS_EVENING=$(( CURRENT_HOUR >= 17 && CURRENT_HOUR <= 21 ))

if (( IS_EVENING )) && [[ -f "${CONFIG_DIR}/analytics.json" ]]; then
  log "🧠 Evening run — iterating strategy…"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "   [DRY RUN] Would run: iterate-strategy.sh"
  else
    bash "${SCRIPT_DIR}/iterate-strategy.sh" || log "⚠️  Strategy iteration failed — continuing"
  fi
else
  log "⏭️  Skipping iteration (evening only, or no analytics)"
fi

# ── STEP 6: MRR tracking ──────────────────────────────────────
step "STEP 6: MRR Tracking"

MRR_WEBHOOK=$(jq -r '.mrr_webhook // ""' "${CONFIG_FILE}" 2>/dev/null || echo "")

if [[ -n "${MRR_WEBHOOK}" ]]; then
  log "💰 Checking MRR attribution…"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "   [DRY RUN] Would run: track-mrr.sh"
  else
    bash "${SCRIPT_DIR}/track-mrr.sh" || log "⚠️  MRR tracking failed — continuing"
  fi
else
  log "⏭️  No MRR webhook configured (optional)"
  log "   Run: track-mrr.sh --setup-webhook for instructions"
fi

# ── Done ──────────────────────────────────────────────────────
banner "CAMPAIGN RUN COMPLETE"

POSTS_TODAY_FINAL=$(jq -r --arg d "${TODAY}" '.posts_today[$d] // 0' "${STATE_FILE}" 2>/dev/null || echo 0)
MRR_ESTIMATE=$(jq -r '.summary.mrr_estimate_usd // 0' "${CONFIG_DIR}/mrr.json" 2>/dev/null || echo "0")
WINNERS=$(jq -r '.summary.winners_count // 0' "${CONFIG_DIR}/analytics.json" 2>/dev/null || echo "0")

log "  📤 Posts today: ${POSTS_TODAY_FINAL}/${POSTS_PER_DAY}"
log "  ⭐ Winners identified: ${WINNERS}"
log "  💰 MRR estimate: \$${MRR_ESTIMATE}"
log "  📋 Full log: ${LOG_FILE}"
log ""
log "Next run: $(${QUIET} && echo 'after quiet hours' || echo 'next heartbeat')"
