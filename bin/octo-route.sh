#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# octo-route.sh — Swap provider routing presets
# ═══════════════════════════════════════════════════════════════════════════════
# Usage:
#   octo-route.sh                    # show current mode + list presets
#   octo-route.sh <mode>             # swap to <mode> preset
#   octo-route.sh rotate             # cycle to next mode in rotation order
#   octo-route.sh status             # show current mode only
#
# Available modes (presets in ~/.claude-octopus/config/presets/):
#   balanced      — each direct account gets its home role, Copilot fallback
#   copilot-only  — everything through Copilot (preserves direct quotas)
#   direct-only   — everything through direct accounts (preserves Copilot quota)
#   claude-heavy  — burn Claude Max quota (build + audit + deliver on Claude)
#   codex-heavy   — burn ChatGPT Pro quota (build + audit + deliver on Codex)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

CONFIG_DIR="${HOME}/.claude-octopus/config"
PRESETS_DIR="${CONFIG_DIR}/presets"
ACTIVE="${CONFIG_DIR}/providers.json"
COUNTER_FILE="${CONFIG_DIR}/.rotation-counter"

ROTATION_ORDER=(balanced copilot-heavy claude-heavy codex-heavy direct-only copilot-only)

list_modes() {
    echo "Available modes:"
    for f in "${PRESETS_DIR}"/*.json; do
        [[ -f "$f" ]] || continue
        local mode name desc
        mode="$(basename "$f" .json)"
        desc="$(jq -r '._description // "(no description)"' "$f" 2>/dev/null)"
        printf "  %-14s %s\n" "$mode" "$desc"
    done
}

current_mode() {
    if [[ -f "$ACTIVE" ]]; then
        jq -r '._mode // "custom (no preset match)"' "$ACTIVE" 2>/dev/null || echo "unknown"
    else
        echo "none (providers.json missing)"
    fi
}

swap_to() {
    local mode="$1"
    local preset="${PRESETS_DIR}/${mode}.json"

    if [[ ! -f "$preset" ]]; then
        echo "error: preset '${mode}' not found at ${preset}" >&2
        echo "" >&2
        list_modes >&2
        exit 1
    fi

    # Backup current config before swap
    if [[ -f "$ACTIVE" ]]; then
        cp "$ACTIVE" "${ACTIVE}.bak"
    fi

    cp "$preset" "$ACTIVE"
    echo "✓ Swapped to mode: ${mode}"
    echo "  Active config:   ${ACTIVE}"
    echo "  Backup:          ${ACTIVE}.bak"
}

rotate_next() {
    local current
    current="$(current_mode)"

    local next_idx=0
    for i in "${!ROTATION_ORDER[@]}"; do
        if [[ "${ROTATION_ORDER[$i]}" == "$current" ]]; then
            next_idx=$(( (i + 1) % ${#ROTATION_ORDER[@]} ))
            break
        fi
    done

    local next="${ROTATION_ORDER[$next_idx]}"
    echo "Rotating: ${current} → ${next}"
    swap_to "$next"
}

case "${1:-status}" in
    status|"")
        echo "Current mode: $(current_mode)"
        echo ""
        list_modes
        ;;
    rotate)
        rotate_next
        ;;
    -h|--help|help)
        sed -n '2,20p' "$0" | sed 's/^# \?//'
        ;;
    *)
        swap_to "$1"
        ;;
esac
