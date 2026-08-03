# octopus-factory — task runner
# Discoverable surface for bin/ scripts. `just` lists everything; recipes are
# thin wrappers that pass through args to the underlying scripts.
#
# Requires `just` (https://github.com/casey/just) — install via:
#   macOS:    brew install just
#   Linux:    apt install just  (or `cargo install just`)
#   Windows:  winget install Casey.Just  (or `scoop install just`)

set shell := ["bash", "-uc"]
set positional-arguments := true

# Recipes run from justfile_directory() by default — relative paths are safe and
# avoid Windows backslash mangling when the absolute path passes through bash -uc.
bin := "./bin"

# Default recipe — list everything grouped by purpose.
default:
    @just --list --unsorted

# ─── Preflight ────────────────────────────────────────────────────────────────

# Run the pre-flight diagnostic. Pass --quiet, --json, --route-only as needed.
[group('preflight')]
doctor *ARGS:
    @{{bin}}/factory-doctor.sh {{ARGS}}

# Multi-hour overnight run across one or more repos (--until, --status, --stop).
[group('preflight')]
overnight *ARGS:
    @{{bin}}/factory-overnight.sh {{ARGS}}

# Show or swap the active routing preset. `just route` lists; `just route copilot-heavy` swaps.
[group('preflight')]
route *ARGS:
    @{{bin}}/octo-route.sh {{ARGS}}

# One-step installer (idempotent).
[group('preflight')]
install:
    @{{bin}}/install.sh

# ─── Factory phases ───────────────────────────────────────────────────────────

# Dispatch a phase to direct Codex (gpt-5.4) — phase ∈ audit/counter/ux/theming/review/security/self-audit/custom.
[group('phases')]
codex PHASE *ARGS:
    @{{bin}}/codex-direct.sh {{PHASE}} {{ARGS}}

# Run secret scan via gitleaks on the working tree.
[group('phases')]
secret-scan *ARGS:
    @{{bin}}/secret-scan.sh {{ARGS}}

# Run the Q1 coding-agent safety gate (local contract by default; add --promptfoo for a provider scan).
[group('phases')]
redteam *ARGS:
    @{{bin}}/redteam-gate.sh run {{replace(ARGS, "\\", "/")}}

# Run the full coding-agent collection used by nightly/manual red-team runs.
[group('phases')]
redteam-nightly *ARGS:
    @{{bin}}/redteam-gate.sh run --profile all {{replace(ARGS, "\\", "/")}}

# Inspect GitHub Actions permissions, action pinning, egress, and Scorecard readiness.
[group('phases')]
ci-posture *ARGS:
    @{{bin}}/ci-posture.sh scan {{replace(ARGS, "\\", "/")}}

# Run CVE / dependency scan via osv-scanner.
[group('phases')]
dep-scan *ARGS:
    @{{bin}}/dep-scan.sh {{ARGS}}

# Compress conversation context (recursive head-tail summarization).
[group('phases')]
compress *ARGS:
    @{{bin}}/context-compress.sh {{ARGS}}

# Build an allowlisted local context pack and repository map.
[group('tools')]
context-pack *ARGS:
    @{{bin}}/context-pack.sh {{replace(ARGS, "\\", "/")}}

# Validate a JSON/YAML role result against config/roles/*.json.
[group('tools')]
validate-role-output *ARGS:
    @python3 {{bin}}/validate-role-output.py {{replace(ARGS, "\\", "/")}}

# ─── State / recovery ─────────────────────────────────────────────────────────

# Checkpoint operations (shadow-git): cp_init / cp_snapshot <phase> / cp_rollback <phase>.
[group('state')]
checkpoint *ARGS:
    @{{bin}}/checkpoint.sh {{ARGS}}

# SQLite state store: state_save / state_load / state_list_runs / state_resume.
[group('state')]
state *ARGS:
    @{{bin}}/state-store.sh {{ARGS}}

# Durable phase graph: validate, select next node, reserve/mark operations, explain nodes.
[group('state')]
graph *ARGS:
    @{{bin}}/factory-graph.sh {{ARGS}}

# Show or estimate run cost.
[group('state')]
cost *ARGS:
    @{{bin}}/cost-estimate.sh {{ARGS}}

# Emit an OpenTelemetry GenAI log line.
[group('state')]
log *ARGS:
    @{{bin}}/otel-log.sh {{ARGS}}

# Append, inspect, summarize, export, or plan a factory run trajectory.
[group('state')]
trajectory *ARGS:
    @{{bin}}/factory-trajectory.sh {{ARGS}}

