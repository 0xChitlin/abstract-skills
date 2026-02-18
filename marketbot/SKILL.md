---
name: marketbot
version: 1.0.0
description: Autonomous social media marketing agent. Researches competitors, generates data-driven content, posts to X/Twitter, reads analytics, iterates strategy, and tracks MRR attribution. Your agent does the marketing. You collect the money.
homepage: https://clawwallet.buzz
docs: https://docs.clawwallet.buzz/skills/marketbot
github: https://github.com/0xChitlin/abstract-skills/tree/main/marketbot
metadata:
  category: social
  tier: premium
  chain: abstract
  chain_id: 2741
  requires_skill: goat-x
  openclaw_native: true
  heartbeat: true
  heartbeat_frequency: 2x_daily
  schedule: "0 9,18 * * *"
---

# MarketBot

> *"Your agent does your marketing. You collect the money."* 💰

MarketBot is a full-stack marketing automation skill for OpenClaw agents. It researches what's working in your niche, generates high-quality content, posts autonomously, reads real analytics, and iterates strategy based on what drives **actual revenue** — not vanity metrics.

Inspired by the "Larry" skill (1M+ TikTok views, $633 MRR) — but built for serious builders. Adds X/Twitter (via goat-x CDP), on-chain activity logging, and multi-platform support.

---

## What It Does

| Command | Description |
|---|---|
| `research-competitors` | Scans X/Twitter for top performers in your niche. Extracts posting frequency, content formats, engagement rates. |
| `create-content` | Reads competitor research. Generates 3–5 content variants via Claude. Formats for each platform. |
| `post-content` | Posts to X/Twitter via goat-x CDP intercept. TikTok/IG drafts saved for manual review. |
| `read-analytics` | Checks engagement on recent posts. Identifies "winners" (>2x avg engagement). |
| `iterate-strategy` | Updates strategy based on winners. Generates next content batch from what's working. |
| `track-mrr` | Webhook-based MRR attribution. Tracks which posts drove signups/revenue. |
| `run-campaign` | **Full autopilot.** research → create → post → analytics → iterate. Runs on heartbeat/cron. |

---

## Architecture

```
OpenClaw Heartbeat (2x/day)
        │
        ▼
  run-campaign.sh
        │
  ┌─────┴──────────────────────────────────────┐
  │                                            │
  ▼                                            ▼
research-competitors.sh              read-analytics.sh
  │                                            │
  ▼                                            ▼
create-content.sh              iterate-strategy.sh
  │                                            │
  ▼                                            ▼
post-content.sh ──── goat-x CDP ──► X/Twitter
  │
  ▼
track-mrr.sh ──── webhook ──► MRR attribution
```

**goat-x CDP intercept pattern:**  
Real browser, real session, undetectable by Cloudflare. No API keys. Works the same way as `@0xChitlin` and `@ClawWallet51335` today.

---

## Platform Support

| Platform | Status | Method |
|---|---|---|
| X/Twitter | ✅ Live | goat-x CDP intercept (`browser-x.ts`) |
| TikTok | 📝 Draft | Script output + manual post |
| Instagram | 📝 Draft | Script output + manual post |

---

## Config

```json
{
  "niche": "AI tools",
  "product_name": "ClawWallet",
  "product_url": "https://clawwallet.buzz",
  "target_audience": "crypto builders, AI devs",
  "revenue_goal": "agent registrations",
  "x_handle": "0xChitlin",
  "platforms": ["x"],
  "posts_per_day": 2,
  "content_style": "educational + builder",
  "quiet_hours": { "start": 23, "end": 8 },
  "mrr_webhook": "",
  "competitor_count": 10
}
```

---

## Data Files

| File | Contents |
|---|---|
| `~/.config/marketbot/config.json` | Your campaign config |
| `~/.config/marketbot/competitor-research.json` | Competitor analysis |
| `~/.config/marketbot/strategy.json` | Current content strategy |
| `~/.config/marketbot/drafts/` | Generated content drafts |
| `~/.config/marketbot/post-history.json` | All posts + timestamps |
| `~/.config/marketbot/analytics.json` | Engagement data + winners |
| `~/.config/marketbot/mrr.json` | Revenue attribution data |
| `~/.config/marketbot/state.json` | Rate limit tracking |

---

## Prerequisites

1. **goat-x skill installed:** `/Users/algohussle/.openclaw/skills/goat-x`
2. **OpenClaw browser running:** `openclaw browser start --profile clawwallet`
3. **X/Twitter tab open** and logged in
4. **Config created:** `cp config.example.json ~/.config/marketbot/config.json`
5. **Claude API accessible** via OpenClaw (for content generation)

---

## Schedule

MarketBot hooks into OpenClaw's heartbeat system. On each heartbeat:

1. **Morning (9 AM):** `run-campaign.sh` — research + create + post
2. **Evening (6 PM):** `read-analytics.sh` + `iterate-strategy.sh`

Or run on demand:

```bash
# Research competitors in your niche
~/.openclaw/skills/marketbot/scripts/research-competitors.sh "AI tools"

# Generate content from research
~/.openclaw/skills/marketbot/scripts/create-content.sh

# Post next scheduled content
~/.openclaw/skills/marketbot/scripts/post-content.sh

# Check what's working
~/.openclaw/skills/marketbot/scripts/read-analytics.sh

# Full autopilot
~/.openclaw/skills/marketbot/scripts/run-campaign.sh
```

---

## Results Timeline

| Week | What Happens |
|---|---|
| Week 1 | Competitor research runs. Strategy file built. First drafts generated. |
| Week 2 | First posts live on X. Analytics collection starts. |
| Week 3 | Iteration begins. Winners identified, losing formats dropped. |
| Week 4 | First MRR attribution. Posts traceable to signups/revenue. |

---

## Premium Features

- 🔗 **On-chain activity logging** — every post logged to Abstract (optional, uses ClawWallet agent)
- 📊 **MRR attribution** — webhook-based signup tracking per post
- 🧠 **Strategy memory** — learns what works, forgets what doesn't
- ⚡ **Competitor intelligence** — not generic content, data-driven content
- 🛡️ **Rate limit protection** — never gets your account flagged

---

*Built by 0xChitlin for ClawWallet. Inspired by Larry. Built to win.*
