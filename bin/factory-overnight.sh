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
#   # One repo, run until 6am, max $50 spend, live cycle output (default)
#   factory-overnight.sh ~/repos/Astra-Deck --until 06:00 --max-spend-total 50
#
#   # Round-robin across three repos, no live output
#   factory-overnight.sh ~/repos/Astra-Deck ~/repos/NovaCut ~/repos/StreamKeep --quiet
#
#   # Time-boxed 4-hour run, up to 10 cycles
#   factory-overnight.sh ~/repos/HEICShift --duration 4h --max-cycles 10
#
#   # Auto-discover every git repo under ~/repos and run round-robin
#   factory-overnight.sh --auto-discover ~/repos --duration 8h
#
#   # Same, but skip a few repos and require clean working trees
#   factory-overnight.sh --auto-discover ~/repos --exclude-repo Maven \
#       --exclude-repo opencut --require-clean-tree --duration 8h
#
#   # Schedule a delayed start (kick off now, actually run starting 23:00)
#   factory-overnight.sh ~/repos/Astra-Deck --start-time 23:00 --until 06:00
#
#   # Healthchecks.io ping every cycle + ntfy.sh end-of-run notification
#   factory-overnight.sh ~/repos/Astra-Deck --duration 6h \
#       --healthcheck-url https://hc-ping.com/<uuid> --notify ntfy=mytopic
#
#   # Resume convergence state from a prior run (skips repos that already converged)
#   factory-overnight.sh ~/repos/Astra-Deck --resume overnight-20260425T020000Z-12345
#
# Options (existing):
#   --until HH:MM             Wall-clock end time (24h format).
#   --duration <Nh|Nm>        Run for N hours or N minutes from now.
#   --max-cycles N            Hard cap on total invocations. Default: unlimited.
#   --max-spend-total USD     Cumulative cost cap. Default: $50.
#   --sleep N                 Seconds between cycles. Default: 60.
#   --cycle-timeout N         Per-cycle hard timeout (seconds). Default: 1800.
#   --convergence-rotations N Stop a repo after N consecutive cycles with no
#                             new ROADMAP work. Default: 3.
#   --no-rotate               Disable round-robin; finish each repo before moving on.
#   --dry-run                 Print what would run, don't actually invoke claude.
#   --status                  Show overnight status (running cycle, last result,
#                             cumulative cost, repos remaining) and exit.
#   --stop                    Touch the sentinel file to halt at next cycle boundary.
#   --model <name>            Override Claude model for the master session.
#
# Options (new):
#   --quiet, -q               Suppress live cycle output (log file only).
#                             Default is verbose: cycle output streams to your
#                             terminal AND to the per-cycle log.
#   --no-color                Disable ANSI color in console output.
#   --heartbeat-sec N         Print "[heartbeat] cycle X | repo | running Ys"
#                             every N seconds during a cycle. Default: 30.
#                             Set to 0 to disable.
#   --start-time HH:MM        Delayed start. Wrapper sleeps until this time
#                             before kicking off cycle 1. Combine with --until.
#   --auto-discover DIR       Find every git repo (top-level, depth=1) under
#                             DIR and add it to the repo list. Stacks with
#                             explicitly-named repos.
#   --exclude-repo PATTERN    Skip any repo whose path contains PATTERN.
#                             Repeatable.
#   --shuffle-repos           Randomize repo order at startup. Avoids the
#                             always-first-repo-converges-last bias.
#   --healthcheck-url URL     POST a "still alive" ping at the start of every
#                             cycle (Healthchecks.io / Better Stack format).
#                             URL receives /start before, /<rc> after.
#   --notify SPEC             Send end-of-run notification. SPEC formats:
#                                 webhook=URL    POST JSON to URL
#                                 ntfy=TOPIC     POST to https://ntfy.sh/TOPIC
#                                 desktop        Local desktop notification
#                                                (notify-send / osascript / msg)
#                             Repeatable.
#   --resume RUN_ID           Rehydrate convergence streaks from a prior run's
#                             state.json. Skips repos that already converged.
#   --fail-fast               Abort the whole session on first non-zero cycle
#                             rc. Default: keep going (a single bad cycle
#                             shouldn't kill the night).
#   --require-clean-tree      Pre-flight: refuse to start if any repo has
#                             uncommitted changes.
#   --require-remote          Pre-flight: refuse to start if any repo has no
#                             `origin` remote configured.
#   --show-config             Print the effective configuration and exit. Use
#                             before kicking off long runs to confirm flags.
#
# Stop conditions (any one ends the overnight session cleanly):
#   - Wall-clock --until or --duration reached
#   - --max-cycles exhausted
#   - --max-spend-total exhausted
#   - Sentinel file ~/.factory-overnight.stop exists
#   - SIGINT/SIGTERM received (cycle child gets SIGTERM; wrapper writes summary)
#   - Every repo has converged (--convergence-rotations cycles in a row with
#     no new ROADMAP work)
#   - --fail-fast and a cycle exited non-zero
#
# Pause/resume during a run:
#   - touch ~/.factory-overnight.pause   → wrapper waits between cycles until
#                                          the file is removed (does not
#                                          interrupt an in-progress cycle)
#   - rm ~/.factory-overnight.pause      → resume
#
# Layout:
#   ~/.claude-octopus/logs/overnight/
#     <run-id>/
#       overnight.log               wrapper-level events (one line per cycle)
#       cycle-NNN-<repo>.log        per-cycle claude output
#       state.json                  current run state (cycles, spend, streaks)
#       summary.md                  human-readable end-of-run brief
#
# Sentinel files:
#   ~/.factory-overnight.lock          exists while a session is active
#   ~/.factory-overnight.stop          touch this to halt at next cycle boundary
#   ~/.factory-overnight.pause         touch this to pause the loop between cycles
#   ~/.factory-overnight.status        human-readable status (auto-updated)
#   ~/.factory-overnight.status.json   machine-readable status
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

