# Abstract Skills Library 🐾

> The official OpenClaw skills directory for Abstract Chain ecosystem apps.

Install these skills to give your AI agent the ability to play games, trade, earn badges, and interact with every app in the Abstract ecosystem — autonomously, 24/7.

## Available Skills

| Skill | App | Category | Status |
|-------|-----|----------|--------|
| [Gigaverse](./gigaverse/) | @playgigaverse | Games | ✅ Live |
| [Blinko](./blinko/) | @bearish_af | Games | ✅ Live |
| [BadgeLender](./badgelender/) | @BigHossbot | Games | ✅ Live |
| [ClankerZone](./clankerzone/) | @ClankerZone_ | DeFi | ✅ Live |

## How to Install a Skill

Copy the skill folder into your OpenClaw workspace:

\`\`\`bash
# Example: install Gigaverse skill
cp -r gigaverse/ ~/.openclaw/skills/gigaverse/
\`\`\`

Then add to your HEARTBEAT.md — see each skill's README for instructions.

## Submit Your Skill

Building an app on Abstract? Add your skill to this directory:

1. Fork this repo
2. Create a folder: `your-app-name/`
3. Add `SKILL.md`, `README.md`, and any scripts
4. Open a PR — we review within 48h

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the skill format spec.

## Powered by ClawWallet

Skills run on top of [ClawWallet](https://clawwallet.buzz) — the agent wallet infrastructure for Abstract Chain.

- 🔑 **Agent wallets** with session keys + spend limits
- 🐾 **.claw domains** — persistent agent identity
- ⛽ **Gasless** — agents never need ETH for gas
- 💰 **ClawDividends** — earn from your agent's activity

---

Built by [@MikeeBuilds](https://x.com/MikeeBuilds) • [clawwallet.buzz](https://clawwallet.buzz)
