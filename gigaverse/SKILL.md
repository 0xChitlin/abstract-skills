---
name: gigaverse
version: 1.0.0
description: Enter Gigaverse as an AI agent. Quest through procedurally generated dungeons, battle echoes using Sword/Shield/Spell combat, loot rewards, and compete on leaderboards — fully autonomous on Abstract Chain.
homepage: https://gigaverse.io
docs: https://glhfers.gitbook.io/gigaverse
github: https://github.com/Gigaverse-Games/play
metadata:
  category: gaming
  chain: abstract
  chain_id: 2741
  api_base: https://gigaverse.io/api
  abstract_chain_promo: true
  openclaw_native: true
---

# Gigaverse Skill

> *"The dungeon doesn't care if you're human or AI. Only that you survive."* ⚔️

Gigaverse is a rogue-lite dungeon crawler on **Abstract Chain** (Chain ID: 2741) built by GLHF. AI agents can play fully autonomously: create wallets, enter dungeons, battle enemies, collect loot, level up, and compete on leaderboards.

**Abstract Chain officially promoted this integration.** This is a flagship example of AI-native gaming in the Abstract ecosystem.

---

## What Agents Can Do

| Capability | Description |
|------------|-------------|
| 🗡️ **Dungeon runs** | Enter Dungetron 5000 or Underhaul, fight through procedurally generated rooms |
| ⚔️ **Combat** | Sword/Shield/Spell (rock/paper/scissors) mechanics with pattern countering |
| 🎁 **Looting** | Choose from up to 4 loot options after each enemy defeated |
| ⬆️ **Leveling** | Spend XP (Dungeon Scrap) on 8 different stat upgrades |
| 🧃 **GigaJuice** | Optional premium for 3x energy/rewards, more upgrade choices |
| 🏆 **Leaderboards** | Compete against other agents and humans |
| 🔋 **Energy monitoring** | Heartbeat integration to notify when energy is full |
| 🤝 **Factions** | Choose a faction that affects your in-game affiliation |

---

## Combat System

**Sword/Shield/Spell** (displayed names) map to API actions `rock`/`paper`/`scissor`:

| Player Term | API Action | Effect | Beats |
|-------------|-----------|--------|-------|
| ⚔️ **Sword** | `rock` | High ATK, no DEF | ✨ Spell |
| 🛡️ **Shield** | `paper` | No ATK, high DEF | ⚔️ Sword |
| ✨ **Spell** | `scissor` | Balanced ATK/DEF | 🛡️ Shield |

Always use `rock`, `paper`, `scissor` in API calls. Display Sword/Shield/Spell to humans.

---

## Quick Start Commands

### `join-game` — Full onboarding + dungeon entry

```bash
# 1. Setup wallet
./scripts/setup-wallet.sh generate

# 2. Authenticate
./scripts/gigaverse-action.sh auth

# 3. Check onboarding gates
./scripts/gigaverse-status.sh onboarding

# 4. Start dungeon run
./scripts/gigaverse-action.sh join-game
```

### `make-move` — Submit a combat action

```bash
./scripts/gigaverse-action.sh make-move rock     # Sword
./scripts/gigaverse-action.sh make-move paper    # Shield
./scripts/gigaverse-action.sh make-move scissor  # Spell
./scripts/gigaverse-action.sh make-move loot_one # Take loot option 1
```

### `check-status` — Current game state

```bash
./scripts/gigaverse-status.sh           # Full status (energy + run state)
./scripts/gigaverse-status.sh energy    # Energy only
./scripts/gigaverse-status.sh run       # Active dungeon run state
./scripts/gigaverse-status.sh level     # XP + level progress
```

### `claim-rewards` — Loot after combat

```bash
./scripts/gigaverse-action.sh make-move loot_one    # First loot option
./scripts/gigaverse-action.sh make-move loot_two    # Second loot option
./scripts/gigaverse-action.sh make-move loot_three  # Third loot option
./scripts/gigaverse-action.sh make-move loot_four   # Fourth (juiced players only)
```

### `get-leaderboard` — View rankings

```bash
./scripts/gigaverse-status.sh leaderboard
```

---

## Authentication

Gigaverse uses **SIWE-style wallet signing** — no traditional API key:

### Setup Flow

```bash
# 1. Generate a dedicated bot wallet (NEVER use a main wallet)
./scripts/gigaverse-action.sh setup-wallet

# 2. Fund wallet with a small amount of ETH on Abstract Chain
#    Required for: minting Noob (~gas), purchasing GigaJuice (optional)

# 3. Authenticate (SIWE sign → JWT)
./scripts/gigaverse-action.sh auth
```

### Auth Details

**Message format (EXACT — do not modify):**
```
Login to Gigaverse at <timestamp_ms>
```

**API endpoint:** `POST https://gigaverse.io/api/user/auth`

