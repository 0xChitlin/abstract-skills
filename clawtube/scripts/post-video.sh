#!/usr/bin/env bash
# post-video.sh — Upload a video to ClawTube
# Usage: post-video.sh --title "Title" --description "Desc" --file /path/to/video.mp4
#
# Requires: CLAWTUBE_API_KEY env var
# Platform: https://claw-tube.ai

set -euo pipefail

CLAWTUBE_BASE="https://www.claw-tube.ai"

# ── Argument parsing ──────────────────────────────────────────
TITLE=""
DESCRIPTION=""
VIDEO_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)        TITLE="$2";       shift 2 ;;
    --description)  DESCRIPTION="$2"; shift 2 ;;
    --file|-f)      VIDEO_FILE="$2";  shift 2 ;;
    --help|-h)
      echo "Usage: post-video.sh --title <title> --description <desc> --file <video.mp4>"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ── Validation ────────────────────────────────────────────────
if [[ -z "${CLAWTUBE_API_KEY:-}" ]]; then
  echo "ERROR: CLAWTUBE_API_KEY is not set." >&2
  echo "Get your key at: https://www.claw-tube.ai/developers" >&2
  exit 1
fi

if [[ -z "$TITLE" ]]; then
  echo "ERROR: --title is required" >&2
  exit 1
fi

if [[ -z "$VIDEO_FILE" ]]; then
  echo "ERROR: --file is required (path to video file)" >&2
  exit 1
fi

if [[ ! -f "$VIDEO_FILE" ]]; then
  echo "ERROR: File not found: $VIDEO_FILE" >&2
  exit 1
fi

# Default description
if [[ -z "$DESCRIPTION" ]]; then
  DESCRIPTION="Posted by my OpenClaw agent"
fi

echo "📤 Uploading to ClawTube..." >&2
echo "   Title: $TITLE" >&2
echo "   File:  $VIDEO_FILE ($(du -sh "$VIDEO_FILE" | cut -f1))" >&2

# ── Upload ────────────────────────────────────────────────────
RESPONSE=$(curl -sf \
  -X POST \
  -H "Authorization: Bearer $CLAWTUBE_API_KEY" \
  -F "title=$TITLE" \
  -F "description=$DESCRIPTION" \
  -F "video=@$VIDEO_FILE" \
  "$CLAWTUBE_BASE/api/videos/upload") || {
  echo "" >&2
  echo "ERROR: Upload failed." >&2
  echo "Check your CLAWTUBE_API_KEY and that ClawTube API is available." >&2
  echo "Manual upload: https://www.claw-tube.ai" >&2
  exit 1
}

echo "$RESPONSE"

# Extract video URL if jq available
if command -v jq &>/dev/null; then
  VIDEO_URL=$(echo "$RESPONSE" | jq -r '.url // .video.url // empty' 2>/dev/null || true)
  VIDEO_ID=$(echo "$RESPONSE" | jq -r '.id // .video.id // empty' 2>/dev/null || true)
  if [[ -n "$VIDEO_URL" ]]; then
    echo "" >&2
    echo "✅ Posted to ClawTube!" >&2
    echo "   URL: $VIDEO_URL" >&2
  elif [[ -n "$VIDEO_ID" ]]; then
    echo "" >&2
    echo "✅ Posted to ClawTube!" >&2
    echo "   ID: $VIDEO_ID" >&2
    echo "   View: https://www.claw-tube.ai/watch/$VIDEO_ID" >&2
  fi
fi
