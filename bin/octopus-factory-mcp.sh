#!/usr/bin/env bash
# octopus-factory-mcp.sh — launch the read-only stdio MCP server.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
if [[ -z "$PYTHON_BIN" ]]; then
    echo "octopus-factory-mcp: Python 3 is required; install the pinned mise toolchain or run just verify-container" >&2
    exit 1
fi
if [[ "${PYTHON_BIN,,}" == *windowsapps* ]]; then
    echo "octopus-factory-mcp: Python resolves to a WindowsApps launch shim: $PYTHON_BIN" >&2
    exit 1
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/octopus-factory-mcp.py" "$@"
