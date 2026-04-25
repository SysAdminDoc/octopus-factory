#!/usr/bin/env bash
# codex-direct.sh — Dispatch a phase to direct ChatGPT Pro Codex via `codex exec`.
#
# Bypasses orchestrate.sh entirely. Lets the master Claude session shell out
# to Codex even when the orchestrator is unavailable (Windows quality-gate
# timing issue) or when the active preset routes "codex-named" phases to
# Copilot's GPT instead of the standalone Codex CLI.
#
# Usage:
#   codex-direct.sh <phase> [--model MODEL] [--cwd DIR] [--out FILE] < prompt
#   codex-direct.sh <phase> [--model MODEL] [--cwd DIR] [--out FILE] -p "prompt body"
#
# Phases (informational — drives the model default + log tag):
#   audit       L3 audit pass (default model: gpt-5.4)
#   counter     L4 counter-audit pass (rare — usually Claude does this)
#   ux          U1 UX polish first pass
#   theming     T1 theming first pass
#   review      Final code review (e.g. /octo:review)
#   security    Adversarial security pass (e.g. /octo:security)
#   self-audit  Roadmap research Phase 5 (cross-family review)
#   custom      User-supplied phase tag — must pass --model
#
# Environment overrides:
#   OCTOPUS_CODEX_MODEL         override model for this call
#   OCTOPUS_CODEX_SANDBOX       sandbox mode (default: read-only — audit phases
#                               never need writes; only override with care)
#   OCTOPUS_CODEX_LOG_DIR       where to drop transcripts
#                               (default: ~/.claude-octopus/logs/codex-direct)
#   OCTOPUS_CODEX_TIMEOUT       per-call timeout in seconds (default: 600)
#
# Exit codes:
#   0   success — final message written to the output file
#   2   auth missing / expired
#   3   quota / rate limit hit
#   4   timeout
#   5   model rejected the prompt (refusal / safety)
#   6   internal codex error
#   1   bad arguments

set -uo pipefail

PHASE=""
MODEL_OVERRIDE=""
CWD=""
OUT_FILE=""
PROMPT_ARG=""

require_value() {
    local opt="$1"
    local value="${2:-}"
    if [[ -z "$value" || "$value" == --* ]]; then
        echo "codex-direct: $opt requires a value" >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        audit|counter|ux|theming|review|security|self-audit|custom)
            PHASE="$1"; shift ;;
        --model)
            require_value "$1" "${2:-}"; MODEL_OVERRIDE="$2"; shift 2 ;;
        --cwd)
            require_value "$1" "${2:-}"; CWD="$2"; shift 2 ;;
        --out)
            require_value "$1" "${2:-}"; OUT_FILE="$2"; shift 2 ;;
        -p|--prompt)
            require_value "$1" "${2:-}"; PROMPT_ARG="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,30p' "$0"
            exit 0 ;;
        *)
            echo "codex-direct: unknown argument: $1" >&2
            exit 1 ;;
    esac
done

if [[ -z "$PHASE" ]]; then
    echo "codex-direct: phase required (audit|counter|ux|theming|review|security|self-audit|custom)" >&2
    exit 1
fi

# --- Phase → default model selection ---
case "$PHASE" in
    audit|counter|review|security|self-audit) DEFAULT_MODEL="gpt-5.4" ;;
    ux|theming)                               DEFAULT_MODEL="gpt-5.4" ;;
    custom)                                   DEFAULT_MODEL="" ;;
esac

MODEL="${OCTOPUS_CODEX_MODEL:-${MODEL_OVERRIDE:-$DEFAULT_MODEL}}"
if [[ -z "$MODEL" ]]; then
    echo "codex-direct: phase=custom requires --model or OCTOPUS_CODEX_MODEL" >&2
    exit 1
fi

SANDBOX="${OCTOPUS_CODEX_SANDBOX:-read-only}"
TIMEOUT_SEC="${OCTOPUS_CODEX_TIMEOUT:-600}"
LOG_DIR="${OCTOPUS_CODEX_LOG_DIR:-$HOME/.claude-octopus/logs/codex-direct}"
mkdir -p "$LOG_DIR"

