#!/usr/bin/env bash
# factory-overnight.sh — round-robin overnight wrapper for the factory loop.
#
# Why this exists:
#   A single Claude Code conversation has a finite context window. Even with
#   auto-compaction, an 8-hour run will eventually fragment context and
#   degrade. The factory loop's Large-Repo Mode is built so each invocation
#   is finite (1 iteration, 3 tasks, atomic commits, exit cleanly) — but
#   that means a SINGLE invocation finishes in ~30 min and stops.
#
#   This wrapper loops invocations externally. Each cycle: spawn a fresh
#   `claude --print` with the factory prompt → recipe runs Large-Repo Mode
#   → exits cleanly → wrapper sleeps → respawns. Cumulative state lives in
#   the repos themselves (state.yaml, atomic commits, ROADMAP.md, etc.) so
#   each fresh session resumes where the prior left off.
#
# Usage:
#   factory-overnight.sh <repo> [<repo>...] [options]
#
# Examples:
#   # One repo, run until 6am, max $50 spend
#   factory-overnight.sh ~/repos/Astra-Deck --until 06:00 --max-spend-total 50
#
#   # Round-robin across three repos until SIGINT or sentinel file
#   factory-overnight.sh ~/repos/Astra-Deck ~/repos/NovaCut ~/repos/StreamKeep
#
#   # Time-boxed 4-hour run, up to 10 cycles
#   factory-overnight.sh ~/repos/HEICShift --duration 4h --max-cycles 10
#
# Options:
#   --until HH:MM             Wall-clock end time (24h format). Wrapper exits
#                             cleanly after the cycle running at that time finishes.
#   --duration <Nh|Nm>        Run for N hours or N minutes from now.
#   --max-cycles N            Hard cap on total invocations across all repos.
#                             Default: unlimited.
#   --max-spend-total USD     Cumulative cost cap across all cycles. Default: $50.
#                             Each cycle gets `--max-budget-usd remaining/cycles_left`.
#   --sleep N                 Seconds between cycles. Default: 60.
#                             Gives breakers cooldown + CI a beat between pushes.
#   --cycle-timeout N         Per-cycle hard timeout (seconds). Default: 1800 (30 min).
#                             Kills the cycle if it hangs.
#   --convergence-rotations N Stop a repo after N consecutive cycles with no
#                             new ROADMAP work. Default: 3.
#   --no-rotate               Disable round-robin; finish each repo before moving on.
#   --dry-run                 Print what would run, don't actually invoke claude.
#   --status                  Show overnight status (running cycle, last result,
#                             cumulative cost, repos remaining) and exit.
#   --stop                    Touch the sentinel file to halt a running overnight
#                             session at the next cycle boundary.
#   --model <name>            Override Claude model for the master session.
#                             Default: claude reads from env / settings.
#
# Stop conditions (any one ends the overnight session cleanly):
#   - Wall-clock --until or --duration reached
#   - --max-cycles exhausted
#   - --max-spend-total exhausted
#   - Sentinel file ~/.factory-overnight.stop exists
#   - SIGINT/SIGTERM received (between cycles only — cycles are atomic)
#   - Every repo has converged (--convergence-rotations cycles in a row with
#     no new ROADMAP work)
#
# Layout:
#   ~/.claude-octopus/logs/overnight/
#     <run-id>/
#       overnight.log               wrapper-level events (one line per cycle)
#       cycle-001-<repo>-<phase>.log per-cycle claude output
#       state.json                  current run state (cycles, spend, repos)
#       summary.md                  human-readable end-of-run brief
#
# Sentinel files:
#   ~/.factory-overnight.lock       exists while a session is active
#   ~/.factory-overnight.stop       touch this to halt at next cycle boundary
#   ~/.factory-overnight.status     human-readable status (auto-updated)
#
# bats-skip-syntax-check: requires-bash-4
#   Uses `declare -A` (associative arrays) which is bash 4.0+. The bats
#   syntax-check suite honors this marker and skips the file when it's
#   running under bash <4 (notably macOS's stock /bin/bash 3.2). The
#   runtime guard below prevents accidental execution on bash <4.

