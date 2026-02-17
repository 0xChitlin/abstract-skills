#!/bin/bash
# gigaverse-action.sh — Execute actions in Gigaverse
# Usage: ./gigaverse-action.sh <command> [args]
#
# Commands:
#   auth              — Authenticate and save JWT
#   setup-wallet      — Generate or import a wallet
#   join-game         — Start a dungeon run
#   make-move <move>  — Submit combat/loot action (rock|paper|scissor|loot_one|loot_two|loot_three|loot_four)
#   levelup [stat_id] — Level up (uses strategy from config, or specify stat 0-7)
#   status            — Quick status check
#   resync            — Sync actionToken from current run state
#   cancel            — Cancel current dungeon run
#   flee              — Flee from current encounter

set -euo pipefail

# ─── Config & Paths ───────────────────────────────────────────────────────────
SECRETS_DIR="${HOME}/.secrets"
CONFIG_DIR="${HOME}/.config/gigaverse"
KEY_FILE="${SECRETS_DIR}/gigaverse-private-key.txt"
JWT_FILE="${SECRETS_DIR}/gigaverse-jwt.txt"
ADDR_FILE="${SECRETS_DIR}/gigaverse-address.txt"
CONFIG_FILE="${CONFIG_DIR}/config.json"
TOKEN_FILE="${SECRETS_DIR}/gigaverse-action-token.txt"

API_BASE="https://gigaverse.io/api"
AGENT_TYPE="gigaverse-play-skill"
AGENT_MODEL="${GIGAVERSE_AGENT_MODEL:-claude-sonnet-4-6}"

# ─── Helpers ──────────────────────────────────────────────────────────────────
die() { echo "❌ $*" >&2; exit 1; }
info() { echo "ℹ️  $*"; }
ok() { echo "✅ $*"; }
warn() { echo "⚠️  $*"; }

require_jwt() {
    [ -f "$JWT_FILE" ] || die "No JWT found. Run: $0 auth"
    JWT=$(cat "$JWT_FILE")
}

require_address() {
    [ -f "$ADDR_FILE" ] || die "No address found. Run: $0 setup-wallet"
    ADDRESS=$(cat "$ADDR_FILE")
}

get_token() {
    if [ -f "$TOKEN_FILE" ]; then
        cat "$TOKEN_FILE"
    else
        echo "0"
    fi
}

save_token() {
    echo "$1" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
}

api_get() {
    local endpoint="$1"
    local auth="${2:-no}"
    if [ "$auth" = "yes" ]; then
        curl -s "${API_BASE}${endpoint}" \
            -H "Authorization: Bearer $JWT" \
            -H "Content-Type: application/json"
    else
        curl -s "${API_BASE}${endpoint}"
    fi
}

api_post() {
    local endpoint="$1"
    local body="$2"
    local auth="${3:-yes}"
    if [ "$auth" = "yes" ]; then
        curl -s -X POST "${API_BASE}${endpoint}" \
            -H "Authorization: Bearer $JWT" \
            -H "Content-Type: application/json" \
            -d "$body"
    else
        curl -s -X POST "${API_BASE}${endpoint}" \
            -H "Content-Type: application/json" \
            -d "$body"
    fi
}

