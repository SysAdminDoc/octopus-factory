#!/usr/bin/env bats
# GitHub Actions supply-chain posture checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/ci-posture.sh"
}

make_repo() {
    local path="$1"
    mkdir -p "$path"
    git -C "$path" init -q
    git -C "$path" config user.email test@example.invalid
    git -C "$path" config user.name ci-posture-test
    printf 'fixture\n' > "$path/fixture.txt"
    git -C "$path" add fixture.txt
    git -C "$path" commit -q -m 'test: initialize fixture'
}

@test "ci posture: repositories without workflows are not applicable" {
    local tmp
    tmp="$(mktemp -d)"
    make_repo "$tmp/repo"

    run bash "$SCRIPT" scan "$tmp/repo" --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '.status == "not-applicable" and .workflow_count == 0'
    rm -rf "$tmp"
}

@test "ci posture: pinned scorecard workflow passes" {
    local tmp
    tmp="$(mktemp -d)"
    make_repo "$tmp/repo"
    mkdir -p "$tmp/repo/.github/workflows"
    cat > "$tmp/repo/.github/workflows/secure.yml" <<'YAML'
name: secure
on: [workflow_dispatch]
permissions:
  contents: read
jobs:
  check:
    permissions:
      contents: read
    runs-on: ubuntu-latest
    steps:
      - uses: step-security/harden-runner@ec9f2d5744a09debf3a187a3f4f675c53b671911
        with:
          egress-policy: audit
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - uses: ossf/scorecard-action@ff5dd8929f96a8a4dc67d13f32b8c75057829621
        with:
          results_format: sarif
YAML

    run bash "$SCRIPT" scan "$tmp/repo" --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '.status == "pass" and (.findings | length) == 0'
    rm -rf "$tmp"
}

@test "ci posture: unpinned and unrestricted workflows fail" {
    local tmp
    tmp="$(mktemp -d)"
    make_repo "$tmp/repo"
    mkdir -p "$tmp/repo/.github/workflows"
    cat > "$tmp/repo/.github/workflows/insecure.yml" <<'YAML'
name: insecure
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: curl https://example.invalid/install.sh | bash
YAML

    run bash "$SCRIPT" scan "$tmp/repo" --json
    [ "$status" -eq 1 ]
    printf '%s' "$output" | jq -e '
      .status == "fail" and
      any(.findings[]; .id == "permissions" and .status == "fail") and
      any(.findings[]; .id == "pinned-action" and .status == "fail")'
    rm -rf "$tmp"
}
