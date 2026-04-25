#!/usr/bin/env bats
# factory-doctor machine-readable output checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/factory-doctor.sh"
    PYTHON_BIN="$(command -v python3 || command -v python || true)"
    if [[ -z "$PYTHON_BIN" ]]; then
        skip "python not installed"
    fi
}

@test "factory-doctor: --json remains valid without jq and exits on hard failures" {
    local tmp
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/.claude-octopus/config"
    cat > "$tmp/.claude-octopus/config/providers.json" <<'JSON'
{
  "_mode": "balanced",
  "routing": {
    "phases": {},
    "roles": {}
  }
}
JSON

    run --separate-stderr env HOME="$tmp" PATH="/usr/bin:/bin" bash "$SCRIPT" --json
    [ "$status" -eq 1 ]
    [[ "$stderr" != *"jq:"* ]]
    [[ "$stderr" != *"command not found"* ]]

    printf '%s' "$output" | "$PYTHON_BIN" -c '
import json
import sys

data = json.load(sys.stdin)
assert data["active_preset"] == "balanced"
assert data["status"] == "broken"
assert data["exit_code"] == 1
assert data["warnings"], data
assert data["failures"], data
'

    rm -rf "$tmp"
}