if (( BASH_VERSINFO[0] < 4 )); then
    echo "factory-overnight.sh: requires bash 4+ (have bash ${BASH_VERSION})." >&2
    echo "  macOS users: brew install bash, then re-run with /opt/homebrew/bin/bash $0 ..." >&2
    exit 1
fi

set -uo pipefail

# --- Defaults ---
SLEEP_SEC=60
CYCLE_TIMEOUT_SEC=1800
MAX_CYCLES=0           # 0 = unlimited
MAX_SPEND_TOTAL=50
CONVERGENCE_ROTATIONS=3
NO_ROTATE=false
DRY_RUN=false
END_TIME=""
DURATION=""
MODEL_OVERRIDE=""
STATUS_ONLY=false
STOP_ONLY=false

REPOS=()

LOCK_FILE="$HOME/.factory-overnight.lock"
STOP_FILE="$HOME/.factory-overnight.stop"
STATUS_FILE="$HOME/.factory-overnight.status"
LOG_ROOT="$HOME/.claude-octopus/logs/overnight"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --until)                  END_TIME="$2"; shift 2 ;;
        --duration)               DURATION="$2"; shift 2 ;;
        --max-cycles)             MAX_CYCLES="$2"; shift 2 ;;
        --max-spend-total)        MAX_SPEND_TOTAL="$2"; shift 2 ;;
        --sleep)                  SLEEP_SEC="$2"; shift 2 ;;
        --cycle-timeout)          CYCLE_TIMEOUT_SEC="$2"; shift 2 ;;
        --convergence-rotations)  CONVERGENCE_ROTATIONS="$2"; shift 2 ;;
        --no-rotate)              NO_ROTATE=true; shift ;;
        --dry-run)                DRY_RUN=true; shift ;;
        --status)                 STATUS_ONLY=true; shift ;;
        --stop)                   STOP_ONLY=true; shift ;;
        --model)                  MODEL_OVERRIDE="$2"; shift 2 ;;
        -h|--help)                sed -n '2,75p' "$0"; exit 0 ;;
        -*)                       echo "factory-overnight: unknown option: $1" >&2; exit 1 ;;
        *)                        REPOS+=("$1"); shift ;;
    esac
done

# --- --status / --stop short-circuits ---
if $STOP_ONLY; then
    touch "$STOP_FILE"
    echo "factory-overnight: sentinel created at $STOP_FILE — running session will halt at next cycle boundary."
    exit 0
fi

if $STATUS_ONLY; then
    if [[ -f "$STATUS_FILE" ]]; then
        cat "$STATUS_FILE"
    else
        echo "no overnight session active (no $STATUS_FILE)"
    fi
    exit 0
fi

# --- Validate ---
if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo "factory-overnight: at least one repo path required" >&2
    echo "Usage: factory-overnight.sh <repo> [<repo>...] [options]" >&2
    exit 1
fi

for repo in "${REPOS[@]}"; do
    if [[ ! -d "$repo" ]]; then
        echo "factory-overnight: repo not found: $repo" >&2
        exit 1
    fi
    if [[ ! -d "$repo/.git" ]]; then
        echo "factory-overnight: not a git repo: $repo" >&2
        exit 1
    fi
done

if [[ -f "$LOCK_FILE" ]]; then
    LOCKED_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "?")
    echo "factory-overnight: lock file $LOCK_FILE exists (pid=$LOCKED_PID)." >&2
    echo "  If no session is actually running: rm $LOCK_FILE" >&2
    exit 1
fi

if ! command -v claude &>/dev/null; then
    echo "factory-overnight: claude CLI not on PATH" >&2
    exit 1
fi

# --- Resolve end time ---
NOW_EPOCH=$(date +%s)
END_EPOCH=0  # 0 = no time limit

