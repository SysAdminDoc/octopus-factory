#!/usr/bin/env bats
# SQLite state-store reliability and input-validation checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/state-store.sh"
    if ! command -v sqlite3 >/dev/null 2>&1; then
        skip "sqlite3 not installed"
    fi
}

@test "state-store: creates schema for an existing empty DB file" {
    local tmp db payload
    tmp="$(mktemp -d)"
    db="$tmp/state.db"
    payload="{\"msg\":\"it's still json\"}"
    : > "$db"

    run env OCTOPUS_STATE_DB="$db" bash "$SCRIPT" save "run'one" "L2" "0" "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"saved: run'one/L2/0"* ]]

    run env OCTOPUS_STATE_DB="$db" bash "$SCRIPT" load "run'one" "L2" "0"
    [ "$status" -eq 0 ]
    [ "$output" = "$payload" ]

    rm -rf "$tmp"
}

@test "state-store: rejects unsafe complete cost values before SQL execution" {
    local tmp db
    tmp="$(mktemp -d)"
    db="$tmp/state.db"

    run env OCTOPUS_STATE_DB="$db" bash "$SCRIPT" save "run1" "L2" "0" "{}"
    [ "$status" -eq 0 ]

    run --separate-stderr env OCTOPUS_STATE_DB="$db" bash "$SCRIPT" complete "run1" "0; DROP TABLE runs"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"cost must be a non-negative decimal number"* ]]

    run sqlite3 "$db" "SELECT COUNT(*) FROM runs;"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    rm -rf "$tmp"
}

@test "state-store: rejects unsafe prune day values before arithmetic or SQL" {
    local tmp db
    tmp="$(mktemp -d)"
    db="$tmp/state.db"

    run env OCTOPUS_STATE_DB="$db" bash "$SCRIPT" init
    [ "$status" -eq 0 ]

    run --separate-stderr env OCTOPUS_STATE_DB="$db" bash "$SCRIPT" prune "30; DROP TABLE runs"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"days must be a non-negative integer"* ]]

    run sqlite3 "$db" "SELECT COUNT(*) FROM runs;"
    [ "$status" -eq 0 ]

    rm -rf "$tmp"
}
