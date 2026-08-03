#!/usr/bin/env bats
# Q1 agent-safety red-team gate contract checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/redteam-gate.sh"
}

make_repo() {
    local path="$1"
    mkdir -p "$path"
    git -C "$path" init -q
    git -C "$path" config user.email test@example.invalid
    git -C "$path" config user.name redteam-test
    printf 'fixture\n' > "$path/fixture.txt"
    git -C "$path" add fixture.txt
    git -C "$path" commit -q -m 'test: initialize fixture'
}

@test "redteam gate: core profile writes clean JSON and HTML reports" {
    local tmp
    tmp="$(mktemp -d)"
    make_repo "$tmp/repo"

    run bash "$SCRIPT" run "$tmp/repo" --run-id bats-core --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '
        .status == "pass" and
        .profile == "core" and
        .coverage == "contract-only" and
        (.checks | map(select(.status == "fail")) | length) == 0 and
        (.report_file | endswith("/redteam/report.json")) and
        (.html_file | endswith("/redteam/report.html"))'
    [ -f "$tmp/repo/.factory/runs/bats-core/redteam/report.json" ]
    [ -f "$tmp/repo/.factory/runs/bats-core/redteam/report.html" ]

    rm -rf "$tmp"
}

@test "redteam gate: all profile snapshots the nightly collection" {
    local tmp
    tmp="$(mktemp -d)"
    make_repo "$tmp/repo"

    run bash "$SCRIPT" run "$tmp/repo" --run-id bats-all --profile all --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '.profile == "all" and .profile_collection == "coding-agent:all"'
    grep -q -- '- coding-agent:all' "$tmp/repo/.factory/runs/bats-all/redteam/promptfooconfig.yaml"

    rm -rf "$tmp"
}

@test "redteam gate: failed checks require a waiver" {
    local tmp
    tmp="$(mktemp -d)"
    make_repo "$tmp/repo"

    run bash "$SCRIPT" run "$tmp/repo" --run-id bats-fail --config "$tmp/missing.yaml" --json
    [ "$status" -eq 1 ]
    printf '%s' "$output" | jq -e '.status == "fail" and .waiver_required == true'

    run bash "$SCRIPT" run "$tmp/repo" --run-id bats-waived --config "$tmp/missing.yaml" \
        --waive 'SEC-123: reviewed and accepted for this fixture' --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '.status == "waived" and (.waiver | startswith("SEC-123"))'

    rm -rf "$tmp"
}