if [[ -n "$DURATION" ]]; then
    case "$DURATION" in
        *h) END_EPOCH=$(( NOW_EPOCH + ${DURATION%h} * 3600 )) ;;
        *m) END_EPOCH=$(( NOW_EPOCH + ${DURATION%m} * 60 )) ;;
        *)  echo "factory-overnight: --duration must end in h or m (e.g. 4h, 90m)" >&2; exit 1 ;;
    esac
fi

if [[ -n "$END_TIME" ]]; then
    # Convert HH:MM to next-occurrence epoch
    TODAY=$(date +%Y-%m-%d)
    TARGET_EPOCH=$(date -d "$TODAY $END_TIME" +%s 2>/dev/null || date +%s)
    if [[ "$TARGET_EPOCH" -le "$NOW_EPOCH" ]]; then
        # Time already passed today, mean tomorrow
        TARGET_EPOCH=$(( TARGET_EPOCH + 86400 ))
    fi
    if [[ "$END_EPOCH" -eq 0 || "$TARGET_EPOCH" -lt "$END_EPOCH" ]]; then
        END_EPOCH=$TARGET_EPOCH
    fi
fi

# --- Run identifiers ---
RUN_TS=$(date -u +%Y%m%dT%H%M%SZ)
RUN_ID="overnight-$RUN_TS-$$"
RUN_DIR="$LOG_ROOT/$RUN_ID"
mkdir -p "$RUN_DIR"
EVENT_LOG="$RUN_DIR/overnight.log"
STATE_FILE="$RUN_DIR/state.json"

# --- Lock ---
trap 'rm -f "$LOCK_FILE" "$STATUS_FILE"' EXIT
echo "$$" > "$LOCK_FILE"
rm -f "$STOP_FILE"  # clear any stale sentinel

log() {
    local msg="$*"
    local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s  %s\n' "$ts" "$msg" | tee -a "$EVENT_LOG"
}

write_status() {
    cat > "$STATUS_FILE" <<EOF
=== factory-overnight session ===
Run ID:           $RUN_ID
Started:          $RUN_TS
Repos:            ${REPOS[*]}
Cycles done:      $CYCLES_DONE
Cumulative cost:  \$$CUM_SPEND
Last cycle:       ${LAST_CYCLE:-none}
Last result:      ${LAST_RESULT:-n/a}
End condition:    ${END_REASON:-running}

Stop:             touch $STOP_FILE
Logs:             $RUN_DIR
EOF
}

cycles_remaining() {
    if [[ "$MAX_CYCLES" -gt 0 ]]; then
        echo "$(( MAX_CYCLES - CYCLES_DONE ))"
        return
    fi
    # MAX_CYCLES=0 (unlimited): estimate from remaining wall-clock so per-cycle
    # budget math doesn't divide total spend by 9999 and round to $0.00.
    # Assume each cycle does ~10min of real LLM work (factory loop is heavy);
    # tune via OVERNIGHT_EST_CYCLE_SEC env var if your cycles run faster.
    local floor_sec="${OVERNIGHT_EST_CYCLE_SEC:-600}"
    if [[ "${END_EPOCH:-0}" -gt 0 ]]; then
        local now=$(date +%s)
        local est_cycle=$(( SLEEP_SEC + floor_sec ))
        local rem=$(( (END_EPOCH - now) / est_cycle ))
        (( rem < 1 )) && rem=1
        (( rem > 20 )) && rem=20
        echo "$rem"
    else
        echo "20"  # truly unbounded — cap so budget math stays sane
    fi
}

spend_remaining() {
    awk -v t="$MAX_SPEND_TOTAL" -v s="$CUM_SPEND" 'BEGIN { printf "%.2f", t - s }'
}

# --- Convergence tracking per repo ---
declare -A CONVERGENCE_STREAK
for repo in "${REPOS[@]}"; do
    CONVERGENCE_STREAK["$repo"]=0
done

# --- Main loop ---
CYCLES_DONE=0
CUM_SPEND=0
REPO_IDX=0
LAST_CYCLE=""
LAST_RESULT=""
END_REASON=""

write_status

