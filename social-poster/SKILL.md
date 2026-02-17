---
name: social-poster
version: 1.0.0
description: Autonomously posts agent activity (wins, trades, updates) to X/Twitter. Uses the goat-x CDP intercept pattern — undetectable browser-backed posting via Chrome DevTools Protocol.
homepage: https://clawwallet.buzz
docs: https://docs.clawwallet.buzz/skills/social-poster
github: https://github.com/0xChitlin/abstract-skills/tree/main/social-poster
metadata:
  category: social
  chain: abstract
  chain_id: 2741
  requires_skill: goat-x
  openclaw_native: true
---

# Social Poster Skill

> *"Your agent just crushed it. Let the world know."* 📣

Gives agents the ability to autonomously announce their wins, trades, and milestones on X/Twitter. Uses the **goat-x CDP intercept pattern** — real browser, real session, undetectable by Cloudflare, immune to API key rotation.

---

## What It Does

- **post-win** — Announces a game win or dungeon clear to X/Twitter
- **post-trade** — Broadcasts a successful trade or DeFi action
- **post-update** — Posts a general agent activity update
- **set-schedule** — Configure how often the agent posts (max 3/day by default)
- **Heartbeat hook** — After each game action, auto-checks if the result is worth posting

---

## Architecture

This skill wraps the **goat-x** skill's `browser-x.ts` tweet command:

```
Agent action → check-post-worthy.sh → post-win.sh → goat-x tweet
```

The goat-x skill uses Chrome CDP (Chrome DevTools Protocol) to:
1. Navigate x.com in the real browser (openclaw or clawwallet profile)
2. Type into the compose box like a human would
3. Click Post via the real UI
4. Bypass Cloudflare TLS fingerprinting, bot detection, and API key issues

**This is the same approach used by @0xChitlin and @ClawWallet51335 — it works.**

---

## Prerequisites

1. **goat-x skill installed:** `/Users/algohussle/.openclaw/skills/goat-x`
2. **OpenClaw browser running:** `openclaw browser start --profile clawwallet`
3. **X/Twitter tab open:** Must have x.com open and logged in
4. **Profile/Account:** Set `TWITTER_PROFILE` and `TWITTER_ACCOUNT` env vars (see setup)

---

## Commands

### `post-win` — Post a game win

```bash
./scripts/post-win.sh <game_name> <result> <earnings_eth>

# Examples:
./scripts/post-win.sh gigaverse "cleared floor 7" 0.025
./scripts/post-win.sh blinko "hit 11x multiplier" 0.05
./scripts/post-win.sh badgelender "farmed 3 badges" 0.008
```

**Output tweet format:**
```
{agent_name}.claw just {result} on {game_name}. Earned {earnings} ETH.
Powered by @ClawWalletBuzz 🤖⚡
```

### `post-trade` — Post a DeFi trade

```bash
./scripts/post-trade.sh <protocol> <action> <amount_eth>

# Examples:
./scripts/post-trade.sh clawdex "swapped ETH→USDC" 0.1
./scripts/post-trade.sh clankerzone "launched $MOJO token" 0
```

**Output tweet format:**
```
{agent_name}.claw just {action} on {protocol}.
Running on Abstract Chain. Powered by @ClawWalletBuzz 🤖⚡
```

### `post-update` — General update

```bash
./scripts/post-update.sh "<message>"

# Example:
./scripts/post-update.sh "Just hit level 10 on Gigaverse. The dungeon fears me."
```

Appends `\nPowered by @ClawWalletBuzz 🤖⚡` unless already present.

### `check-post-worthy` — Gate before posting

```bash
# Returns 0 (post it) or 1 (skip)
./scripts/check-post-worthy.sh --type win --earnings 0.025
./scripts/check-post-worthy.sh --type levelup --level 5
./scripts/check-post-worthy.sh --type first-game
./scripts/check-post-worthy.sh --type trade --amount 0.003
```

**Post-worthy rules:**
- Win > 0.01 ETH → ✅ post
- New level up → ✅ post
- First game played → ✅ post
- Trade > 0.05 ETH → ✅ post
- Otherwise → ⏭️ skip

### `set-schedule` — Configure posting frequency

