#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# factory-trajectory.sh — canonical append-only run ledger
# ═══════════════════════════════════════════════════════════════════════════════
# Every factory run can emit a normalized JSONL trajectory under
# .factory/runs/<run_id>/trajectory.jsonl. The ledger is intentionally local,
# append-only, and descriptive: replay-plan never executes recorded commands.
#
# Usage:
#   factory-trajectory.sh init [<run_id>]
#   factory-trajectory.sh emit <event> [--phase P] [--iteration N]
#       [--actor NAME] [--payload JSON | --payload-env NAME]
#   factory-trajectory.sh show [<run_id>] [--json] [--last N] [--event NAME]
#   factory-trajectory.sh summarize [<run_id>] [--json]
#   factory-trajectory.sh export-eval [<run_id>] [<output.json>]
#   factory-trajectory.sh replay-plan [<run_id>] [--json]
#
# Environment:
#   OCTOPUS_RUN_ID              run identifier (default: factory-<timestamp>-pid)
#   OCTOPUS_TRAJECTORY_ROOT     run root (default: <repo>/.factory/runs)
#   OCTOPUS_TRAJECTORY_REPO     repository path recorded in run_start
#   OCTOPUS_TRAJECTORY_DISABLED  set to 1/true to disable best-effort hooks
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

_repo_root() {
    if [[ -n "${OCTOPUS_TRAJECTORY_REPO:-}" ]]; then
        printf '%s\n' "$OCTOPUS_TRAJECTORY_REPO"
        return 0
    fi
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

REPO_ROOT="$(_repo_root)"
TRAJECTORY_ROOT="${OCTOPUS_TRAJECTORY_ROOT:-${REPO_ROOT}/.factory/runs}"
DEFAULT_RUN_ID="factory-$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_ID="${OCTOPUS_RUN_ID:-$DEFAULT_RUN_ID}"

_require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "factory-trajectory: jq is required" >&2
        return 1
    fi
}

_require_run_id() {
    if [[ ! "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "factory-trajectory: run id may contain only letters, numbers, dot, underscore, and hyphen" >&2
        return 1
    fi
}

_run_dir() {
    printf '%s/%s\n' "$TRAJECTORY_ROOT" "$RUN_ID"
}

_trajectory_file() {
    printf '%s/trajectory.jsonl\n' "$(_run_dir)"
}

_ensure_file() {
    _require_jq
    _require_run_id
    mkdir -p "$(_run_dir)"
    touch "$(_trajectory_file)"
}

_now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_event_allowed() {
    case "$1" in
        run_start|run_end|prompt_dispatch|model_selection|tool_command|command_output|\
        file_diff|checkpoint|commit|cost_delta|gate_result|fallback|\
        user_interruption|phase_decision)
            return 0 ;;
        *)
            echo "factory-trajectory: unsupported event '$1'" >&2
            echo "  allowed: run_start run_end prompt_dispatch model_selection tool_command command_output" >&2
            echo "           file_diff checkpoint commit cost_delta gate_result fallback user_interruption phase_decision" >&2
            return 1 ;;
    esac
}

_redact_payload() {
    local payload="$1"
    jq -ce '
        if type != "object" then error("payload must be a JSON object") else . end
        | walk(
            if type == "object" then
                with_entries(
                    if (.key | test("(?i)^(password|secret|token|api[_-]?(key|token)|access[_-]?token|refresh[_-]?token|id[_-]?token|bearer[_-]?token|authorization|cookie|private[_-]?key)$"))
                    then .value = "[REDACTED]"
                    else .
                    end
                )
            else .
            end
        )
    ' <<<"$payload"
}

