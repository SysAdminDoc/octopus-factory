#!/usr/bin/env bats
# Local agent-evaluation contract checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/eval-agent.sh"
    TMP_ROOT="$(mktemp -d)"
}

teardown() {
    if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
        rm -rf "$TMP_ROOT"
    fi
}

@test "eval-agent: all local fixtures satisfy the factory contract" {
    run bash "$SCRIPT" run --output "$TMP_ROOT/report.json" \
        --artifact-dir "$TMP_ROOT/artifacts" --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '
        .status == "pass" and
        .scenario_count == 5 and
        .passed == 5 and
        ([.results[].checks | to_entries[] | .value] | all)
    '
    [ -f "$TMP_ROOT/report.json" ]
    run jq -e '[.results[].trajectory.event_count] | min > 0' "$TMP_ROOT/report.json"
    [ "$status" -eq 0 ]
}

@test "eval-agent: nightly provider matrix remains adapter-driven" {
    run bash "$SCRIPT" nightly --providers alpha,beta --scenario broken-python-cli \
        --output "$TMP_ROOT/nightly.json" --artifact-dir "$TMP_ROOT/nightly-artifacts" --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '
        .mode == "nightly" and
        .provider_execution == "synthetic-contract" and
        .scenario_count == 2 and
        ([.results[].provider] | sort) == ["alpha", "beta"]
    '
}
