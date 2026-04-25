#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# cost-estimate.sh — Tiered cost calculation for agent calls
# ═══════════════════════════════════════════════════════════════════════════════
# Pattern ported from cline/cline (Apache 2.0):
#   src/utils/cost.ts:calculateApiCostInternal
#
# Cline's formula handles the four pricing components correctly:
#   cost = (cacheWritesPrice/1e6) * cacheCreation
#        + (cacheReadsPrice/1e6) * cacheRead
#        + (inputPrice/1e6) * input
#        + (outputPrice/1e6) * output
#
# Also distinguishes Anthropic vs OpenAI token-counting wrappers: Anthropic
# reports cache-creation separately from input; OpenAI folds cache-creation
# into the input count. This script follows Anthropic's model (our primary).
#
# Usage:
#   cost-estimate.sh calc <model> <input> <output> [<cache_r>] [<cache_c>]
#   cost-estimate.sh prices                                      # list known models
#   cost-estimate.sh register <model> <in/M> <out/M> [<cr/M>] [<cw/M>]
#
# Prices in USD per 1 million tokens, as of 2026-04 (update as vendors adjust).
# Prices read from ~/.claude-octopus/config/model-prices.json if present,
# else from this script's embedded defaults.
#
# Output: single decimal number (USD), suitable for aggregation.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

PRICES_FILE="${HOME}/.claude-octopus/config/model-prices.json"

# Embedded defaults — only used if $PRICES_FILE is missing
# Prices are $ per 1M tokens (input, output, cache_read, cache_write)
_default_prices() {
    cat <<'JSON'
{
  "claude-opus-4.7":       {"input": 15.00, "output": 75.00, "cache_read": 1.50,  "cache_write": 18.75},
  "claude-sonnet-4.6":     {"input":  3.00, "output": 15.00, "cache_read": 0.30,  "cache_write":  3.75},
  "claude-sonnet-4.5":     {"input":  3.00, "output": 15.00, "cache_read": 0.30,  "cache_write":  3.75},
  "claude-haiku-4.5":      {"input":  1.00, "output":  5.00, "cache_read": 0.10,  "cache_write":  1.25},
  "gpt-5.4":               {"input":  2.50, "output": 10.00, "cache_read": 0.25,  "cache_write":  2.50},
  "gpt-5.4-mini":          {"input":  0.15, "output":  0.60, "cache_read": 0.015, "cache_write":  0.15},
  "gpt-5.3-codex":         {"input":  2.50, "output": 10.00, "cache_read": 0.25,  "cache_write":  2.50},
  "gpt-5.2":               {"input":  2.50, "output": 10.00, "cache_read": 0.25,  "cache_write":  2.50},
  "gpt-5-mini":            {"input":  0.15, "output":  0.60, "cache_read": 0.015, "cache_write":  0.15},
  "o3":                    {"input": 15.00, "output": 60.00, "cache_read": 7.50,  "cache_write": 15.00},
  "gemini-2.5-pro":        {"input":  1.25, "output": 10.00, "cache_read": 0.3125,"cache_write":  1.25},
  "gemini-2.5-flash":      {"input":  0.075,"output":  0.30, "cache_read": 0.01875,"cache_write": 0.075},
  "gpt-image-1":           {"input": 10.00, "output": 40.00, "cache_read": 0.0,   "cache_write":  0.0,
                            "_note": "per-image ~$0.04 at 1024x1024; token accounting approximate"}
}
JSON
}

_load_prices() {
    if [[ -f "$PRICES_FILE" ]]; then
        cat "$PRICES_FILE"
    else
        _default_prices
    fi
}

cmd_calc() {
    local model="${1:?usage: calc <model> <input> <output> [<cache_r>] [<cache_c>]}"
    local input="${2:?}"
    local output="${3:?}"
    local cache_read="${4:-0}"
    local cache_write="${5:-0}"

    local prices
    prices=$(_load_prices)

    local result
    result=$(echo "$prices" | jq -r --arg m "$model" \
        --argjson in "$input" \
        --argjson out "$output" \
        --argjson cr "$cache_read" \
        --argjson cw "$cache_write" '
    if .[$m] == null then
        "ERROR: unknown model \($m)"
    else
        .[$m] as $p |
        (
            (($p.input       // 0) * $in  / 1000000) +
            (($p.output      // 0) * $out / 1000000) +
            (($p.cache_read  // 0) * $cr  / 1000000) +
            (($p.cache_write // 0) * $cw  / 1000000)
        ) | tostring
    end
    ')
    echo "$result"
}

cmd_prices() {
    _load_prices | jq -r 'to_entries[] | "\(.key):\n  input=$\(.value.input)/M  output=$\(.value.output)/M  cache_r=$\(.value.cache_read)/M  cache_w=$\(.value.cache_write)/M"'
}

cmd_register() {
    local model="${1:?usage: register <model> <in/M> <out/M> [<cr/M>] [<cw/M>]}"
    local input_p="${2:?}"
    local output_p="${3:?}"
    local cache_r_p="${4:-0}"
    local cache_w_p="${5:-0}"

    mkdir -p "$(dirname "$PRICES_FILE")"
    local current
    if [[ -f "$PRICES_FILE" ]]; then
        current=$(cat "$PRICES_FILE")
    else
        current=$(_default_prices)
    fi

    echo "$current" | jq --arg m "$model" \
        --argjson i "$input_p" --argjson o "$output_p" \
        --argjson cr "$cache_r_p" --argjson cw "$cache_w_p" '
        .[$m] = { "input": $i, "output": $o, "cache_read": $cr, "cache_write": $cw }
    ' > "$PRICES_FILE"

    echo "registered $model: in=\$$input_p/M out=\$$output_p/M cr=\$$cache_r_p/M cw=\$$cache_w_p/M"
}

cmd_help() {
    sed -n '2,30p' "$0" | sed 's/^# \?//'
}

case "${1:-help}" in
    calc)     shift; cmd_calc "$@" ;;
    prices)   shift; cmd_prices "$@" ;;
    register) shift; cmd_register "$@" ;;
    help|-h|--help) cmd_help ;;
    *) echo "unknown command: $1" >&2; cmd_help; exit 1 ;;
esac