_append_event() {
    local event="$1"
    local phase="$2"
    local iteration="$3"
    local actor="$4"
    local payload="$5"
    local file
    local timestamp
    local event_id
    local normalized_iteration="null"

    _ensure_file
    _event_allowed "$event"
    payload="$(_redact_payload "$payload")" || {
        echo "factory-trajectory: payload must be a JSON object" >&2
        return 1
    }

    if [[ -n "$iteration" ]]; then
        if [[ ! "$iteration" =~ ^[0-9]+$ ]]; then
            echo "factory-trajectory: iteration must be a non-negative integer" >&2
            return 1
        fi
        normalized_iteration="$iteration"
    fi

    timestamp="$(_now_iso)"
    event_id="${RUN_ID}-${timestamp//[^0-9A-Za-z]/}-${BASHPID}"
    file="$(_trajectory_file)"

    jq -cn \
        --arg schema_version "1" \
        --arg event_id "$event_id" \
        --arg timestamp "$timestamp" \
        --arg run_id "$RUN_ID" \
        --arg event "$event" \
        --arg phase "$phase" \
        --arg actor "$actor" \
        --argjson iteration "$normalized_iteration" \
        --argjson data "$payload" \
        '{
            schema_version: ($schema_version | tonumber),
            event_id: $event_id,
            timestamp: $timestamp,
            run_id: $run_id,
            event: $event,
            phase: (if $phase == "" then null else $phase end),
            iteration: $iteration,
            actor: (if $actor == "" then null else $actor end),
            data: $data
        }' >> "$file"
}

_ensure_run_started() {
    local file
    file="$(_trajectory_file)"
    _ensure_file
    if [[ ! -s "$file" ]]; then
        _append_event run_start "" "" "factory-trajectory" "$(jq -cn \
            --arg repo "${OCTOPUS_TRAJECTORY_REPO:-$REPO_ROOT}" \
            --arg cwd "$PWD" \
            --arg source "${OCTOPUS_TRAJECTORY_SOURCE:-factory-trajectory}" \
            --arg pid "$$" \
            '{repo_path:$repo,cwd:$cwd,source:$source,pid:($pid|tonumber)}')"
    fi
}

_read_events() {
    local run_id="$1"
    local file="${TRAJECTORY_ROOT}/${run_id}/trajectory.jsonl"
    if [[ ! -f "$file" ]]; then
        echo "factory-trajectory: trajectory not found: $file" >&2
        return 1
    fi
    cat "$file"
}

