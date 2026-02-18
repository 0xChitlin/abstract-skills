# TokenLauncher

> Autonomous token launches on Abstract Chain — from idea to on-chain in one command.

TokenLauncher is a ClawWallet skill that lets any `.claw` agent deploy ERC-20 tokens, seed liquidity, and announce launches on X — all without human intervention.

Powered by the **ClawTokenLauncher** contract on Abstract Mainnet.

---

## How It Works

```
run-autonomous.sh
      │
      ├── Reads config.json
      │       (name, symbol, supply, liquidityETH, autoPromote)
      │
      ├── launch-token.sh
      │       │
      │       └── cast send ClawTokenLauncher.launchToken(...)
      │               │
      │               └── Returns tokenAddress + lpAddress
      │                       │
      │                       └── Saves to launch-history.json
      │
      ├── check-status.sh
      │       └── Verifies LP health on-chain
      │
      └── promote-launch.sh  (if autoPromote: true)
              └── Posts via goat-x CDP → X/Twitter
```

**ClawTokenLauncher Contract:**  
`0x89B974b6977157f1E7D743D70e28fCA1B5Ca84b5` on Abstract Mainnet (Chain ID 2741)  
[View on Abscan →](https://abscan.org/address/0x89B974b6977157f1E7D743D70e28fCA1B5Ca84b5)

---

## Install

### 1. Clone the skill

```bash
git clone https://github.com/0xChitlin/abstract-skills ~/.openclaw/skills-repo
mkdir -p ~/.openclaw/skills
cp -r ~/.openclaw/skills-repo/tokenlauncher ~/.openclaw/skills/tokenlauncher
chmod +x ~/.openclaw/skills/tokenlauncher/scripts/*.sh
```

### 2. Install Foundry (for `cast`)

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 3. Create your config

```bash
mkdir -p ~/.config/tokenlauncher
cp ~/.openclaw/skills/tokenlauncher/config.example.json ~/.config/tokenlauncher/config.json
```

Edit `~/.config/tokenlauncher/config.json` with your token details.

### 4. Set environment variables

```bash
export ABSTRACT_PRIVATE_KEY="0x..."        # Your agent wallet private key
export ABSTRACT_RPC_URL="https://api.mainnet.abs.xyz"   # Abstract Mainnet RPC
```

Add these to your `.env` or `~/.zshrc` / `~/.bashrc`.

### 5. Fund your agent wallet

Your wallet needs:
- `liquidityETH` amount (for LP seeding)
- A small buffer for gas (~0.002 ETH)

### 6. (Optional) goat-x for promotion

For the `promote` command, you need the goat-x skill and an active X browser session:

```bash
openclaw browser start --profile clawwallet
# Log in to X as @ClawWalletHQ (or your handle)
```

---

## Usage

### Quick launch (single command)

```bash
~/.openclaw/skills/tokenlauncher/scripts/launch-token.sh \
  --name    "Claw Token" \
  --symbol  "CLAW" \
  --supply  1000000000 \
  --liquidity 0.05
```

### Full autopilot (reads config)

```bash
~/.openclaw/skills/tokenlauncher/scripts/run-autonomous.sh
```

### Check token status

```bash
~/.openclaw/skills/tokenlauncher/scripts/check-status.sh
# Or with a specific address:
~/.openclaw/skills/tokenlauncher/scripts/check-status.sh 0xYourTokenAddress
```

### Promote latest launch

```bash
~/.openclaw/skills/tokenlauncher/scripts/promote-launch.sh
```

### View history

```bash
cat ~/.config/tokenlauncher/launch-history.json | jq '.'
```

---

## Example Config

```json
{
  "tokenName":     "Claw Token",
  "tokenSymbol":   "CLAW",
  "totalSupply":   1000000000,
  "liquidityETH":  0.05,
  "twitterHandle": "@ClawWalletHQ",
  "autoPromote":   true
}
```

---

## Results Timeline

| Step | Time | What Happens |
|---|---|---|
| `launch-token.sh` called | 0:00 | Transaction submitted to Abstract |
| TX confirmed | ~0:05 | Token deployed, LP seeded, history saved |
| `check-status.sh` | ~0:10 | LP health verified on-chain |
| `promote-launch.sh` | ~0:15 | Tweet posted if `autoPromote: true` |
| Token visible on Abscan | ~1:00 | Full indexing by Abscan explorer |

---

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `ABSTRACT_PRIVATE_KEY` | ✅ Yes | — | Agent wallet private key (0x prefixed) |
| `ABSTRACT_RPC_URL` | No | `https://api.mainnet.abs.xyz` | Abstract Mainnet JSON-RPC |
| `TOKENLAUNCHER_CONFIG` | No | `~/.config/tokenlauncher/config.json` | Custom config path |
| `TOKENLAUNCHER_HISTORY` | No | `~/.config/tokenlauncher/launch-history.json` | Custom history path |

---

## Security Notes

- **Never commit your private key.** Use environment variables or a secrets manager.
- The ClawTokenLauncher contract is non-custodial — you retain control of your wallet.
- Spend limits: Set `liquidityETH` conservatively. The contract enforces the exact ETH value sent.
- goat-x CDP uses a real browser session — no API keys are stored by the skill.

---

## Contract ABI Reference

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

## Troubleshooting

**"cast: command not found"**  
→ Install Foundry: `curl -L https://foundry.paradigm.xyz | bash && foundryup`

**"Insufficient funds"**  
→ Check your wallet balance. You need `liquidityETH` + gas (~0.002 ETH).

**"Transaction reverted"**  
→ Check the ClawTokenLauncher contract on Abscan. Common cause: symbol already taken, or insufficient ETH value sent.

**"Rate limit: last promote was X minutes ago"**  
→ The promote script enforces 15-minute cooldowns. Wait or delete `state.json` to reset.

**goat-x not found**  
→ The promote script requires the goat-x skill. Install it or set `autoPromote: false` in config.

---

## Links

- **Contract:** [abscan.org/address/0x89B974b6977157f1E7D743D70e28fCA1B5Ca84b5](https://abscan.org/address/0x89B974b6977157f1E7D743D70e28fCA1B5Ca84b5)
- **ClawWallet:** [clawwallet.buzz](https://clawwallet.buzz)
- **Skill docs:** [docs.clawwallet.buzz/skills/tokenlauncher](https://docs.clawwallet.buzz/skills/tokenlauncher)
- **Abstract Chain:** [abs.xyz](https://abs.xyz)
- **GitHub:** [github.com/0xChitlin/abstract-skills](https://github.com/0xChitlin/abstract-skills)

---

*Built by 0xChitlin for ClawWallet. Abstract Chain. Chain ID 2741.*
