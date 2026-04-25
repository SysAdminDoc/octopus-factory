#!/usr/bin/env bats
# Bash-syntax sanity for every shell script in the repo.
# `bash -n` parses without executing — catches missing fi/done, unmatched
# quotes, etc. Doesn't catch logic errors, but does catch "I broke it
# while editing" failures before they reach a user.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "bin/*.sh: bash -n syntax check" {
    local local_bash_major
    local_bash_major="${BASH_VERSINFO[0]:-0}"
    for f in "$REPO_ROOT"/bin/*.sh; do
        # Honor the in-file skip marker so scripts can declare a minimum bash
        # version. Format: a line containing `bats-skip-syntax-check: requires-bash-N`
        # in the first 100 lines opts the file out when local bash < N.
        local required_major
        required_major="$(grep -m1 -oE 'bats-skip-syntax-check: requires-bash-[0-9]+' "$f" \
            | grep -oE '[0-9]+$' || true)"
        if [[ -n "$required_major" && "$local_bash_major" -lt "$required_major" ]]; then
            echo "skip $(basename "$f"): requires bash $required_major+ (have $local_bash_major)" >&3
            continue
        fi
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
