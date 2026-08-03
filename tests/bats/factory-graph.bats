#!/usr/bin/env bats
# Durable graph and operation-journal contract checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/factory-graph.sh"
    GRAPH="$REPO_ROOT/config/workflows/factory.graph.json"
}

@test "factory-graph: validates the phase contract and explains approval nodes" {
    run bash "$SCRIPT" validate "$GRAPH" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "valid"'* ]]
    [[ "$output" == *'"nodes": 18'* ]]

    run bash "$SCRIPT" explain ai_scrub
    [ "$status" -eq 0 ]
    [[ "$output" == *"history-rewrite"* ]]
    [[ "$output" == *"force-push"* ]]
}

@test "factory-graph: reserves operations before advancing and remains idempotent" {
    local tmp state
    tmp="$(mktemp -d)"
    state="$tmp/workflow-state.json"

    run env OCTOPUS_RUN_ID=graph-test bash "$SCRIPT" mark "$state" preflight running --operation-id preflight-op
    [ "$status" -eq 0 ]
    [[ "$output" == *"marked preflight running"* ]]

    run env OCTOPUS_RUN_ID=graph-test bash "$SCRIPT" mark "$state" preflight running --operation-id preflight-op
    [ "$status" -eq 0 ]
    [[ "$output" == *"idempotent"* ]]

    run bash "$SCRIPT" mark "$state" preflight succeeded --operation-id preflight-op
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" next "$state" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"next": "wip_adoption"'* ]]

    run bash "$SCRIPT" mark "$state" wip_adoption running --side-effect create-branch
    [ "$status" -eq 0 ]
    [[ "$output" == *"create-branch"* ]]
    run bash "$SCRIPT" mark "$state" wip_adoption running --side-effect create-branch
    [ "$status" -eq 0 ]
    [[ "$output" == *"idempotent"* ]]

    rm -rf "$tmp"
}

@test "factory-graph: destructive operations stop for explicit approval" {
    local tmp state
    tmp="$(mktemp -d)"
    state="$tmp/workflow-state.json"

    run bash "$SCRIPT" mark "$state" preflight succeeded --operation-id preflight-op
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" mark "$state" wip_adoption succeeded --operation-id wip-op
    [ "$status" -eq 0 ]

    run bash "$SCRIPT" mark "$state" ai_scrub running --operation-id scrub-op
    [ "$status" -eq 3 ]
    [[ "$output" == *"history-rewrite"* ]]
    [[ "$output" == *"force-push"* ]]

    run bash "$SCRIPT" mark "$state" ai_scrub running --operation-id scrub-op \
        --approve history-rewrite --approve force-push
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" mark "$state" ai_scrub succeeded --operation-id scrub-op
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" next "$state"
    [ "$status" -eq 0 ]
    [[ "$output" == *"next: research"* ]]

    rm -rf "$tmp"
}
