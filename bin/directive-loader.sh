#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# directive-loader.sh — Keyword-matched lazy loader for directives
# ═══════════════════════════════════════════════════════════════════════════════
# Pattern adapted from OpenHands microagents:
#   https://docs.openhands.dev/usage/prompting/microagents-overview
#
# Each directive declares its activation criteria via YAML frontmatter:
#   ---
#   name: directive-foo
#   type: knowledge
#   triggers: [keyword1, keyword2, ...]
#   agents: [role1, role2, ...]
#   ---
#
# Loader scans a prompt / phase name, matches triggers, returns paths to
# relevant directive files. Replaces recipes' hardcoded "load directive-X.md"
# with a data-driven dispatch.
#
# Usage:
#   directive-loader.sh match <prompt-text>              # print matching directive paths
#   directive-loader.sh match-agent <role> <prompt>      # match + filter by agent role
#   directive-loader.sh list                             # list all registered directives
#   directive-loader.sh register <path>                  # add a directive dir to search
#
# Directive search paths (in order):
#   1. $OCTOPUS_DIRECTIVES_DIR env var
#   2. ./memory/directives/ (relative to cwd — repo-local overrides)
#   3. ~/.claude/projects/*/memory/directives/ (project-installed)
#   4. Installed octopus-factory memory/directives/ (system default)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

_search_paths() {
    local paths=()
    [[ -n "${OCTOPUS_DIRECTIVES_DIR:-}" ]] && paths+=("${OCTOPUS_DIRECTIVES_DIR}")
    [[ -d "./memory/directives" ]] && paths+=("./memory/directives")
    # Claude Code project memory dirs — glob safely
    for d in "${HOME}"/.claude/projects/*/memory/directives; do
        [[ -d "$d" ]] && paths+=("$d")
    done
    # Installed octopus-factory
    [[ -d "${HOME}/octopus-factory/memory/directives" ]] && paths+=("${HOME}/octopus-factory/memory/directives")
    [[ -d "${HOME}/repos/octopus-factory/memory/directives" ]] && paths+=("${HOME}/repos/octopus-factory/memory/directives")
    printf '%s\n' "${paths[@]}"
}

# Extract a YAML list field from frontmatter. Returns comma-separated values.
# Handles both inline [a, b] and multi-line - a / - b formats.
_extract_field() {
    local file="$1"
    local field="$2"
    awk -v f="$field" '
        /^---[[:space:]]*$/ { if (in_fm) exit; in_fm=1; next }
        !in_fm { next }
        $0 ~ "^" f ":" {
            # Strip "field:" prefix
            sub("^" f ":[[:space:]]*", "")
            # Inline array form: [a, b, c]
            if (/^\[/) {
                gsub(/^\[|\][[:space:]]*$/, "")
                gsub(/[[:space:]]*,[[:space:]]*/, ",")
                print
            } else if (/^-/) {
                # Multi-line (not handling here for simplicity)
            } else {
                print
            }
            exit
        }
    ' "$file"
}

# Build an index of all directives found, with their triggers
_build_index() {
    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        for file in "$dir"/directive-*.md; do
            [[ -f "$file" ]] || continue
            local name triggers agents
            name=$(_extract_field "$file" "name")
            triggers=$(_extract_field "$file" "triggers")
            agents=$(_extract_field "$file" "agents")
            [[ -z "$name" ]] && name=$(basename "$file" .md)
            # Tab-separated: path <tab> name <tab> triggers <tab> agents
            printf '%s\t%s\t%s\t%s\n' "$file" "$name" "$triggers" "$agents"
        done
    done < <(_search_paths)
}

cmd_list() {
    _build_index | while IFS=$'\t' read -r path name triggers agents; do
        echo "  ${name}"
        echo "    path:     ${path}"
        echo "    triggers: ${triggers}"
        echo "    agents:   ${agents}"
        echo ""
    done
}

cmd_match() {
    local prompt="${1:?usage: match <prompt-text>}"
    local prompt_lc
    prompt_lc=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    _build_index | while IFS=$'\t' read -r path name triggers agents; do
        [[ -z "$triggers" ]] && continue
        # Test each trigger keyword against the prompt
        local matched=false
        IFS=',' read -ra trig_arr <<< "$triggers"
        for t in "${trig_arr[@]}"; do
            t=$(echo "$t" | tr -d '"' | xargs)   # strip quotes + whitespace
            t=$(echo "$t" | tr '[:upper:]' '[:lower:]')
            [[ -z "$t" ]] && continue
            if [[ "$prompt_lc" == *"$t"* ]]; then
                matched=true
                break
            fi
        done
        [[ "$matched" == "true" ]] && echo "$path"
    done
}

cmd_match_agent() {
    local role="${1:?usage: match-agent <role> <prompt>}"
    local prompt="${2:?}"

    cmd_match "$prompt" | while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        local agents
        agents=$(_extract_field "$path" "agents")
        [[ -z "$agents" ]] && continue
        # Trigger match + agent match
        local role_lc
        role_lc=$(echo "$role" | tr '[:upper:]' '[:lower:]')
        local agents_lc
        agents_lc=$(echo "$agents" | tr '[:upper:]' '[:lower:]')
        if [[ "$agents_lc" == *"$role_lc"* ]]; then
            echo "$path"
        fi
    done
}

cmd_help() {
    sed -n '2,30p' "$0" | sed 's/^# \?//'
}

case "${1:-help}" in
    list)         shift; cmd_list "$@" ;;
    match)        shift; cmd_match "$@" ;;
    match-agent)  shift; cmd_match_agent "$@" ;;
    help|-h|--help) cmd_help ;;
    *) echo "unknown command: $1" >&2; cmd_help; exit 1 ;;
esac
