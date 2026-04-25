#!/usr/bin/env bats
# Bash-syntax sanity for every shell script in the repo.
# `bash -n` parses without executing — catches missing fi/done, unmatched
# quotes, etc. Doesn't catch logic errors, but does catch "I broke it
# while editing" failures before they reach a user.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "bin/*.sh: bash -n syntax check" {
    for f in "$REPO_ROOT"/bin/*.sh; do
        run bash -n "$f"
        [ "$status" -eq 0 ] || {
            echo "syntax error in $f:" >&2
            echo "$output" >&2
            return 1
        }
    done
}

@test "config/presets/build.sh: bash -n syntax check" {
    run bash -n "$REPO_ROOT/config/presets/build.sh"
    [ "$status" -eq 0 ]
}

@test ".githooks/pre-commit: bash -n syntax check" {
    run bash -n "$REPO_ROOT/.githooks/pre-commit"
    [ "$status" -eq 0 ]
}

@test "every shell script under bin/ is executable" {
    for f in "$REPO_ROOT"/bin/*.sh; do
        [ -x "$f" ] || {
            echo "not executable: $f" >&2
            return 1
        }
    done
}

@test ".githooks/pre-commit is executable" {
    [ -x "$REPO_ROOT/.githooks/pre-commit" ]
}

@test "config/presets/build.sh is executable" {
    [ -x "$REPO_ROOT/config/presets/build.sh" ]
}
