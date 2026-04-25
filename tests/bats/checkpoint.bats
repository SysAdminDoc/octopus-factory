#!/usr/bin/env bats
# Shadow-git checkpoint recovery checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/checkpoint.sh"
    TMP_REPO="$(mktemp -d)/repo"
    mkdir -p "$TMP_REPO"
    git init --quiet "$TMP_REPO"
    cd "$TMP_REPO"
    git config user.email "test@example.invalid"
    git config user.name "checkpoint test"
    printf '.factory/\n' > .gitignore
    printf 'base\n' > file.txt
    git add .gitignore file.txt
    git commit --quiet -m init
}

teardown() {
    if [[ -n "${TMP_REPO:-}" && -d "$TMP_REPO" ]]; then
        rm -rf "$(dirname "$TMP_REPO")"
    fi
}

@test "checkpoint: initializes and diffs an exact snapshot" {
    run bash "$SCRIPT" init
    [ "$status" -eq 0 ]

    run env OCTOPUS_RUN_ID="run-a" bash "$SCRIPT" snapshot L2 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"snapshot: factory-run-a-L2-1"* ]]

    printf 'changed\n' > file.txt
    run bash "$SCRIPT" diff L2 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"-base"* ]]
    [[ "$output" == *"+changed"* ]]

    run bash "$SCRIPT" rollback L2 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"rolled back worktree to L2/1"* ]]
    [ "$(cat file.txt)" = "base" ]
}

@test "checkpoint: does not treat phase labels as grep regex" {
    run bash "$SCRIPT" init
    [ "$status" -eq 0 ]

    run env OCTOPUS_RUN_ID="run-regex" bash "$SCRIPT" snapshot Lx 1
    [ "$status" -eq 0 ]

    run --separate-stderr bash "$SCRIPT" diff 'L.' 1
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"no snapshot matching L./1"* ]]
}

@test "checkpoint: rejects unsafe labels and gc day values" {
    run bash "$SCRIPT" init
    [ "$status" -eq 0 ]

    run --separate-stderr bash "$SCRIPT" snapshot 'L2;rm' 1
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"phase may contain only"* ]]

    run --separate-stderr bash "$SCRIPT" gc '30;rm'
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"days must be a non-negative integer"* ]]
}
