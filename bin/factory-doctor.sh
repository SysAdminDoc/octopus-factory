#!/usr/bin/env bash
# factory-doctor.sh — pre-run diagnostic for the factory loop.
#
# Verifies:
#   1. CLI installed + authed for each provider (claude / codex / copilot / gemini)
#   2. orchestrate.sh reachable + executable
#   3. providers.json present + valid JSON + names a known preset
#   4. Active preset's routing actually invokes the binaries you care about
#   5. ImageMagick + git + gh CLI present (release-build prerequisites)
#   6. ~/.claude-octopus/config/providers.json matches one of the shipped presets
#
# Output is plain English diagnostics. Exit 0 if everything's wired; exit 1 if
# any HARD problem (missing CLI, broken auth, bad JSON); exit 2 if SOFT warnings
# only (preset doesn't fire one of the binaries you might expect).
#
# Usage:
#   factory-doctor.sh                 # full report
#   factory-doctor.sh --quiet         # only print problems (suppress OK lines)
#   factory-doctor.sh --json          # machine-readable
#   factory-doctor.sh --route-only    # just show what each phase routes to
#
# Run this BEFORE invoking the factory on a long run so you don't spend
# 30 minutes wondering why Codex never fires.

set -uo pipefail

QUIET=false
JSON=false
ROUTE_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --quiet|-q) QUIET=true ;;
        --json) JSON=true ;;
        --route-only) ROUTE_ONLY=true ;;
        -h|--help)
            sed -n '2,18p' "$0"
            exit 0 ;;
        *)
            echo "factory-doctor: unknown arg: $arg" >&2
            exit 1 ;;
    esac
done

HARD_FAILURES=()
SOFT_WARNINGS=()
OK_LINES=()

ok()    { OK_LINES+=("[OK]    $1"); }
warn()  { SOFT_WARNINGS+=("[WARN]  $1"); }
fail()  { HARD_FAILURES+=("[FAIL]  $1"); }

PROVIDERS_JSON="${HOME}/.claude-octopus/config/providers.json"
ORCH_SH="${HOME}/.claude/plugins/cache/nyldn-plugins/octo/9.23.0/scripts/orchestrate.sh"

# ---------- Section 1: providers.json ----------
if [[ ! -f "$PROVIDERS_JSON" ]]; then
    fail "providers.json missing at $PROVIDERS_JSON — run octo:doctor or copy a preset from config/presets/"
    ACTIVE_MODE="<missing>"
