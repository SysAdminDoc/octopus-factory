#!/usr/bin/env bash
# factory-graph.sh — validate and operate the durable phase graph.
#
# Usage:
#   factory-graph.sh validate [graph.json]
#   factory-graph.sh next [state.json] [--json]
#   factory-graph.sh mark <state.json> <node> <status> [options]
#   factory-graph.sh explain <node> [--json]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
if [[ -z "$PYTHON_BIN" ]]; then
    echo "factory-graph: Python 3 is required; install the pinned mise toolchain or run just verify-container" >&2
    exit 1
fi
if [[ "${PYTHON_BIN,,}" == *windowsapps* ]]; then
    echo "factory-graph: Python resolves to a WindowsApps launch shim: $PYTHON_BIN" >&2
    echo "factory-graph: install the pinned mise toolchain or run just verify-container" >&2
    exit 1
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/factory-graph.py" "$@"
