#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# checkpoint.sh — Shadow-git snapshots for stop-on-regression rollback
# ═══════════════════════════════════════════════════════════════════════════════
# Pattern ported from cline/cline (Apache 2.0):
#   src/integrations/checkpoints/CheckpointGitOperations.ts
#   src/integrations/checkpoints/CheckpointTracker.ts
#
# Snapshots never touch user history. Uses a separate `.git` directory with
# `core.worktree=<user_repo>` so the user's main `.git` is untouched.
#
# Usage:
#   checkpoint.sh init                          # initialize shadow repo for CWD
#   checkpoint.sh snapshot <phase> [<iter>]     # commit current worktree to shadow
#   checkpoint.sh diff <phase> [<iter>]         # show diff vs a snapshot
#   checkpoint.sh rollback <phase> [<iter>]     # restore worktree to snapshot
#   checkpoint.sh list                          # list all snapshots
#   checkpoint.sh gc [<days>]                   # prune snapshots older than N days
#
# Shadow location: <repo>/.factory/shadow-git/  (per-repo, in .gitignore)
# Commit message:  factory-${run_id}-${phase}-${iter}
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || { echo "not a git repo" >&2; exit 1; }
}

REPO="$(_repo_root)"
SHADOW_DIR="${REPO}/.factory/shadow-git"
SHADOW_GIT_ENV=(--git-dir="${SHADOW_DIR}" --work-tree="${REPO}")
RUN_ID="${OCTOPUS_RUN_ID:-factory-$(date +%s)}"

_ensure_shadow() {
    if [[ ! -d "$SHADOW_DIR" ]]; then
        echo "shadow-git not initialized; run: checkpoint.sh init" >&2
        return 1
    fi
}

# Rename nested .git directories to .git_disabled before `git add`
# (ported detail from Cline: avoids submodule errors when shadow scans subdirs)
_disable_nested_gits() {
    # shellcheck disable=SC2044
    while IFS= read -r -d '' gitdir; do
        # Skip the shadow itself and the user's top-level .git
        [[ "$gitdir" == "${SHADOW_DIR}" ]] && continue
        [[ "$gitdir" == "${REPO}/.git" ]] && continue
        mv "$gitdir" "${gitdir}_disabled"
    done < <(find "$REPO" -maxdepth 4 -name '.git' -type d -print0 2>/dev/null)
}

_restore_nested_gits() {
    # shellcheck disable=SC2044
    while IFS= read -r -d '' disabled; do
        mv "$disabled" "${disabled%_disabled}"
    done < <(find "$REPO" -maxdepth 4 -name '.git_disabled' -type d -print0 2>/dev/null)
}

cmd_init() {
    mkdir -p "$(dirname "$SHADOW_DIR")"
    if [[ -d "$SHADOW_DIR" ]]; then
        echo "already initialized: $SHADOW_DIR"
        return 0
    fi

    # Initialize bare git dir pointing worktree at the user repo
    # (--bare puts HEAD/refs directly in SHADOW_DIR instead of SHADOW_DIR/.git)
    git init --quiet --bare "${SHADOW_DIR}"
    git "${SHADOW_GIT_ENV[@]}" config core.worktree "$REPO"
    git "${SHADOW_GIT_ENV[@]}" config user.email "factory@octopus-factory.local"
    git "${SHADOW_GIT_ENV[@]}" config user.name "octopus-factory"
    git "${SHADOW_GIT_ENV[@]}" config commit.gpgsign false
    git "${SHADOW_GIT_ENV[@]}" config gc.auto 0

    # Use the user repo's .gitignore by default — shadow respects their patterns
    echo "shadow-git/" > "${SHADOW_DIR}/info/exclude" 2>/dev/null || true

    # Add the shadow dir to the user's gitignore if the project is tracked
    if [[ -f "${REPO}/.gitignore" ]] && ! grep -q "^\.factory/" "${REPO}/.gitignore"; then
        echo ".factory/" >> "${REPO}/.gitignore"
        echo "added .factory/ to user .gitignore"
    fi

    echo "initialized: $SHADOW_DIR"
}

cmd_snapshot() {
    local phase="${1:?usage: snapshot <phase> [<iter>]}"
    local iter="${2:-0}"
    _ensure_shadow

    _disable_nested_gits
    # shellcheck disable=SC2064
    trap "_restore_nested_gits" EXIT INT TERM

    git "${SHADOW_GIT_ENV[@]}" add -A 2>/dev/null
    local msg="factory-${RUN_ID}-${phase}-${iter}"
    if git "${SHADOW_GIT_ENV[@]}" commit --quiet --allow-empty -m "$msg" 2>/dev/null; then
        local sha
        sha=$(git "${SHADOW_GIT_ENV[@]}" rev-parse --short HEAD)
        echo "snapshot: ${msg} (${sha})"
    fi
}

cmd_diff() {
    local phase="${1:?usage: diff <phase> [<iter>]}"
    local iter="${2:-0}"
    _ensure_shadow
    local msg_pattern="factory-.*-${phase}-${iter}"
    local sha
    sha=$(git "${SHADOW_GIT_ENV[@]}" log --grep="$msg_pattern" --format='%H' -1)
    if [[ -z "$sha" ]]; then
        echo "no snapshot matching ${phase}/${iter}" >&2
        return 1
    fi
    git "${SHADOW_GIT_ENV[@]}" diff "$sha" -- .
}

cmd_rollback() {
    local phase="${1:?usage: rollback <phase> [<iter>]}"
    local iter="${2:-0}"
    _ensure_shadow
    local msg_pattern="factory-.*-${phase}-${iter}"
    local sha
    sha=$(git "${SHADOW_GIT_ENV[@]}" log --grep="$msg_pattern" --format='%H' -1)
    if [[ -z "$sha" ]]; then
        echo "no snapshot matching ${phase}/${iter}" >&2
        return 1
    fi

    _disable_nested_gits
    # shellcheck disable=SC2064
    trap "_restore_nested_gits" EXIT INT TERM

    # Restore worktree to the snapshot's tree state (no ref update on user's main git)
    git "${SHADOW_GIT_ENV[@]}" checkout "$sha" -- .
    echo "rolled back worktree to ${phase}/${iter} (${sha:0:7})"
}

cmd_list() {
    _ensure_shadow
    git "${SHADOW_GIT_ENV[@]}" log --format='%h  %ai  %s' 2>/dev/null | head -50
}

cmd_gc() {
    local days="${1:-30}"
    _ensure_shadow
    local cutoff
    cutoff=$(date -d "${days} days ago" +%s 2>/dev/null || date -v-"${days}d" +%s 2>/dev/null || echo 0)
    git "${SHADOW_GIT_ENV[@]}" gc --prune="${days}.days.ago" --aggressive --quiet
    echo "gc: pruned snapshots older than ${days} days"
}

cmd_help() {
    sed -n '2,25p' "$0" | sed 's/^# \?//'
}

case "${1:-help}" in
    init)     shift; cmd_init "$@" ;;
    snapshot) shift; cmd_snapshot "$@" ;;
    diff)     shift; cmd_diff "$@" ;;
    rollback) shift; cmd_rollback "$@" ;;
    list)     shift; cmd_list "$@" ;;
    gc)       shift; cmd_gc "$@" ;;
    help|-h|--help) cmd_help ;;
    *) echo "unknown command: $1" >&2; cmd_help; exit 1 ;;
esac
