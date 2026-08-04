#!/usr/bin/env bash
# prompt-builder-build.sh — build the native PyInstaller artifact.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/../tools/prompt-builder" && pwd)"
PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
TEMP_VENV=""

cleanup() {
    if [[ -n "$TEMP_VENV" && -d "$TEMP_VENV" ]]; then
        rm -rf "$TEMP_VENV"
    fi
}
trap cleanup EXIT

if [[ -z "$PYTHON_BIN" ]]; then
    echo "prompt-builder-build: Python 3 is required" >&2
    exit 1
fi
if [[ "${PYTHON_BIN,,}" == *windowsapps* ]]; then
    echo "prompt-builder-build: Python resolves to a WindowsApps launch shim: $PYTHON_BIN" >&2
    exit 1
fi

if ! "$PYTHON_BIN" -c 'import PyQt6, PyInstaller' >/dev/null 2>&1; then
    TEMP_VENV="$(mktemp -d)"
    "$PYTHON_BIN" -m venv "$TEMP_VENV"
    if [[ -x "$TEMP_VENV/bin/python" ]]; then
        PYTHON_BIN="$TEMP_VENV/bin/python"
    elif [[ -x "$TEMP_VENV/Scripts/python.exe" ]]; then
        PYTHON_BIN="$TEMP_VENV/Scripts/python.exe"
    else
        echo "prompt-builder-build: virtualenv Python executable was not created" >&2
        exit 1
    fi
    "$PYTHON_BIN" -m pip install --disable-pip-version-check --quiet -r "$PROJECT_DIR/requirements.txt"
fi

cd "$PROJECT_DIR"
"$PYTHON_BIN" -m PyInstaller prompt-builder.spec --clean --noconfirm

if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
    echo "Built: tools/prompt-builder/dist/prompt-builder.exe"
else
    echo "Built: tools/prompt-builder/dist/prompt-builder"
fi
