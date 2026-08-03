#!/usr/bin/env bash
# ci-posture.sh — GitHub Actions supply-chain posture inspection.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python)"
else
    echo "ci-posture: Python 3 is required" >&2
    exit 2
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/ci-posture.py" "$@"