ts() { date -u +%Y%m%dT%H%M%SZ; }
TIMESTAMP="$(ts)"
RUN_ID="codex-${PHASE}-${TIMESTAMP}-$$"
TRANSCRIPT="$LOG_DIR/${RUN_ID}.jsonl"
LAST_MSG="${OUT_FILE:-$LOG_DIR/${RUN_ID}.last.md}"

# --- Pre-flight ---
if ! command -v codex &>/dev/null; then
    echo "codex-direct: codex CLI not on PATH" >&2
    exit 2
fi

if [[ ! -s "$HOME/.codex/auth.json" ]]; then
    echo "codex-direct: ~/.codex/auth.json missing or empty — run 'codex login'" >&2
    exit 2
fi

# Quick auth probe — confirm the access token isn't dead. `codex` will refresh
# automatically if it can; if it can't, it'll print to stderr and exit non-zero
# before we waste the user's time on the real prompt.
if ! codex --version &>/dev/null; then
    echo "codex-direct: codex --version failed — CLI broken or unauthenticated" >&2
    exit 2
fi

# --- Resolve CWD ---
WORKDIR="${CWD:-$PWD}"
if [[ ! -d "$WORKDIR" ]]; then
    echo "codex-direct: --cwd '$WORKDIR' does not exist" >&2
    exit 1
fi

# --- Build invocation ---
ARGS=(
    exec
    --model "$MODEL"
    --sandbox "$SANDBOX"
    --skip-git-repo-check
    --json
    --output-last-message "$LAST_MSG"
    --color never
    -C "$WORKDIR"
)

# --- Run with timeout, capturing JSONL transcript ---
echo "codex-direct: phase=$PHASE model=$MODEL sandbox=$SANDBOX cwd=$WORKDIR" >&2
echo "codex-direct: transcript=$TRANSCRIPT" >&2
echo "codex-direct: last-message=$LAST_MSG" >&2

invoke() {
    if [[ -n "$PROMPT_ARG" ]]; then
        codex "${ARGS[@]}" "$PROMPT_ARG"
    else
        codex "${ARGS[@]}"
    fi
}

# Use `timeout` if available (GNU coreutils — git-bash on Windows ships it)
if command -v timeout &>/dev/null; then
    if [[ -n "$PROMPT_ARG" ]]; then
        timeout --signal=TERM "${TIMEOUT_SEC}s" \
            codex "${ARGS[@]}" "$PROMPT_ARG" > "$TRANSCRIPT" 2>&1
    else
        timeout --signal=TERM "${TIMEOUT_SEC}s" \
            codex "${ARGS[@]}" > "$TRANSCRIPT" 2>&1
    fi
    RC=$?
else
    invoke > "$TRANSCRIPT" 2>&1
    RC=$?
fi

# --- Classify exit ---
case "$RC" in
    0) ;;
    124|137)
        echo "codex-direct: TIMEOUT after ${TIMEOUT_SEC}s — partial transcript at $TRANSCRIPT" >&2
        exit 4 ;;
    *)
        if grep -q -i 'rate.limit\|quota.exceeded\|insufficient_quota\|billing_hard_limit_reached' "$TRANSCRIPT" 2>/dev/null; then
            echo "codex-direct: QUOTA hit — transcript $TRANSCRIPT" >&2
            exit 3
        fi
        if grep -q -i 'unauthor\|invalid.token\|expired.token\|please.run.codex.login' "$TRANSCRIPT" 2>/dev/null; then
            echo "codex-direct: AUTH expired — run 'codex login' — transcript $TRANSCRIPT" >&2
            exit 2
        fi
        if grep -q -i "i can'\?t\|i cannot\|refus" "$TRANSCRIPT" 2>/dev/null; then
            echo "codex-direct: model REFUSAL — transcript $TRANSCRIPT" >&2
            exit 5
        fi
        echo "codex-direct: codex exec failed rc=$RC — transcript $TRANSCRIPT" >&2
        exit 6 ;;
esac

# --- Verify last-message file landed ---
if [[ ! -s "$LAST_MSG" ]]; then
    echo "codex-direct: empty last-message file — codex returned no final answer" >&2
    echo "codex-direct: transcript $TRANSCRIPT" >&2
    exit 6
fi

echo "codex-direct: OK — last message at $LAST_MSG" >&2
echo "$LAST_MSG"
exit 0
