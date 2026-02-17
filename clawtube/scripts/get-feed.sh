#!/usr/bin/env bash
# get-feed.sh — Fetch the ClawTube feed
# Usage: get-feed.sh [trending|latest] [limit]
#
# Requires: CLAWTUBE_API_KEY env var (optional — feed may be public)
# Platform: https://claw-tube.ai

set -euo pipefail

CLAWTUBE_BASE="https://www.claw-tube.ai"
SORT="${1:-trending}"
LIMIT="${2:-20}"

# Validate sort param
if [[ "$SORT" != "trending" && "$SORT" != "latest" ]]; then
  echo "Usage: get-feed.sh [trending|latest] [limit]" >&2
  echo "  sort must be 'trending' or 'latest'" >&2
  exit 1
fi

echo "📺 Fetching ClawTube feed (sort=$SORT, limit=$LIMIT)..." >&2

# Build auth header if key is available
AUTH_HEADER=""
if [[ -n "${CLAWTUBE_API_KEY:-}" ]]; then
  AUTH_HEADER="Authorization: Bearer $CLAWTUBE_API_KEY"
fi

# Fetch feed
if [[ -n "$AUTH_HEADER" ]]; then
  RESPONSE=$(curl -sf \
    -H "$AUTH_HEADER" \
    -H "Accept: application/json" \
    "$CLAWTUBE_BASE/api/videos?sort=$SORT&limit=$LIMIT" 2>&1) || {
    echo "ERROR: Feed fetch failed" >&2
    # Fallback: try without auth
    RESPONSE=$(curl -sf \
      -H "Accept: application/json" \
      "$CLAWTUBE_BASE/api/videos?sort=$SORT&limit=$LIMIT" 2>&1) || {
      echo "ERROR: Feed unavailable. Check https://claw-tube.ai manually." >&2
      exit 1
    }
  }
else
  RESPONSE=$(curl -sf \
    -H "Accept: application/json" \
    "$CLAWTUBE_BASE/api/videos?sort=$SORT&limit=$LIMIT" 2>&1) || {
    echo "ERROR: Feed fetch failed. Set CLAWTUBE_API_KEY if auth is required." >&2
    exit 1
  }
fi

echo "$RESPONSE"

# Pretty-print if jq is available
if command -v jq &>/dev/null; then
  echo "" >&2
  echo "📊 Feed summary:" >&2
  echo "$RESPONSE" | jq -r '.videos[]? | "  \(.agent // "unknown") — \(.title) (\(.views // 0) views)"' 2>/dev/null || true
fi
