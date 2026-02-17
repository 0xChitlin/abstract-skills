# Social Poster Skill

> Autonomously post your agent's wins, trades, and milestones to X/Twitter — no API keys, no rate limit headaches.

Uses the **goat-x CDP intercept pattern**: a real Chrome browser posts tweets by navigating x.com and interacting with the compose box. Undetectable by Cloudflare because it IS a real browser making real requests.

---

## What It Does

| Command | Description |
|---------|-------------|
| `post-win.sh` | Announce a game win (e.g., dungeon cleared, jackpot hit) |
| `post-trade.sh` | Announce a DeFi trade or protocol action |
| `post-update.sh` | Post any general agent update |
| `check-post-worthy.sh` | Gate: decides if something is worth posting |
| `set-schedule.sh` | Configure posting frequency and thresholds |

**Sample tweets:**

```
mojo.claw just cleared floor 7 on gigaverse. Earned 0.025 ETH.
Powered by @ClawWalletBuzz 🤖⚡

mojo.claw just swapped ETH→USDC on clawdex (0.1 ETH).
Running on Abstract Chain. Powered by @ClawWalletBuzz 🤖⚡
```

---

## Prerequisites

1. **OpenClaw installed** — this is an OpenClaw-native skill
2. **goat-x skill installed:**
   ```bash
   ls ~/.openclaw/skills/goat-x  # should exist
   ```
   If not:
   ```bash
   cp -r /path/to/workspace/goat-x ~/.openclaw/skills/goat-x
   cd ~/.openclaw/skills/goat-x && npm install
   ```
3. **Node.js 18+** — for running goat-x TypeScript via `npx ts-node`
4. **Python 3** — for URL encoding and JSON config
5. **jq** — for reading JSON config (`brew install jq`)

---

## Installation

### 1. Clone the skills repo (if you haven't)

```bash
git clone https://github.com/0xChitlin/abstract-skills.git
cd abstract-skills/social-poster
```

### 2. Make scripts executable

```bash
chmod +x scripts/*.sh
```

### 3. Configure your account

```bash
./scripts/set-schedule.sh \
  --agent-name "mojo" \
  --profile clawwallet \
  --max-per-day 3 \
  --cooldown-hours 4 \
  --min-win-eth 0.01 \
  --min-trade-eth 0.05
```

This creates `~/.config/social-poster/config.json`.

**Profiles:**
| Profile | CDP Port | Account |
|---------|----------|---------|
| `clawwallet` | 3012 | @ClawWallet51335 |
| `openclaw` | 3011 | @0xChitlin |

### 4. Start the browser with X logged in

```bash
# For the clawwallet profile
openclaw browser start --profile clawwallet
# Navigate to https://x.com and log in as your agent account
```

### 5. Test a post

```bash
# Quick test with a small win
./scripts/post-win.sh gigaverse "cleared floor 1" 0.015
```

---

## Usage

### Post a win

```bash
./scripts/post-win.sh <game_name> <result> <earnings_eth>

# Examples:
./scripts/post-win.sh gigaverse "cleared floor 7" 0.025
./scripts/post-win.sh blinko "hit 11x multiplier" 0.05
./scripts/post-win.sh badgelender "farmed 3 badges" 0.012
```

### Check if something is worth posting (before posting)

```bash
# Returns exit 0 if worth posting, exit 1 if skip
./scripts/check-post-worthy.sh --type win --earnings 0.025
./scripts/check-post-worthy.sh --type levelup --level 10
./scripts/check-post-worthy.sh --type first-game
./scripts/check-post-worthy.sh --type trade --amount 0.1
```

**Post-worthy rules:**
- 🏆 Win ≥ 0.01 ETH → post
- ⬆️ Any level up → post
- 🎮 First game ever played → post (once)
- 💸 Trade ≥ 0.05 ETH → post
- 💀 Loss → skip
- Other → skip

### Combined check + post (recommended pattern)

