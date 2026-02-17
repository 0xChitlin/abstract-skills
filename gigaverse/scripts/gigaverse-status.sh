#!/bin/bash
# gigaverse-status.sh — Check Gigaverse agent state
# Usage: ./gigaverse-status.sh [check]
#
# Checks:
#   (default)     — Full status dashboard
#   energy        — Energy level only
#   run           — Active dungeon run state
#   onboarding    — Check onboarding gate (noob + username + faction)
#   level         — XP balance and level progress
#   juice         — GigaJuice status
#   leaderboard   — Top players

set -euo pipefail

# ─── Config & Paths ───────────────────────────────────────────────────────────
SECRETS_DIR="${HOME}/.secrets"
JWT_FILE="${SECRETS_DIR}/gigaverse-jwt.txt"
ADDR_FILE="${SECRETS_DIR}/gigaverse-address.txt"
CONFIG_FILE="${HOME}/.config/gigaverse/config.json"

API_BASE="https://gigaverse.io/api"

# ─── Helpers ──────────────────────────────────────────────────────────────────
die() { echo "❌ $*" >&2; exit 1; }
info() { echo "   $*"; }
header() { echo ""; echo "── $* ──"; }

require_address() {
    [ -f "$ADDR_FILE" ] || die "No address found. Run: gigaverse-action.sh setup-wallet"
    ADDRESS=$(cat "$ADDR_FILE")
}

