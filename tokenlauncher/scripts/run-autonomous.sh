#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# TokenLauncher — run-autonomous.sh
# Full autopilot: reads config → launches token → waits → promotes → logs.
#
# Usage:
#   ./run-autonomous.sh
#   ./run-autonomous.sh --config /path/to/config.json
#   ./run-autonomous.sh --dry-run    # Validate config only, no TX sent
#
# Required env:
#   ABSTRACT_PRIVATE_KEY   — agent wallet private key
#   ABSTRACT_RPC_URL       — (optional) defaults to https://api.mainnet.abs.xyz
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Constants ─────────────────────────────────────────────────────────────────
CONFIG_FILE="${TOKENLAUNCHER_CONFIG:-$HOME/.config/tokenlauncher/config.json}"
HISTORY_FILE="${TOKENLAUNCHER_HISTORY:-$HOME/.config/tokenlauncher/launch-history.json}"
LOG_DIR="$HOME/.config/tokenlauncher/logs"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
DEFAULT_RPC="https://api.mainnet.abs.xyz"
POLL_INTERVAL=5       # seconds between on-chain polls
MAX_POLL_ATTEMPTS=60  # max ~5 minutes of polling

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()    { local msg="[$(date -u +%H:%M:%S)] [tokenlauncher] $*"; echo -e "${CYAN}${msg}${RESET}"; echo "$msg" >> "$LOG_FILE"; }
ok()     { local msg="[$(date -u +%H:%M:%S)] [✓] $*";           echo -e "${GREEN}${msg}${RESET}"; echo "$msg" >> "$LOG_FILE"; }
warn()   { local msg="[$(date -u +%H:%M:%S)] [!] $*";           echo -e "${YELLOW}${msg}${RESET}"; echo "$msg" >> "$LOG_FILE"; }
die()    { local msg="[$(date -u +%H:%M:%S)] [✗] ERROR: $*";    echo -e "${RED}${msg}${RESET}" >&2; echo "$msg" >> "$LOG_FILE"; exit 1; }
section(){ echo -e "\n${BOLD}═══ $* ═══${RESET}\n"; }

DRY_RUN=false

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)   CONFIG_FILE="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    *) echo "Unknown arg: $1. Usage: $0 [--config path] [--dry-run]" >&2; exit 1 ;;
  esac
done

# ── Setup ─────────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR" "$(dirname "$HISTORY_FILE")"
RUN_ID="run-$(date +%Y%m%d-%H%M%S)"

echo "" | tee -a "$LOG_FILE"
echo -e "${BOLD}╔═══════════════════════════════════════════════════╗${RESET}" | tee -a "$LOG_FILE"
echo -e "${BOLD}║  🤖 TokenLauncher — Autonomous Mode               ║${RESET}" | tee -a "$LOG_FILE"
echo -e "${BOLD}║  Run ID: $RUN_ID                  ║${RESET}" | tee -a "$LOG_FILE"
echo -e "${BOLD}╚═══════════════════════════════════════════════════╝${RESET}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# ── Load config ───────────────────────────────────────────────────────────────
section "Step 1 — Load Config"
[[ -f "$CONFIG_FILE" ]] || die "Config not found at $CONFIG_FILE. Run: cp config.example.json $CONFIG_FILE"

log "Reading config from $CONFIG_FILE"
TOKEN_NAME=$(jq -r '.tokenName'     "$CONFIG_FILE")
TOKEN_SYMBOL=$(jq -r '.tokenSymbol' "$CONFIG_FILE")
TOTAL_SUPPLY=$(jq -r '.totalSupply' "$CONFIG_FILE")
LIQUIDITY_ETH=$(jq -r '.liquidityETH' "$CONFIG_FILE")
AUTO_PROMOTE=$(jq -r '.autoPromote // false' "$CONFIG_FILE")

# Validate required fields
[[ "$TOKEN_NAME"    == "null" || -z "$TOKEN_NAME"    ]] && die "config.tokenName is required"
[[ "$TOKEN_SYMBOL"  == "null" || -z "$TOKEN_SYMBOL"  ]] && die "config.tokenSymbol is required"
[[ "$TOTAL_SUPPLY"  == "null" || -z "$TOTAL_SUPPLY"  ]] && die "config.totalSupply is required"
[[ "$LIQUIDITY_ETH" == "null" || -z "$LIQUIDITY_ETH" ]] && die "config.liquidityETH is required"

ok "Config loaded:"
log "  tokenName:    $TOKEN_NAME"
log "  tokenSymbol:  $TOKEN_SYMBOL"
log "  totalSupply:  $TOTAL_SUPPLY"
log "  liquidityETH: $LIQUIDITY_ETH ETH"
log "  autoPromote:  $AUTO_PROMOTE"

if $DRY_RUN; then
  warn "DRY RUN mode — no transaction will be submitted."
  ok "Config is valid. Ready to launch when you remove --dry-run."
  exit 0
fi

# ── Validate env ──────────────────────────────────────────────────────────────
section "Step 2 — Environment Check"
[[ -z "${ABSTRACT_PRIVATE_KEY:-}" ]] && die "ABSTRACT_PRIVATE_KEY env var not set"
command -v cast >/dev/null 2>&1 || die "Foundry 'cast' not found. Install: curl -L https://foundry.paradigm.xyz | bash && foundryup"
command -v jq   >/dev/null 2>&1 || die "'jq' not found. Install: brew install jq"

RPC_URL="${ABSTRACT_RPC_URL:-$DEFAULT_RPC}"

