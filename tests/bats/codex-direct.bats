#!/usr/bin/env bats
# codex-direct argument-validation smoke. These tests exercise parser failures
# that should fail before any codex CLI/auth preflight runs.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/codex-direct.sh"
}

@test "codex-direct: --help exits 0" {
    run --separate-stderr bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "codex-direct: requires a phase" {
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"phase required"* ]]
}

@test "codex-direct: custom phase requires a model before codex preflight" {
    run --separate-stderr bash "$SCRIPT" custom
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"phase=custom requires --model"* ]]
}

@test "codex-direct: rejects missing option values clearly" {
    run --separate-stderr bash "$SCRIPT" audit --model
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"--model requires a value"* ]]

    run --separate-stderr bash "$SCRIPT" audit --cwd --out result.md
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"--cwd requires a value"* ]]

    run --separate-stderr bash "$SCRIPT" audit --prompt
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"--prompt requires a value"* ]]
}
