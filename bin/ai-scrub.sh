#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# ai-scrub.sh — Remove AI-attribution references from git history
# ═══════════════════════════════════════════════════════════════════════════════
# Usage:
#   ai-scrub.sh <repo-path> [--dry-run]                 # default: dry-run (safe)
#   ai-scrub.sh <repo-path> --apply                     # rewrites history locally
#   ai-scrub.sh <repo-path> --apply --include-files     # also purges AI-context files
#   ai-scrub.sh <repo-path> --apply --push              # apply + force-push to origin
#
# Recipe: ~/.claude/projects/c--Users----repos/memory/recipe-ai-scrub.md
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Parse args ────────────────────────────────────────────────────────────
REPO=""
MODE="dry-run"
INCLUDE_FILES=0
PUSH=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) MODE="dry-run"; shift ;;
        --apply) MODE="apply"; shift ;;
        --include-files) INCLUDE_FILES=1; shift ;;
        --push) PUSH=1; shift ;;
        -h|--help)
            sed -n '2,15p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        -*) echo "unknown flag: $1" >&2; exit 1 ;;
        *) REPO="$1"; shift ;;
    esac
done

if [[ -z "$REPO" ]]; then
    echo "usage: ai-scrub.sh <repo-path> [--dry-run|--apply] [--include-files] [--push]" >&2
    exit 1
fi

REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "repo not found: $REPO" >&2; exit 1; }
[[ -d "$REPO/.git" ]] || { echo "not a git repo: $REPO" >&2; exit 1; }

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPO_NAME="$(basename "$REPO")"
BACKUP_DIR="$HOME/repos/backups"
mkdir -p "$BACKUP_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AI-Reference Scrub"
echo "  repo:   $REPO"
echo "  mode:   $MODE"
echo "  files:  $([ "$INCLUDE_FILES" == "1" ] && echo "purge AI-context files" || echo "messages only")"
echo "  push:   $([ "$PUSH" == "1" ] && echo "force-push after apply" || echo "no push")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── Phase 1: preconditions ────────────────────────────────────────────────
echo ""
echo "[1/6] Preconditions"

cd "$REPO"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "  ✗ working tree has uncommitted changes — stash or commit first" >&2
    exit 1
fi
echo "  ✓ working tree clean"

if ! command -v git-filter-repo &>/dev/null && ! python -c "import git_filter_repo" &>/dev/null 2>&1; then
    echo "  ✗ git-filter-repo not found" >&2
    echo "    install: pip install --user git-filter-repo" >&2
    exit 1
fi
echo "  ✓ git-filter-repo available"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
CURRENT_SHA="$(git rev-parse HEAD)"
echo "  ✓ current: $CURRENT_BRANCH @ ${CURRENT_SHA:0:8}"

CONTRIBUTORS="$(git log --format='%ae' | sort -u | wc -l | tr -d ' ')"
if [[ "$CONTRIBUTORS" -gt 1 ]]; then
    echo ""
    echo "  ⚠ this repo has $CONTRIBUTORS distinct committer emails."
    echo "    Rewriting history will invalidate all clones held by other contributors."
    if [[ "$MODE" == "apply" ]]; then
        read -r -p "    Continue? [type 'yes' to proceed] " ack
        [[ "$ack" == "yes" ]] || { echo "aborted."; exit 1; }
    fi
fi

SIGNED_COMMITS="$(git log --format='%G?' | grep -cE '^(G|U|X|Y|R|E)$' || true)"
if [[ "$SIGNED_COMMITS" -gt 0 ]]; then
    echo ""
    echo "  ⚠ $SIGNED_COMMITS commit(s) have GPG signatures. Rewrite will invalidate them."
    if [[ "$MODE" == "apply" ]]; then
        read -r -p "    Continue anyway? [type 'yes' to proceed] " ack
        [[ "$ack" == "yes" ]] || { echo "aborted."; exit 1; }
    fi
fi

# ─── Phase 2: backup (always, regardless of mode) ──────────────────────────
echo ""
echo "[2/6] Backup"

BUNDLE="$BACKUP_DIR/${REPO_NAME}-${TIMESTAMP}.bundle"
git bundle create "$BUNDLE" --all >/dev/null
echo "  ✓ local bundle: $BUNDLE"

if git remote get-url origin &>/dev/null; then
    BACKUP_BRANCH="pre-ai-scrub-${TIMESTAMP}"
    if [[ "$MODE" == "apply" ]]; then
        git push origin "${CURRENT_BRANCH}:refs/heads/${BACKUP_BRANCH}" >/dev/null 2>&1 \
            && echo "  ✓ remote backup branch: origin/${BACKUP_BRANCH}" \
            || echo "  ⚠ remote backup push failed (continuing — local bundle is authoritative)"
    else
        echo "  • remote backup branch will be: origin/${BACKUP_BRANCH} (created on --apply)"
    fi