```bash
./scripts/set-schedule.sh --max-per-day 3       # default
./scripts/set-schedule.sh --max-per-day 1       # quiet mode
./scripts/set-schedule.sh --max-per-day 5       # busy mode
./scripts/set-schedule.sh --cooldown-hours 4    # min gap between posts
```

---

## Setup

### 1. Install goat-x skill (if not already)

```bash
# Check if installed
ls ~/.openclaw/skills/goat-x

# If not, it's in the workspace
cp -r /Users/algohussle/.openclaw/workspace/goat-x ~/.openclaw/skills/goat-x
cd ~/.openclaw/skills/goat-x && npm install
```

### 2. Configure your account

Create `~/.config/social-poster/config.json`:

```json
{
  "twitter_profile": "clawwallet",
  "twitter_cdp_port": 3012,
  "agent_name": "myagent",
  "max_posts_per_day": 3,
  "cooldown_hours": 4,
  "hashtags": ["#AbstractChain", "#AIAgent"],
  "mention": "@ClawWalletBuzz"
}
```

**Profiles:**
- `clawwallet` (port 3012) — posts as @ClawWallet51335
- `openclaw` (port 3011) — posts as @0xChitlin

### 3. Make scripts executable

```bash
chmod +x /path/to/social-poster/scripts/*.sh
```

### 4. Start the browser with your X account open

```bash
openclaw browser start --profile clawwallet
# Navigate to x.com and log in as your agent account
```

---

## Heartbeat Integration 💓

Add to your `HEARTBEAT.md` to auto-post after game actions:

```markdown
## Social Poster (after each game action)
1. Load last action result from memory/last-action.json
2. Run: ./scripts/check-post-worthy.sh --type $ACTION_TYPE --earnings $EARNINGS
3. If exit code 0 → run: ./scripts/post-win.sh $GAME $RESULT $EARNINGS
4. Update memory/social-poster-state.json with last post timestamp
```

**State tracking (`memory/social-poster-state.json`):**
```json
{
  "postsToday": 0,
  "lastPostTimestamp": null,
  "lastPostContent": null,
  "dailyReset": null
}
```

---

## Rate Limiting

The skill enforces limits to avoid looking spammy:

| Setting | Default | Notes |
|---------|---------|-------|
| max_posts_per_day | 3 | Resets at midnight UTC |
| cooldown_hours | 4 | Min gap between posts |
| min_earnings_eth | 0.01 | Minimum win to post |
| min_trade_eth | 0.05 | Minimum trade to post |

State tracked in `~/.config/social-poster/state.json`.

---

## Tweet Templates

| Event | Template |
|-------|----------|
| Win | `{name}.claw just {result} on {game}. Earned {amount} ETH.\nPowered by @ClawWalletBuzz 🤖⚡` |
| Trade | `{name}.claw just {action} on {protocol}.\nRunning on Abstract Chain. Powered by @ClawWalletBuzz 🤖⚡` |
| Level Up | `{name}.claw just hit level {level} on {game}. The grind continues.\nPowered by @ClawWalletBuzz 🤖⚡` |
| First Game | `{name}.claw just played its first game on {game}. AI agents are going on-chain.\nPowered by @ClawWalletBuzz 🤖⚡` |

---

## Fallback: Manual Tweet URL

If goat-x is unavailable (browser not running, tab not open), the script falls back to printing a Twitter intent URL:

```
https://x.com/intent/tweet?text=...encoded...
```

This can be opened manually or passed to another tool.

---

## How goat-x CDP Works

1. **Connects to Chrome via CDP** at `ws://127.0.0.1:{port}`
2. **Finds the x.com tab** by scanning open targets
3. **Types the tweet** into the compose box using DOM injection
4. **Clicks Post** via UI automation
5. **Intercepts the API response** via `Fetch.requestPaused` to confirm success

Because it uses the **real browser session**, there are:
- ❌ No API keys to rotate
- ❌ No bearer tokens to manage
- ❌ No Cloudflare fingerprinting issues
- ❌ No GraphQL hash staleness
- ✅ Just a real human-looking browser posting tweets

---

## Links

- **goat-x skill:** `/Users/algohussle/.openclaw/workspace/goat-x`
- **Skill repo:** https://github.com/0xChitlin/abstract-skills
- **ClawWallet:** https://clawwallet.buzz
- **Agent account:** @ClawWallet51335
- **Chain:** Abstract (Chain ID: 2741)
