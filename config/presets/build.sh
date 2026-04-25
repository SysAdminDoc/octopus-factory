#!/usr/bin/env bash
# build.sh — generate config/presets/<mode>.json from base.json + overlays/<mode>.json
#
# Modes:
#   build.sh              # rebuild every preset (default)
#   build.sh <mode>       # rebuild a single preset
#   build.sh --verify     # rebuild in-memory and diff against committed presets;
#                         # exit 1 if any preset has drifted from its source
#                         # (use in pre-commit / CI to keep base+overlays the source of truth)
#
# Source of truth:
#   - presets/overlays/_base.json  — fields shared across every preset (providers, tiers, semantics)
#   - presets/overlays/<m>.json    — mode-specific routing + descriptive metadata
#
# Generated artifact:
#   - presets/<mode>.json          — checked in so install.sh + octo-route.sh consume them as-is
#
# Merge semantics: jq's `*` operator deep-merges objects (rightmost wins on scalar
# conflicts; nested objects merge recursively). Overlay wins on every shared key.
#
# Note: _base.json lives in overlays/ rather than presets/ so a `presets/*.json`
# glob (used by octo-route.sh + install.sh) doesn't pick it up as a swappable mode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAYS_DIR="${SCRIPT_DIR}/overlays"
BASE="${OVERLAYS_DIR}/_base.json"

if [[ ! -f "$BASE" ]]; then
    echo "build.sh: missing $BASE" >&2
    exit 1
fi

verify_mode=false
target_mode=""
for arg in "$@"; do
    case "$arg" in
        --verify) verify_mode=true ;;
        -h|--help)
            sed -n '2,18p' "$0"
            exit 0 ;;
        -*)
            echo "build.sh: unknown flag: $arg" >&2
            exit 1 ;;
        *) target_mode="$arg" ;;
    esac
done

build_one() {
    local overlay="$1"
    local mode out
    mode="$(basename "$overlay" .json)"
    out="${SCRIPT_DIR}/${mode}.json"
    jq -S -s '.[0] * .[1]' "$BASE" "$overlay"
}

list_overlays() {
    if [[ -n "$target_mode" ]]; then
        local f="${OVERLAYS_DIR}/${target_mode}.json"
        if [[ ! -f "$f" ]]; then
            echo "build.sh: no overlay for mode '$target_mode' at $f" >&2
            exit 1
        fi
        printf '%s\n' "$f"
    else
        # Skip _base.json (and anything else with leading underscore) — those
        # are merge sources, not standalone presets.
        find "$OVERLAYS_DIR" -maxdepth 1 -name '*.json' ! -name '_*' | sort
    fi
}

if $verify_mode; then
    drift=0
    while IFS= read -r overlay; do
        mode="$(basename "$overlay" .json)"
        committed="${SCRIPT_DIR}/${mode}.json"
        if [[ ! -f "$committed" ]]; then
            echo "✗ ${mode}: committed preset missing — run build.sh to generate"
            drift=1
            continue
        fi
        # Compare semantically (sort keys both sides) so cosmetic ordering
        # differences don't trigger false drift.
        diff_out="$(diff <(build_one "$overlay") <(jq -S . "$committed") || true)"
        if [[ -n "$diff_out" ]]; then
            echo "✗ ${mode}: drift between source (base+overlay) and committed preset:"
            echo "$diff_out" | sed 's/^/    /'
            drift=1
        else
            echo "✓ ${mode}"
        fi
    done < <(list_overlays)
    exit $drift
fi

while IFS= read -r overlay; do
    mode="$(basename "$overlay" .json)"
    out="${SCRIPT_DIR}/${mode}.json"
    build_one "$overlay" > "$out"
    echo "  ✓ ${mode}.json"
done < <(list_overlays)
