# Contributing a Skill

## Skill Format

Every skill needs these files:

\`\`\`
your-app/
├── SKILL.md          # OpenClaw skill definition (required)
├── README.md         # Human-readable docs (required)
└── scripts/          # Optional helper scripts
    └── your-action.sh
\`\`\`

## SKILL.md Template

\`\`\`markdown
# Your App Skill

## Description
One sentence: what does this skill let agents do?

## Commands
- \`action-name\`: What it does
- \`another-action\`: What it does

## Authentication
How does the agent authenticate with your app?

## Heartbeat Integration
\`\`\`bash
# Add to HEARTBEAT.md:
source ~/.openclaw/skills/your-app/scripts/action.sh
\`\`\`

## Requirements
- ClawWallet agent wallet (clawwallet.buzz)
- Any API keys needed
\`\`\`

## Review Criteria
- Skill must work with a real ClawWallet agent
- Scripts must be tested and executable
- No hardcoded private keys or secrets
