#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# apply.sh — Apply octopus-factory patches to the Claude Octopus plugin
# ═══════════════════════════════════════════════════════════════════════════════
# Idempotent: detects already-patched files and skips.
# Backs up originals as .bak.<date>.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Locate octo plugin ───────────────────────────────────────────────────
OCTO_BASE="${HOME}/.claude/plugins/cache/nyldn-plugins/octo"
if [[ ! -d "$OCTO_BASE" ]]; then
    echo "ERROR: Claude Octopus plugin not found at $OCTO_BASE" >&2
    echo "Install via Claude Code first: /plugin install octo@nyldn-plugins" >&2
    exit 1
fi

# Pick the latest installed version
OCTO_VERSION=$(ls "$OCTO_BASE" | sort -V | tail -1)
PLUGIN_DIR="${OCTO_BASE}/${OCTO_VERSION}"
LIB_DIR="${PLUGIN_DIR}/scripts/lib"

if [[ ! -d "$LIB_DIR" ]]; then
    echo "ERROR: lib/ directory not found at $LIB_DIR" >&2
    exit 1
fi

DATE_TAG=$(date +%Y%m%d)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  octopus-factory patch applier"
echo "  octo version: ${OCTO_VERSION}"
echo "  target lib:   ${LIB_DIR}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

applied=0
skipped=0

# ─── Patch 1: dispatch.sh ────────────────────────────────────────────────
echo ""
echo "[1/2] dispatch.sh — per-role Copilot model selection"

DISPATCH="${LIB_DIR}/dispatch.sh"

if grep -q "copilot-sonnet)" "$DISPATCH" 2>/dev/null; then
    echo "  • already patched — skipping"
    skipped=$((skipped + 1))
else
    cp "$DISPATCH" "${DISPATCH}.bak.${DATE_TAG}"
    echo "  ✓ backup: ${DISPATCH}.bak.${DATE_TAG}"

    # Use python for the multi-line replace (sed cross-platform pain)
    python - "$DISPATCH" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    content = f.read()

old = '''        copilot|copilot-research)  # v9.9.0: GitHub Copilot CLI \xe2\x80\x94 copilot -p (Issue #198)
            echo "copilot --no-ask-user"
            ;;'''.decode('utf-8') if hasattr(b'', 'decode') else '''        copilot|copilot-research)  # v9.9.0: GitHub Copilot CLI \u2014 copilot -p (Issue #198)
            echo "copilot --no-ask-user"
            ;;'''

new = '''        copilot|copilot-research|copilot-sonnet|copilot-haiku|copilot-opus|copilot-gpt5|copilot-codex|copilot-gpt5mini)
            # v9.9.0: GitHub Copilot CLI \u2014 copilot -p (Issue #198)
            # octopus-factory patch: per-role model selection.
            local _copilot_model=""
            case "$agent_type" in
                copilot-sonnet)    _copilot_model="claude-sonnet-4.6" ;;
                copilot-haiku)     _copilot_model="claude-haiku-4.5" ;;
                copilot-opus)      _copilot_model="claude-opus-4.7" ;;
                copilot-gpt5)      _copilot_model="gpt-5.4" ;;
                copilot-codex)     _copilot_model="gpt-5.3-codex" ;;
                copilot-gpt5mini)  _copilot_model="gpt-5.4-mini" ;;
            esac
            if [[ -n "${OCTOPUS_COPILOT_MODEL_OVERRIDE:-}" ]]; then
                _copilot_model="${OCTOPUS_COPILOT_MODEL_OVERRIDE}"
            fi
            local _copilot_cmd="copilot"
            if [[ -x "${HOME}/.claude-octopus/bin/copilot-fallback.sh" ]]; then
                _copilot_cmd="${HOME}/.claude-octopus/bin/copilot-fallback.sh"
            fi
            if [[ -n "$_copilot_model" ]]; then
                echo "${_copilot_cmd} --no-ask-user --model ${_copilot_model}"
            else
                echo "${_copilot_cmd} --no-ask-user"
            fi
            ;;'''

if old not in content:
    print("  ERROR: original block not found in dispatch.sh", file=sys.stderr)
    print("  This usually means octo version drift. See patches/dispatch-copilot-models.md for manual application.", file=sys.stderr)
    sys.exit(2)

content = content.replace(old, new)
with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("  \u2713 patched")
PYEOF
    applied=$((applied + 1))
fi

# ─── Patch 2: provider-routing.sh ────────────────────────────────────────
echo ""
echo "[2/2] provider-routing.sh — Copilot fallback chain"

ROUTING="${LIB_DIR}/provider-routing.sh"

if grep -q "copilot|copilot-\*)" "$ROUTING" 2>/dev/null; then
    echo "  • already patched — skipping"
    skipped=$((skipped + 1))
else
    cp "$ROUTING" "${ROUTING}.bak.${DATE_TAG}"
    echo "  ✓ backup: ${ROUTING}.bak.${DATE_TAG}"

    python - "$ROUTING" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    content = f.read()

old = '''        claude-sonnet|claude*)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "gemini"; then
                echo "gemini"
            else
                echo "$locked_provider"
            fi
            ;;
        *)
            echo "$locked_provider"
            ;;
    esac
}'''

new = '''        claude-sonnet|claude*)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "gemini"; then
                echo "gemini"
            else
                echo "$locked_provider"
            fi
            ;;
        copilot|copilot-*)
            # octopus-factory patch: Copilot fallback chain.
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "claude-sonnet"; then
                echo "claude-sonnet"
            elif ! is_provider_locked "gemini"; then
                echo "gemini"
            else
                echo "$locked_provider"
            fi
            ;;
        *)
            echo "$locked_provider"
            ;;
    esac
}'''

if old not in content:
    print("  ERROR: original block not found in provider-routing.sh", file=sys.stderr)
    print("  This usually means octo version drift. See patches/provider-routing-copilot-fallback.md for manual application.", file=sys.stderr)
    sys.exit(2)

content = content.replace(old, new)
with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("  \u2713 patched")
PYEOF
    applied=$((applied + 1))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done. Applied: ${applied}. Skipped (already patched): ${skipped}."
echo ""
echo "  Verify:"
echo "    bash -c 'source ${LIB_DIR}/dispatch.sh && get_agent_command copilot-sonnet'"
echo "    bash -c 'source ${LIB_DIR}/provider-routing.sh && get_alternate_provider copilot'"
echo ""
echo "  Rollback (if needed):"
echo "    cp ${LIB_DIR}/dispatch.sh.bak.${DATE_TAG} ${LIB_DIR}/dispatch.sh"
echo "    cp ${LIB_DIR}/provider-routing.sh.bak.${DATE_TAG} ${LIB_DIR}/provider-routing.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
