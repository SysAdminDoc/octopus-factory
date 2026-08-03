#!/usr/bin/env bash
# benchmark-board.sh — run the deterministic public benchmark board.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
if [[ -z "$PYTHON_BIN" ]]; then
    echo "benchmark-board: Python 3 is required; install the pinned mise toolchain or run just verify-container" >&2
    exit 1
fi
if [[ "${PYTHON_BIN,,}" == *windowsapps* ]]; then
    echo "benchmark-board: Python resolves to a WindowsApps launch shim: $PYTHON_BIN" >&2
    exit 1
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/benchmark-board.py" "$@"