# ─── Setup Wallet ─────────────────────────────────────────────────────────────
cmd_setup_wallet() {
    echo "🔐 Gigaverse Wallet Setup"
    echo ""
    echo "  [1] Generate new wallet (recommended)"
    echo "  [2] Import existing private key"
    echo ""
    read -r -p "Choice [1/2]: " choice

    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"

    if [ "$choice" = "2" ]; then
        warn "SECURITY WARNING: Only import dedicated bot wallets with minimal funds!"
        warn "NEVER import a wallet with significant assets."
        echo ""
        read -r -s -p "Enter private key (0x...): " PRIVATE_KEY
        echo ""
    else
        # Generate using node + viem
        if ! command -v node &>/dev/null; then
            die "node.js required. Install: https://nodejs.org"
        fi

        echo "Generating wallet..."
        WALLET_DATA=$(node -e "
const { generatePrivateKey, privateKeyToAccount } = require('viem/accounts');
const pk = generatePrivateKey();
const account = privateKeyToAccount(pk);
console.log(JSON.stringify({ privateKey: pk, address: account.address }));
" 2>/dev/null) || die "Failed to generate wallet. Ensure viem is installed: npm install -g viem"

        PRIVATE_KEY=$(echo "$WALLET_DATA" | jq -r '.privateKey')
        ADDRESS=$(echo "$WALLET_DATA" | jq -r '.address')
    fi

    # Save key
    echo "$PRIVATE_KEY" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"

    # Derive address if not already set
    if [ -z "${ADDRESS:-}" ]; then
        ADDRESS=$(node -e "
const { privateKeyToAccount } = require('viem/accounts');
const account = privateKeyToAccount('$PRIVATE_KEY');
console.log(account.address);
" 2>/dev/null) || die "Failed to derive address"
    fi

    echo "$ADDRESS" > "$ADDR_FILE"
    chmod 600 "$ADDR_FILE"

    ok "Wallet configured!"
    echo ""
    echo "   Address:  $ADDRESS"
    echo "   Key file: $KEY_FILE"
    echo ""
    warn "Fund this address with ETH on Abstract Chain (Chain ID: 2741)"
    warn "Required for: Noob mint (gas) + optional GigaJuice"
    echo ""
    info "Next: Run '$0 auth' to authenticate"

    # Create default config
    if [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$CONFIG_DIR"
        cat > "$CONFIG_FILE" << EOF
{
  "mode": "autonomous",
  "wallet_address": "$ADDRESS",
  "output_verbosity": "summarized",
  "on_death": "auto_restart",
  "strategy": {
    "combat": "balanced",
    "loot_priority": ["rarity", "hp", "atk"]
  },
  "preferences": {
    "default_faction": null,
    "username_style": "random",
    "notify_on_full_energy": true,
    "juice_declined": false
  }
}
EOF
        ok "Config created at $CONFIG_FILE"
    fi
}

# ─── Authenticate ─────────────────────────────────────────────────────────────
cmd_auth() {
    [ -f "$KEY_FILE" ] || die "No wallet found. Run: $0 setup-wallet"
    require_address

    echo "🔐 Authenticating with Gigaverse..."

    PRIVATE_KEY=$(cat "$KEY_FILE")
    TIMESTAMP=$(date +%s)000
    MESSAGE="Login to Gigaverse at ${TIMESTAMP}"

    info "Address: $ADDRESS"
    info "Message: $MESSAGE"

    # Sign using viem
    SIGNATURE=$(node -e "
const { privateKeyToAccount } = require('viem/accounts');
async function sign() {
    const account = privateKeyToAccount('$PRIVATE_KEY');
    const sig = await account.signMessage({ message: '$MESSAGE' });
    console.log(sig);
}
sign();
" 2>/dev/null) || die "Failed to sign. Ensure viem is installed: npm install -g viem"

    [ -n "$SIGNATURE" ] || die "Empty signature returned"

    info "Signature: ${SIGNATURE:0:20}..."

    RESPONSE=$(api_post "/user/auth" "{
        \"signature\": \"$SIGNATURE\",
        \"address\": \"$ADDRESS\",
        \"message\": \"$MESSAGE\",
        \"timestamp\": $TIMESTAMP,
        \"agent_metadata\": {
            \"type\": \"$AGENT_TYPE\",
            \"model\": \"$AGENT_MODEL\"
        }
    }" "no")

    JWT=$(echo "$RESPONSE" | jq -r '.jwt // empty' 2>/dev/null)
    [ -n "$JWT" ] || die "Auth failed. Response: $(echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE")"

    echo "$JWT" > "$JWT_FILE"
    chmod 600 "$JWT_FILE"

    EXPIRES=$(echo "$RESPONSE" | jq -r '.expiresAt // empty' 2>/dev/null)
    if [ -n "$EXPIRES" ]; then
        EXPIRES_DATE=$(date -r $((EXPIRES / 1000)) 2>/dev/null || date -d "@$((EXPIRES / 1000))" 2>/dev/null || echo "unknown")
        info "Expires: $EXPIRES_DATE"
    fi

    echo ""
    ok "Authenticated! JWT saved to $JWT_FILE"
}

# ─── Join Game (Start Dungeon Run) ────────────────────────────────────────────
cmd_join_game() {
    require_jwt
    require_address

    local dungeon_id="${1:-1}"
    local is_juiced="${2:-false}"

    echo "⚔️  Starting dungeon run (dungeonId: $dungeon_id)..."

    # Check energy first
    ENERGY_DATA=$(api_get "/offchain/player/energy/$ADDRESS" "no")
    CURRENT=$(echo "$ENERGY_DATA" | jq -r '.entities[0].parsedData.currentEnergy // 0' 2>/dev/null)
    MAX=$(echo "$ENERGY_DATA" | jq -r '.entities[0].parsedData.maxEnergy // 240' 2>/dev/null)
    info "Energy: $CURRENT / $MAX"

    if [ "$CURRENT" -lt 40 ] 2>/dev/null; then
        warn "Low energy ($CURRENT). Dungetron 5000 costs 40 energy."
        warn "Energy regens at 10/hour. Wait ~$((( 40 - CURRENT ) / 10)) hours."
    fi

    # Check for active run first
    STATE=$(api_get "/game/dungeon/state" "yes")
    IS_ACTIVE=$(echo "$STATE" | jq -r '.data.isActive // false' 2>/dev/null)
    if [ "$IS_ACTIVE" = "true" ]; then
        warn "Active run detected! Resuming instead of starting new."
        CURRENT_TOKEN=$(echo "$STATE" | jq -r '.actionToken // 0' 2>/dev/null)
        save_token "$CURRENT_TOKEN"
        echo "$STATE" | jq .
        return
    fi

    # Start new run (always token 0)
    save_token "0"
    RESPONSE=$(api_post "/game/dungeon/action" "{
        \"action\": \"start_run\",
        \"dungeonId\": $dungeon_id,
        \"actionToken\": 0,
        \"data\": {
            \"consumables\": [],
            \"isJuiced\": $is_juiced,
            \"index\": 0
        }
    }" "yes")

    SUCCESS=$(echo "$RESPONSE" | jq -r '.success // false' 2>/dev/null)
    NEW_TOKEN=$(echo "$RESPONSE" | jq -r '.actionToken // 0' 2>/dev/null)

    if [ "$SUCCESS" = "true" ]; then
        save_token "$NEW_TOKEN"
        ok "Run started! Action token: $NEW_TOKEN"
        echo "$RESPONSE" | jq '.data // .' 2>/dev/null
    else
        warn "Start failed:"
        echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
        exit 1
    fi
}

# ─── Make Move ────────────────────────────────────────────────────────────────
cmd_make_move() {
    require_jwt
    local action="${1:-}"
    [ -n "$action" ] || die "Usage: $0 make-move <rock|paper|scissor|loot_one|loot_two|loot_three|loot_four|flee|cancel_run>"

    local current_token
    current_token=$(get_token)

    # Display friendly names
    case "$action" in
        rock)    info "⚔️  Sword (rock) — token $current_token" ;;
        paper)   info "🛡️  Shield (paper) — token $current_token" ;;
        scissor) info "✨ Spell (scissor) — token $current_token" ;;
        loot_*)  info "🎁 Looting ($action) — token $current_token" ;;
        flee)    info "🏃 Fleeing — token $current_token" ;;
        *)       info "🎮 Action: $action — token $current_token" ;;
    esac

    RESPONSE=$(api_post "/game/dungeon/action" "{
        \"action\": \"$action\",
        \"dungeonId\": 1,
        \"actionToken\": $current_token,
        \"data\": {}
    }" "yes")

    SUCCESS=$(echo "$RESPONSE" | jq -r '.success // false' 2>/dev/null)
    NEW_TOKEN=$(echo "$RESPONSE" | jq -r '.actionToken // empty' 2>/dev/null)

    if [ "$SUCCESS" = "true" ]; then
        if [ -n "$NEW_TOKEN" ]; then
            save_token "$NEW_TOKEN"
            info "New action token: $NEW_TOKEN"
        fi
        echo "$RESPONSE" | jq '.data // .' 2>/dev/null
    else
        ERROR=$(echo "$RESPONSE" | jq -r '.error // "unknown error"' 2>/dev/null)
        warn "Action failed: $ERROR"

        # If stale token, offer resync
        if echo "$ERROR" | grep -qi "token"; then
            info "Resyncing token from game state..."
            cmd_resync
        fi
        exit 1
    fi
}

