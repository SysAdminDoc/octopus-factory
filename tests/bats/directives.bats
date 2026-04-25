#!/usr/bin/env bats
# Directive + recipe frontmatter validation. Wraps bin/lint-directives.py
# so the existing test runner covers it.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LINT="$REPO_ROOT/bin/lint-directives.py"
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not installed"
    fi
}

@test "lint-directives: every committed directive + recipe passes" {
    run python3 "$LINT"
    [ "$status" -eq 0 ] || {
        echo "$output" >&2
        return 1
    }
}

@test "lint-directives: --help exits 0" {
    run python3 "$LINT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Schema"* ]]
}

@test "lint-directives: rejects file with no frontmatter fence" {
    local tmp
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/directives"
    printf 'no fence here\n' > "$tmp/directives/bad.md"
    run python3 "$LINT" "$tmp/directives"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must begin with"* ]]
    rm -rf "$tmp"
}

@test "lint-directives: rejects directive missing required type field" {
    local tmp
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/directives"
    cat > "$tmp/directives/bad.md" <<'EOF'
---
name: Bad
description: missing type
triggers: [a]
agents: [b]
---
EOF
    run python3 "$LINT" "$tmp/directives"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing required field 'type'"* ]]
    rm -rf "$tmp"
}

@test "lint-directives: rejects type with invalid enum value" {
    local tmp
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/directives"
    cat > "$tmp/directives/bad.md" <<'EOF'
---
name: Bad
description: wrong type enum
type: blueprint
triggers: [a]
agents: [b]
---
EOF
    run python3 "$LINT" "$tmp/directives"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be one of"* ]]
    rm -rf "$tmp"
}

@test "lint-directives: rejects directive with empty triggers list" {
    local tmp
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/directives"
    cat > "$tmp/directives/bad.md" <<'EOF'
---
name: Bad
description: triggers must be non-empty
type: knowledge
triggers: []
agents: [b]
---
EOF
    run python3 "$LINT" "$tmp/directives"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be a non-empty list"* ]]
    rm -rf "$tmp"
}

@test "lint-directives: recipes don't require triggers/agents" {
    local tmp
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/recipes"
    cat > "$tmp/recipes/test.md" <<'EOF'
---
name: Test Recipe
description: recipes only need name/description/type
type: reference
---
EOF
    run python3 "$LINT" "$tmp/recipes"
    [ "$status" -eq 0 ]
    rm -rf "$tmp"
}