elif ! command -v jq &>/dev/null; then
    warn "jq not on PATH — falling back to grep-based parsing (less reliable)"
    ACTIVE_MODE=$(grep -oE '"_mode"[[:space:]]*:[[:space:]]*"[^"]+"' "$PROVIDERS_JSON" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
elif ! jq empty "$PROVIDERS_JSON" 2>/dev/null; then
    fail "providers.json exists but is not valid JSON"
    ACTIVE_MODE="<invalid>"
else
    ACTIVE_MODE=$(jq -r '._mode // "<unknown>"' "$PROVIDERS_JSON")
    ok "providers.json valid; active preset: $ACTIVE_MODE"
fi

# ---------- Section 2: CLI availability + auth ----------

# claude
if command -v claude &>/dev/null; then
    ok "claude CLI present ($(claude --version 2>&1 | head -1))"
else
    warn "claude CLI not on PATH — master-session mode still works inside Claude Code, but headless dispatch won't"
fi

# codex
if command -v codex &>/dev/null; then
    CODEX_VER=$(codex --version 2>&1 | head -1)
    ok "codex CLI present ($CODEX_VER)"
    if [[ -s "${HOME}/.codex/auth.json" ]]; then
        # Look for active token + plan tier
        if grep -q '"plan"[[:space:]]*:[[:space:]]*"pro"\|chatgpt_plan_type":"pro' "${HOME}/.codex/auth.json" 2>/dev/null; then
            ok "codex authed (ChatGPT Pro plan detected)"
        elif grep -q '"plan"[[:space:]]*:[[:space:]]*"plus"\|chatgpt_plan_type":"plus' "${HOME}/.codex/auth.json" 2>/dev/null; then
            warn "codex authed on ChatGPT Plus — gpt-5 / gpt-5-codex models gated to Pro tier"
        else
            ok "codex auth.json present (plan tier not detected — token still valid?)"
        fi
        if grep -q '"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"sk-' "${HOME}/.codex/auth.json" 2>/dev/null; then
            ok "OPENAI_API_KEY present in auth.json (gpt-image-1 path available)"
        else
            warn "no OPENAI_API_KEY in auth.json — Path 2 of directive-logo.md unreachable"
        fi
    else
        fail "codex CLI installed but ~/.codex/auth.json missing or empty — run 'codex login'"
    fi
else
    fail "codex CLI not on PATH — install via 'npm i -g @openai/codex' or 'brew install codex'"
fi

# copilot
if command -v copilot &>/dev/null; then
    ok "copilot CLI present ($(copilot --version 2>&1 | head -1))"
    # Probing copilot auth headlessly is unreliable — accept its presence
    if [[ -d "${HOME}/.copilot" || -d "${APPDATA:-}/Copilot" || -d "${HOME}/Library/Application Support/copilot" ]]; then
        ok "copilot config directory present"
    else
        warn "copilot config dir not detected — may not be authed (run 'copilot auth login')"
    fi
else
    warn "copilot CLI not on PATH — copilot-heavy preset will fail every dispatch"
fi

# gemini
if command -v gemini &>/dev/null; then
    ok "gemini CLI present ($(gemini --version 2>&1 | head -1))"
else
    warn "gemini CLI not on PATH — research breadth phase will be skipped"
fi

# ---------- Section 3: orchestrator ----------
if [[ -x "$ORCH_SH" ]]; then
    ok "orchestrate.sh present + executable at $ORCH_SH"
    # Don't actually invoke --help here; it can be slow on Windows
else
    warn "orchestrate.sh missing or not executable — recipe falls back to single-session mode"
fi

# ---------- Section 4: build prerequisites ----------
if command -v magick &>/dev/null; then
    ok "ImageMagick present ($(magick -version 2>&1 | head -1 | cut -c1-60))"
else
    warn "ImageMagick (magick) not on PATH — G-phase logo rasterization will halt"
fi

if command -v git &>/dev/null; then
    ok "git present ($(git --version))"
else
    fail "git not on PATH"
fi

if command -v gh &>/dev/null; then
    ok "gh CLI present ($(gh --version | head -1))"
else
    warn "gh CLI not on PATH — Q3 release phase can't create GitHub releases"
fi

# ---------- Section 5: routing analysis ----------
ROUTING_REPORT=""
if [[ -f "$PROVIDERS_JSON" ]] && command -v jq &>/dev/null; then
    ROUTING_REPORT=$(jq -r '
        .routing.phases | to_entries | .[] |
        "  \(.key)  →  \(.value)"
    ' "$PROVIDERS_JSON" 2>/dev/null)

    # Audit-specific routing — what fires for L3 / L4 / review / security / ux / theming?
    # "codex:..." (e.g. codex:default) means standalone codex CLI.
    # "copilot-codex" means Copilot CLI's GPT-5.3-Codex backend.
    # We care specifically about audit-related routing, not image/logo.
    AUDIT_TARGETS=$(jq -r '
        .routing.phases as $p |
        $p.review, $p.security, $p.ux, $p.theming
    ' "$PROVIDERS_JSON" 2>/dev/null | sort -u | paste -sd ',' -)

    AUDIT_USES_DIRECT_CODEX=$(echo "$AUDIT_TARGETS" | grep -cE '(^|,)codex:' || true)
    AUDIT_USES_COPILOT_CODEX=$(echo "$AUDIT_TARGETS" | grep -c 'copilot-codex' || true)

    if [[ "$AUDIT_USES_DIRECT_CODEX" -gt 0 ]]; then
        ok "audit phases (review/security/ux/theming) route to direct codex CLI"
    elif [[ "$AUDIT_USES_COPILOT_CODEX" -gt 0 ]]; then
        warn "audit phases route to copilot-codex (Copilot's GPT-5.3-Codex), NOT the standalone codex CLI"
        warn "  → if you expect to see 'codex exec' invocations in your terminal during audit, you won't"
        warn "  → fixes:"
        warn "       octo-route.sh balanced       # routes review/security to direct codex"
        warn "       octo-route.sh codex-heavy    # all audit phases via direct codex"
        warn "       --final-codex-pass flag      # adds direct-codex pass on the final iteration only"
        warn "  → ALTERNATIVELY (v0.5.1+): single-session L3 audit now invokes bin/codex-direct.sh,"
        warn "    which shells out to direct codex regardless of preset routing."
    else
        warn "audit phases route to NEITHER direct codex NOR copilot-codex — Codex never fires"
    fi

    # Image / logo path (separate concern from audit routing)
    IMAGE_TARGET=$(jq -r '.routing.roles.image // "<unset>"' "$PROVIDERS_JSON" 2>/dev/null)
    case "$IMAGE_TARGET" in
        codex:image) ok "logo P5 / G-phase falls back to gpt-image-1 if Path 1 fails (image=$IMAGE_TARGET)" ;;
        gemini:image) ok "logo path uses Gemini image directly (image=$IMAGE_TARGET)" ;;
        copilot-svg) ok "logo path uses Copilot-SVG (no API billing — image=$IMAGE_TARGET)" ;;
        *) warn "logo image role = '$IMAGE_TARGET' — verify directive-logo.md routing matches" ;;
    esac

    # Surface what claude direct vs copilot-* routes look like
    DIRECT_CLAUDE=$(jq -r '
        .routing | [.phases, .roles] | map(values // [] | tostring) |
        map(select(test("\"claude\""))) | length
    ' "$PROVIDERS_JSON" 2>/dev/null)
    if [[ "$DIRECT_CLAUDE" == "0" ]]; then
        ok "preset never routes direct to Claude — Max quota only used on escalation (correct for copilot-heavy)"
    else
        ok "preset routes $DIRECT_CLAUDE phase(s) directly to Claude — Max quota will be consumed"
    fi
fi

# ---------- Output ----------
if $JSON; then
    {
        printf '{\n'
        printf '  "active_preset": "%s",\n' "$ACTIVE_MODE"
        printf '  "ok": [\n'
        printf '%s\n' "${OK_LINES[@]}" | jq -R . | paste -sd ',' -
        printf '  ],\n'
        printf '  "warnings": [\n'
        printf '%s\n' "${SOFT_WARNINGS[@]}" | jq -R . | paste -sd ',' -
        printf '  ],\n'
        printf '  "failures": [\n'
        printf '%s\n' "${HARD_FAILURES[@]}" | jq -R . | paste -sd ',' -
        printf '  ]\n}\n'
    }
elif $ROUTE_ONLY; then
    echo "Active preset: $ACTIVE_MODE"
    echo "Phase routing:"
    echo "$ROUTING_REPORT"
else
    echo "=== octopus-factory doctor ==="
    echo "Active preset: $ACTIVE_MODE"
    echo ""

    if ! $QUIET; then
        for line in "${OK_LINES[@]}"; do echo "$line"; done
        echo ""
    fi

    if [[ ${#SOFT_WARNINGS[@]} -gt 0 ]]; then
        echo "Warnings (factory will run, but with caveats):"
        for line in "${SOFT_WARNINGS[@]}"; do echo "$line"; done
        echo ""
    fi

    if [[ ${#HARD_FAILURES[@]} -gt 0 ]]; then
        echo "Failures (fix before invoking the factory):"
        for line in "${HARD_FAILURES[@]}"; do echo "$line"; done
        echo ""
    fi

    if [[ -n "$ROUTING_REPORT" ]]; then
        echo "Phase routing under '$ACTIVE_MODE' preset:"
        echo "$ROUTING_REPORT"
        echo ""
    fi

    echo "=== summary ==="
    if [[ ${#HARD_FAILURES[@]} -gt 0 ]]; then
        echo "STATUS: BROKEN — ${#HARD_FAILURES[@]} hard failure(s); fix before invoking the factory."
        exit 1
    elif [[ ${#SOFT_WARNINGS[@]} -gt 0 ]]; then
        echo "STATUS: OK with ${#SOFT_WARNINGS[@]} warning(s) — factory will run; review warnings if you expected something to fire that won't."
        exit 2
    else
        echo "STATUS: OK — every CLI authed, preset routing looks sane."
        exit 0
    fi
fi