# ─── Level Up ─────────────────────────────────────────────────────────────────
cmd_levelup() {
    require_jwt

    local stat_id="${1:-}"
    local noob_id="${GIGAVERSE_NOOB_ID:-}"

    # Try to get noob ID from config or account
    if [ -z "$noob_id" ] && command -v jq &>/dev/null; then
        require_address
        ACCOUNT=$(api_get "/game/account/$ADDRESS" "no")
        noob_id=$(echo "$ACCOUNT" | jq -r '.noob.id // .noob.ID_CID // empty' 2>/dev/null)
    fi

    [ -n "$noob_id" ] || die "Could not determine Noob ID. Set GIGAVERSE_NOOB_ID env var."

    # If no stat given, use strategy from config
    if [ -z "$stat_id" ] && [ -f "$CONFIG_FILE" ]; then
        STRATEGY=$(jq -r '.strategy.combat // "balanced"' "$CONFIG_FILE" 2>/dev/null)
        case "$STRATEGY" in
            aggressive) stat_id="0" ;; # Sword ATK
            defensive)  stat_id="6" ;; # Max HP
            *)          stat_id="6" ;; # Balanced: Max HP
        esac
        info "Using strategy '$STRATEGY' → stat $stat_id"
    fi

    [ -n "$stat_id" ] || die "Specify stat ID (0-7). See SKILL.md for stat table."

    RESPONSE=$(api_post "/game/skill/levelup" "{
        \"skillId\": 1,
        \"statId\": $stat_id,
        \"noobId\": $noob_id
    }" "yes")

    echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"

    SUCCESS=$(echo "$RESPONSE" | jq -r '.success // false' 2>/dev/null)
    [ "$SUCCESS" = "true" ] && ok "Leveled up! Stat $stat_id increased."
}

