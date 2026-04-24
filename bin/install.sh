#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# install.sh — One-step installer for octopus-factory
# ═══════════════════════════════════════════════════════════════════════════════
# Run from anywhere; resolves its own location.
# Idempotent: safe to re-run.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─── Detect target directories ────────────────────────────────────────────
OCTOPUS_BIN="${HOME}/.claude-octopus/bin"
OCTOPUS_CONFIG="${HOME}/.claude-octopus/config"
OCTOPUS_PRESETS="${OCTOPUS_CONFIG}/presets"
OCTOPUS_WORKFLOWS="${OCTOPUS_CONFIG}/workflows"
PROMPTS_DIR="${HOME}/repos/ai-prompts"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  octopus-factory installer"
echo "  source: ${REPO_ROOT}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── Step 1: prereq check ─────────────────────────────────────────────────
echo ""
echo "[1/6] Prereq check"

missing=()
for cmd in git bash python jq; do
    if ! command -v "$cmd" &>/dev/null; then
        missing+=("$cmd")
    fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "  ✗ missing required commands: ${missing[*]}" >&2
    echo "    install them first; aborting." >&2
    exit 1
fi
echo "  ✓ git, bash, python, jq present"

# Optional commands — warn but don't block
for cmd in git-filter-repo cloc syft cosign; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "  ⚠ optional command missing: $cmd"
        case "$cmd" in
            git-filter-repo) echo "      install: pip install --user git-filter-repo" ;;
            cloc)            echo "      install: brew install cloc OR apt install cloc" ;;
            syft)            echo "      install: see https://github.com/anchore/syft" ;;
            cosign)          echo "      install: see https://github.com/sigstore/cosign" ;;
        esac
    fi
done

# Octopus plugin
if [[ ! -d "${HOME}/.claude/plugins/cache/nyldn-plugins/octo" ]]; then
    echo "  ⚠ Claude Octopus plugin not detected at expected path."
    echo "    Install it via Claude Code: /plugin install octo@nyldn-plugins"
    echo "    (continuing — recipes still install, but octo-specific scripts won't dispatch)"
fi

# ─── Step 2: scripts ──────────────────────────────────────────────────────
echo ""
echo "[2/6] Installing scripts to ${OCTOPUS_BIN}"
mkdir -p "${OCTOPUS_BIN}"
for script in "${REPO_ROOT}/bin"/*.sh; do
    [[ "$(basename "$script")" == "install.sh" ]] && continue
    cp "$script" "${OCTOPUS_BIN}/"
    chmod +x "${OCTOPUS_BIN}/$(basename "$script")"
    echo "  ✓ $(basename "$script")"
done

# ─── Step 3: presets + workflows ──────────────────────────────────────────
echo ""
echo "[3/6] Installing config to ${OCTOPUS_CONFIG}"
mkdir -p "${OCTOPUS_PRESETS}" "${OCTOPUS_WORKFLOWS}"
cp "${REPO_ROOT}/config/presets/"*.json "${OCTOPUS_PRESETS}/"
echo "  ✓ $(ls "${OCTOPUS_PRESETS}" | wc -l | tr -d ' ') presets"
cp "${REPO_ROOT}/config/workflows/"*.yaml "${OCTOPUS_WORKFLOWS}/"
echo "  ✓ $(ls "${OCTOPUS_WORKFLOWS}" | wc -l | tr -d ' ') workflow YAMLs"

# Set initial active config (don't overwrite existing)
if [[ ! -f "${OCTOPUS_CONFIG}/providers.json" ]]; then
    cp "${OCTOPUS_PRESETS}/balanced.json" "${OCTOPUS_CONFIG}/providers.json"
    echo "  ✓ providers.json initialized to 'balanced' preset"
else
    echo "  • providers.json already exists — leaving alone (use octo-route.sh to swap)"
fi

# ─── Step 4: prompts ──────────────────────────────────────────────────────
echo ""
echo "[4/6] Installing prompts to ${PROMPTS_DIR}"
mkdir -p "${PROMPTS_DIR}"
cp "${REPO_ROOT}/prompts/"*.txt "${PROMPTS_DIR}/"
echo "  ✓ $(ls "${PROMPTS_DIR}" | wc -l | tr -d ' ') prompts"

# ─── Step 5: memory ───────────────────────────────────────────────────────
echo ""
echo "[5/6] Memory files (recipes / directives / reference)"
echo "  Memory files live in your Claude Code project's memory directory,"
echo "  which is project-specific. Copy manually:"
echo ""
echo "    cp -r ${REPO_ROOT}/memory/recipes/* <your-claude-memory-dir>/"
echo "    cp -r ${REPO_ROOT}/memory/directives/* <your-claude-memory-dir>/"
echo "    cp -r ${REPO_ROOT}/memory/reference/* <your-claude-memory-dir>/"
echo ""
echo "  Default Claude Code memory paths:"
echo "    macOS / Linux: ~/.claude/projects/<project-id>/memory/"
echo "    Windows:       %USERPROFILE%\\.claude\\projects\\<project-id>\\memory\\"

# ─── Step 6: optional patches ─────────────────────────────────────────────
echo ""
echo "[6/6] Optional plugin patches"
echo "  octopus-factory includes optional patches to octo's dispatch.sh and"
echo "  provider-routing.sh that enable per-role Copilot model selection and"
echo "  cross-provider fallback chains."
echo ""
echo "  Apply with:"
echo "    bash ${REPO_ROOT}/patches/apply.sh"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Install complete."
echo ""
echo "  Verify: ${OCTOPUS_BIN}/octo-route.sh status"
echo "  Read:   ${REPO_ROOT}/README.md  (usage)"
echo "          ${REPO_ROOT}/docs/ARCHITECTURE.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
