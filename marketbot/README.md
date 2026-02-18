# MarketBot 🤖💰

> **"Your agent does your marketing. You collect the money."**

MarketBot is a premium OpenClaw skill that turns your agent into a full-stack marketing machine. Inspired by "Larry" — the AI marketing agent that generated 1M+ TikTok views and $633 MRR — MarketBot goes further: **X/Twitter, multi-platform, revenue attribution, and strategy that learns.**

---

## What It Does

| | |
|---|---|
| 🔍 **Research** | Scans X/Twitter for top performers in your niche. Extracts what formats, topics, and posting frequencies drive engagement. |
| 🧠 **Create** | Generates 3–5 content variants via Claude — data-driven, not generic. Formats for X (280 chars), TikTok (scripts), and Instagram (captions). |
| 📤 **Post** | Posts to X/Twitter autonomously via goat-x CDP intercept (no API keys, no Cloudflare blocks). TikTok/IG drafts saved for review. |
| 📊 **Analyze** | Checks engagement on every post. Identifies "winners" (>2x average engagement). |
| 🔄 **Iterate** | Updates strategy based on winners. Next content batch uses what's working. Drops what isn't. |
| 💰 **Track MRR** | Webhook-based attribution. Knows which posts drove signups. Weekly revenue summary. |

---

## Quick Start

### 1. Prerequisites

```bash
# goat-x skill (for X/Twitter posting)
ls /Users/algohussle/.openclaw/skills/goat-x
# Should show: browser-x.ts, cli.ts, etc.

# OpenClaw browser running with X logged in
openclaw browser start --profile clawwallet
# Navigate to x.com and log in as @ClawWallet51335 or @0xChitlin
```

### 2. Install

```bash
# Clone or copy the marketbot skill
ls ~/.openclaw/skills/marketbot/scripts/
# Should show all 7 scripts

# Make scripts executable
chmod +x ~/.openclaw/skills/marketbot/scripts/*.sh
```

### 3. Configure

```bash
mkdir -p ~/.config/marketbot

# Copy and edit config
cp ~/.openclaw/skills/marketbot/config.example.json ~/.config/marketbot/config.json
nano ~/.config/marketbot/config.json
```

Set your values:

```json
{
  "niche": "AI tools",
  "product_name": "ClawWallet",
  "product_url": "https://clawwallet.buzz",
  "target_audience": "crypto builders, AI devs",
  "revenue_goal": "agent registrations",
  "x_handle": "ClawWallet51335",
  "platforms": ["x"],
  "posts_per_day": 2,
  "content_style": "educational + builder"
}
```

### 4. Run Your First Campaign

```bash
# Research competitors in your niche
~/.openclaw/skills/marketbot/scripts/research-competitors.sh "AI tools"

# Generate content based on research
~/.openclaw/skills/marketbot/scripts/create-content.sh

# Review drafts
cat ~/.config/marketbot/drafts/*_x_drafts.txt

# Post the best one (or dry-run first)
~/.openclaw/skills/marketbot/scripts/post-content.sh --dry-run
~/.openclaw/skills/marketbot/scripts/post-content.sh

# Or just run full autopilot
~/.openclaw/skills/marketbot/scripts/run-campaign.sh
```

---

## Commands Reference

### `research-competitors.sh`
```bash
research-competitors.sh [niche_keyword]
research-competitors.sh "crypto wallet"
research-competitors.sh "AI developer tools"
```
Finds top X accounts in your niche. Saves findings to `~/.config/marketbot/competitor-research.json`.

### `create-content.sh`
```bash
create-content.sh                    # use config defaults
create-content.sh --count 5          # generate 5 variants
create-content.sh --style "casual"   # override content style
```
Generates content batches. Saves to `~/.config/marketbot/drafts/`.

### `post-content.sh`
```bash
post-content.sh                                    # auto-pick next draft
post-content.sh --batch batch_20250217 --variant v1  # specific content
post-content.sh --text "Custom tweet text"         # direct post
post-content.sh --dry-run                          # preview without posting
```

### `read-analytics.sh`
```bash
read-analytics.sh                    # check last 7 days
read-analytics.sh --days 14          # check last 2 weeks
read-analytics.sh --handle @myacct   # check specific handle
```

### `iterate-strategy.sh`
```bash
iterate-strategy.sh                  # update strategy from analytics
iterate-strategy.sh --generate-content  # update + auto-generate next batch
```

### `track-mrr.sh`
```bash
track-mrr.sh                         # check for new conversions
track-mrr.sh --summary               # weekly MRR summary
track-mrr.sh --record POST_URL       # record a manual conversion
track-mrr.sh --setup-webhook         # show webhook setup instructions
```

### `run-campaign.sh`
```bash
run-campaign.sh                      # full autopilot (heartbeat mode)
run-campaign.sh --status             # show current state
run-campaign.sh --dry-run            # simulate all steps
run-campaign.sh --force-research     # force re-research
run-campaign.sh --force-post         # post regardless of limits
```

---

## Config Options

| Key | Default | Description |
|---|---|---|
| `niche` | required | Topic niche (e.g., "AI tools", "crypto", "fitness app") |
| `product_name` | required | Your product name |
| `product_url` | required | Your product URL |
| `target_audience` | required | Who you're targeting |
| `revenue_goal` | required | What constitutes a conversion |
| `x_handle` | required | Your X/Twitter handle (without @) |
| `platforms` | `["x"]` | Platforms to use: `x`, `tiktok`, `instagram` |
| `posts_per_day` | `2` | Max posts per day on X |
| `content_style` | `"educational + builder"` | Tone: educational, casual, controversial, technical |
| `quiet_hours.start` | `23` | Hour (0-23) to stop posting |
| `quiet_hours.end` | `8` | Hour (0-23) to resume posting |
| `mrr_webhook` | `""` | Webhook URL for conversion tracking |
| `mrr_webhook_token` | `""` | Auth token for webhook |
| `competitor_count` | `10` | How many competitors to analyze |

