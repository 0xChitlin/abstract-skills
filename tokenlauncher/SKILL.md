---
name: tokenlauncher
version: 1.0.0
description: Autonomously launch tokens on Abstract Chain — deploys contract, seeds liquidity, promotes via X
homepage: https://clawwallet.buzz
docs: https://docs.clawwallet.buzz/skills/tokenlauncher
github: https://github.com/0xChitlin/abstract-skills/tree/main/tokenlauncher
metadata:
  category: defi
  tier: free
  chain: abstract
  chain_id: 2741
  contract: "0x89B974b6977157f1E7D743D70e28fCA1B5Ca84b5"
  requires_skill: goat-x
  openclaw_native: true
  heartbeat: false
---

# TokenLauncher

> *"From idea to on-chain token in one command."* 🚀

TokenLauncher is an OpenClaw skill that lets any `.claw` agent autonomously launch ERC-20 tokens on Abstract Chain using the **ClawTokenLauncher** contract. It handles everything: deployment, liquidity seeding, launch history tracking, and optional X/Twitter promotion — all without manual steps.

---

## Contract

**ClawTokenLauncher** — Abstract Mainnet (Chain ID 2741)  
Address: `0x89B974b6977157f1E7D743D70e28fCA1B5Ca84b5`  
[View on Abscan](https://abscan.org/address/0x89B974b6977157f1E7D743D70e28fCA1B5Ca84b5)

### ABI (relevant functions)

```json
[
  {
    "name": "launchToken",
    "type": "function",
    "stateMutability": "payable",
    "inputs": [
      { "name": "name",         "type": "string"  },
      { "name": "symbol",       "type": "string"  },
      { "name": "supply",       "type": "uint256" },
      { "name": "liquidityETH", "type": "uint256" }
    ],
    "outputs": [
      { "name": "tokenAddress", "type": "address" },
      { "name": "lpAddress",    "type": "address" }
    ]
  }
]
```

---

## Config Schema

```json
{
  "tokenName":     "string  — full token name (e.g. 'Claw Token')",
  "tokenSymbol":   "string  — ticker symbol, max 8 chars (e.g. 'CLAW')",
  "totalSupply":   "number  — total supply in whole tokens (e.g. 1000000000)",
  "liquidityETH":  "number  — ETH to seed LP (e.g. 0.05)",
  "twitterHandle": "string  — X handle to post from (e.g. '@ClawWalletHQ')",
  "autoPromote":   "boolean — post to X after launch (true/false)"
}
```

**Config file location:** `~/.config/tokenlauncher/config.json`

---

## Commands

### `launch` — Deploy a token

Launches a new ERC-20 token via ClawTokenLauncher. Seeds liquidity from your agent wallet. Saves results to `launch-history.json`.

**Usage:**
```bash
~/.openclaw/skills/tokenlauncher/scripts/launch-token.sh \
  --name    "My Token" \
  --symbol  "MTK" \
  --supply  1000000000 \
  --liquidity 0.05
```

**Steps performed:**
1. Validates config and wallet balance
2. Calls `launchToken(name, symbol, supply, liquidityETH)` via `cast send` (Foundry) with ETH value attached
3. Parses `tokenAddress` and `lpAddress` from transaction logs
4. Saves entry to `~/.config/tokenlauncher/launch-history.json`
5. Prints summary: token address, Abscan link, LP address

**Required env:**
- `ABSTRACT_PRIVATE_KEY` — agent wallet private key
- `ABSTRACT_RPC_URL` — Abstract Mainnet RPC (defaults to `https://api.mainnet.abs.xyz`)

---

### `status` — Check token health

Fetches on-chain stats for a launched token: price, volume, LP health.

**Usage:**
```bash
~/.openclaw/skills/tokenlauncher/scripts/check-status.sh [TOKEN_ADDRESS]
```

If no address is provided, uses the most recent entry in `launch-history.json`.

**Output:**
- Token name, symbol, total supply
- Current price (if LP active)
- LP ETH/token reserves
- Abscan link

---

### `promote` — Post launch announcement to X

Reads the latest launch from `launch-history.json` and posts a promotion tweet via the goat-x CDP pattern.

**Usage:**
```bash
~/.openclaw/skills/tokenlauncher/scripts/promote-launch.sh [TOKEN_ADDRESS]
```

**Tweet template:**
```
🚀 Just launched $SYMBOL on Abstract Chain via @ClawWalletHQ!
Token: {address} | LP seeded with {eth} ETH | abscan.org/token/{address}
```

**Required:** goat-x skill installed + X browser session active (openclaw or clawwallet browser profile).

**Rate limit protection:** Script checks `~/.config/tokenlauncher/state.json` for last promote timestamp. Enforces 15-minute minimum between posts.

---

### `list` — Show launch history

Prints all tokens launched by this agent, with status and links.

**Usage:**
```bash
cat ~/.config/tokenlauncher/launch-history.json | jq '.'
```

Or via the run-autonomous script with `--mode list`.

---

## Autopilot Mode

Run the full pipeline in one command:

```bash
~/.openclaw/skills/tokenlauncher/scripts/run-autonomous.sh
```

**Pipeline:**
1. Reads `~/.config/tokenlauncher/config.json`
2. Calls `launch-token.sh` with config values
3. Waits for on-chain confirmation (polls Abscan)
4. If `autoPromote: true` → calls `promote-launch.sh`
5. Logs full run to `~/.config/tokenlauncher/logs/YYYY-MM-DD.log`

---

## Data Files

| File | Contents |
|---|---|
| `~/.config/tokenlauncher/config.json` | Token config for autopilot |
| `~/.config/tokenlauncher/launch-history.json` | All launched tokens (address, txHash, LP, timestamp) |
| `~/.config/tokenlauncher/state.json` | Rate limit state for promotions |
| `~/.config/tokenlauncher/logs/` | Dated autopilot run logs |

---

## Prerequisites

1. **Foundry installed:** `cast` must be available (`curl -L https://foundry.paradigm.xyz | bash`)
2. **Agent wallet funded:** Must hold enough ETH for `liquidityETH + gas`
3. **`ABSTRACT_PRIVATE_KEY` set:** In `.env` or shell environment
4. **goat-x skill** (for `promote` command only): `/Users/algohussle/.openclaw/skills/goat-x`
5. **Config created:** `cp ~/.openclaw/skills/tokenlauncher/config.example.json ~/.config/tokenlauncher/config.json`

---

*Built by 0xChitlin for ClawWallet. Powered by ClawTokenLauncher on Abstract.*
