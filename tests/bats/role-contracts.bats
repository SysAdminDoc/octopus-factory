#!/usr/bin/env bats
# Role contract, output validation, and fallback-envelope checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    VALIDATOR="$REPO_ROOT/bin/validate-role-output.py"
    FALLBACK="$REPO_ROOT/bin/copilot-fallback.sh"
    PYTHON_BIN="$(command -v python3 || command -v python || true)"
    if [[ -z "$PYTHON_BIN" ]]; then
        skip "python not installed"
    fi
    TMP_ROOT="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMP_ROOT"
}

@test "role contracts: all definitions validate" {
    run "$PYTHON_BIN" "$VALIDATOR" --validate-contracts --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "pass"'* ]]
}

@test "role contracts: JSON output enforces handoff and artifact evidence" {
    cat > "$TMP_ROOT/result.json" <<'JSON'
{
  "role": "implementer",
  "contract_version": 1,
  "status": "pass",
  "summary": "Implemented the bounded task.",
  "task": {"id": "T-1", "goal": "Make the behavior correct."},
  "artifacts": [{"path": "src/app.py", "kind": "source"}],
  "tests": [{"name": "unit", "status": "pass", "evidence": "pytest: 3 passed"}],
  "findings": [],
  "handoff": {
    "next_role": "critic",
    "task_id": "T-1",
    "required_artifacts": ["src/app.py"],
    "output_schema_ref": "config/roles/critic.json",
    "forbidden_side_effects": ["force_push", "release_publish"]
  }
}
JSON

    run "$PYTHON_BIN" "$VALIDATOR" implementer "$TMP_ROOT/result.json" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "pass"'* ]]

    printf '%s\n' '{"role":"implementer","contract_version":1,"status":"pass","summary":"missing handoff"}' \
        > "$TMP_ROOT/invalid.json"
    run "$PYTHON_BIN" "$VALIDATOR" implementer "$TMP_ROOT/invalid.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"handoff"* ]]
}

@test "role contracts: YAML output uses the same strict schema" {
    if ! "$PYTHON_BIN" -c 'import yaml' >/dev/null 2>&1; then
        skip "PyYAML not installed"
    fi
    cat > "$TMP_ROOT/result.yaml" <<'YAML'
role: critic
contract_version: 1
status: pass
summary: Reviewed the implementation with evidence.
task:
  id: T-2
  goal: Find regressions.
artifacts:
  - path: reports/critic.json
    kind: report
tests:
  - name: regression suite
    status: pass
    evidence: "bats: 10 passed"
findings: []
handoff:
  next_role: defender
  task_id: T-2
  required_artifacts:
    - reports/critic.json
  output_schema_ref: config/roles/defender.json
  forbidden_side_effects:
    - edit_source
YAML
    run "$PYTHON_BIN" "$VALIDATOR" critic "$TMP_ROOT/result.yaml" --format yaml
    [ "$status" -eq 0 ]
    [[ "$output" == *"valid"* ]]
}

@test "role contracts: quota fallback replays the exact contract envelope" {
    local fakebin input copilot_capture codex_capture
    fakebin="$TMP_ROOT/fake-bin"
    input="$TMP_ROOT/input.txt"
    copilot_capture="$TMP_ROOT/copilot.prompt"
    codex_capture="$TMP_ROOT/codex.prompt"
    mkdir -p "$fakebin"
    printf '%s\n' 'cat > "$OCTO_COPILOT_CAPTURE"; echo quota exceeded >&2; exit 1' \
        > "$fakebin/copilot"
    printf '%s\n' 'cat > "$OCTO_CODEX_CAPTURE"; echo fallback-ok; exit 0' \
        > "$fakebin/codex"
    chmod +x "$fakebin/copilot" "$fakebin/codex"
    printf '%s\n' 'TASK-ID=T-3; preserve this structured task exactly.' > "$input"

    run env HOME="$TMP_ROOT" PATH="$fakebin:/usr/bin:/bin" \
        OCTO_COPILOT_CAPTURE="$copilot_capture" OCTO_CODEX_CAPTURE="$codex_capture" \
        OCTOPUS_ROLE=implementer OCTOPUS_TRAJECTORY_DISABLED=1 \
        bash "$FALLBACK" --no-ask-user --model copilot-sonnet < "$input"
    [ "$status" -eq 0 ]
    [ -s "$copilot_capture" ]
    [ -s "$codex_capture" ]
    cmp -s "$copilot_capture" "$codex_capture"
    run grep -F "TASK-ID=T-3" "$codex_capture"
    [ "$status" -eq 0 ]
    run grep -F "config/roles/implementer.json" "$codex_capture"
    [ "$status" -eq 0 ]
}
