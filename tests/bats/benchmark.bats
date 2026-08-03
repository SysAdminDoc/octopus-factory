#!/usr/bin/env bats
# Public benchmark board smoke checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/benchmark-board.sh"
    OUTPUT="$REPO_ROOT/.factory/benchmarks/latest.json"
}

teardown() {
    if [[ -d "$REPO_ROOT/.factory/benchmarks" ]]; then
        rm -rf "$REPO_ROOT/.factory/benchmarks"
    fi
}

@test "benchmark board: balanced preset produces passing metrics and fixture expectations" {
    run bash "$SCRIPT" run --presets balanced --timeout 120 --json
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT" ]
    run jq -e '
        .status == "pass" and
        .fixture_count == 5 and
        .preset_count == 1 and
        .presets[0].preset == "balanced" and
        .presets[0].passed == 5 and
        (.presets[0] | has("cost_usd") and has("wall_clock_seconds") and has("commits") and has("tests_run") and has("rollback_events") and has("human_interventions")) and
        (.fixtures | length) == 5
    ' "$OUTPUT"
    [ "$status" -eq 0 ]
}

@test "benchmark board: unknown presets fail closed" {
    run bash "$SCRIPT" run --presets not-a-preset --timeout 5 --json
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown preset"* ]]
}
