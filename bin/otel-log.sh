#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# otel-log.sh — OpenTelemetry GenAI semconv logging helper
# ═══════════════════════════════════════════════════════════════════════════════
# Emits session log entries using OpenTelemetry GenAI semantic conventions:
#   https://opentelemetry.io/docs/specs/semconv/gen-ai/
#
# Standardized fields (replaces our custom naming):
#   gen_ai.operation.name          invoke_agent | chat | generate_content
#   gen_ai.provider.name           anthropic | openai | google | github_copilot
#   gen_ai.agent.name              grader | critic | defender | implementer
#   gen_ai.request.model           what was requested
#   gen_ai.response.model          what actually responded
#   gen_ai.usage.input_tokens      prompt tokens
#   gen_ai.usage.output_tokens     response tokens
#   gen_ai.usage.cache_read.input_tokens
#   gen_ai.usage.cache_creation.input_tokens
#   gen_ai.conversation.id         factory run_id
#
# Custom extensions (spec is silent on these):
#   factory.phase                  P1/W3/L2/L3/U1/T1/D1/Q3/etc.
#   factory.iteration              iteration number within phase
#   factory.cost_usd               decimal cost for this call
#   factory.breaker_events         array of breaker trips during call
#
# Log format: JSON-lines (one event per line) — greppable by otel-aware tools
# Location:   ~/.claude-octopus/logs/factory-${project}-${timestamp}.log
#
# Usage:
#   otel-log.sh event <json-payload>                       # append one event
#   otel-log.sh start-span <span-name>                     # emit span-start event
#   otel-log.sh end-span <span-name> [<extra-json>]        # emit span-end event
#   otel-log.sh usage <provider> <model> <role> <in> <out> <cache_r> <cache_c> [<cost>]
#     — convenience for the most common emission (per model call)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

_default_log() {
    local project="${OCTOPUS_PROJECT:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")}"
    local timestamp="${OCTOPUS_RUN_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
    echo "${HOME}/.claude-octopus/logs/factory-${project}-${timestamp}.log"
}

LOG="${OCTOPUS_OTEL_LOG:-$(_default_log)}"
RUN_ID="${OCTOPUS_RUN_ID:-factory-$(date +%s)}"

_ensure_log() {
    mkdir -p "$(dirname "$LOG")"
    touch "$LOG"
}

_now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"
}

cmd_event() {
    local payload="${1:?usage: event <json-payload>}"
    _ensure_log
    # Wrap payload with standard fields
    echo "$payload" | jq -c --arg ts "$(_now_iso)" --arg rid "$RUN_ID" '
        . + {
            "@timestamp": $ts,
            "gen_ai.conversation.id": $rid
        }
    ' >> "$LOG"
}

cmd_start_span() {
    local span_name="${1:?usage: start-span <name>}"
    cmd_event "$(jq -n --arg n "$span_name" '{
        "event": "span_start",
        "span.name": $n
    }')"
}

cmd_end_span() {
    local span_name="${1:?usage: end-span <name> [<extra-json>]}"
    local extra="${2:-{\}}"
    local base
    base=$(jq -nc --arg n "$span_name" '{event:"span_end","span.name":$n}')
    cmd_event "$(jq -nc --argjson base "$base" --argjson extra "$extra" '$base + $extra')"
}

cmd_usage() {
    local provider="${1:?usage: usage <provider> <model> <role> <in> <out> [<cache_r>] [<cache_c>] [<cost>]}"
    local model="${2:?}"
    local role="${3:?}"
    local in_tok="${4:?}"
    local out_tok="${5:?}"
    local cache_r="${6:-0}"
    local cache_c="${7:-0}"
    local cost="${8:-0}"
    local phase="${OCTOPUS_FACTORY_PHASE:-}"
    local iter="${OCTOPUS_FACTORY_ITERATION:-}"

    cmd_event "$(jq -nc \
        --arg prov "$provider" \
        --arg mdl "$model" \
        --arg role "$role" \
        --argjson in_tok "$in_tok" \
        --argjson out_tok "$out_tok" \
        --argjson cache_r "$cache_r" \
        --argjson cache_c "$cache_c" \
        --arg cost "$cost" \
        --arg phase "$phase" \
        --arg iter "$iter" '
    {
        "event": "agent_call",
        "gen_ai.operation.name": "invoke_agent",
        "gen_ai.provider.name": $prov,
        "gen_ai.agent.name": $role,
        "gen_ai.request.model": $mdl,
        "gen_ai.response.model": $mdl,
        "gen_ai.usage.input_tokens": $in_tok,
        "gen_ai.usage.output_tokens": $out_tok,
        "gen_ai.usage.cache_read.input_tokens": $cache_r,
        "gen_ai.usage.cache_creation.input_tokens": $cache_c,
        "factory.phase": $phase,
        "factory.iteration": $iter,
        "factory.cost_usd": ($cost | tonumber? // 0)
    }')"
}

cmd_breaker() {
    local breaker="${1:?usage: breaker <name> <action> [<detail>]}"
    local action="${2:?}"
    local detail="${3:-}"
    cmd_event "$(jq -nc \
        --arg b "$breaker" --arg a "$action" --arg d "$detail" \
        --arg phase "${OCTOPUS_FACTORY_PHASE:-}" '
    {
        "event": "breaker_trip",
        "factory.breaker.name": $b,
        "factory.breaker.action": $a,
        "factory.breaker.detail": $d,
        "factory.phase": $phase
    }')"
}

cmd_tail() {
    local n="${1:-20}"
    _ensure_log
    tail -n "$n" "$LOG" | jq -r '
        [.["@timestamp"], ."event", ."gen_ai.agent.name" // ."factory.breaker.name" // "-", ."gen_ai.request.model" // ."factory.breaker.action" // "-"]
        | @tsv
    ' 2>/dev/null
}

cmd_help() {
    sed -n '2,35p' "$0" | sed 's/^# \?//'
}

case "${1:-help}" in
    event)      shift; cmd_event "$@" ;;
    start-span) shift; cmd_start_span "$@" ;;
    end-span)   shift; cmd_end_span "$@" ;;
    usage)      shift; cmd_usage "$@" ;;
    breaker)    shift; cmd_breaker "$@" ;;
    tail)       shift; cmd_tail "$@" ;;
    help|-h|--help) cmd_help ;;
    *) echo "unknown command: $1" >&2; cmd_help; exit 1 ;;
esac
