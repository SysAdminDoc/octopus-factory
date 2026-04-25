#!/usr/bin/env bats
# Routing-preset structural + drift checks.
# Catches: malformed JSON, missing required schema fields, generated artifact
# drifted from base+overlay source.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    PRESETS_DIR="$REPO_ROOT/config/presets"
}

@test "every preset is valid JSON" {
    for f in "$PRESETS_DIR"/*.json; do
        run jq empty "$f"
        [ "$status" -eq 0 ] || {
            echo "invalid JSON: $f" >&2
            echo "$output" >&2
            return 1
        }
    done
}

@test "every overlay is valid JSON" {
    for f in "$PRESETS_DIR"/overlays/*.json; do
        run jq empty "$f"
        [ "$status" -eq 0 ]
    done
}

@test "every preset has required top-level fields" {
    # _mode, _description, version, providers, routing, tiers
    for f in "$PRESETS_DIR"/*.json; do
        run jq -e '. | (._mode and ._description and .version and .providers and .routing and .tiers)' "$f"
        [ "$status" -eq 0 ] || {
            echo "missing required fields in $(basename "$f"):" >&2
            jq -r 'keys | join(", ")' "$f" >&2
            return 1
        }
    done
}

@test "every preset has routing.phases and routing.roles" {
    for f in "$PRESETS_DIR"/*.json; do
        run jq -e '.routing | (.phases and .roles)' "$f"
        [ "$status" -eq 0 ]
    done
}

@test "every preset has providers.codex.default and providers.gemini.default" {
    for f in "$PRESETS_DIR"/*.json; do
        run jq -e '.providers | (.codex.default and .gemini.default)' "$f"
        [ "$status" -eq 0 ]
    done
}

@test "_mode field matches filename" {
    for f in "$PRESETS_DIR"/*.json; do
        local expected actual
        expected="$(basename "$f" .json)"
        actual="$(jq -r '._mode' "$f")"
        [ "$expected" = "$actual" ] || {
            echo "filename '$expected' does not match _mode '$actual'" >&2
            return 1
        }
    done
}

@test "build.sh --verify reports clean (no drift between source and committed)" {
    run "$PRESETS_DIR/build.sh" --verify
    [ "$status" -eq 0 ] || {
        echo "$output" >&2
        return 1
    }
}

@test "build.sh idempotent: rebuild then verify still clean" {
    run "$PRESETS_DIR/build.sh"
    [ "$status" -eq 0 ]
    run "$PRESETS_DIR/build.sh" --verify
    [ "$status" -eq 0 ]
}
