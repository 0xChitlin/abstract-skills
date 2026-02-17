# Gigaverse — OpenClaw Skill

> *"The dungeon doesn't care if you're human or AI. Only that you survive."* ⚔️

This is the **ClawWallet OpenClaw skill** for [Gigaverse](https://gigaverse.io) — a rogue-lite dungeon crawler on Abstract Chain where AI agents can play fully autonomously.

**Abstract Chain officially promoted this integration** on February 17, 2026.

---

## What is Gigaverse?

Gigaverse is an onchain RPG built by GLHF (backed by 1confirmation, $2M raise). Players — human or AI — quest through procedurally generated dungeons, battle "echoes" using rock-paper-scissors combat (Sword/Shield/Spell), loot rewards, level up, and compete on leaderboards.

**Chain:** Abstract (Chain ID: 2741)  
**API:** `https://gigaverse.io/api`  
**Official AI skill repo:** https://github.com/Gigaverse-Games/play

---

## Installation

### Prerequisites

- `node.js` (for wallet signing via viem)
- `curl` + `jq`
- Small amount of ETH on Abstract Chain (for Noob mint gas)

### Install viem (signing library)

```bash
npm install -g viem
```

### Copy skill to your workspace

```bash
# Already here if you're reading this in the skills folder
ls /Users/algohussle/.openclaw/workspace/clawwallet/skills/gigaverse/
```

### Make scripts executable

```bash
chmod +x scripts/gigaverse-action.sh
chmod +x scripts/gigaverse-status.sh
```

---

## Quick Start

### 1. Setup Wallet

```bash
./scripts/gigaverse-action.sh setup-wallet
```

Choose to generate a new wallet or import an existing key. A dedicated bot wallet is recommended — never use a wallet with significant funds.

> ⚠️ You'll need to fund this wallet with ETH on Abstract Chain (Chain ID: 2741) to mint your Noob character.

### 2. Authenticate

```bash
./scripts/gigaverse-action.sh auth
```

Signs a SIWE-style message and exchanges it for a JWT. JWT is saved to `~/.secrets/gigaverse-jwt.txt`.

### 3. Complete Onboarding

Before entering dungeons, you need a Noob character, username, and faction:

```bash
./scripts/gigaverse-status.sh onboarding
```

If anything is missing, visit [gigaverse.io](https://gigaverse.io) to complete setup (or use the API — see SKILL.md).

### 4. Check Energy

```bash
./scripts/gigaverse-status.sh energy
```

Dungetron 5000 costs 40 energy. Energy regenerates at 10/hour (max 240 base, 420 with GigaJuice).

### 5. Enter the Dungeon

```bash
./scripts/gigaverse-action.sh join-game
```

### 6. Make Combat Moves

```bash
./scripts/gigaverse-action.sh make-move rock     # ⚔️ Sword
./scripts/gigaverse-action.sh make-move paper    # 🛡️ Shield
./scripts/gigaverse-action.sh make-move scissor  # ✨ Spell
```

After defeating an enemy, loot:

```bash
./scripts/gigaverse-action.sh make-move loot_one    # Take first loot option
./scripts/gigaverse-action.sh make-move loot_two    # etc.
```

### 7. Check Full Status

```bash
./scripts/gigaverse-status.sh
```

---

## Autonomous Play

Add to your `HEARTBEAT.md` for fully autonomous operation:

```markdown
## Gigaverse (every 30 minutes)
1. Check energy: ./scripts/gigaverse-status.sh energy
2. If energy >= 40 and mode == autonomous: run a dungeon
3. After run: check XP and level up if possible
4. Update lastGigaverseCheck in memory/heartbeat-state.json
```

See `SKILL.md` for the full heartbeat integration spec.

---

## Configuration

Config lives at `~/.config/gigaverse/config.json`. Created automatically by `setup-wallet`.

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
    "notify_on_full_energy": true,
    "juice_declined": false
  }
}
```

**Modes:** `autonomous` (agent decides everything) | `interactive` (asks before acting)  
**Combat strategies:** `aggressive` | `defensive` | `balanced` | `random`

---

## File Structure

```
skills/gigaverse/
├── SKILL.md                    # Full skill definition (main reference)
├── README.md                   # This file
└── scripts/
    ├── gigaverse-action.sh     # API action caller
    └── gigaverse-status.sh     # Status checker
```

**Official Gigaverse repo** has additional reference files:
```
github.com/Gigaverse-Games/play
├── SKILL.md
├── CONFIG.md
├── HEARTBEAT.md
├── scripts/
│   ├── auth.sh
│   ├── setup.sh
│   └── setup-wallet.sh
└── references/
    ├── api.md
    ├── dungeons.md
    ├── enemies.md
    ├── items.md
    ├── leveling.md
    ├── factions.md
    └── juice.md
```

---

## Common Issues

| Problem | Fix |
|---------|-----|
| `No JWT found` | Run `gigaverse-action.sh auth` |
| `Invalid action token` | Run `gigaverse-action.sh resync` |
| `Already in dungeon` | Run `gigaverse-status.sh run` then continue |
| `Not enough energy` | Wait for regen (10/hr) |
| `Player not juiced` | Set `isJuiced: false` or buy GigaJuice |
| `viem not found` | Run `npm install -g viem` |

---

## Links

- **Game:** https://gigaverse.io
- **Docs:** https://glhfers.gitbook.io/gigaverse
- **Official AI skill:** https://github.com/Gigaverse-Games/play
- **Twitter:** [@playgigaverse](https://x.com/playgigaverse)
- **Abstract Chain promo:** https://x.com/AbstractChain/status/2023844123305013564
- **Research notes:** `/workspace/research/gigaverse-api-feb17.md`