_json_summary() {
    local run_id="$1"
    _read_events "$run_id" | jq -s --arg run_id "$run_id" '
        def nonnull(values): [values[] | select(. != null)];
        def count_event($name): ([.[] | select(.event == $name)] | length);
        . as $events |
        {
            schema_version: 1,
            run_id: $run_id,
            event_count: ($events | length),
            event_counts: ($events | group_by(.event) | map({key: .[0].event, value: length}) | from_entries),
            phases: (nonnull([$events[].phase]) | unique),
            first_timestamp: ($events[0].timestamp // null),
            last_timestamp: ($events[-1].timestamp // null),
            commits: ([$events[] | select(.event == "commit") | .data.sha // empty] | unique),
            checkpoints: count_event("checkpoint"),
            tool_commands: count_event("tool_command"),
            gate_failures: ([$events[] | select(.event == "gate_result" and ((.data.status // "") | ascii_downcase | IN("fail","failed","error")))] | length),
            fallbacks: count_event("fallback"),
            interruptions: count_event("user_interruption"),
            terminal_status: ([$events[] | select(.event == "run_end") | .data.status] | last // "running"),
            repo_path: ([$events[] | select(.event == "run_start") | .data.repo_path] | first // null)
        }
    '
}

cmd_init() {
    if [[ $# -gt 0 ]]; then
        RUN_ID="$1"
    fi
    _require_run_id
    _ensure_file
    if [[ ! -s "$(_trajectory_file)" ]]; then
        _append_event run_start "" "" "factory-trajectory" "$(jq -cn \
            --arg repo "${OCTOPUS_TRAJECTORY_REPO:-$REPO_ROOT}" \
            --arg cwd "$PWD" \
            --arg source "${OCTOPUS_TRAJECTORY_SOURCE:-factory-trajectory}" \
            --arg pid "$$" \
            '{repo_path:$repo,cwd:$cwd,source:$source,pid:($pid|tonumber)}')"
        echo "initialized: $(_trajectory_file)"
    else
        echo "already initialized: $(_trajectory_file)"
    fi
}

cmd_emit() {
    local event="${1:?usage: emit <event> [--phase P] [--iteration N] [--actor NAME] [--payload JSON]}"
    shift
    local phase=""
    local iteration=""
    local actor=""
    local payload="{}"
    local payload_env=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase)
                [[ $# -ge 2 ]] || { echo "factory-trajectory: --phase requires a value" >&2; return 1; }
                phase="$2"; shift 2 ;;
            --iteration)
                [[ $# -ge 2 ]] || { echo "factory-trajectory: --iteration requires a value" >&2; return 1; }
                iteration="$2"; shift 2 ;;
            --actor)
                [[ $# -ge 2 ]] || { echo "factory-trajectory: --actor requires a value" >&2; return 1; }
                actor="$2"; shift 2 ;;
            --payload)
                [[ $# -ge 2 ]] || { echo "factory-trajectory: --payload requires a value" >&2; return 1; }
                payload="$2"; shift 2 ;;
            --payload-env)
                [[ $# -ge 2 ]] || { echo "factory-trajectory: --payload-env requires a variable name" >&2; return 1; }
                if [[ ! "$2" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                    echo "factory-trajectory: --payload-env requires a valid environment variable name" >&2
                    return 1
                fi
                payload_env="$2"; shift 2 ;;
            *)
                echo "factory-trajectory: unknown emit option: $1" >&2
                return 1 ;;
        esac
    done

    if [[ -n "$payload_env" ]]; then
        payload="${!payload_env-}"
        [[ -n "$payload" ]] || { echo "factory-trajectory: payload environment variable is empty: $payload_env" >&2; return 1; }
    fi

    if [[ "$event" != "run_start" ]]; then
        _ensure_run_started
    fi
    _append_event "$event" "$phase" "$iteration" "$actor" "$payload"
    echo "emitted: $RUN_ID/$event"
}

cmd_show() {
    local run_id="${1:-$RUN_ID}"
    if [[ $# -gt 0 ]]; then shift; fi
    local as_json=false
    local last=""
    local event_filter=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) as_json=true; shift ;;
            --last)
                [[ $# -ge 2 ]] || { echo "factory-trajectory: --last requires a value" >&2; return 1; }
                last="$2"; shift 2 ;;
            --event)
                [[ $# -ge 2 ]] || { echo "factory-trajectory: --event requires a value" >&2; return 1; }
                event_filter="$2"; shift 2 ;;
            *) echo "factory-trajectory: unknown show option: $1" >&2; return 1 ;;
        esac
    done

    _require_jq
    if [[ -n "$last" && ! "$last" =~ ^[1-9][0-9]*$ ]]; then
        echo "factory-trajectory: --last must be a positive integer" >&2
        return 1
    fi

    local stream
    stream="$(_read_events "$run_id")"
    if [[ -n "$event_filter" ]]; then
        stream="$(printf '%s\n' "$stream" | jq -c --arg event "$event_filter" 'select(.event == $event)')"
    fi
    if [[ -n "$last" ]]; then
        stream="$(printf '%s\n' "$stream" | tail -n "$last")"
    fi
    if $as_json; then
        printf '%s\n' "$stream"
    else
        printf '%s\n' "$stream" | jq -r '[.timestamp, .event, (.phase // "-"), (.actor // "-")] | @tsv'
    fi
}

cmd_summarize() {
    local run_id="${1:-$RUN_ID}"
    if [[ $# -gt 0 ]]; then shift; fi
    local as_json=false
    if [[ $# -gt 0 && "$1" == "--json" ]]; then
        as_json=true
        shift
    fi
    [[ $# -eq 0 ]] || { echo "factory-trajectory: unknown summarize option: $1" >&2; return 1; }
    local summary
    summary="$(_json_summary "$run_id")"
    if $as_json; then
        printf '%s\n' "$summary"
    else
        printf '%s\n' "$summary" | jq -r '
            "Run: \(.run_id)",
            "Repository: \(.repo_path // "-")",
            "Events: \(.event_count)",
            "Window: \(.first_timestamp // "-") → \(.last_timestamp // "-")",
            "Commands: \(.tool_commands), checkpoints: \(.checkpoints), gate failures: \(.gate_failures)",
            "Fallbacks: \(.fallbacks), interruptions: \(.interruptions)",
            "Status: \(.terminal_status)"
        '
    fi
}

_eval_export() {
    local run_id="$1"
    _read_events "$run_id" | jq -s --arg run_id "$run_id" --arg file "${TRAJECTORY_ROOT}/${run_id}/trajectory.jsonl" '
        def nonnull(values): [values[] | select(. != null)];
        def epoch:
            sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
        def duration:
            if .[0].timestamp == null or .[-1].timestamp == null then null
            else ((.[-1].timestamp | epoch) - (.[0].timestamp | epoch))
            end;
        . as $events |
        {
            schema_version: 1,
            run_id: $run_id,
            trajectory_file: $file,
            repo_path: (nonnull([$events[] | select(.event == "run_start") | .data.repo_path]) | first // null),
            started_at: ($events[0].timestamp // null),
            ended_at: ([$events[] | select(.event == "run_end") | .timestamp] | last // null),
            duration_seconds: ($events | duration),
            event_count: ($events | length),
            phases: (nonnull([$events[].phase]) | unique),
            commits: ([$events[] | select(.event == "commit") | .data.sha // empty] | unique),
            gates: ([$events[] | select(.event == "gate_result") | {name:(.data.name // "unknown"),status:(.data.status // "unknown")}]),
            commands: ([$events[] | select(.event == "tool_command") | {command:(.data.command // "unknown"),exit_code:(.data.exit_code // null)}]),
            fallback_count: ([$events[] | select(.event == "fallback")] | length),
            interruption_count: ([$events[] | select(.event == "user_interruption")] | length),
            final_status: ([$events[] | select(.event == "run_end") | .data.status] | last // "running")
        }
    '
}

cmd_export_eval() {
    local run_id="${1:-$RUN_ID}"
    if [[ $# -gt 0 ]]; then shift; fi
    local output=""
    if [[ $# -gt 0 ]]; then
        output="$1"
        shift
    fi
    [[ $# -eq 0 ]] || { echo "factory-trajectory: too many export-eval arguments" >&2; return 1; }
    local result
    result="$(_eval_export "$run_id")"
    if [[ -n "$output" ]]; then
        mkdir -p "$(dirname "$output")"
        printf '%s\n' "$result" > "$output"
        echo "exported: $output"
    else
        printf '%s\n' "$result"
    fi
}

cmd_replay_plan() {
    local run_id="${1:-$RUN_ID}"
    if [[ $# -gt 0 ]]; then shift; fi
    local as_json=false
    if [[ $# -gt 0 && "$1" == "--json" ]]; then
        as_json=true
        shift
    fi
    [[ $# -eq 0 ]] || { echo "factory-trajectory: unknown replay-plan option: $1" >&2; return 1; }
    local plan
    plan="$(_read_events "$run_id" | jq -s --arg run_id "$run_id" '
        {
            schema_version: 1,
            run_id: $run_id,
            executable: false,
            warning: "Descriptive plan only; recorded commands and side effects are never executed.",
            steps: [
                .[]
                | select(.event | IN("prompt_dispatch","model_selection","tool_command","command_output","checkpoint","commit","gate_result","fallback","phase_decision","user_interruption"))
                | {
                    event_id,
                    timestamp,
                    event,
                    phase,
                    iteration,
                    action: (
                        .data.action
                        // .data.command
                        // .data.decision
                        // .data.name
                        // .data.sha
                        // .data.reason
                        // .event
                    ),
                    status: (.data.status // null),
                    exit_code: (.data.exit_code // null),
                    requires_confirmation: (
                        (.data.destructive // false)
                        or (.data.command // "" | test("(?i)(push|reset|delete|force|publish|rewrite)"))
                    )
                }
            ]
        }
    ')"
    if $as_json; then
        printf '%s\n' "$plan"
    else
        printf '%s\n' "$plan" | jq -r '
            "Replay plan for \(.run_id) (executable: \(.executable))",
            .warning,
            (.steps[] | "- \(.timestamp) [\(.event)] \(.action // "-")\(if .requires_confirmation then " [confirmation required]" else "" end)")
        '
    fi
}

cmd_help() {
    sed -n '2,23p' "$0" | sed 's/^# \?//'
}

case "${1:-help}" in
    init)         shift; cmd_init "$@" ;;
    emit)         shift; cmd_emit "$@" ;;
    show)         shift; cmd_show "$@" ;;
    summarize)    shift; cmd_summarize "$@" ;;
    export-eval)  shift; cmd_export_eval "$@" ;;
    replay-plan)  shift; cmd_replay_plan "$@" ;;
    help|-h|--help) cmd_help ;;
    *) echo "factory-trajectory: unknown command: $1" >&2; cmd_help; exit 1 ;;
esac