log "=== factory-overnight started ==="
log "Run ID:           $RUN_ID"
log "Repos:            ${REPOS[*]}"
log "Until:            ${END_EPOCH:-unbounded} ($([ "$END_EPOCH" -gt 0 ] && date -d "@$END_EPOCH" || echo unbounded))"
log "Max cycles:       ${MAX_CYCLES:-unlimited}"
log "Max spend total:  \$$MAX_SPEND_TOTAL"
log "Sleep:            ${SLEEP_SEC}s"
log "Cycle timeout:    ${CYCLE_TIMEOUT_SEC}s"
log "Convergence rot:  $CONVERGENCE_ROTATIONS"
log "Round-robin:      $($NO_ROTATE && echo no || echo yes)"
log "Dry run:          $DRY_RUN"
log ""

while :; do
    # --- Stop checks ---
    if [[ -f "$STOP_FILE" ]]; then
        END_REASON="sentinel file $STOP_FILE present"
        log "STOP: $END_REASON"
        rm -f "$STOP_FILE"
        break
    fi

    NOW_EPOCH=$(date +%s)
    if [[ "$END_EPOCH" -gt 0 && "$NOW_EPOCH" -ge "$END_EPOCH" ]]; then
        END_REASON="wall-clock end time reached"
        log "STOP: $END_REASON"
        break
    fi

    if [[ "$MAX_CYCLES" -gt 0 && "$CYCLES_DONE" -ge "$MAX_CYCLES" ]]; then
        END_REASON="max-cycles ($MAX_CYCLES) reached"
        log "STOP: $END_REASON"
        break
    fi

    REMAINING=$(spend_remaining)
    if awk "BEGIN { exit !($REMAINING <= 0) }"; then
        END_REASON="cumulative cost cap reached (\$$MAX_SPEND_TOTAL)"
        log "STOP: $END_REASON"
        break
    fi

    # --- All repos converged? ---
    ALL_CONVERGED=true
    for repo in "${REPOS[@]}"; do
        if [[ "${CONVERGENCE_STREAK[$repo]}" -lt "$CONVERGENCE_ROTATIONS" ]]; then
            ALL_CONVERGED=false
            break
        fi
    done
    if $ALL_CONVERGED; then
        END_REASON="every repo converged (no new work for $CONVERGENCE_ROTATIONS cycles each)"
        log "STOP: $END_REASON"
        break
    fi

    # --- Pick next repo (round-robin OR sequential) ---
    if $NO_ROTATE; then
        TARGET_REPO="${REPOS[0]}"
        # Skip if converged
        while [[ "${CONVERGENCE_STREAK[$TARGET_REPO]}" -ge "$CONVERGENCE_ROTATIONS" ]]; do
            REPOS=("${REPOS[@]:1}")
            if [[ ${#REPOS[@]} -eq 0 ]]; then
                END_REASON="all repos converged (no-rotate mode)"
                log "STOP: $END_REASON"
                break 2
            fi
            TARGET_REPO="${REPOS[0]}"
        done
    else
        # Find next non-converged repo
        TRIED=0
        while true; do
            TARGET_REPO="${REPOS[$REPO_IDX]}"
            if [[ "${CONVERGENCE_STREAK[$TARGET_REPO]}" -lt "$CONVERGENCE_ROTATIONS" ]]; then
                break
            fi
            REPO_IDX=$(( (REPO_IDX + 1) % ${#REPOS[@]} ))
            TRIED=$(( TRIED + 1 ))
            if [[ "$TRIED" -ge "${#REPOS[@]}" ]]; then
                END_REASON="all repos converged"
                log "STOP: $END_REASON"
                break 2
            fi
        done
    fi

    CYCLE_NUM=$(( CYCLES_DONE + 1 ))
    CYCLE_LOG="$RUN_DIR/cycle-$(printf '%03d' $CYCLE_NUM)-$(basename "$TARGET_REPO").log"

    # --- Compute per-cycle budget ---
    REM=$(spend_remaining)
    CYC_REM=$(cycles_remaining)
    PER_CYCLE_BUDGET=$(awk -v r="$REM" -v c="$CYC_REM" \
        'BEGIN { b = r / (c < 1 ? 1 : c); if (b > 5) b = 5; printf "%.2f", b }')
    # Cap at $5 per cycle so a single bad cycle can't drain the budget.

    log "--- Cycle $CYCLE_NUM ---"
    log "Repo:             $TARGET_REPO"
    log "Per-cycle budget: \$$PER_CYCLE_BUDGET"
    log "Streak:           ${CONVERGENCE_STREAK[$TARGET_REPO]}/$CONVERGENCE_ROTATIONS"

    # --- Build the prompt for this cycle ---
    CYCLE_PROMPT=$(cat <<EOF
Run the factory loop on $TARGET_REPO. Autonomous mode. Apply the
overnight-cycle profile (--overnight flag semantics from the recipe):

- This is overnight cycle $CYCLE_NUM of an externally-driven loop.
- Run exactly ONE iteration of Large-Repo Mode (1 iteration, up to 3 P0/P1
  Now-tier tasks, atomic per-task commits + push, exit cleanly).
- Apply directive-roadmap-research.md ALWAYS (even if ROADMAP looks full —
  Phase 1 delta scan must run; cumulative source list at
  docs/research/iter-*-sources.md).
- Audit phases (L3 Critic, U1, T1, Q1, Q2, Phase 5 self-audit) MUST shell
  out to bin/codex-direct.sh for cross-family signal.
- DO NOT run Q3 release on a routine cycle — the wrapper will manually
  trigger releases via --release on a designated cycle if explicitly
  scheduled. Patch-bump commits + push, no GitHub Release.
- On exit, write to .factory/state.yaml a 'cycle_outcome' field with one of:
    "advanced"  — Now tasks closed, ROADMAP changed
    "researched" — research surfaced new items but no implementation closed
    "no-op"      — research found nothing new and Now tier is empty
  This drives the wrapper's convergence-rotation counter.

Routing: copilot-heavy preset (default). Master session escalates only on
PEC UNCERTAIN ≥3, debate stalemate, security-critical, or novel architecture.
Bulk implementation routes to copilot-sonnet, audit to codex-direct.

Begin.
EOF
)

    if $DRY_RUN; then
        log "[DRY-RUN] would invoke: claude -p --dangerously-skip-permissions --max-budget-usd $PER_CYCLE_BUDGET ..."
        log "[DRY-RUN] cycle log: $CYCLE_LOG"
        CYCLE_RC=0
        CYCLE_OUTCOME="advanced"  # fake for dry-run
        CYCLE_SPEND="0.00"
    else
        # --- Invoke claude headlessly ---
        CLAUDE_ARGS=(
            -p
            --dangerously-skip-permissions
            --max-budget-usd "$PER_CYCLE_BUDGET"
            --output-format text
            --no-session-persistence
            --add-dir "$TARGET_REPO"
            --add-dir "$HOME/repos/octopus-factory"
            --add-dir "$HOME/.claude-octopus"
        )
        if [[ -n "$MODEL_OVERRIDE" ]]; then
            CLAUDE_ARGS+=(--model "$MODEL_OVERRIDE")
        fi

        # Pipe prompt via stdin: claude CLI 2.1.78+ no longer accepts a trailing
        # positional prompt after multi-value flags like --add-dir.
        if command -v timeout &>/dev/null; then
            printf '%s' "$CYCLE_PROMPT" | timeout --signal=TERM "${CYCLE_TIMEOUT_SEC}s" \
                claude "${CLAUDE_ARGS[@]}" \
                > "$CYCLE_LOG" 2>&1
        else
            printf '%s' "$CYCLE_PROMPT" | claude "${CLAUDE_ARGS[@]}" \
                > "$CYCLE_LOG" 2>&1
        fi
        CYCLE_RC=$?

        # --- Read cycle outcome from state.yaml ---
        STATE_YAML="$TARGET_REPO/.factory/state.yaml"
        CYCLE_OUTCOME="unknown"
        if [[ -f "$STATE_YAML" ]]; then
            CYCLE_OUTCOME=$(grep -E '^cycle_outcome:' "$STATE_YAML" 2>/dev/null \
                | tail -1 | sed 's/^cycle_outcome:\s*//; s/[\"]//g' || true)
            CYCLE_OUTCOME="${CYCLE_OUTCOME:-unknown}"
        fi

        # --- Estimate cycle spend (very rough — we don't have a precise hook) ---
        # claude --max-budget-usd is a hard cap, not a reporter; we attribute
        # the per-cycle budget as 50% spent (typical) unless the cycle hit cap.
        if grep -q -i "budget.*exceeded\|max-budget.*hit\|spending limit" "$CYCLE_LOG" 2>/dev/null; then
            CYCLE_SPEND="$PER_CYCLE_BUDGET"
        else
            CYCLE_SPEND=$(awk -v b="$PER_CYCLE_BUDGET" 'BEGIN { printf "%.2f", b * 0.5 }')
        fi
        CUM_SPEND=$(awk -v c="$CUM_SPEND" -v s="$CYCLE_SPEND" 'BEGIN { printf "%.2f", c + s }')
    fi

    CYCLES_DONE=$(( CYCLES_DONE + 1 ))
    LAST_CYCLE="$TARGET_REPO ($CYCLE_OUTCOME)"
    LAST_RESULT="rc=$CYCLE_RC outcome=$CYCLE_OUTCOME"
    log "Cycle $CYCLE_NUM done: rc=$CYCLE_RC outcome=$CYCLE_OUTCOME spend≈\$$CYCLE_SPEND cum=\$$CUM_SPEND"

    # --- Update convergence streak ---
    case "$CYCLE_OUTCOME" in
        advanced)   CONVERGENCE_STREAK["$TARGET_REPO"]=0 ;;
        researched) CONVERGENCE_STREAK["$TARGET_REPO"]=$(( CONVERGENCE_STREAK["$TARGET_REPO"] / 2 )) ;;  # half-decay
        no-op)      CONVERGENCE_STREAK["$TARGET_REPO"]=$(( CONVERGENCE_STREAK["$TARGET_REPO"] + 1 )) ;;
        *)          CONVERGENCE_STREAK["$TARGET_REPO"]=$(( CONVERGENCE_STREAK["$TARGET_REPO"] + 1 )) ;;
    esac

    # --- Rotate to next repo (if not --no-rotate) ---
    if ! $NO_ROTATE; then
        REPO_IDX=$(( (REPO_IDX + 1) % ${#REPOS[@]} ))
    fi

    write_status

    # --- Sleep before next cycle ---
    if [[ "$SLEEP_SEC" -gt 0 ]]; then
        log "Sleeping ${SLEEP_SEC}s before next cycle..."
        sleep "$SLEEP_SEC"
    fi
done

# --- Summary ---
SUMMARY_FILE="$RUN_DIR/summary.md"
{
    echo "# factory-overnight summary"
    echo ""
    echo "**Run ID:** $RUN_ID"
    echo "**Started:** $RUN_TS"
    echo "**Ended:**   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "**End reason:** $END_REASON"
    echo "**Cycles completed:** $CYCLES_DONE"
    echo "**Cumulative spend:** \$$CUM_SPEND"
    echo ""
    echo "## Per-repo state"
    echo ""
    for repo in "${REPOS[@]}"; do
        echo "- \`$repo\` — convergence streak: ${CONVERGENCE_STREAK[$repo]}/$CONVERGENCE_ROTATIONS"
    done
    echo ""
    echo "## Cycle log"
    echo ""
    echo '```'
    cat "$EVENT_LOG"
    echo '```'
} > "$SUMMARY_FILE"

log ""
log "=== factory-overnight ended ==="
log "End reason:       $END_REASON"
log "Cycles done:      $CYCLES_DONE"
log "Cumulative cost:  \$$CUM_SPEND"
log "Summary:          $SUMMARY_FILE"

write_status
echo ""
echo "Summary written to $SUMMARY_FILE"
exit 0
