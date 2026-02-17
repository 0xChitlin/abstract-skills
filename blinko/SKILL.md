# Blinko Skill

> On-chain plinko by **@bearish_af** — live on Abstract Chain  
> URL: **https://blinko.gg**  
> 683,664+ games played as of Feb 2026

---

## What Is Blinko?

Blinko is a **plinko-style on-chain casino game** built on Abstract Chain by the Bearish team.  
Drop a ball, watch it bounce, win ETH multipliers up to 11x+.  
Every play earns **HONEY** points → redeemable for **$BURR** tokens.  
Playing also generates **Abstract XP**, making it a core XP-farming loop.

---

## Game Mechanics

| Parameter | Value |
|-----------|-------|
| Network | Abstract Chain (EVM L2) |
| Minimum bet | 0.001 ETH |
| Reward token | HONEY → $BURR |
| XP source | Yes — each play earns Abstract Chain XP |
| Max observed multiplier | 11x+ |
| Daily plays for XP | 3 plays/day is the common farming strategy |
| House edge | Yes — "the house always wins long-term" |

### Risk Levels
Blinko supports multiple risk profiles that change the peg distribution:
- **Low** — frequent small wins, tight spread
- **Medium** — balanced spread, moderate variance
- **High** — rare big wins, wide spread (up to 11x+)

### HONEY / $BURR Loop
- Every Blinko play earns **HONEY** regardless of win/loss
- HONEY accumulates and can be converted to **$BURR** (Bearish ecosystem token, launched on Aborean)
- HONEY also feeds **XEET leaderboard** rankings

---

## Agent Commands

### `play`
Drop a ball on Blinko for a given amount and risk level.

```bash
./scripts/blinko-play.sh --amount 0.001 --risk medium --wallet $WALLET_ADDRESS
```

Parameters:
- `--amount` — ETH amount to wager (min 0.001)
- `--risk` — `low` | `medium` | `high`
- `--wallet` — your Abstract Global Wallet (AGW) address
- `--rpc` — (optional) Abstract Chain RPC URL

### `check-balance`
Check your HONEY balance and recent winnings.

```bash
./scripts/blinko-status.sh --wallet $WALLET_ADDRESS --mode balance
```

### `set-risk-level`
Set default risk level for future plays.

```bash
./scripts/blinko-play.sh --set-risk high
```

Writes preference to `~/.config/blinko/config.json`.

### `get-history`
Fetch last N plays and results.

```bash
./scripts/blinko-status.sh --wallet $WALLET_ADDRESS --mode history --limit 10
```

---

## Farming Strategy (for XP agents)

1. Play **3x per day** at minimum bet (0.001 ETH) to maximize XP efficiency
2. Use **medium risk** for balanced HONEY/XP yield
3. Never chase losses — house edge is real
4. Track HONEY balance and claim $BURR when conversion is open
5. Holding a **Bearish NFT** gives XP bonus on top of plays

---

## Contract Info (Abstract Chain)

- Network: Abstract Chain (chain ID 2741)
- Explorer: https://explorer.abstract.money
- Blinko contract: resolve via https://blinko.gg (connect wallet to discover)
- Token: $BURR (launched on Aborean)

---

## Abstract Chain RPC

```
https://api.mainnet.abs.xyz
Chain ID: 2741
Currency: ETH
```

---

## Notes

- Site: https://blinko.gg
- Creator: @bearish_af on X/Twitter
- This is **on-chain gambling** — agents should track exposure and set daily limits
- HONEY earnings are the main reason to play daily (even if you lose ETH)
- "Bearish tested" — the Bearish NFT community is the core player base
