#!/usr/bin/env bats
# Local context-pack contract checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/context-pack.sh"
    TMP_ROOT="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMP_ROOT"
}

@test "context-pack: writes bounded map and redacted pack without running repo commands" {
    mkdir -p "$TMP_ROOT/.github/workflows"
    printf '%s\n' '{"scripts":{"test":"npm test"}}' > "$TMP_ROOT/package.json"
    printf '%s\n' 'API_KEY=do-not-leak' > "$TMP_ROOT/README.md"
    printf '%s\n' 'def main(): pass' > "$TMP_ROOT/main.py"
    printf '%s\n' 'test: npm test' > "$TMP_ROOT/justfile"
    printf '%s\n' 'name: ci' > "$TMP_ROOT/.github/workflows/ci.yml"

    run bash "$SCRIPT" "$TMP_ROOT" --json
    [ "$status" -eq 0 ]
    [ -f "$TMP_ROOT/.factory/context/pack.md" ]
    [ -f "$TMP_ROOT/.factory/context/repo-map.json" ]
    [[ "$output" == *'"status": "ok"'* ]]

    run grep -F "Node.js" "$TMP_ROOT/.factory/context/pack.md"
    [ "$status" -eq 0 ]
    run grep -F "<redacted>" "$TMP_ROOT/.factory/context/pack.md"
    [ "$status" -eq 0 ]
    run grep -F "npm test" "$TMP_ROOT/.factory/context/pack.md"
    [ "$status" -eq 0 ]
    run grep -F "API_KEY=do-not-leak" "$TMP_ROOT/.factory/context/pack.md"
    [ "$status" -ne 0 ]
}

@test "context-pack: refuses output paths outside the repository context directory" {
    run bash "$SCRIPT" "$TMP_ROOT" --output-dir "$TMP_ROOT/../escape"
    [ "$status" -eq 1 ]
    [[ "$output" == *"under <repo>/.factory/context"* ]]
}