# ─── Resync Action Token ───────────────────────────────────────────────────────
cmd_resync() {
    require_jwt

    STATE=$(api_get "/game/dungeon/state" "yes")
    CURRENT_TOKEN=$(echo "$STATE" | jq -r '.actionToken // 0' 2>/dev/null)
    save_token "$CURRENT_TOKEN"
    ok "Action token resynced: $CURRENT_TOKEN"
}

# ─── Cancel Run ───────────────────────────────────────────────────────────────
cmd_cancel() {
    cmd_make_move "cancel_run"
}

# ─── Flee ─────────────────────────────────────────────────────────────────────
cmd_flee() {
    cmd_make_move "flee"
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────
COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
    setup-wallet)  cmd_setup_wallet "$@" ;;
    auth)          cmd_auth "$@" ;;
    join-game)     cmd_join_game "$@" ;;
    make-move)     cmd_make_move "$@" ;;
    levelup)       cmd_levelup "$@" ;;
    resync)        cmd_resync "$@" ;;
    cancel)        cmd_cancel "$@" ;;
    flee)          cmd_flee "$@" ;;
    help|--help|-h)
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  setup-wallet        Generate or import Gigaverse wallet"
        echo "  auth                Authenticate → JWT"
        echo "  join-game [id]      Start dungeon run (default: dungeonId 1)"
        echo "  make-move <action>  Submit: rock|paper|scissor|loot_one..four|flee|cancel_run"
        echo "  levelup [stat_id]   Level up Noob (0-7, or auto from strategy)"
        echo "  resync              Re-sync actionToken from current run state"
        echo "  cancel              Cancel current run"
        echo "  flee                Flee current encounter"
        echo ""
        echo "Stat IDs: 0=SwordATK 1=SwordDEF 2=ShieldATK 3=ShieldDEF 4=SpellATK 5=SpellDEF 6=MaxHP 7=MaxArmor"
        ;;
    *)
        die "Unknown command: $COMMAND. Run '$0 help'"
        ;;
esac