else
    echo "  • no origin remote — local bundle only"
fi

# ─── Phase 3: build the scrub operation ────────────────────────────────────
echo ""
echo "[3/6] Scrub operation"

WORKDIR="/tmp/ai-scrub-${REPO_NAME}-${TIMESTAMP}"
mkdir -p "$WORKDIR"
CLONE="${WORKDIR}/clone"

git clone --no-local --mirror "$REPO" "$CLONE" >/dev/null 2>&1
echo "  ✓ scratch clone: $CLONE"

# Python callback for filter-repo
CALLBACK_PY="${WORKDIR}/callback.py"
cat > "$CALLBACK_PY" <<'PYEOF'
import re

PATTERNS = [
    # Co-Authored-By trailers (most common)
    re.compile(rb'(?m)^Co-Authored-By:\s*Claude(\s+Code)?\s*<[^>]*>\s*\n?', re.IGNORECASE),
    re.compile(rb'(?m)^Co-Authored-By:\s*(OpenAI\s+)?Codex\s*<[^>]*>\s*\n?', re.IGNORECASE),
    re.compile(rb'(?m)^Co-Authored-By:\s*GitHub\s+Copilot\s*<[^>]*>\s*\n?', re.IGNORECASE),
    re.compile(rb'(?m)^Co-Authored-By:\s*(Cursor|Cline|Aider|Continue|Sweep|Devin)\s*<[^>]*>\s*\n?', re.IGNORECASE),
    # Generated-with signatures
    re.compile(rb'(?m)^\s*(?:🤖|🦾)?\s*Generated with \[?Claude Code\]?(?:\([^)]*\))?\s*$\n?', re.IGNORECASE),
    re.compile(rb'(?m)^\s*Generated by Claude(?:\s+Code)?(?:\s+v?\d+(?:\.\d+)*)?\s*$\n?', re.IGNORECASE),
    re.compile(rb'(?m)^\s*Made with Claude(?:\s+Code)?\s*$\n?', re.IGNORECASE),
    re.compile(rb'(?m)^\s*Written (?:by|with) Claude(?:\s+Code)?\s*$\n?', re.IGNORECASE),
    # URL attributions
    re.compile(rb'https?://claude\.ai\S*', re.IGNORECASE),
    re.compile(rb'https?://(?:www\.)?anthropic\.com/claude-code\S*', re.IGNORECASE),
    re.compile(rb'https?://(?:chat\.)?openai\.com\S*', re.IGNORECASE),
    re.compile(rb'https?://chatgpt\.com\S*', re.IGNORECASE),
    # Via-phrases (line-anchored to avoid false positives on prose)
    re.compile(rb'(?m)^\s*(?:via|using)\s+(?:Claude(?:\s+Code)?|Codex|ChatGPT|Copilot|Cursor|Cline|Aider)\s*$\n?', re.IGNORECASE),
    # Trailing AI-assistant phrases
    re.compile(rb'(?m)^\s*(?:AI[- ]assisted|auto[- ]generated by|assisted by AI)\s*.*$\n?', re.IGNORECASE),
]

BLANK_RUN = re.compile(rb'\n{3,}')
TRAILING_WS = re.compile(rb'[ \t]+$', re.MULTILINE)

def commit_callback(commit, metadata):
    msg = commit.message
    for p in PATTERNS:
        msg = p.sub(b'', msg)
    msg = BLANK_RUN.sub(b'\n\n', msg)
    msg = TRAILING_WS.sub(b'', msg)
    msg = msg.strip(b'\n') + b'\n'
    if not msg.strip():
        msg = b'(message removed)\n'
    commit.message = msg
PYEOF

# Build filter-repo command
FILTER_ARGS=(--force --commit-callback "$(cat "$CALLBACK_PY")")

if [[ "$INCLUDE_FILES" == "1" ]]; then
    FILTER_ARGS+=(
        --path CLAUDE.md --invert-paths
        --path CODEX_CHANGELOG.md --invert-paths
        --path CLAUDE_NOTES.md --invert-paths
        --path AGENTS.md --invert-paths
        --path AI_CONTEXT.md --invert-paths
        --path .claude/ --invert-paths
        --path .codex/ --invert-paths
        --path .cursorrules --invert-paths
        --path .continuerc --invert-paths
        --path .clinerc --invert-paths
    )
    echo "  • will purge: CLAUDE.md, CODEX_CHANGELOG.md, .claude/, .codex/, etc."
fi

cd "$CLONE"
echo "  • running filter-repo on scratch clone..."
git-filter-repo "${FILTER_ARGS[@]}" 2>&1 | tail -5
echo "  ✓ scratch-clone rewrite complete"