# Check wallet balance
log "Checking wallet balance..."
WALLET_ADDR=$(cast wallet address --private-key "$ABSTRACT_PRIVATE_KEY" 2>/dev/null || true)
if [[ -n "$WALLET_ADDR" ]]; then
  BALANCE_WEI=$(cast balance "$WALLET_ADDR" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
  if command -v python3 >/dev/null 2>&1; then
    BALANCE_ETH=$(python3 -c "print(f'{int(\"$BALANCE_WEI\") / 10**18:.6f}')")
    log "Wallet: $WALLET_ADDR"
    log "Balance: $BALANCE_ETH ETH"

    # Estimate needed: liquidityETH + 0.005 ETH gas buffer
    NEEDED=$(python3 -c "print(float('$LIQUIDITY_ETH') + 0.005)")
    ENOUGH=$(python3 -c "print('yes' if float('$BALANCE_ETH') >= float('$NEEDED') else 'no')")
    if [[ "$ENOUGH" == "no" ]]; then
      die "Insufficient balance. Need ~$NEEDED ETH (liquidity + gas), have $BALANCE_ETH ETH"
    fi
    ok "Balance sufficient ($BALANCE_ETH ETH >= $NEEDED ETH needed)"
  fi
fi

ok "Environment checks passed"

# ── Launch token ──────────────────────────────────────────────────────────────
section "Step 3 — Launch Token"
log "Calling launch-token.sh..."

export TOKENLAUNCHER_HISTORY="$HISTORY_FILE"
export TOKENLAUNCHER_CONFIG="$CONFIG_FILE"

LAUNCH_OUTPUT=$("$SCRIPT_DIR/launch-token.sh" \
  --name      "$TOKEN_NAME" \
  --symbol    "$TOKEN_SYMBOL" \
  --supply    "$TOTAL_SUPPLY" \
  --liquidity "$LIQUIDITY_ETH" 2>&1) || die "launch-token.sh failed:\n$LAUNCH_OUTPUT"

echo "$LAUNCH_OUTPUT" | tee -a "$LOG_FILE"

# Extract token address from history (most reliable)
TOKEN_ADDRESS=$(jq -r '.[-1].tokenAddress' "$HISTORY_FILE" 2>/dev/null || echo "")
TX_HASH=$(jq -r '.[-1].txHash' "$HISTORY_FILE" 2>/dev/null || echo "")
LP_ADDRESS=$(jq -r '.[-1].lpAddress' "$HISTORY_FILE" 2>/dev/null || echo "")

ok "Token launched: $TOKEN_ADDRESS"
ok "TX: $TX_HASH"

# ── Wait for confirmation ─────────────────────────────────────────────────────
section "Step 4 — Wait for On-Chain Confirmation"
log "Polling for confirmation on Abstract... (up to $((MAX_POLL_ATTEMPTS * POLL_INTERVAL))s)"

CONFIRMED=false
for (( attempt=1; attempt<=MAX_POLL_ATTEMPTS; attempt++ )); do
  RECEIPT_STATUS=$(cast receipt "$TX_HASH" --rpc-url "$RPC_URL" --field status 2>/dev/null || echo "")
  if [[ "$RECEIPT_STATUS" == "1" || "$RECEIPT_STATUS" == "0x1" ]]; then
    CONFIRMED=true
    ok "Confirmed in block! (attempt $attempt)"
    break
  elif [[ "$RECEIPT_STATUS" == "0" || "$RECEIPT_STATUS" == "0x0" ]]; then
    die "Transaction reverted! Check: https://abscan.org/tx/$TX_HASH"
  fi
  log "Not yet confirmed (attempt $attempt/$MAX_POLL_ATTEMPTS)... waiting ${POLL_INTERVAL}s"
  sleep "$POLL_INTERVAL"
done

if ! $CONFIRMED; then
  warn "TX not confirmed after $(( MAX_POLL_ATTEMPTS * POLL_INTERVAL ))s. Check manually: https://abscan.org/tx/$TX_HASH"
fi

# ── Check status ──────────────────────────────────────────────────────────────
section "Step 5 — Check Token Status"
log "Verifying token on-chain..."
"$SCRIPT_DIR/check-status.sh" "$TOKEN_ADDRESS" 2>&1 | tee -a "$LOG_FILE" || warn "Status check failed (token may still be indexing)"

# ── Promote ───────────────────────────────────────────────────────────────────
if [[ "$AUTO_PROMOTE" == "true" ]]; then
  section "Step 6 — Promote on X"
  log "autoPromote is enabled — posting to X..."
  "$SCRIPT_DIR/promote-launch.sh" "$TOKEN_ADDRESS" 2>&1 | tee -a "$LOG_FILE" || warn "Promote failed (see logs)"
  ok "Promotion step complete"
else
  section "Step 6 — Promotion Skipped"
  log "autoPromote is false in config. Run promote-launch.sh manually to post."
fi

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════╗${RESET}" | tee -a "$LOG_FILE"
echo -e "${BOLD}║  ✅ AUTONOMOUS LAUNCH COMPLETE                    ║${RESET}" | tee -a "$LOG_FILE"
echo -e "${BOLD}╚═══════════════════════════════════════════════════╝${RESET}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo -e "  ${BOLD}Token:${RESET}   \$$TOKEN_SYMBOL — $TOKEN_NAME" | tee -a "$LOG_FILE"
echo -e "  ${BOLD}Address:${RESET} ${GREEN}$TOKEN_ADDRESS${RESET}" | tee -a "$LOG_FILE"
echo -e "  ${BOLD}LP:${RESET}      ${GREEN}$LP_ADDRESS${RESET}" | tee -a "$LOG_FILE"
echo -e "  ${BOLD}TX:${RESET}      https://abscan.org/tx/$TX_HASH" | tee -a "$LOG_FILE"
echo -e "  ${BOLD}Token:${RESET}   https://abscan.org/token/$TOKEN_ADDRESS" | tee -a "$LOG_FILE"
echo -e "  ${BOLD}Log:${RESET}     $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
