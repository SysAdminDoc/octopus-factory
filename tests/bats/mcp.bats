#!/usr/bin/env bats
# Read-only MCP protocol and trajectory checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SERVER="$REPO_ROOT/bin/octopus-factory-mcp.sh"
    TMP_ROOT="$(mktemp -d)"
    export OCTOPUS_TRAJECTORY_ROOT="$TMP_ROOT/runs"
    export OCTOPUS_RUN_ID="mcp-test"
}

teardown() {
    if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
        rm -rf "$TMP_ROOT"
    fi
}

@test "mcp: negotiates stdio lifecycle and exposes only read-only tools" {
    run "$SERVER" <<'JSON'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"bats","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"prompts/list","params":{}}
JSON
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | jq -s -e '
        .[0].result.protocolVersion == "2025-06-18" and
        (.[1].result.tools | map(.name) | sort) == ["factory.list_resources", "factory.read_resource"] and
        (.[1].result.tools | all(.annotations.readOnlyHint == true and .annotations.destructiveHint == false and .annotations.openWorldHint == false)) and
        (.[2].result.prompts | length) > 0
    '
}

@test "mcp: reads an allowlisted prompt and logs the call to the trajectory ledger" {
    run "$SERVER" <<'JSON'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"bats","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"octopus-factory://prompts/factory-loop-prompts.txt"}}
{"jsonrpc":"2.0","id":3,"method":"prompts/get","params":{"name":"factory-loop-prompts.txt"}}
JSON
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | jq -s -e '
        (.[1].result.contents[0].uri == "octopus-factory://prompts/factory-loop-prompts.txt") and
        (.[1].result.contents[0].text | length) > 100 and
        (.[2].result.messages[0].content.text | length) > 100
    '
    [ -f "$OCTOPUS_TRAJECTORY_ROOT/mcp-test/trajectory.jsonl" ]
    run jq -s -e '[.[] | select(.event == "tool_command" and .actor == "mcp")] | length == 2' \
        "$OCTOPUS_TRAJECTORY_ROOT/mcp-test/trajectory.jsonl"
    [ "$status" -eq 0 ]
}

@test "mcp: rejects traversal and unknown write-capable tools" {
    run "$SERVER" <<'JSON'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"bats","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"octopus-factory://prompts/../README.md"}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"factory.execute","arguments":{"command":"touch injected"}}}
JSON
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | jq -s -e '
        .[1].error.code == -32602 and
        (.[1].error.message | test("allowlisted")) and
        .[2].error.code == -32602 and
        (.[2].error.message | test("write-capable"))
    '
    [ ! -e "$REPO_ROOT/injected" ]
}

@test "mcp: policy is explicit and read-only" {
    run jq -e '
        .schema_version == 1 and
        .read_only == true and
        (.allowed_roots | length) >= 5 and
        (.operations["tools/call"] == "read-only-tools") and
        (.forbidden_operations | index("execute")) != null and
        (.forbidden_operations | index("network")) != null
    ' "$REPO_ROOT/config/mcp-policy.json"
    [ "$status" -eq 0 ]

    local bad_policy="$TMP_ROOT/bad-policy.json"
    jq '.operations["factory.write"] = "write"' "$REPO_ROOT/config/mcp-policy.json" > "$bad_policy"
    run "$SERVER" --policy "$bad_policy" </dev/null
    [ "$status" -eq 2 ]
    [[ "$output" == *"write-capable operation"* ]]
}