# ─── Phase 4: report ───────────────────────────────────────────────────────
echo ""
echo "[4/6] Change report"

ORIG_COMMIT_COUNT="$(cd "$REPO" && git log --oneline | wc -l | tr -d ' ')"
NEW_COMMIT_COUNT="$(git log --oneline | wc -l | tr -d ' ')"
CHANGED_COUNT=$((ORIG_COMMIT_COUNT - NEW_COMMIT_COUNT))

echo "  original commits: $ORIG_COMMIT_COUNT"
echo "  new commits:      $NEW_COMMIT_COUNT"
echo "  delta:            $CHANGED_COUNT (should be 0 unless empty commits dropped)"

# Count messages that differ
DIFF_COUNT=0
SAMPLES_SHOWN=0
echo ""
echo "  Sample of changed commits (up to 5):"
while IFS= read -r sha; do
    [[ "$SAMPLES_SHOWN" -ge 5 ]] && break
    ORIG_MSG="$(cd "$REPO" && git log --format='%B' -1 "$sha" 2>/dev/null || echo '')"
    NEW_MSG="$(git log --format='%B' -1 "$sha" 2>/dev/null || echo '')"
    if [[ "$ORIG_MSG" != "$NEW_MSG" && -n "$NEW_MSG" ]]; then
        echo ""
        echo "  ─── ${sha:0:8} ───────────────────────"
        echo "  BEFORE:"
        echo "$ORIG_MSG" | head -10 | sed 's/^/    /'
        echo "  AFTER:"
        echo "$NEW_MSG" | head -10 | sed 's/^/    /'
        SAMPLES_SHOWN=$((SAMPLES_SHOWN + 1))
    fi
done < <(cd "$REPO" && git log --format='%H' | head -100)

# ─── Phase 5: apply-or-stop decision ───────────────────────────────────────
echo ""
echo "[5/6] $([ "$MODE" == "apply" ] && echo "Apply" || echo "Dry-run complete")"

if [[ "$MODE" == "dry-run" ]]; then
    echo "  • scratch clone preserved at: $CLONE"
    echo "  • no changes made to $REPO"
    echo ""
    echo "  To apply these changes:"
    echo "    ai-scrub.sh '$REPO' --apply$([ "$INCLUDE_FILES" == "1" ] && echo ' --include-files')"
    exit 0
fi

echo ""
read -r -p "  Apply these changes to the real repo? [type 'yes' to proceed] " ack
[[ "$ack" == "yes" ]] || { echo "  aborted — no changes made."; exit 1; }

cd "$REPO"
git-filter-repo "${FILTER_ARGS[@]}" 2>&1 | tail -5
echo "  ✓ real-repo rewrite complete"

# Re-add origin (filter-repo strips it by default)
if [[ -z "$(git remote -v)" ]]; then
    # Try to recover origin URL from the scratch clone's config backup
    ORIGIN_URL="$(cd "$CLONE" && git config --get remote.origin.url || true)"
    if [[ -n "$ORIGIN_URL" ]]; then
        git remote add origin "$ORIGIN_URL"
        echo "  ✓ re-added origin: $ORIGIN_URL"
    else
        echo "  ⚠ origin remote stripped by filter-repo — re-add manually before push"
    fi
fi

# ─── Phase 6: force-push (explicit, separate confirmation) ────────────────
echo ""
echo "[6/6] Remote push"

if [[ "$PUSH" == "0" ]]; then
    echo "  • --push not specified. To push now:"
    echo "    cd '$REPO' && rtk git push --force-with-lease origin $CURRENT_BRANCH"
    echo "    cd '$REPO' && rtk git push --force-with-lease origin --tags"
    echo ""
    echo "  Backup locations:"
    echo "    local bundle:  $BUNDLE"
    [[ -n "${BACKUP_BRANCH:-}" ]] && echo "    remote branch: origin/$BACKUP_BRANCH"
    exit 0
fi

echo ""
echo "  ⚠ About to FORCE-PUSH rewritten history to origin."
echo "    Existing clones will become invalid."
echo "    Backup at: origin/$BACKUP_BRANCH + $BUNDLE"
echo ""
read -r -p "  Type 'force push' to proceed: " ack
[[ "$ack" == "force push" ]] || { echo "  aborted — local rewrite kept, remote unchanged."; exit 1; }

git push --force-with-lease origin "$CURRENT_BRANCH"
git push --force-with-lease origin --tags
echo "  ✓ force-pushed"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Scrub complete."
echo "  Local bundle:   $BUNDLE"
echo "  Remote backup:  origin/$BACKUP_BRANCH"
echo ""
echo "  Verify on GitHub:"
echo "    rtk gh repo view --web"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
