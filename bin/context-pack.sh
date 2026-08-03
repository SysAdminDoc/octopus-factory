#!/usr/bin/env bash
# context-pack.sh — deterministic, local-only repository map and context pack.
#
# Usage: context-pack.sh <repo> [--output-dir <repo>/.factory/context] [--json]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
if [[ -z "$PYTHON_BIN" ]]; then
    echo "context-pack: Python 3 is required; install the pinned mise toolchain or run just verify-container" >&2
    exit 1
fi
if [[ "${PYTHON_BIN,,}" == *windowsapps* ]]; then
    echo "context-pack: Python resolves to a WindowsApps launch shim: $PYTHON_BIN" >&2
    echo "context-pack: install the pinned mise toolchain or run just verify-container" >&2
    exit 1
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/context-pack.py" "$@"
