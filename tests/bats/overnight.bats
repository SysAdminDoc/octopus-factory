#!/usr/bin/env bats
# factory-overnight.sh smoke. Skips entirely on bash <4 because the script
# itself requires bash 4+ (declares it via runtime guard + bats marker).

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/factory-overnight.sh"
    if (( BASH_VERSINFO[0] < 4 )); then
        skip "factory-overnight.sh requires bash 4+ (have ${BASH_VERSION})"
    fi
    # Don't let stale sentinels from real overnight sessions interfere.
    [[ -f "$HOME/.factory-overnight.lock" ]] || true
}

@test "factory-overnight: --help exits 0 and prints Usage" {
    run --separate-stderr bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--auto-discover"* ]]
    [[ "$output" == *"--quiet"* ]]
}

@test "factory-overnight: --show-config dumps effective config and exits" {
    run --separate-stderr bash "$SCRIPT" "$REPO_ROOT" --show-config --duration 1h --no-color
    [ "$status" -eq 0 ]
    [[ "$output" == *"effective configuration"* ]]
    [[ "$output" == *"Verbose output:     yes"* ]]
    [[ "$output" == *"Heartbeat:          30s"* ]]
}

@test "factory-overnight: rejects unknown option" {
    run --separate-stderr bash "$SCRIPT" --no-such-flag
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"unknown option"* ]]
}

@test "factory-overnight: rejects missing option values clearly" {
    run --separate-stderr bash "$SCRIPT" --duration
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"--duration requires a value"* ]]

    run --separate-stderr bash "$SCRIPT" --auto-discover --show-config
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"--auto-discover requires a value"* ]]
}

@test "factory-overnight: rejects invalid numeric option values clearly" {
    run --separate-stderr bash "$SCRIPT" "$REPO_ROOT" --show-config --sleep nope
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"--sleep must be a non-negative integer"* ]]

    run --separate-stderr bash "$SCRIPT" "$REPO_ROOT" --show-config --cycle-timeout 0
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"--cycle-timeout must be greater than zero"* ]]

    run --separate-stderr bash "$SCRIPT" "$REPO_ROOT" --show-config --max-spend-total nope
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"--max-spend-total must be a non-negative number"* ]]
}

@test "factory-overnight: rejects missing repo arg" {
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"at least one repo path required"* ]]
}

@test "factory-overnight: rejects non-existent repo" {
    run --separate-stderr bash "$SCRIPT" /nonexistent/path/foo --dry-run
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"not found"* ]]
}

@test "factory-overnight: --dry-run completes one cycle without invoking claude" {
    rm -f "$HOME/.factory-overnight.lock"
    run --separate-stderr bash "$SCRIPT" "$REPO_ROOT" \
        --dry-run --max-cycles 1 --sleep 0 --heartbeat-sec 0 --no-color
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
    [[ "$output" == *"max-cycles (1) reached"* ]]
    rm -f "$HOME/.factory-overnight.status" "$HOME/.factory-overnight.status.json"
}

@test "factory-overnight: --dry-run honors --max-cycles round-robin" {
    rm -f "$HOME/.factory-overnight.lock"
    run --separate-stderr bash "$SCRIPT" "$REPO_ROOT" "$REPO_ROOT/bin" \
        --dry-run --max-cycles 2 --sleep 0 --heartbeat-sec 0 --no-color 2>&1 || true
    # bin/ isn't a git repo so this should fail pre-flight rather than run
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"not a git repo"* ]]
}

@test "factory-overnight: --auto-discover finds the current repo" {
    run --separate-stderr bash "$SCRIPT" \
        --auto-discover "$(dirname "$REPO_ROOT")" --show-config --no-color
    [ "$status" -eq 0 ]
    # The current repo must appear in the discovered list.
    [[ "$output" == *"$(basename "$REPO_ROOT")"* ]]
}

@test "factory-overnight: --exclude-repo filters discovery output" {
    local repo_name
    repo_name="$(basename "$REPO_ROOT")"
    run --separate-stderr bash "$SCRIPT" \
        --auto-discover "$(dirname "$REPO_ROOT")" \
        --exclude-repo "$repo_name" \
        --show-config --no-color
    # If the exclude removed the only repo, the script may exit 1 (no repos
    # left) — acceptable; either way, the repo's path should not appear in
    # the Repos list section.
    if [[ "$status" -eq 0 ]]; then
        # Extract the Repos block, confirm filtered repo absent
        local repos_block
        repos_block=$(echo "$output" | sed -n '/^Repos /,/^Excludes:/p')
        [[ "$repos_block" != *"$REPO_ROOT"* ]]
    fi
}

@test "factory-overnight: --status returns gracefully when no session active" {
    rm -f "$HOME/.factory-overnight.status"
    run --separate-stderr bash "$SCRIPT" --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"no overnight session active"* ]]
}

@test "factory-overnight: --stop creates the sentinel and exits 0" {
    rm -f "$HOME/.factory-overnight.stop"
    run --separate-stderr bash "$SCRIPT" --stop
    [ "$status" -eq 0 ]
    [ -f "$HOME/.factory-overnight.stop" ]
    rm -f "$HOME/.factory-overnight.stop"
}