# ─── Tools ────────────────────────────────────────────────────────────────────

# Lazy-load a directive into the current prompt context.
[group('tools')]
directive *ARGS:
    @{{bin}}/directive-loader.sh {{ARGS}}

# Cross-provider quota fallback handler (Copilot → Codex → Claude).
[group('tools')]
fallback *ARGS:
    @{{bin}}/copilot-fallback.sh {{ARGS}}

# Rewrite git history to remove AI-attribution. DESTRUCTIVE — see recipe docs.
[group('tools')]
ai-scrub *ARGS:
    @{{bin}}/ai-scrub.sh {{ARGS}}

# ─── Dev ──────────────────────────────────────────────────────────────────────

# Rebuild every routing preset from overlays/_base.json + overlays/<mode>.json.
[group('dev')]
preset-build *ARGS:
    @./config/presets/build.sh {{ARGS}}

# Verify committed presets match base+overlay sources (for pre-commit / CI).
[group('dev')]
preset-verify:
    @./config/presets/build.sh --verify

# Activate the repo-local git hooks (sets core.hooksPath = .githooks).
[group('dev')]
hooks-install:
    @git config core.hooksPath .githooks
    @echo "✓ core.hooksPath → .githooks"
    @ls .githooks | sed 's/^/  /'

# Deactivate the repo-local git hooks (resets core.hooksPath).
[group('dev')]
hooks-uninstall:
    @git config --unset core.hooksPath || true
    @echo "✓ core.hooksPath unset (back to .git/hooks)"

# Run promptfoo regression tests over the prompt suite.
[group('dev')]
test:
    cd tests/prompts && npx promptfoo eval

# Launch the prompt-builder GUI (PyQt6 helper for assembling factory prompts).
[group('tools')]
prompt-builder *ARGS:
    cd tools/prompt-builder && python -m prompt_builder {{ARGS}}

# Build the prompt-builder as a standalone executable via PyInstaller.
[group('dev')]
prompt-builder-build:
    #!/usr/bin/env bash
    set -euo pipefail
    cd tools/prompt-builder
    python -m pip install -r requirements.txt --quiet
    python -m PyInstaller prompt-builder.spec --clean --noconfirm
    echo "Built: tools/prompt-builder/dist/prompt-builder$( [ \"$OSTYPE\" = msys -o \"$OSTYPE\" = cygwin ] && echo .exe || true )"

# Run bats-core unit tests (syntax / preset / justfile smoke).
[group('dev')]
test-bats *ARGS:
    @bats tests/bats/ {{ARGS}}

# Run the deterministic local agent-evaluation contract harness.
[group('dev')]
eval-agent *ARGS:
    @{{bin}}/eval-agent.sh run {{replace(ARGS, "\\", "/")}}

# Run the provider-matrix harness. Supply --adapter for real provider calls.
[group('dev')]
eval-agent-nightly *ARGS:
    @{{bin}}/eval-agent.sh nightly {{replace(ARGS, "\\", "/")}}

# Run the deterministic fixture board across the configured routing presets.
[group('dev')]
benchmark *ARGS:
    @{{bin}}/benchmark-board.sh run {{replace(ARGS, "\\", "/")}}

# Run native checks without depending on just's shebang handling.
[group('dev')]
verify-native *ARGS:
    @{{bin}}/verify.sh native {{replace(ARGS, "\\", "/")}}

# Build and run the hermetic verification image with network disabled.
[group('dev')]
verify-container *ARGS:
    @{{bin}}/verify.sh container {{replace(ARGS, "\\", "/")}}

# Validate YAML frontmatter on every directive + recipe.
[group('dev')]
lint-directives *ARGS:
    @python3 bin/lint-directives.py {{ARGS}}

# Lint all bash scripts with shellcheck (skips if shellcheck not installed).
[group('dev')]
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "shellcheck not installed — skipping" >&2
        exit 0
    fi
    shellcheck {{bin}}/*.sh
    echo "✓ shellcheck clean"

# Print version + dependency status.
[group('dev')]
version:
    #!/usr/bin/env bash
    echo "octopus-factory"
    grep -m1 '^## v' CHANGELOG.md | sed 's/^## /  /'
    just --version | sed 's/^/  /'
    bash --version | head -1 | sed 's/^/  /'
    for cmd in claude codex copilot gemini gh git jq sqlite3; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "  ✓ $cmd"
        else
            echo "  ✗ $cmd (missing)"
        fi
    done
