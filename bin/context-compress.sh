#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# context-compress.sh — Recursive head-tail chat history compression
# ═══════════════════════════════════════════════════════════════════════════════
# Pattern ported from Aider (Apache 2.0):
#   aider/history.py:ChatSummary → summarize / summarize_real / summarize_all
#
# Called between factory phases when token estimate exceeds threshold.
# Keeps recent messages verbatim (tail), summarizes older ones (head),
# recurses if combined result still over limit.
#
# Usage:
#   context-compress.sh estimate <file>              # estimate tokens in file
#   context-compress.sh compress <file> <max>        # compress to fit max tokens
#   context-compress.sh should-compress <file> <ctx-size>  # returns 0 if >70% full
#
# Config:
#   OCTOPUS_CONTEXT_COMPRESS_THRESHOLD (default 0.70) — trigger at this % full
#   OCTOPUS_CONTEXT_SPLIT_RATIO (default 0.50) — head/tail split point
#   OCTOPUS_WEAK_MODEL (set from preset) — model used for summarization
#
# Algorithm (Aider's):
#   1. Estimate tokens. If below threshold, return as-is.
#   2. Split at 50% token boundary → head (older) + tail (recent).
#   3. Summarize head via weak model.
#   4. Concatenate summary + tail.
#   5. If combined STILL over limit, recurse on the combined result.
#
# Token estimation: crude but portable — 1 token ≈ 4 chars for English prose,
# adjusted for code. Matches Aider's heuristic close enough for gating.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

THRESHOLD="${OCTOPUS_CONTEXT_COMPRESS_THRESHOLD:-0.70}"
SPLIT_RATIO="${OCTOPUS_CONTEXT_SPLIT_RATIO:-0.50}"
WEAK_MODEL="${OCTOPUS_WEAK_MODEL:-copilot-haiku}"

_estimate_tokens() {
    # Crude: total chars / 4, with 10% adjustment for code-heavy content
    local file="$1"
    local chars
    chars=$(wc -c < "$file" 2>/dev/null || echo 0)
    # Round up: +3 then integer divide by 4
    echo $(( (chars + 3) / 4 ))
}

cmd_estimate() {
    local file="${1:?usage: estimate <file>}"
    _estimate_tokens "$file"
}

cmd_should_compress() {
    local file="${1:?usage: should-compress <file> <ctx-size>}"
    local ctx_size="${2:?}"
    local est
    est=$(_estimate_tokens "$file")
    local trigger
    # bash doesn't do float; scale threshold * ctx_size via awk
    trigger=$(awk "BEGIN { printf \"%.0f\", ${ctx_size} * ${THRESHOLD} }")
    if (( est >= trigger )); then
        echo "yes (${est} tokens >= ${trigger} threshold)"
        return 0
    else
        echo "no (${est} tokens < ${trigger} threshold)"
        return 1
    fi
}

# Compress <file> so result fits in <max> tokens.
# Strategy: split file at ~50% token boundary (by line count proxy),
# summarize the head via dispatcher, keep the tail verbatim.
cmd_compress() {
    local file="${1:?usage: compress <file> <max-tokens>}"
    local max_tokens="${2:?}"

    local est
    est=$(_estimate_tokens "$file")
    if (( est <= max_tokens )); then
        cat "$file"
        return 0
    fi

    # Find the split line: target head = 50% of budget, rest is tail
    local total_lines
    total_lines=$(wc -l < "$file")
    local split_line
    split_line=$(awk "BEGIN { printf \"%.0f\", ${total_lines} * ${SPLIT_RATIO} }")

    local head_file tail_file summary_file
    head_file=$(mktemp)
    tail_file=$(mktemp)
    summary_file=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$head_file' '$tail_file' '$summary_file'" EXIT

    head -n "$split_line" "$file" > "$head_file"
    tail -n +"$((split_line + 1))" "$file" > "$tail_file"

    # Summarize head via weak model
    # This hits whichever provider OCTOPUS_WEAK_MODEL points to, via octo's dispatch
    {
        echo "Summarize the following conversation history into 3-5 bullet points covering:"
        echo "- intent (what the user/session was trying to accomplish)"
        echo "- changes_made (what the agent did)"
        echo "- decisions_taken (with rationale)"
        echo "- next_steps (open items when this chunk ended)"
        echo ""
        echo "Preserve exact file paths, error strings, and critical identifiers. Do not"
        echo "paraphrase numeric constants or command strings."
        echo ""
        echo "---"
        cat "$head_file"
    } | _dispatch_weak > "$summary_file"

    # Combine summary + tail verbatim
    {
        echo "# [factory/compressed-history] Older conversation summarized below:"
        echo "#"
        cat "$summary_file"
        echo ""
        echo "# [factory/compressed-history] Recent conversation (verbatim):"
        echo "#"
        cat "$tail_file"
    } > "${file}.compressed"

    # Recurse if still over budget
    local new_est
    new_est=$(_estimate_tokens "${file}.compressed")
    if (( new_est > max_tokens )); then
        cmd_compress "${file}.compressed" "$max_tokens"
    else
        cat "${file}.compressed"
    fi
    rm -f "${file}.compressed"
}

# Dispatch via octo's weak model
_dispatch_weak() {
    # Route through existing dispatch — assume the caller has OCTOPUS_WEAK_MODEL set
    case "$WEAK_MODEL" in
        copilot-haiku|copilot-sonnet|copilot-gpt5mini|copilot*)
            # Prefer fallback wrapper if installed, otherwise direct copilot
            if [[ -x "${HOME}/.claude-octopus/bin/copilot-fallback.sh" ]]; then
                local model="${WEAK_MODEL#copilot-}"
                case "$model" in
                    haiku)    model="claude-haiku-4.5" ;;
                    sonnet)   model="claude-sonnet-4.6" ;;
                    gpt5mini) model="gpt-5.4-mini" ;;
                esac
                "${HOME}/.claude-octopus/bin/copilot-fallback.sh" --no-ask-user --model "$model"
            else
                copilot --no-ask-user
            fi
            ;;
        codex:mini|codex:*)
            codex exec --skip-git-repo-check --full-auto --model gpt-5.4-mini --sandbox read-only -
            ;;
        gemini:flash|gemini:*)
            gemini -m gemini-2.5-flash -o text --approval-mode yolo -p "$(cat)"
            ;;
        claude|*)
            # Fall back to passing through cat — caller gets raw text when no model configured
            cat
            ;;
    esac
}

cmd_help() {
    sed -n '2,30p' "$0" | sed 's/^# \?//'
}

case "${1:-help}" in
    estimate)         shift; cmd_estimate "$@" ;;
    compress)         shift; cmd_compress "$@" ;;
    should-compress)  shift; cmd_should_compress "$@" ;;
    help|-h|--help)   cmd_help ;;
    *) echo "unknown command: $1" >&2; cmd_help; exit 1 ;;
esac
