#!/usr/bin/env bats
# Canonical trajectory ledger checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/factory-trajectory.sh"
    TMP_ROOT="$(mktemp -d)"
    export OCTOPUS_TRAJECTORY_ROOT="$TMP_ROOT/runs"
    export OCTOPUS_TRAJECTORY_REPO="$TMP_ROOT/repo"
    export OCTOPUS_RUN_ID="run-a"
}

teardown() {
    if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
        rm -rf "$TMP_ROOT"
    fi
}

@test "trajectory: emits normalized events and redacts sensitive keys" {
    run bash "$SCRIPT" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"initialized:"* ]]

    run bash "$SCRIPT" emit prompt_dispatch --phase L1 --iteration 1 \
        --actor researcher --payload '{"prompt_hash":"abc","api_token":"secret","input_tokens":10,"safe":true}'
    [ "$status" -eq 0 ]

    run bash "$SCRIPT" emit tool_command --phase L1 --iteration 1 \
        --payload '{"command":"git status","destructive":false}'
    [ "$status" -eq 0 ]

    local trajectory="$OCTOPUS_TRAJECTORY_ROOT/$OCTOPUS_RUN_ID/trajectory.jsonl"
    [ "$(wc -l < "$trajectory")" -eq 3 ]
    run jq -s -e '
        .[0].schema_version == 1 and
        .[0].event == "run_start" and
        .[1].event == "prompt_dispatch" and
        .[1].data.api_token == "[REDACTED]" and
        .[1].data.input_tokens == 10 and
        .[1].data.safe == true and
        .[2].data.command == "git status"
    ' "$trajectory"
    [ "$status" -eq 0 ]
}

@test "trajectory: summarizes, exports eval data, and creates a non-executable replay plan" {
    run bash "$SCRIPT" emit phase_decision --phase L1 --iteration 1 \
        --payload '{"decision":"continue","reason":"work remains"}'
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" emit commit --phase L2 --iteration 1 \
        --payload '{"sha":"abc123","message":"feat: add ledger"}'
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" emit gate_result --phase Q1 --iteration 1 \
        --payload '{"name":"tests","status":"pass"}'
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" emit run_end --payload '{"status":"completed"}'
    [ "$status" -eq 0 ]

    run bash "$SCRIPT" summarize run-a --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '.event_count == 5 and .commits == ["abc123"] and .terminal_status == "completed" and .gate_failures == 0'

    local eval_file="$TMP_ROOT/eval.json"
    run bash "$SCRIPT" export-eval run-a "$eval_file"
    [ "$status" -eq 0 ]
    [ -f "$eval_file" ]
    run jq -e '.event_count == 5 and .final_status == "completed" and .commits == ["abc123"]' "$eval_file"
    [ "$status" -eq 0 ]

    run bash "$SCRIPT" replay-plan run-a --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '.executable == false and (.steps | length) == 3 and (.steps | any(.event == "commit" and .requires_confirmation == false))'
}

@test "trajectory: filters show output and rejects unsafe run ids" {
    run bash "$SCRIPT" emit tool_command --phase L2 --payload '{"command":"echo safe"}'
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" emit fallback --phase L2 --payload '{"from":"copilot","to":"codex"}'
    [ "$status" -eq 0 ]

    run bash "$SCRIPT" show run-a --json --event tool_command --last 1
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e -s 'length == 1 and .[0].event == "tool_command"'

    run --separate-stderr env OCTOPUS_RUN_ID='bad/../../path' bash "$SCRIPT" init
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"run id may contain only"* ]]
}

@test "trajectory: OTel usage hook preserves token metrics" {
    export OCTOPUS_RUN_ID="otel-run"
    export OCTOPUS_OTEL_LOG="$TMP_ROOT/otel.log"

    run bash "$REPO_ROOT/bin/otel-log.sh" usage anthropic claude-sonnet-4.6 implementer 10 20 3 4 0.5
    [ "$status" -eq 0 ]

    local trajectory="$OCTOPUS_TRAJECTORY_ROOT/otel-run/trajectory.jsonl"
    run jq -s -e '
        .[1].event == "model_selection" and
        .[1].data.provider == "anthropic" and
        .[1].data.input_tokens == 10 and
        .[1].data.output_tokens == 20 and
        .[1].data.cache_read_tokens == 3 and
        .[1].data.cache_creation_tokens == 4
    ' "$trajectory"
    [ "$status" -eq 0 ]
}