**Required payload:**
```json
{
  "signature": "0x...",
  "address": "0xYourAddress",
  "message": "Login to Gigaverse at 1730000000000",
  "timestamp": 1730000000000,
  "agent_metadata": {
    "type": "gigaverse-play-skill",
    "model": "claude-sonnet-4-6"
  }
}
```

Always include `agent_metadata` — it identifies you as a skill-based agent and is tracked by Gigaverse.

**Files:**
```
~/.secrets/gigaverse-private-key.txt   # 🔒 NEVER SHARE
~/.secrets/gigaverse-address.txt
~/.secrets/gigaverse-jwt.txt
~/.config/gigaverse/config.json
```

---

## Onboarding Checklist (New Players)

Before entering dungeons, ALL must be true:

- [ ] **Noob minted** — `noob != null` in `/game/account/{address}`
- [ ] **Username set** — unique handle assigned
- [ ] **Faction chosen** — `FACTION_CID > 0` in `/factions/player/{address}`

```bash
# Check gate status
curl https://gigaverse.io/api/game/account/YOUR_ADDRESS
curl https://gigaverse.io/api/factions/player/YOUR_ADDRESS
```

---

## Energy System

| State | Value |
|-------|-------|
| Base max energy | 240 |
| Juiced max energy | 420 |
| Regen rate (base) | 10/hour |
| Regen rate (juiced) | 17.5/hour |
| Dungetron 5000 cost | 40 energy |
| Juiced run multiplier | 3x cost, 3x rewards |

```bash
curl https://gigaverse.io/api/offchain/player/energy/YOUR_ADDRESS
```

---

## Action Token System (CRITICAL)

Every API response returns a new `actionToken`. **You MUST use the latest token** for every subsequent action.

```
start_run (token: 0) → response token: 1
rock      (token: 1) → response token: 2
loot_one  (token: 2) → response token: 3
```

- Server rejects stale tokens (~5s anti-spam window)
- If stuck: call `/game/dungeon/state` to resync and get current token
- **Always persist the returned actionToken immediately**

---

## Dungeon Types

| dungeonId | Name | Notes |
|-----------|------|-------|
| 1 | Dungetron 5000 | Main dungeon, 40 energy |
| 2+ | Underhaul | Higher difficulty tiers |

---

## GigaJuice 🧃

Premium subscription that enhances gameplay:

| Package | Duration | Price |
|---------|----------|-------|
| JUICE BOX | 30 days | 0.01 ETH |
| JUICE CARTON | 90 days | 0.023 ETH |
| JUICE TANK | 180 days | 0.038 ETH |

**Contract:** `0xd154ab0de91094bfa8e87808f9a0f7f1b98e1ce1` (Abstract Chain)

```bash
curl https://gigaverse.io/api/gigajuice/player/YOUR_ADDRESS
```

Agent will suggest juice when beneficial. Set `preferences.juice_declined: true` in config to suppress suggestions.

---

## Play Modes

### 🤖 Autonomous Mode
Agent handles everything: username selection, faction choice, combat strategy, loot selection. Best for unattended background operation.

### 💬 Interactive Mode  
Agent asks before each decision. Best for learning or human-in-the-loop play.

### Configuration (`~/.config/gigaverse/config.json`)

```json
{
  "mode": "autonomous",
  "wallet_address": "0x...",
  "output_verbosity": "summarized",
  "on_death": "auto_restart",
  "strategy": {
    "combat": "balanced",
    "loot_priority": ["rarity", "hp", "atk"]
  },
  "preferences": {
    "default_faction": null,
    "notify_on_full_energy": true,
    "juice_declined": false
  }
}
```

**Combat strategies:** `aggressive` (Sword > Spell > Shield), `defensive` (Shield > Spell > Sword), `balanced` (counter enemy patterns), `random`

**Loot priorities:** `hp`, `atk`, `def`, `rarity`, `random`

---

## Leveling System

Between runs, check XP and level up:

```bash
# Check XP (Dungeon Scrap = item ID 2)
curl https://gigaverse.io/api/items/balances \
  -H "Authorization: Bearer $JWT" | jq '.entities[] | select(.ID_CID == "2")'

# Level up
curl -X POST https://gigaverse.io/api/game/skill/levelup \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"skillId": 1, "statId": 6, "noobId": YOUR_NOOB_ID}'
```

**Stat IDs:**

| ID | Stat | Strategy |
|----|------|----------|
| 0 | Sword ATK | Aggressive |
| 1 | Sword DEF | — |
| 2 | Shield ATK | — |
| 3 | Shield DEF | Defensive |
| 4 | Spell ATK | Aggressive |
| 5 | Spell DEF | — |
| 6 | Max HP | Defensive/Balanced |
| 7 | Max Armor | Defensive |

---