---

## OpenClaw Heartbeat Integration

Add to your `HEARTBEAT.md` to run automatically:

```markdown
## MarketBot Campaign
- Run: ~/.openclaw/skills/marketbot/scripts/run-campaign.sh
- Frequency: 2x daily (9 AM + 6 PM)
- Check status: run-campaign.sh --status
```

Or add a cron via OpenClaw:

```bash
openclaw cron add "marketbot-morning" "0 9 * * *" \
  "~/.openclaw/skills/marketbot/scripts/run-campaign.sh"

openclaw cron add "marketbot-evening" "0 18 * * *" \
  "~/.openclaw/skills/marketbot/scripts/run-campaign.sh"
```

---

## Example: SaaS Product Campaign

**Scenario:** You're launching ClawWallet — an agent wallet for Abstract Chain.

**Config:**
```json
{
  "niche": "AI crypto agents",
  "product_name": "ClawWallet",
  "product_url": "https://clawwallet.buzz",
  "target_audience": "crypto builders, Abstract chain devs",
  "revenue_goal": "agent registrations",
  "x_handle": "ClawWallet51335",
  "platforms": ["x"],
  "posts_per_day": 2,
  "content_style": "educational + builder",
  "quiet_hours": { "start": 23, "end": 8 }
}
```

**What MarketBot does:**
1. Researches top accounts in "AI crypto agents" — finds @elonmusk, @VitalikButerin, etc. (just kidding, finds actual niche builders)
2. Notes: threads get 3x engagement, technical content outperforms hype
3. Generates: 5 content variants — 2 threads, 1 question, 2 tips
4. Posts: best 2 per day on X via goat-x CDP
5. Reads analytics after 24h: which posts got traction
6. Updates strategy: "threads + code snippets = winners"
7. Next batch: more threads, code examples, fewer hype posts

---

## Expected Results Timeline

| Week | What Happens |
|---|---|
| **Week 1** | Competitor research runs. Strategy file built. First 5-10 content batches generated. You review drafts. |
| **Week 2** | First posts live on X. Analytics collection starts. Early engagement signals coming in. |
| **Week 3** | Strategy iterates based on real data. Winning formats identified. Losing formats dropped. Content quality improves automatically. |
| **Week 4** | MRR attribution starts. Posts traceable to signups/revenue. First MRR data. |
| **Month 2** | Consistent posting cadence. Strategy fully personalized to your audience. Revenue correlation established. |
| **Month 3** | Snowball effect. High-performing posts identified and replicated. Audience growth compounds. |

---

## Architecture

```
OpenClaw Heartbeat
    │
    ▼
run-campaign.sh
    ├── research-competitors.sh    ← goat-x CDP search
    │       └── competitor-research.json
    ├── create-content.sh          ← Claude (via OpenClaw)
    │       └── drafts/*.json
    ├── post-content.sh            ← goat-x CDP tweet
    │       └── post-history.json
    ├── read-analytics.sh          ← goat-x CDP search
    │       └── analytics.json
    ├── iterate-strategy.sh        ← pattern analysis
    │       └── strategy.json
    └── track-mrr.sh               ← webhook + attribution
            └── mrr.json
```

---

## Data Files

All data lives in `~/.config/marketbot/`:

| File | Description |
|---|---|
| `config.json` | Your campaign configuration |
| `competitor-research.json` | Latest competitor analysis |
| `strategy.json` | Current content strategy + history |
| `drafts/` | Generated content batches |
| `post-history.json` | Every post ever made |
| `analytics.json` | Latest engagement data + winners |
| `mrr.json` | Revenue attribution data |
| `state.json` | Rate limit state (posts today, etc.) |
| `*.log` | Operation logs per script |

---

## goat-x CDP Pattern

MarketBot uses the same goat-x CDP intercept pattern as `@0xChitlin` and `@ClawWallet51335`:

- **Real browser**, real session — no synthetic API calls
- **Undetectable** by Cloudflare, X's bot detection, TLS fingerprinting
- **No API keys** — works even after X's API pricing changes
- **Profile-based** — uses `--profile clawwallet` or `--profile openclaw`

X/Twitter is the only platform with automated posting. TikTok and Instagram require manual posting (scripts are generated, you record/post).

---

## Premium Features

MarketBot is a **premium ClawWallet skill**:

- 🔗 Strategy memory across iterations (learns over months, not days)
- 📊 MRR attribution — know exactly which posts drive revenue
- ⚡ Competitor intelligence — data-driven content, not generic
- 🛡️ Rate limit protection — respects platform limits automatically
- 🧠 Multi-iteration learning — gets smarter every week

---

## Troubleshooting

**goat-x not found:**
```bash
ls /Users/algohussle/.openclaw/skills/goat-x/src/cli.ts
# If missing, install goat-x skill first
```

**Browser not running:**
```bash
openclaw browser status --profile clawwallet
openclaw browser start --profile clawwallet
```

**Rate limit hit:**
```bash
cat ~/.config/marketbot/state.json
# Shows posts_today — resets at midnight
```

**Content generation failed:**
```bash
# Check if openclaw run works
openclaw run --prompt "say hi" --model anthropic/claude-opus-4-5
```

---

*Built by 0xChitlin for ClawWallet. If this drives your MRR, send a tweet.*  
*GitHub: [abstract-skills/marketbot](https://github.com/0xChitlin/abstract-skills/tree/main/marketbot)*
