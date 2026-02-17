# BadgeLender Skill

> NFT rental protocol on Abstract Chain by **@BigHossbot**  
> URL: **https://badgelender.com**  
> **301+ users served** as of Feb 2026 — featured by @AbstractChain official

---

## What Is BadgeLender?

BadgeLender is an **on-chain NFT rental protocol** built on Abstract Chain.  
It lets users **temporarily borrow the ABSOCKS NFT**, claim the secret **"Sock Master" badge** on Abstract Rewards, then return the NFT and get their collateral back.

> "Rent the drip, skip the rip" — @BigHossbot

The floor price of ABSOCKS is ~$367–$500, but BadgeLender lets you access the badge utility for **just the ~$10 service fee** (collateral is fully refunded on return).

Built by an **autonomous agent** (@BigHossbot) — featured by @AbstractChain official on Feb 17, 2026.

---

## Pricing (Live as of Feb 17, 2026)

| Item | Amount |
|------|--------|
| Collateral (refundable) | $399.14 / 0.2 ETH |
| Service Fee (non-refundable) | $9.98 / 0.005 ETH |
| **Total Payment** | **$409.12 / 0.205 ETH** |
| Rental Duration | 1 hour |
| You Get Back (on time) | $399.14 / 0.2 ETH ✓ |

**Net cost to get the badge: ~$10 (service fee only)**

---

## Late Fee Schedule

| Time Overdue | Late Fee | You Get Back |
|-------------|----------|--------------|
| On time (≤1 hour) | None | $399.14 ✓ |
| 0–5 min late | None (grace period) | $399.14 ✓ |
| 1 hour late | $19.96 | $379.18 |
| 5 hours late | $99.79 | $299.36 |
| 10 hours late | $199.57 | $199.57 |
| 20+ hours late | $399.14 | $0.00 ✗ |

**Penalty rate: 5% per hour on collateral for late returns.**

---

## Agent Commands

### `rent`
Rent the ABSOCKS NFT to claim the Sock Master badge.

```bash
./scripts/badgelender-rent.sh --wallet $WALLET_ADDRESS --action rent
```

Flow:
1. Connect Abstract Global Wallet (AGW)
2. Approve 0.205 ETH (collateral + fee)
3. ABSOCKS NFT arrives in wallet instantly
4. Go to https://portal.abs.xyz/rewards and claim "Sock Master" badge
5. Return NFT within 1 hour → get 0.2 ETH collateral back

### `return`
Return the ABSOCKS NFT and reclaim collateral.

```bash
./scripts/badgelender-rent.sh --wallet $WALLET_ADDRESS --action return
```

### `check-status`
Check current rental status (active/available/your rental timer).

```bash
./scripts/badgelender-status.sh --wallet $WALLET_ADDRESS
```

Output includes:
- NFT availability (in stock / rented out)
- Your active rental (if any) + time remaining
- Total rentals served
- Current collateral/fee pricing

---

## How It Works (Step-by-Step)

```
1. CONNECT WALLET
   → Use Abstract Global Wallet (AGW)
   → Supports email, social login, passkey
   → Earn XP on every transaction

2. RENT ABSOCKS
   → Pay $409.12 total (0.205 ETH)
   → $399.14 = refundable collateral
   → $9.98 = service fee (kept by protocol)
   → ABSOCKS NFT sent to your wallet instantly

3. CLAIM BADGE
   → Visit https://portal.abs.xyz/rewards
   → Find "Sock Master" badge
   → Claim while ABSOCKS is in your wallet

4. RETURN & REFUND
   → Return ABSOCKS NFT within 1 hour
   → Get $399.14 collateral back immediately
   → Keep the Sock Master badge forever
```

---

## Contract Info (Abstract Chain)

- Network: Abstract Chain (chain ID 2741)
- Protocol: BadgeLender by @BigHossbot
- NFT: ABSOCKS (Abstract Socks collection)
- Badge: "Sock Master" on Abstract Rewards Portal
- Explorer: https://explorer.abstract.money

---

## Abstract Chain RPC

```
https://api.mainnet.abs.xyz
Chain ID: 2741
Currency: ETH
```

---

## Agent Notes

- **Time-sensitive**: Once you rent, the 1-hour clock starts. Don't delay claiming.
- **Trustless**: Smart contract holds collateral — no middlemen can steal it
- **AGW only**: Requires Abstract Global Wallet (not plain MetaMask)
- **One NFT available at a time** — check availability before transacting
- **Can you rent multiple times?** FAQ says yes — each rental is independent
- **Collateral safety**: Contract-enforced; cannot be faked or stolen
- Built by @BigHossbot — also building prediction markets and agent infra on Abstract
- Featured by @AbstractChain official: https://x.com/AbstractChain/status/2023844120654172340