# ─── Defaults ───────────────────────────────────────────────────────────────
SLEEP_SEC=60
CYCLE_TIMEOUT_SEC=1800
MAX_CYCLES=0           # 0 = unlimited
MAX_SPEND_TOTAL=50
CONVERGENCE_ROTATIONS=3
NO_ROTATE=false
DRY_RUN=false
END_TIME=""
START_TIME=""
DURATION=""
MODEL_OVERRIDE=""
STATUS_ONLY=false
STOP_ONLY=false

# new defaults
QUIET=false
USE_COLOR=true                       # auto-disabled if stdout not a TTY
HEARTBEAT_SEC=30
AUTO_DISCOVER_DIR=""
EXCLUDES=()
SHUFFLE_REPOS=false
HEALTHCHECK_URL=""
NOTIFY_SPECS=()
RESUME_RUN_ID=""
FAIL_FAST=false
REQUIRE_CLEAN_TREE=false
REQUIRE_REMOTE=false
SHOW_CONFIG=false

REPOS=()

LOCK_FILE="$HOME/.factory-overnight.lock"
STOP_FILE="$HOME/.factory-overnight.stop"
PAUSE_FILE="$HOME/.factory-overnight.pause"
STATUS_FILE="$HOME/.factory-overnight.status"
STATUS_JSON="$HOME/.factory-overnight.status.json"
LOG_ROOT="$HOME/.claude-octopus/logs/overnight"

# ─── Parse args ─────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --until)                  END_TIME="$2"; shift 2 ;;
        --start-time)             START_TIME="$2"; shift 2 ;;
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
        --quiet|-q)               QUIET=true; shift ;;
        --no-color)               USE_COLOR=false; shift ;;
        --heartbeat-sec)          HEARTBEAT_SEC="$2"; shift 2 ;;
        --auto-discover)          AUTO_DISCOVER_DIR="$2"; shift 2 ;;
        --exclude-repo)           EXCLUDES+=("$2"); shift 2 ;;
        --shuffle-repos)          SHUFFLE_REPOS=true; shift ;;
        --healthcheck-url)        HEALTHCHECK_URL="$2"; shift 2 ;;
        --notify)                 NOTIFY_SPECS+=("$2"); shift 2 ;;
        --resume)                 RESUME_RUN_ID="$2"; shift 2 ;;
        --fail-fast)              FAIL_FAST=true; shift ;;
        --require-clean-tree)     REQUIRE_CLEAN_TREE=true; shift ;;
        --require-remote)         REQUIRE_REMOTE=true; shift ;;
        --show-config)            SHOW_CONFIG=true; shift ;;
        -h|--help)                sed -n '2,135p' "$0"; exit 0 ;;
        -*)                       echo "factory-overnight: unknown option: $1" >&2; exit 1 ;;
        *)                        REPOS+=("$1"); shift ;;
    esac
done

# ─── --status / --stop short-circuits ───────────────────────────────────────
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

# ─── Color helpers ──────────────────────────────────────────────────────────
if $USE_COLOR && [[ -t 1 ]]; then
    C_DIM=$'\033[2m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
    C_YLW=$'\033[33m'; C_BLU=$'\033[34m'; C_CYN=$'\033[36m'; C_RST=$'\033[0m'
    C_BOLD=$'\033[1m'
else
    C_DIM=""; C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_CYN=""; C_RST=""; C_BOLD=""
fi

