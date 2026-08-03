#!/usr/bin/env bash
# redteam-gate.sh — deterministic Q1 agent-safety gate with optional Promptfoo.
#
# Usage:
#   redteam-gate.sh run [<repo>] [--profile core|all] [--json]
#   redteam-gate.sh run [<repo>] --promptfoo
#   redteam-gate.sh run [<repo>] --waive "ticket or operator rationale"
#
# Reports always live at <repo>/.factory/runs/<run_id>/redteam/report.{json,html}.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python)"
else
    echo "redteam-gate: Python 3 is required" >&2
    exit 2
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/redteam-gate.py" "$@"
