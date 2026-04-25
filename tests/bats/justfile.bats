#!/usr/bin/env bats
# Justfile + recipe smoke. Skips entirely if `just` isn't installed
# (it's an optional prereq, not required to use the factory).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    cd "$REPO_ROOT"
    if ! command -v just >/dev/null 2>&1; then
        skip "just not installed — skipping justfile recipe tests"
    fi
}

@test "just --list parses without error" {
    run just --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"preset-verify"* ]]
    [[ "$output" == *"doctor"* ]]
}

@test "just version recipe runs" {
    run just version
    [ "$status" -eq 0 ]
    [[ "$output" == *"octopus-factory"* ]]
}

@test "just preset-verify exits 0 (no drift on a clean tree)" {
    run just preset-verify
    [ "$status" -eq 0 ]
}

@test "just preset-build is idempotent" {
    run just preset-build
    [ "$status" -eq 0 ]
    run just preset-verify
    [ "$status" -eq 0 ]
}