# ─── Auto-discover repos under a directory ──────────────────────────────────
if [[ -n "$AUTO_DISCOVER_DIR" ]]; then
    if [[ ! -d "$AUTO_DISCOVER_DIR" ]]; then
        echo "factory-overnight: --auto-discover dir not found: $AUTO_DISCOVER_DIR" >&2
        exit 1
    fi
    while IFS= read -r found; do
        REPOS+=("$found")
    done < <(find "$AUTO_DISCOVER_DIR" -mindepth 2 -maxdepth 2 -type d -name '.git' \
                 -exec dirname {} \; | sort)
fi

# ─── Apply --exclude-repo filters ───────────────────────────────────────────
if [[ ${#EXCLUDES[@]} -gt 0 ]]; then
    FILTERED=()
    for repo in "${REPOS[@]}"; do
        skip=false
        for pat in "${EXCLUDES[@]}"; do
            if [[ "$repo" == *"$pat"* ]]; then skip=true; break; fi
        done
        $skip || FILTERED+=("$repo")
    done
    REPOS=("${FILTERED[@]}")
fi

# ─── --shuffle-repos ────────────────────────────────────────────────────────
if $SHUFFLE_REPOS && [[ ${#REPOS[@]} -gt 1 ]]; then
    # Fisher-Yates via shuf if available, else shell random
    if command -v shuf &>/dev/null; then
        mapfile -t REPOS < <(printf '%s\n' "${REPOS[@]}" | shuf)
    else
        for ((i=${#REPOS[@]}-1; i>0; i--)); do
            j=$((RANDOM % (i+1)))
            tmp="${REPOS[i]}"; REPOS[i]="${REPOS[j]}"; REPOS[j]="$tmp"
        done
    fi
fi

# ─── Validate repos ─────────────────────────────────────────────────────────
if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo "factory-overnight: at least one repo path required" >&2
    echo "  give one or more positional repo args, OR --auto-discover <dir>" >&2
    exit 1
fi

PREFLIGHT_ERRORS=()
for repo in "${REPOS[@]}"; do
    if [[ ! -d "$repo" ]]; then
        PREFLIGHT_ERRORS+=("not found: $repo")
        continue
    fi
    if [[ ! -d "$repo/.git" ]]; then
        PREFLIGHT_ERRORS+=("not a git repo: $repo")
        continue
    fi
    if $REQUIRE_REMOTE; then
        if ! git -C "$repo" remote get-url origin &>/dev/null; then
            PREFLIGHT_ERRORS+=("no 'origin' remote: $repo")
        fi
    fi
    if $REQUIRE_CLEAN_TREE; then
        if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
            PREFLIGHT_ERRORS+=("uncommitted changes: $repo")
        fi
    fi
done

if [[ ${#PREFLIGHT_ERRORS[@]} -gt 0 ]]; then
    echo "factory-overnight: pre-flight failed:" >&2
    for e in "${PREFLIGHT_ERRORS[@]}"; do echo "  - $e" >&2; done
    exit 1
fi

# Note: --show-config short-circuit lives further down (after time + run-id
# resolution) so the dump shows resolved values. Lock + claude-CLI checks
# below are only relevant for actual runs, so they sit AFTER --show-config.

# ─── Resolve start + end time ───────────────────────────────────────────────
NOW_EPOCH=$(date +%s)
END_EPOCH=0          # 0 = no time limit
START_EPOCH=0        # 0 = start immediately

if [[ -n "$DURATION" ]]; then
    case "$DURATION" in
        *h) END_EPOCH=$(( NOW_EPOCH + ${DURATION%h} * 3600 )) ;;
        *m) END_EPOCH=$(( NOW_EPOCH + ${DURATION%m} * 60 )) ;;
        *)  echo "factory-overnight: --duration must end in h or m (e.g. 4h, 90m)" >&2; exit 1 ;;
    esac
fi

if [[ -n "$END_TIME" ]]; then
    TODAY=$(date +%Y-%m-%d)
    TARGET_EPOCH=$(date -d "$TODAY $END_TIME" +%s 2>/dev/null || date +%s)
    if [[ "$TARGET_EPOCH" -le "$NOW_EPOCH" ]]; then
        TARGET_EPOCH=$(( TARGET_EPOCH + 86400 ))
    fi
    if [[ "$END_EPOCH" -eq 0 || "$TARGET_EPOCH" -lt "$END_EPOCH" ]]; then
        END_EPOCH=$TARGET_EPOCH
    fi
fi

if [[ -n "$START_TIME" ]]; then
    TODAY=$(date +%Y-%m-%d)
    START_EPOCH=$(date -d "$TODAY $START_TIME" +%s 2>/dev/null || echo 0)
    if [[ "$START_EPOCH" -le "$NOW_EPOCH" ]]; then
        START_EPOCH=$(( START_EPOCH + 86400 ))
    fi
fi

# ─── Run identifiers ────────────────────────────────────────────────────────
RUN_TS=$(date -u +%Y%m%dT%H%M%SZ)
RUN_ID="overnight-$RUN_TS-$$"
RUN_DIR="$LOG_ROOT/$RUN_ID"
mkdir -p "$RUN_DIR"
EVENT_LOG="$RUN_DIR/overnight.log"
STATE_FILE="$RUN_DIR/state.json"

# ─── Convergence tracking per repo ──────────────────────────────────────────
declare -A CONVERGENCE_STREAK
for repo in "${REPOS[@]}"; do
    CONVERGENCE_STREAK["$repo"]=0
done

# ─── --resume rehydration ───────────────────────────────────────────────────
if [[ -n "$RESUME_RUN_ID" ]]; then
    PRIOR_STATE="$LOG_ROOT/$RESUME_RUN_ID/state.json"
    if [[ ! -f "$PRIOR_STATE" ]]; then
        echo "factory-overnight: --resume run-id not found at $PRIOR_STATE" >&2
        exit 1
    fi
    if command -v jq &>/dev/null; then
        while IFS=$'\t' read -r repo streak; do
            if [[ -n "${CONVERGENCE_STREAK[$repo]+x}" ]]; then
                CONVERGENCE_STREAK["$repo"]="$streak"
            fi
        done < <(jq -r '.streaks | to_entries[] | "\(.key)\t\(.value)"' "$PRIOR_STATE" 2>/dev/null)
    else
        echo "factory-overnight: --resume requires jq" >&2
        exit 1
    fi
fi

# ─── --show-config: dump and exit ───────────────────────────────────────────
if $SHOW_CONFIG; then
    cat <<EOF
=== factory-overnight effective configuration ===
Run ID:             $RUN_ID
Repos (${#REPOS[@]}):
$(printf '  - %s\n' "${REPOS[@]}")
Excludes:           ${EXCLUDES[*]:-(none)}
Auto-discover dir:  ${AUTO_DISCOVER_DIR:-(none)}
Shuffle:            $SHUFFLE_REPOS
Sleep between:      ${SLEEP_SEC}s
Cycle timeout:      ${CYCLE_TIMEOUT_SEC}s
Max cycles:         ${MAX_CYCLES:-unlimited}
Max spend total:    \$$MAX_SPEND_TOTAL
Convergence rot.:   $CONVERGENCE_ROTATIONS
Round-robin:        $($NO_ROTATE && echo no || echo yes)
Verbose output:     $($QUIET && echo no || echo yes)
Heartbeat:          ${HEARTBEAT_SEC}s
Color:              $USE_COLOR
Start time:         ${START_TIME:-now} ($([ "$START_EPOCH" -gt 0 ] && date -d "@$START_EPOCH" || echo immediately))
End time:           ${END_TIME:-${DURATION:-unbounded}} ($([ "$END_EPOCH" -gt 0 ] && date -d "@$END_EPOCH" || echo unbounded))
Healthcheck URL:    ${HEALTHCHECK_URL:-(none)}
Notify specs:       ${NOTIFY_SPECS[*]:-(none)}
Resume from:        ${RESUME_RUN_ID:-(fresh)}
Fail-fast:          $FAIL_FAST
Require clean tree: $REQUIRE_CLEAN_TREE
Require remote:     $REQUIRE_REMOTE
Model override:     ${MODEL_OVERRIDE:-(default)}
Dry-run:            $DRY_RUN
Logs:               $RUN_DIR
EOF
    exit 0
fi

# ─── Lock + claude PATH check (only when we're actually going to run) ───────
if [[ -f "$LOCK_FILE" ]]; then
    LOCKED_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "?")
    echo "factory-overnight: lock file $LOCK_FILE exists (pid=$LOCKED_PID)." >&2
    echo "  If no session is actually running: rm $LOCK_FILE" >&2
    exit 1
fi

if ! $DRY_RUN && ! command -v claude &>/dev/null; then
    echo "factory-overnight: claude CLI not on PATH" >&2
    exit 1
fi

# ─── Lock + signal handling ─────────────────────────────────────────────────
CHILD_PID=""
HEARTBEAT_PID=""

cleanup() {
    [[ -n "$HEARTBEAT_PID" ]] && kill "$HEARTBEAT_PID" 2>/dev/null || true
    [[ -n "$CHILD_PID" ]] && kill "$CHILD_PID" 2>/dev/null || true
    rm -f "$LOCK_FILE" "$STATUS_FILE" "$STATUS_JSON"
}
trap cleanup EXIT

handle_signal() {
    local sig="$1"
    END_REASON="received $sig"
    log "STOP: $END_REASON (will write summary then exit)"
    [[ -n "$HEARTBEAT_PID" ]] && kill "$HEARTBEAT_PID" 2>/dev/null || true
    [[ -n "$CHILD_PID" ]] && kill -TERM "$CHILD_PID" 2>/dev/null || true
}
trap 'handle_signal SIGINT' INT
trap 'handle_signal SIGTERM' TERM

echo "$$" > "$LOCK_FILE"
rm -f "$STOP_FILE"  # clear any stale sentinel

# ─── Logging helpers ────────────────────────────────────────────────────────
log() {
    local msg="$*"
    local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s%s%s  %s\n' "$C_DIM" "$ts" "$C_RST" "$msg" | tee -a "$EVENT_LOG"
}

log_event() {
    # log() with a colored prefix — for status transitions the user wants to see
    local color="$1" tag="$2" msg="$3"
    local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s%s%s  %s%s%s %s\n' "$C_DIM" "$ts" "$C_RST" "$color" "[$tag]" "$C_RST" "$msg" | tee -a "$EVENT_LOG"
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
Pause:            touch $PAUSE_FILE
Logs:             $RUN_DIR
EOF
    write_status_json
}

write_status_json() {
    if ! command -v jq &>/dev/null; then return 0; fi
    local streaks_json="{}"
    for repo in "${REPOS[@]}"; do
        streaks_json=$(echo "$streaks_json" | jq --arg k "$repo" --argjson v "${CONVERGENCE_STREAK[$repo]:-0}" '.[$k]=$v')
    done
    jq -n \
        --arg run_id "$RUN_ID" \
        --arg started "$RUN_TS" \
        --argjson cycles "$CYCLES_DONE" \
        --argjson spend "$CUM_SPEND" \
        --arg last_cycle "${LAST_CYCLE:-}" \
        --arg last_result "${LAST_RESULT:-}" \
        --arg end_reason "${END_REASON:-running}" \
        --argjson streaks "$streaks_json" \
        --arg log_dir "$RUN_DIR" \
        '{run_id:$run_id, started:$started, cycles_done:$cycles, cum_spend:$spend, last_cycle:$last_cycle, last_result:$last_result, end_reason:$end_reason, streaks:$streaks, log_dir:$log_dir}' \
        > "$STATUS_JSON" 2>/dev/null || true
    cp "$STATUS_JSON" "$STATE_FILE" 2>/dev/null || true
}

# ─── Healthcheck pings ──────────────────────────────────────────────────────
healthcheck_ping() {
    [[ -z "$HEALTHCHECK_URL" ]] && return 0
    local suffix="${1:-}"  # /start, /<rc>, or empty for default ping
    local url="$HEALTHCHECK_URL${suffix:+/$suffix}"
    if command -v curl &>/dev/null; then
        curl -fsS -m 10 --retry 3 -o /dev/null "$url" 2>/dev/null || true
    fi
}

# ─── End-of-run notifications ───────────────────────────────────────────────
send_notification() {
    [[ ${#NOTIFY_SPECS[@]} -eq 0 ]] && return 0
    local subject="factory-overnight $RUN_ID ended"
    local body
    body=$(printf 'End reason: %s\nCycles: %s\nSpend: $%s\nRepos: %s\nLogs: %s' \
        "${END_REASON:-unknown}" "$CYCLES_DONE" "$CUM_SPEND" "${REPOS[*]}" "$RUN_DIR")
    for spec in "${NOTIFY_SPECS[@]}"; do
        case "$spec" in
            webhook=*)
                local url="${spec#webhook=}"
                if command -v curl &>/dev/null; then
                    curl -fsS -m 30 -X POST -H 'Content-Type: application/json' \
                        --data "$(jq -n --arg s "$subject" --arg b "$body" '{subject:$s, body:$b}')" \
                        "$url" -o /dev/null 2>/dev/null \
                        && log_event "$C_GRN" "notify" "webhook posted: $url" \
                        || log_event "$C_YLW" "notify" "webhook failed: $url"
                fi
                ;;
            ntfy=*)
                local topic="${spec#ntfy=}"
                if command -v curl &>/dev/null; then
                    curl -fsS -m 30 \
                        -H "Title: $subject" \
                        -d "$body" \
                        "https://ntfy.sh/$topic" -o /dev/null 2>/dev/null \
                        && log_event "$C_GRN" "notify" "ntfy posted: $topic" \
                        || log_event "$C_YLW" "notify" "ntfy failed: $topic"
                fi
                ;;
            desktop)
                if command -v notify-send &>/dev/null; then
                    notify-send "$subject" "$body" 2>/dev/null || true
                elif command -v osascript &>/dev/null; then
                    osascript -e "display notification \"$body\" with title \"$subject\"" 2>/dev/null || true
                elif command -v msg.exe &>/dev/null; then
                    msg.exe '*' "$subject — $body" 2>/dev/null || true
                fi
                log_event "$C_GRN" "notify" "desktop notification sent"
                ;;
            *)
                log_event "$C_YLW" "notify" "unknown notify spec: $spec"
                ;;
        esac
    done
}

# ─── Cycle math helpers ─────────────────────────────────────────────────────
cycles_remaining() {
    if [[ "$MAX_CYCLES" -gt 0 ]]; then
        echo "$(( MAX_CYCLES - CYCLES_DONE ))"
        return
    fi
    local floor_sec="${OVERNIGHT_EST_CYCLE_SEC:-600}"
    if [[ "${END_EPOCH:-0}" -gt 0 ]]; then
        local now=$(date +%s)
        local est_cycle=$(( SLEEP_SEC + floor_sec ))
        local rem=$(( (END_EPOCH - now) / est_cycle ))
        (( rem < 1 )) && rem=1
        (( rem > 20 )) && rem=20
        echo "$rem"
    else
        echo "20"
    fi
}

spend_remaining() {
    awk -v t="$MAX_SPEND_TOTAL" -v s="$CUM_SPEND" 'BEGIN { printf "%.2f", t - s }'
}

# ─── Heartbeat (background loop while a cycle is running) ───────────────────
start_heartbeat() {
    [[ "$HEARTBEAT_SEC" -le 0 ]] && return 0
    local cycle="$1" repo="$2" start_epoch="$3"
    (
        while sleep "$HEARTBEAT_SEC"; do
            local elapsed=$(( $(date +%s) - start_epoch ))
            printf '%s[heartbeat]%s cycle %s | %s | running %ds\n' \
                "$C_BLU" "$C_RST" "$cycle" "$(basename "$repo")" "$elapsed" >&2
        done
    ) &
    HEARTBEAT_PID=$!
}

stop_heartbeat() {
    [[ -n "$HEARTBEAT_PID" ]] && kill "$HEARTBEAT_PID" 2>/dev/null || true
    HEARTBEAT_PID=""
}

# ─── Main loop ──────────────────────────────────────────────────────────────
CYCLES_DONE=0
CUM_SPEND=0
REPO_IDX=0
LAST_CYCLE=""
LAST_RESULT=""
END_REASON=""

write_status

# Banner — give the user a clear "I'm starting" signal even before cycle 1.
printf '\n%s━━━ factory-overnight starting ━━━%s\n' "$C_BOLD" "$C_RST"
log "Run ID:           $RUN_ID"
log "Repos (${#REPOS[@]}):    $(printf '%s ' "${REPOS[@]}")"
log "Until:            ${END_EPOCH:-unbounded} ($([ "$END_EPOCH" -gt 0 ] && date -d "@$END_EPOCH" || echo unbounded))"
log "Max cycles:       ${MAX_CYCLES:-unlimited}"
log "Max spend total:  \$$MAX_SPEND_TOTAL"
log "Sleep:            ${SLEEP_SEC}s"
log "Cycle timeout:    ${CYCLE_TIMEOUT_SEC}s"
log "Convergence rot:  $CONVERGENCE_ROTATIONS"
log "Round-robin:      $($NO_ROTATE && echo no || echo yes)"
log "Verbose output:   $($QUIET && echo no || echo yes)"
log "Heartbeat:        ${HEARTBEAT_SEC}s"
log "Dry run:          $DRY_RUN"
log ""

# ─── Delayed start ──────────────────────────────────────────────────────────
if [[ "$START_EPOCH" -gt 0 ]]; then
    NOW_EPOCH=$(date +%s)
    if [[ "$START_EPOCH" -gt "$NOW_EPOCH" ]]; then
        local_wait=$(( START_EPOCH - NOW_EPOCH ))
        log_event "$C_CYN" "delay" "waiting until $START_TIME ($local_wait s) before cycle 1"
        sleep "$local_wait"
    fi
fi

while :; do
    # ─── Stop checks ────────────────────────────────────────────────────────
    if [[ -f "$STOP_FILE" ]]; then
        END_REASON="sentinel file $STOP_FILE present"
        log_event "$C_RED" "STOP" "$END_REASON"
        rm -f "$STOP_FILE"
        break
    fi

    # If a SIGINT/SIGTERM set END_REASON, exit cleanly
    if [[ -n "$END_REASON" ]]; then
        break
    fi

    NOW_EPOCH=$(date +%s)
    if [[ "$END_EPOCH" -gt 0 && "$NOW_EPOCH" -ge "$END_EPOCH" ]]; then
        END_REASON="wall-clock end time reached"
        log_event "$C_RED" "STOP" "$END_REASON"
        break
    fi

    if [[ "$MAX_CYCLES" -gt 0 && "$CYCLES_DONE" -ge "$MAX_CYCLES" ]]; then
        END_REASON="max-cycles ($MAX_CYCLES) reached"
        log_event "$C_RED" "STOP" "$END_REASON"
        break
    fi

    REMAINING=$(spend_remaining)
    if awk "BEGIN { exit !($REMAINING <= 0) }"; then
        END_REASON="cumulative cost cap reached (\$$MAX_SPEND_TOTAL)"
        log_event "$C_RED" "STOP" "$END_REASON"
        break
    fi

    # ─── Pause sentinel — wait between cycles, don't interrupt running ─────
    if [[ -f "$PAUSE_FILE" ]]; then
        log_event "$C_YLW" "pause" "$PAUSE_FILE present — waiting (rm to resume)..."
        while [[ -f "$PAUSE_FILE" ]]; do
            sleep 5
            # Honor stop while paused
            if [[ -f "$STOP_FILE" ]]; then
                END_REASON="stopped while paused"
                log_event "$C_RED" "STOP" "$END_REASON"
                rm -f "$STOP_FILE"
                break 2
            fi
        done
        log_event "$C_GRN" "pause" "resumed"
    fi

    # ─── All repos converged? ──────────────────────────────────────────────
    ALL_CONVERGED=true
    for repo in "${REPOS[@]}"; do
        if [[ "${CONVERGENCE_STREAK[$repo]}" -lt "$CONVERGENCE_ROTATIONS" ]]; then
            ALL_CONVERGED=false
            break
        fi
    done
    if $ALL_CONVERGED; then
        END_REASON="every repo converged (no new work for $CONVERGENCE_ROTATIONS cycles each)"
        log_event "$C_GRN" "STOP" "$END_REASON"
        break
    fi

    # ─── Pick next repo (round-robin OR sequential) ────────────────────────
    if $NO_ROTATE; then
        TARGET_REPO="${REPOS[0]}"
        while [[ "${CONVERGENCE_STREAK[$TARGET_REPO]}" -ge "$CONVERGENCE_ROTATIONS" ]]; do
            REPOS=("${REPOS[@]:1}")
            if [[ ${#REPOS[@]} -eq 0 ]]; then
                END_REASON="all repos converged (no-rotate mode)"
                log_event "$C_GRN" "STOP" "$END_REASON"
                break 2
            fi
            TARGET_REPO="${REPOS[0]}"
        done
    else
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
                log_event "$C_GRN" "STOP" "$END_REASON"
                break 2
            fi
        done
    fi

    CYCLE_NUM=$(( CYCLES_DONE + 1 ))
    CYCLE_LOG="$RUN_DIR/cycle-$(printf '%03d' $CYCLE_NUM)-$(basename "$TARGET_REPO").log"

    # ─── Compute per-cycle budget ──────────────────────────────────────────
    REM=$(spend_remaining)
    CYC_REM=$(cycles_remaining)
    PER_CYCLE_BUDGET=$(awk -v r="$REM" -v c="$CYC_REM" \
        'BEGIN { b = r / (c < 1 ? 1 : c); if (b > 5) b = 5; printf "%.2f", b }')

    printf '\n%s━━━ Cycle %s ━━━%s\n' "$C_BOLD" "$CYCLE_NUM" "$C_RST"
    log "Repo:             $TARGET_REPO"
    log "Per-cycle budget: \$$PER_CYCLE_BUDGET"
    log "Streak:           ${CONVERGENCE_STREAK[$TARGET_REPO]}/$CONVERGENCE_ROTATIONS"
    log "Per-cycle log:    $CYCLE_LOG"

    # ─── Healthcheck: cycle start ──────────────────────────────────────────
    healthcheck_ping start

    # ─── Build the prompt for this cycle ───────────────────────────────────
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
        log_event "$C_CYN" "DRY-RUN" "would invoke: claude -p --max-budget-usd $PER_CYCLE_BUDGET ..."
        log_event "$C_CYN" "DRY-RUN" "cycle log: $CYCLE_LOG"
        CYCLE_RC=0
        CYCLE_OUTCOME="advanced"
        CYCLE_SPEND="0.00"
    else
        # ─── Invoke claude headlessly ──────────────────────────────────────
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

        # ─── Heartbeat + run ───────────────────────────────────────────────
        local_start=$(date +%s)
        start_heartbeat "$CYCLE_NUM" "$TARGET_REPO" "$local_start"

        # The pipefail cycle:
        #   - In verbose mode, claude output goes through tee → console + log.
        #   - In quiet mode, claude output goes to log only.
        #   - PIPESTATUS[0] preserves claude's exit code (tee always succeeds).
        if command -v timeout &>/dev/null; then
            CLAUDE_INVOCATION=( timeout --signal=TERM "${CYCLE_TIMEOUT_SEC}s"
                                claude "${CLAUDE_ARGS[@]}" )
        else
            CLAUDE_INVOCATION=( claude "${CLAUDE_ARGS[@]}" )
        fi

        if $QUIET; then
            printf '%s' "$CYCLE_PROMPT" | "${CLAUDE_INVOCATION[@]}" \
                > "$CYCLE_LOG" 2>&1 &
            CHILD_PID=$!
            wait "$CHILD_PID"
            CYCLE_RC=$?
        else
            # tee while preserving claude's exit code via PIPESTATUS
            printf '%s' "$CYCLE_PROMPT" | "${CLAUDE_INVOCATION[@]}" 2>&1 \
                | tee "$CYCLE_LOG" &
            CHILD_PID=$!
            wait "$CHILD_PID"
            # The wait gave us tee's status; recover claude's via the pipeline's PIPESTATUS
            CYCLE_RC=${PIPESTATUS[0]:-$?}
        fi
        CHILD_PID=""
        stop_heartbeat

        # ─── Read cycle outcome from state.yaml ────────────────────────────
        STATE_YAML="$TARGET_REPO/.factory/state.yaml"
        CYCLE_OUTCOME="unknown"
        if [[ -f "$STATE_YAML" ]]; then
            CYCLE_OUTCOME=$(grep -E '^cycle_outcome:' "$STATE_YAML" 2>/dev/null \
                | tail -1 | sed 's/^cycle_outcome:\s*//; s/[\"]//g' || true)
            CYCLE_OUTCOME="${CYCLE_OUTCOME:-unknown}"
        fi

        # ─── Estimate cycle spend (rough — see CHANGELOG for stream-json TODO) ─
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

    # Color-code the outcome line
    case "$CYCLE_OUTCOME" in
        advanced)   OUTCOME_COLOR="$C_GRN" ;;
        researched) OUTCOME_COLOR="$C_CYN" ;;
        no-op)      OUTCOME_COLOR="$C_YLW" ;;
        *)          OUTCOME_COLOR="$C_DIM" ;;
    esac
    log_event "$OUTCOME_COLOR" "cycle $CYCLE_NUM" \
        "rc=$CYCLE_RC outcome=$CYCLE_OUTCOME spend≈\$$CYCLE_SPEND cum=\$$CUM_SPEND"

    healthcheck_ping "$CYCLE_RC"

    # ─── Fail-fast ─────────────────────────────────────────────────────────
    if $FAIL_FAST && [[ "$CYCLE_RC" -ne 0 ]]; then
        END_REASON="fail-fast: cycle $CYCLE_NUM exited rc=$CYCLE_RC"
        log_event "$C_RED" "STOP" "$END_REASON"
        break
    fi

    # ─── Update convergence streak ─────────────────────────────────────────
    case "$CYCLE_OUTCOME" in
        advanced)   CONVERGENCE_STREAK["$TARGET_REPO"]=0 ;;
        researched) CONVERGENCE_STREAK["$TARGET_REPO"]=$(( CONVERGENCE_STREAK["$TARGET_REPO"] / 2 )) ;;
        no-op)      CONVERGENCE_STREAK["$TARGET_REPO"]=$(( CONVERGENCE_STREAK["$TARGET_REPO"] + 1 )) ;;
        *)          CONVERGENCE_STREAK["$TARGET_REPO"]=$(( CONVERGENCE_STREAK["$TARGET_REPO"] + 1 )) ;;
    esac

    # ─── Rotate to next repo (if not --no-rotate) ──────────────────────────
    if ! $NO_ROTATE; then
        REPO_IDX=$(( (REPO_IDX + 1) % ${#REPOS[@]} ))
    fi

    write_status

    # ─── Sleep before next cycle ───────────────────────────────────────────
    if [[ "$SLEEP_SEC" -gt 0 ]]; then
        log "Sleeping ${SLEEP_SEC}s before next cycle..."
        sleep "$SLEEP_SEC" &
        SLEEP_PID=$!
        wait "$SLEEP_PID" 2>/dev/null || true
    fi
done

# ─── Summary ────────────────────────────────────────────────────────────────
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

printf '\n%s━━━ factory-overnight ended ━━━%s\n' "$C_BOLD" "$C_RST"
log "End reason:       $END_REASON"
log "Cycles done:      $CYCLES_DONE"
log "Cumulative cost:  \$$CUM_SPEND"
log "Summary:          $SUMMARY_FILE"

write_status
send_notification

echo ""
echo "Summary written to $SUMMARY_FILE"
exit 0