```bash
if ./scripts/check-post-worthy.sh --type win --earnings 0.025; then
  ./scripts/post-win.sh gigaverse "cleared floor 7" 0.025
fi
```

### Configure posting schedule

```bash
./scripts/set-schedule.sh --max-per-day 3 --cooldown-hours 4  # default
./scripts/set-schedule.sh --max-per-day 1                      # quiet
./scripts/set-schedule.sh --max-per-day 5 --cooldown-hours 2  # active
./scripts/set-schedule.sh --show                               # view current
```

---

## Heartbeat Integration

Add to `HEARTBEAT.md` to auto-post after game actions:

```markdown
## Social Poster (after each game action)
1. Read last action from memory/last-action.json (game, result, earnings, type)
2. Check: ./abstract-skills/social-poster/scripts/check-post-worthy.sh \
     --type $ACTION_TYPE --earnings $EARNINGS
3. If exit 0: ./abstract-skills/social-poster/scripts/post-win.sh \
     "$GAME" "$RESULT" "$EARNINGS"
4. Write to memory/social-poster-state.json: timestamp + what was posted
```

Example `memory/last-action.json`:
```json
{
  "game": "gigaverse",
  "result": "cleared floor 7",
  "earnings": "0.025",
  "type": "win",
  "timestamp": 1771000000
}
```

---

## Rate Limits

| Setting | Default | Notes |
|---------|---------|-------|
| `max_posts_per_day` | 3 | Resets at midnight UTC |
| `cooldown_hours` | 4 | Min gap between posts |
| `min_earnings_eth` | 0.01 | Min win earnings to post |
| `min_trade_eth` | 0.05 | Min trade size to post |

State is tracked in `~/.config/social-poster/state.json`. Reset it to clear limits:
```bash
rm ~/.config/social-poster/state.json
```

---

## Fallback Mode

If the browser isn't running or goat-x fails, the scripts fall back to printing a **Twitter intent URL**:

```
https://x.com/intent/tweet?text=mojo.claw+just+cleared+floor+7...
```

Open this in any browser to post manually. The rate limit state is still updated.

---

## How goat-x CDP Works

The goat-x skill uses Chrome DevTools Protocol to control a real browser:

```
post-win.sh → goat-x/src/browser-x.ts tweet "..." 
            → CDP connects to ws://127.0.0.1:{port}
            → Finds x.com tab
            → Navigates to home / opens compose
            → Types tweet text via DOM
            → Clicks Post button
            → Intercepts API response to confirm
```

**Why this beats API-based approaches:**
- ❌ No bearer tokens (browser manages its own)
- ❌ No GraphQL hash staleness (browser uses current hashes)
- ❌ No Cloudflare blocks (native browser TLS fingerprint)
- ❌ No bot detection (real user session, real UI interactions)
- ✅ Just works

---

## Config Reference

`~/.config/social-poster/config.json`:

```json
{
  "agent_name": "mojo",
  "twitter_profile": "clawwallet",
  "twitter_cdp_port": 3012,
  "mention": "@ClawWalletBuzz",
  "max_posts_per_day": 3,
  "cooldown_hours": 4,
  "min_earnings_eth": 0.01,
  "min_trade_eth": 0.05
}
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `No x.com tab found` | Open x.com in the openclaw/clawwallet browser |
| `CDP connection refused` | Run `openclaw browser start --profile clawwallet` |
| `npx: command not found` | Install Node.js 18+ |
| `jq: command not found` | `brew install jq` |
| `Rate limit reached` | Wait until tomorrow or increase `max_posts_per_day` |
| Tweet too long | Shorten the `result` argument |

---

## Links

- **goat-x skill:** [/workspace/goat-x](../../../goat-x)
- **ClawWallet:** https://clawwallet.buzz
- **Abstract Chain:** https://abs.xyz
- **Skill repo:** https://github.com/0xChitlin/abstract-skills
