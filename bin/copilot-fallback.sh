#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# copilot-fallback.sh — Copilot CLI wrapper with auto-fallback to Codex on quota
# ═══════════════════════════════════════════════════════════════════════════════
# Usage (drop-in for `copilot --no-ask-user [args]`):
#   echo "<prompt>" | copilot-fallback.sh --no-ask-user [--model X] [other args]
#
# Behavior:
#   1. Caches stdin so the same prompt can be replayed.
#   2. Checks per-host lockout file. If Copilot is locked-out (quota hit recently),
#      skip Copilot entirely and go straight to Codex.
#   3. Otherwise tries Copilot first.
#   4. On Copilot quota / rate-limit error: writes lockout file (60-min TTL),
#      logs the fallback, retries the same prompt via Codex exec (gpt-5.4 default,
#      gpt-5.3-codex if --model copilot-codex was requested).
#   5. Lockout TTL prevents retry-storm during quota outage.
#   6. On Codex success: returns Codex's output. On Codex failure: returns Codex's error.
#
# Lockout file: ~/.claude-octopus/state/copilot-lockout
#   Contains: <epoch-seconds> <reason>
#   TTL: OCTOPUS_COPILOT_LOCKOUT_TTL env var (default 3600 = 60min)
#
# Override the TTL or model mapping per call:
#   OCTOPUS_COPILOT_LOCKOUT_TTL=1800 ...
#   OCTOPUS_FALLBACK_CODEX_MODEL=gpt-5.4 ...
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

LOCKOUT_FILE="${HOME}/.claude-octopus/state/copilot-lockout"
LOCKOUT_TTL="${OCTOPUS_COPILOT_LOCKOUT_TTL:-3600}"
FALLBACK_LOG="${HOME}/.claude-octopus/provider-fallbacks.log"
mkdir -p "$(dirname "$LOCKOUT_FILE")" "$(dirname "$FALLBACK_LOG")"

# Cache stdin (Copilot consumes it once; retries need replay)
prompt_file=$(mktemp -t "octo-copilot-prompt.XXXXXX")
err_file=$(mktemp -t "octo-copilot-err.XXXXXX")
trap 'rm -f "$prompt_file" "$err_file"' EXIT INT TERM
if [[ ! -t 0 ]]; then
    cat > "$prompt_file"
else
    : > "$prompt_file"
fi

# Determine target Codex model from Copilot args (so copilot-codex falls to a Codex variant)
fallback_codex_model="${OCTOPUS_FALLBACK_CODEX_MODEL:-gpt-5.4}"
for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "--model" ]]; then
        next=$((i+1))
        if [[ $next -le $# ]]; then
            requested_model="${!next}"
            case "$requested_model" in
                gpt-5.3-codex|gpt-5.2-codex)  fallback_codex_model="gpt-5.3-codex" ;;
                gpt-5.4-mini|gpt-5-mini)      fallback_codex_model="gpt-5.4-mini" ;;
                gpt-5.4|gpt-5.2|gpt-5)        fallback_codex_model="gpt-5.4" ;;
                # Claude/Haiku/Opus on Copilot have no Codex equivalent — fall to gpt-5.4
                claude*)                       fallback_codex_model="gpt-5.4" ;;
            esac
        fi
    fi
done

# Helper: write lockout file
_lock_copilot() {
    local reason="$1"
    printf '%s %s\n' "$(date +%s)" "$reason" > "$LOCKOUT_FILE"
}

# Helper: check if lockout is active (and still within TTL)
_is_locked_out() {
    [[ -f "$LOCKOUT_FILE" ]] || return 1
    local locked_at
    locked_at=$(awk '{print $1}' "$LOCKOUT_FILE" 2>/dev/null || echo 0)
    [[ -z "$locked_at" || "$locked_at" == "0" ]] && return 1
    local now=$(date +%s)
    local age=$((now - locked_at))
    if (( age < LOCKOUT_TTL )); then
        return 0
    else
        # TTL expired — clear lockout
        rm -f "$LOCKOUT_FILE"
        return 1
    fi
}

# Helper: log fallback event
_log_fallback() {
    local detail="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '[%s] provider=copilot status=fallback detail=%s\n' \
        "$timestamp" "$detail" >> "$FALLBACK_LOG"
}

# Helper: dispatch via Codex (replay cached prompt)
_dispatch_codex() {
    local model="$1"
    if [[ -s "$prompt_file" ]]; then
        codex exec --skip-git-repo-check --full-auto --model "$model" \
            --sandbox "${OCTOPUS_CODEX_SANDBOX:-workspace-write}" - < "$prompt_file"
    else
        codex exec --skip-git-repo-check --full-auto --model "$model" \
            --sandbox "${OCTOPUS_CODEX_SANDBOX:-workspace-write}" -
    fi
}

# Path 1: lockout active — skip Copilot entirely
if _is_locked_out; then
    _log_fallback "lockout-active-skipping-copilot-using-${fallback_codex_model}"
    echo "INFO: Copilot lockout active (TTL ${LOCKOUT_TTL}s); using Codex ${fallback_codex_model}" >&2
    _dispatch_codex "$fallback_codex_model"
    exit $?
fi

# Path 2: try Copilot first
set +e
if [[ -s "$prompt_file" ]]; then
    copilot "$@" < "$prompt_file" 2> "$err_file"
else
    copilot "$@" 2> "$err_file"
fi
exit_code=$?
set -e

# Quota / rate-limit detection patterns (case-insensitive)
quota_patterns='quota.{0,20}exceeded|rate.{0,5}limit|premium.{0,5}request.{0,5}limit|monthly.{0,5}limit|out.of.{0,10}(quota|requests)|insufficient.quota|429|too many requests|RESOURCE_EXHAUSTED|usage.cap.reached'

# Check for quota error in stderr
if grep -qiE "$quota_patterns" "$err_file" 2>/dev/null; then
    _lock_copilot "quota-exhausted-$(date -u +%FT%TZ)"
    _log_fallback "quota-exhausted-falling-back-to-codex-${fallback_codex_model}"
    matched=$(grep -iE "$quota_patterns" "$err_file" | head -1 | tr -d '\n' | cut -c1-120)
    echo "WARN: Copilot quota exhausted (matched: ${matched})" >&2
    echo "WARN: Locking out Copilot for ${LOCKOUT_TTL}s; falling back to Codex ${fallback_codex_model}" >&2
    _dispatch_codex "$fallback_codex_model"
    exit $?
fi

# Path 3: copilot succeeded (or non-quota error) — pass through
cat "$err_file" >&2
exit $exit_code