require_jwt() {
    [ -f "$JWT_FILE" ] || die "No JWT found. Run: gigaverse-action.sh auth"
    JWT=$(cat "$JWT_FILE")
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

# ─── Energy Status ────────────────────────────────────────────────────────────
check_energy() {
    require_address

    header "🔋 Energy"
    ENERGY=$(api_get "/offchain/player/energy/$ADDRESS" "no")

    CURRENT=$(echo "$ENERGY" | jq -r '.entities[0].parsedData.currentEnergy // "?"' 2>/dev/null)
    MAX=$(echo "$ENERGY" | jq -r '.entities[0].parsedData.maxEnergy // "240"' 2>/dev/null)
    LAST_REGEN=$(echo "$ENERGY" | jq -r '.entities[0].parsedData.lastRegenTime // 0' 2>/dev/null)

    if [ "$CURRENT" != "?" ] && [ "$MAX" != "0" ]; then
        PCT=$(( CURRENT * 100 / MAX ))
        BAR=$(printf '█%.0s' $(seq 1 $(( PCT / 10 ))))
        EMPTY=$(printf '░%.0s' $(seq 1 $(( (100 - PCT) / 10 ))))
        echo "   Energy: $CURRENT / $MAX  [${BAR}${EMPTY}] ${PCT}%"

        if [ "$CURRENT" -ge "$MAX" ] 2>/dev/null; then
            echo "   ✅ FULL — Ready to quest!"
        elif [ "$CURRENT" -ge 40 ] 2>/dev/null; then
            echo "   ⚡ Ready for Dungetron 5000 (40 energy cost)"
        else
            HOURS_NEEDED=$(( ( 40 - CURRENT ) / 10 ))
            echo "   ⏳ Need $(( 40 - CURRENT )) more energy (~${HOURS_NEEDED}h regen)"
        fi

        NOW=$(date +%s)
        if [ "$LAST_REGEN" -gt 0 ] 2>/dev/null; then
            SINCE=$(( NOW - LAST_REGEN ))
            echo "   Last regen: ${SINCE}s ago"
        fi
    else
        echo "   ⚠️  Could not fetch energy. Raw:"
        echo "$ENERGY" | jq . 2>/dev/null || echo "$ENERGY"
    fi
}

# ─── Onboarding Gate ──────────────────────────────────────────────────────────
check_onboarding() {
    require_address

    header "🎮 Onboarding Status"
    ACCOUNT=$(api_get "/game/account/$ADDRESS" "no")
    FACTION=$(api_get "/factions/player/$ADDRESS" "no")

    HAS_NOOB=$(echo "$ACCOUNT" | jq -r '.noob // empty' 2>/dev/null)
    USERNAME=$(echo "$ACCOUNT" | jq -r '.username // empty' 2>/dev/null)
    CAN_ENTER=$(echo "$ACCOUNT" | jq -r '.canEnterGame // false' 2>/dev/null)
    FACTION_ID=$(echo "$FACTION" | jq -r '.entities[0].FACTION_CID // 0' 2>/dev/null)

    if [ -n "$HAS_NOOB" ] && [ "$HAS_NOOB" != "null" ]; then
        NOOB_ID=$(echo "$ACCOUNT" | jq -r '.noob.ID_CID // .noob.id // "?"' 2>/dev/null)
        echo "   ✅ Noob: minted (ID: $NOOB_ID)"
    else
        echo "   ❌ Noob: NOT minted (required — costs gas on Abstract Chain)"
    fi

    if [ -n "$USERNAME" ] && [ "$USERNAME" != "null" ]; then
        echo "   ✅ Username: $USERNAME"
    else
        echo "   ❌ Username: not set"
    fi

    if [ "$FACTION_ID" != "0" ] && [ -n "$FACTION_ID" ]; then
        echo "   ✅ Faction: ID $FACTION_ID"
    else
        echo "   ❌ Faction: not chosen"
    fi

    echo ""
    if [ "$CAN_ENTER" = "true" ]; then
        echo "   🟢 READY — All gates passed. Can enter dungeons!"
    else
        echo "   🔴 NOT READY — Complete onboarding above first."
    fi
}

# ─── Active Run State ─────────────────────────────────────────────────────────
check_run() {
    require_jwt

    header "⚔️  Active Run State"
    STATE=$(api_get "/game/dungeon/state" "yes")

    IS_ACTIVE=$(echo "$STATE" | jq -r '.data.isActive // false' 2>/dev/null)

    if [ "$IS_ACTIVE" = "true" ]; then
        TOKEN=$(echo "$STATE" | jq -r '.actionToken // "?"' 2>/dev/null)
        ROOM=$(echo "$STATE" | jq -r '.data.currentRoom // "?"' 2>/dev/null)
        PLAYER_HP=$(echo "$STATE" | jq -r '.data.playerHp // "?"' 2>/dev/null)
        PLAYER_MAX_HP=$(echo "$STATE" | jq -r '.data.playerMaxHp // "?"' 2>/dev/null)
        ENEMY=$(echo "$STATE" | jq -r '.data.currentEnemy.name // "?"' 2>/dev/null)
        ENEMY_HP=$(echo "$STATE" | jq -r '.data.currentEnemy.hp // "?"' 2>/dev/null)
        DUNGEON=$(echo "$STATE" | jq -r '.data.dungeonId // "?"' 2>/dev/null)

        echo "   🟢 ACTIVE RUN"
        echo "   Dungeon:     $DUNGEON"
        echo "   Room:        $ROOM"
        echo "   Action Token: $TOKEN"
        echo "   Player HP:   $PLAYER_HP / $PLAYER_MAX_HP"
        echo "   Enemy:       $ENEMY (HP: $ENEMY_HP)"
        echo ""
        echo "   Available actions: rock | paper | scissor | flee | cancel_run"
        echo "   Run: gigaverse-action.sh make-move <action>"
    else
        echo "   No active run. Start one:"
        echo "   gigaverse-action.sh join-game"
    fi
}

# ─── Level & XP ───────────────────────────────────────────────────────────────
check_level() {
    require_jwt
    require_address

    header "⬆️  Level & XP"

    # Get scrap (XP) balance — item ID 2
    BALANCES=$(api_get "/items/balances" "yes")
    SCRAP=$(echo "$BALANCES" | jq -r '.entities[] | select(.ID_CID == "2") | .BALANCE_CID' 2>/dev/null || echo "0")

    echo "   XP (Dungeon Scrap): $SCRAP"

    # Get account for noob ID
    ACCOUNT=$(api_get "/game/account/$ADDRESS" "no")
    NOOB_ID=$(echo "$ACCOUNT" | jq -r '.noob.ID_CID // .noob.id // empty' 2>/dev/null)

    if [ -n "$NOOB_ID" ] && [ "$NOOB_ID" != "null" ]; then
        PROGRESS=$(api_get "/offchain/skills/progress/$NOOB_ID" "no")
        LEVEL=$(echo "$PROGRESS" | jq -r '.entities[0].LEVEL_CID // 0' 2>/dev/null)
        echo "   Current Level:      $LEVEL"

        # XP cost table
        COSTS=(0 11 14 18 22 25 29 33 37 41 45)
        NEXT_LEVEL=$(( LEVEL + 1 ))
        if [ "$NEXT_LEVEL" -lt "${#COSTS[@]}" ]; then
            NEXT_COST="${COSTS[$NEXT_LEVEL]}"
            if [ "$SCRAP" -ge "$NEXT_COST" ] 2>/dev/null; then
                echo "   ✅ LEVEL UP AVAILABLE! (have $SCRAP scrap, need $NEXT_COST)"
                echo "   Run: gigaverse-action.sh levelup"
            else
                NEEDED=$(( NEXT_COST - SCRAP ))
                echo "   Next level (L$NEXT_LEVEL) costs: $NEXT_COST scrap (need $NEEDED more)"
            fi
        fi
    else
        echo "   Noob not found — complete onboarding first"
    fi
}

# ─── GigaJuice Status ────────────────────────────────────────────────────────
check_juice() {
    require_address

    header "🧃 GigaJuice Status"
    JUICE=$(api_get "/gigajuice/player/$ADDRESS" "no")

    IS_JUICED=$(echo "$JUICE" | jq -r '.isJuiced // false' 2>/dev/null)
    EXPIRES=$(echo "$JUICE" | jq -r '.expiresAt // empty' 2>/dev/null)

    if [ "$IS_JUICED" = "true" ]; then
        echo "   ✅ JUICED"
        if [ -n "$EXPIRES" ]; then
            EXP_DATE=$(date -r $((EXPIRES / 1000)) 2>/dev/null || date -d "@$((EXPIRES / 1000))" 2>/dev/null || echo "?")
            echo "   Expires: $EXP_DATE"
        fi
        echo "   Benefits: 420 max energy, 17.5/hr regen, 3x rewards, extra loot options"
    else
        echo "   ❌ Not juiced"
        echo ""
        echo "   Packages:"
        echo "   JUICE BOX    — 30 days  — 0.010 ETH"
        echo "   JUICE CARTON — 90 days  — 0.023 ETH"
        echo "   JUICE TANK   — 180 days — 0.038 ETH"
        echo ""
        echo "   Contract: 0xd154ab0de91094bfa8e87808f9a0f7f1b98e1ce1 (Abstract Chain)"
    fi

    # Show active offerings if any
    OFFERINGS=$(echo "$JUICE" | jq -r '.offerings // [] | length' 2>/dev/null || echo "0")
    if [ "$OFFERINGS" -gt 0 ] 2>/dev/null; then
        echo ""
        echo "   🔥 Active sale/offering available!"
        echo "$JUICE" | jq '.offerings' 2>/dev/null
    fi
}

# ─── Full Status Dashboard ────────────────────────────────────────────────────
check_all() {
    echo "═══════════════════════════════════"
    echo "  🎮 GIGAVERSE STATUS DASHBOARD"
    echo "═══════════════════════════════════"

    require_address
    echo "   Wallet: $ADDRESS"

    check_energy
    check_onboarding
    check_run
    check_level
    check_juice

    echo ""
    echo "═══════════════════════════════════"
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────
CHECK="${1:-all}"
shift || true

case "$CHECK" in
    all|"")    check_all ;;
    energy)    check_energy ;;
    onboarding) check_onboarding ;;
    run)       require_jwt; check_run ;;
    level)     check_level ;;
    juice)     check_juice ;;
    leaderboard)
        echo "🏆 Leaderboard — visit https://gigaverse.io/leaderboard"
        echo "   (API leaderboard endpoint not yet public)"
        ;;
    help|--help|-h)
        echo "Usage: $0 [check]"
        echo ""
        echo "Checks:"
        echo "  (default)    Full status dashboard"
        echo "  energy       Energy level + regen"
        echo "  onboarding   Gate check (noob + username + faction)"
        echo "  run          Active dungeon run state"
        echo "  level        XP balance + level progress"
        echo "  juice        GigaJuice status + offerings"
        echo "  leaderboard  Leaderboard info"
        ;;
    *)
        echo "❌ Unknown check: $CHECK. Run '$0 help'"
        exit 1
        ;;
esac
