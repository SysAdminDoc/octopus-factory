#!/usr/bin/env bash
# verify.sh — native and hermetic verification lanes.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
IMAGE_TAG="${OCTOPUS_VERIFY_IMAGE:-octopus-factory-verify:local}"

usage() {
    sed -n '2,8p' "$0"
    cat >&2 <<'EOF'

Commands:
  native     Run the repository's deterministic checks on the current host.
  container  Build the verification image and run native checks with
             network disabled inside the container.
EOF
}

require_native_tools() {
    local missing=()
    local tool
    for tool in bash python3 git jq bats; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "verify: missing native tool(s): ${missing[*]}" >&2
        echo "verify: use just verify-container or the .devcontainer image" >&2
        return 2
    fi
}

run_native() {
    require_native_tools
    cd "$REPO_ROOT"
    echo "verify: bats"
    bats tests/bats/
    echo "verify: directive lint"
    python3 bin/lint-directives.py
    echo "verify: preset drift"
    bash config/presets/build.sh --verify
    echo "verify: prompt-builder Python compile"
    python3 -c 'import ast, pathlib; [ast.parse(path.read_text(encoding="utf-8"), filename=str(path)) for path in pathlib.Path("tools/prompt-builder/prompt_builder").glob("*.py")]'
    if command -v shellcheck >/dev/null 2>&1; then
        echo "verify: shellcheck"
        shellcheck bin/*.sh
    else
        echo "verify: shellcheck not installed on native host (container lane includes it)"
    fi
    echo "verify: native checks passed"
}

run_container() {
    command -v docker >/dev/null 2>&1 || {
        echo "verify: Docker CLI not found; install Docker or use just verify-native" >&2
        return 2
    }
    command -v python3 >/dev/null 2>&1 || {
        echo "verify: Python 3 is required to probe the Docker daemon" >&2
        return 2
    }
    if ! python3 -c 'import subprocess, sys; sys.exit(subprocess.run(["docker", "info"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15).returncode)' 2>/dev/null; then
        echo "verify: Docker daemon is unavailable; start Docker and retry just verify-container" >&2
        return 2
    fi
    echo "verify: building $IMAGE_TAG"
    docker build --pull --tag "$IMAGE_TAG" --file "$REPO_ROOT/.devcontainer/Dockerfile" "$REPO_ROOT"
    echo "verify: running $IMAGE_TAG with network disabled"
    docker run --rm --network none \
        --env OCTOPUS_CONTAINER_VERIFICATION=1 \
        --volume "$REPO_ROOT:/workspace" \
        --workdir /workspace \
        "$IMAGE_TAG" bash bin/verify.sh native
}

case "${1:-}" in
    native)
        shift
        run_native "$@"
        ;;
    container)
        shift
        run_container "$@"
        ;;
    -h|--help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