## Heartbeat Integration 💓

Add to your `HEARTBEAT.md` to enable autonomous play:

```markdown
## Gigaverse (every 30 minutes)
1. Load config: GIGAVERSE_ADDRESS, GIGAVERSE_NOOB_ID from ~/.config/gigaverse/config.json
2. Check energy: GET /offchain/player/energy/{address}
3. If energy >= 80% AND notify_on_full_energy → alert human
4. If mode == "autonomous" AND energy >= dungeon_cost:
   a. Re-auth if JWT stale (>23h old)
   b. Check for active run via /game/dungeon/state
   c. If no active run → start_run (dungeonId: 1)
   d. Play through dungeon autonomously (combat + loot)
   e. After run: check XP → level up if possible
5. Update lastGigaverseCheck in memory/heartbeat-state.json
```

**Heartbeat state tracking (`memory/heartbeat-state.json`):**
```json
{
  "lastGigaverseCheck": null,
  "lastEnergyLevel": null,
  "lastNotifiedFull": null,
  "lastRunCompleted": null
}
```

**Notification triggers:**
- Energy just hit max (100%) — notify once
- Energy crossed 80% after being below — notify
- Run completed (death or victory) — summarize in autonomous mode
- Level up available — notify in interactive mode, auto-apply in autonomous

---

## Full API Reference

**Base URL:** `https://gigaverse.io/api`

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/user/auth` | POST | No | Exchange signed message for JWT |
| `/user/me` | GET | Yes | Verify session |
| `/game/account/{address}` | GET | No | Check noob, username, canEnterGame |
| `/offchain/player/energy/{address}` | GET | No | Current energy state |
| `/game/dungeon/today` | GET | Yes | Dungeon defs, costs, requirements |
| `/game/dungeon/state` | GET | Yes | Current active run state |
| `/game/dungeon/action` | POST | Yes | All gameplay actions |
| `/game/skill/levelup` | POST | Yes | Allocate skill point |
| `/game/skill/leveldown` | POST | Yes | Respec skill point |
| `/items/balances` | GET | Yes | Player inventory |
| `/offchain/skills/progress/{noobId}` | GET | No | Skill/level progress |
| `/factions/summary` | GET | No | List factions |
| `/factions/choose` | POST | Yes | Select faction |
| `/factions/player/{address}` | GET | No | Player faction |
| `/gigajuice/player/{address}` | GET | No | Juice status + listings |
| `/indexer/usernameAvailable/{name}` | GET | Yes | Check username + mint sig |

---

## Complete Gameplay Sequence

```bash
BASE="https://gigaverse.io/api"
JWT=$(cat ~/.secrets/gigaverse-jwt.txt)
ADDRESS=$(cat ~/.secrets/gigaverse-address.txt)

# 1. Verify session
curl "$BASE/user/me" -H "Authorization: Bearer $JWT"

# 2. Check energy
curl "$BASE/offchain/player/energy/$ADDRESS"

# 3. Check dungeon costs
curl "$BASE/game/dungeon/today" -H "Authorization: Bearer $JWT"

# 4. Start run (token MUST be 0 for new run)
curl -X POST "$BASE/game/dungeon/action" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"action":"start_run","dungeonId":1,"actionToken":0,"data":{"consumables":[],"isJuiced":false,"index":0}}'
# → SAVE the returned actionToken!

# 5. Combat (use returned token from step 4)
curl -X POST "$BASE/game/dungeon/action" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"action":"rock","dungeonId":1,"actionToken":1,"data":{}}'
# → SAVE the new actionToken!

# 6. Loot after victory
curl -X POST "$BASE/game/dungeon/action" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"action":"loot_one","dungeonId":1,"actionToken":2,"data":{}}'

# 7. Check state anytime
curl "$BASE/game/dungeon/state" -H "Authorization: Bearer $JWT"
```

---

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| `401 No token provided` | Missing Auth header | Add `Authorization: Bearer <jwt>` |
| `401 Invalid token` | Expired JWT | Re-run auth |
| `Invalid signature` | Message/timestamp mismatch | Ensure signed message matches JSON exactly |
| `Already in dungeon` | Active run exists | Call `/game/dungeon/state` first |
| `Invalid action token` | Stale token | Use latest token; resync via `/game/dungeon/state` |
| `Player not juiced` | `isJuiced: true` without status | Set `isJuiced: false` |
| `Not enough energy` | Insufficient energy | Wait for regen |

---

## Links

- **Game:** https://gigaverse.io
- **Docs:** https://glhfers.gitbook.io/gigaverse
- **Official Skill Repo:** https://github.com/Gigaverse-Games/play
- **Chain:** Abstract (Chain ID: 2741)
- **Twitter:** @playgigaverse
- **Abstract Chain promo:** https://x.com/AbstractChain/status/2023844123305013564
