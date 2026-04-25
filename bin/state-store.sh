#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# state-store.sh — SQLite-backed phase checkpoint store
# ═══════════════════════════════════════════════════════════════════════════════
# Schema ported from langchain-ai/langgraph/libs/checkpoint-sqlite (MIT).
# Provides crash recovery + resume across factory runs.
#
# Usage:
#   state-store.sh init                                    # create DB if missing
#   state-store.sh save <run_id> <phase> <iter> <json>     # save a checkpoint
#   state-store.sh load <run_id> <phase> [<iter>]          # load latest (or specific)
#   state-store.sh list [<run_id>]                         # list runs / checkpoints
#   state-store.sh resume <run_id>                         # get next phase to run
#   state-store.sh prune <days>                            # delete runs older than N days
#
# Database: ${OCTOPUS_STATE_DB:-~/.factory/state.db}  (per-repo when run inside one)
# Schema:   table `checkpoints` + index on (thread_id, checkpoint_ns)
#
# Integrates with:
#   - recipe-factory-loop.md phase transitions (save after each phase end)
#   - circuit-breakers directive (load prior iteration on stop-on-regression)
#   - Large-Repo Mode (resume across runs)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

_find_db() {
    if [[ -n "${OCTOPUS_STATE_DB:-}" ]]; then
        echo "$OCTOPUS_STATE_DB"
        return
    fi
    # If inside a git repo, use repo-local .factory/state.db
    local repo_root
    if repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        echo "${repo_root}/.factory/state.db"
    else
        echo "${HOME}/.claude-octopus/state.db"
    fi
}

DB="$(_find_db)"

_require_sqlite() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "state-store: sqlite3 is required but was not found on PATH" >&2
        return 1
    fi
}

_sql_quote() {
    local value="${1-}"
    value=${value//\'/\'\'}
    printf "'%s'" "$value"
}

_sql_null_or_quote() {
    local value="${1-}"
    if [[ -z "$value" ]]; then
        printf 'NULL'
    else
        _sql_quote "$value"
    fi
}

_require_non_negative_decimal() {
    local label="$1"
    local value="$2"
    if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "state-store: ${label} must be a non-negative decimal number" >&2
        return 1
    fi
}

_require_non_negative_integer() {
    local label="$1"
    local value="$2"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "state-store: ${label} must be a non-negative integer" >&2
        return 1
    fi
}

_ensure_db() {
    _require_sqlite
    mkdir -p "$(dirname "$DB")"
    sqlite3 "$DB" <<'SQL'
CREATE TABLE IF NOT EXISTS checkpoints (
  thread_id             TEXT NOT NULL,           -- factory run_id
  checkpoint_ns         TEXT NOT NULL DEFAULT '',-- phase name (P1/W3/L2/L3/U1/T1/D1/Q3/etc.)
  checkpoint_id         TEXT NOT NULL,           -- iteration id
  parent_checkpoint_id  TEXT,                    -- prior iteration (resume chain)
  type                  TEXT DEFAULT 'json',     -- 'json' | 'msgpack'
  checkpoint            BLOB,                    -- phase state payload
  metadata              BLOB,                    -- metrics, cost, breakers, timing
  created_at            INTEGER DEFAULT (strftime('%s','now')),
  PRIMARY KEY (thread_id, checkpoint_ns, checkpoint_id)
);
CREATE INDEX IF NOT EXISTS idx_checkpoints_thread ON checkpoints(thread_id, created_at);
CREATE INDEX IF NOT EXISTS idx_checkpoints_phase  ON checkpoints(checkpoint_ns, created_at);

CREATE TABLE IF NOT EXISTS runs (
  run_id       TEXT PRIMARY KEY,
  repo_path    TEXT,
  mode         TEXT,                             -- orchestrated | single-session | large-repo
  started_at   INTEGER DEFAULT (strftime('%s','now')),
  ended_at     INTEGER,
  status       TEXT DEFAULT 'running',           -- running | completed | halted | crashed
  total_cost   REAL DEFAULT 0.0
);
SQL
}

cmd_init() {
    _ensure_db
    echo "initialized: $DB"
}

cmd_save() {
    local run_id="${1:?usage: save <run_id> <phase> <iter> <json-payload>}"
    local phase="${2:?}"
    local iter="${3:?}"
    local payload
    local parent="${5:-}"
    local quoted_parent

    if [[ $# -ge 4 ]]; then
        payload="$4"
    else
        payload="{}"
    fi

    _ensure_db
    quoted_parent="$(_sql_null_or_quote "$parent")"
    sqlite3 "$DB" <<SQL
INSERT OR REPLACE INTO runs (run_id, repo_path, status)
VALUES ($(_sql_quote "$run_id"), $(_sql_quote "$PWD"), 'running');

INSERT OR REPLACE INTO checkpoints
  (thread_id, checkpoint_ns, checkpoint_id, parent_checkpoint_id, type, checkpoint)
VALUES
  ($(_sql_quote "$run_id"), $(_sql_quote "$phase"), $(_sql_quote "$iter"),
   ${quoted_parent},
   'json', $(_sql_quote "$payload"));
SQL
    echo "saved: ${run_id}/${phase}/${iter}"
}

cmd_load() {
    local run_id="${1:?usage: load <run_id> <phase> [<iter>]}"
    local phase="${2:?}"
    local iter="${3:-}"

    _ensure_db
    if [[ -n "$iter" ]]; then
        sqlite3 "$DB" "SELECT checkpoint FROM checkpoints WHERE thread_id=$(_sql_quote "$run_id") AND checkpoint_ns=$(_sql_quote "$phase") AND checkpoint_id=$(_sql_quote "$iter");"
    else
        sqlite3 "$DB" "SELECT checkpoint FROM checkpoints WHERE thread_id=$(_sql_quote "$run_id") AND checkpoint_ns=$(_sql_quote "$phase") ORDER BY created_at DESC LIMIT 1;"
    fi
}

cmd_list() {
    _ensure_db
    local run_id="${1:-}"
    if [[ -n "$run_id" ]]; then
        echo "=== checkpoints for run ${run_id} ==="
        sqlite3 -header -column "$DB" <<SQL
SELECT checkpoint_ns AS phase, checkpoint_id AS iter,
       datetime(created_at, 'unixepoch') AS at,
       length(checkpoint) AS bytes
FROM checkpoints WHERE thread_id=$(_sql_quote "$run_id")
ORDER BY created_at;
SQL
    else
        echo "=== all runs ==="
        sqlite3 -header -column "$DB" <<SQL
SELECT run_id, status, mode,
       datetime(started_at, 'unixepoch') AS started,
       CASE WHEN ended_at IS NULL THEN '-'
            ELSE datetime(ended_at, 'unixepoch') END AS ended,
       printf('$%.2f', total_cost) AS cost,
       (SELECT COUNT(*) FROM checkpoints WHERE thread_id=runs.run_id) AS checkpoints
FROM runs ORDER BY started_at DESC LIMIT 20;
SQL
    fi
}

cmd_resume() {
    local run_id="${1:?usage: resume <run_id>}"
    _ensure_db
    # Return the last phase that completed, so caller knows where to pick up
    sqlite3 "$DB" "SELECT checkpoint_ns || '/' || checkpoint_id FROM checkpoints WHERE thread_id=$(_sql_quote "$run_id") ORDER BY created_at DESC LIMIT 1;"
}

cmd_complete() {
    local run_id="${1:?usage: complete <run_id> [cost]}"
    local cost="${2:-0}"
    _require_non_negative_decimal "cost" "$cost"
    _ensure_db
    sqlite3 "$DB" "UPDATE runs SET status='completed', ended_at=strftime('%s','now'), total_cost=${cost} WHERE run_id=$(_sql_quote "$run_id");"
    echo "completed: ${run_id}"
}

cmd_prune() {
    local days="${1:-30}"
    _require_non_negative_integer "days" "$days"
    _ensure_db
    local cutoff=$(( $(date +%s) - days * 86400 ))
    local deleted
    deleted=$(sqlite3 "$DB" "SELECT COUNT(*) FROM runs WHERE started_at < ${cutoff};")
    sqlite3 "$DB" <<SQL
DELETE FROM checkpoints WHERE thread_id IN (SELECT run_id FROM runs WHERE started_at < ${cutoff});
DELETE FROM runs WHERE started_at < ${cutoff};
VACUUM;
SQL
    echo "pruned ${deleted} runs older than ${days} days"
}

cmd_help() {
    sed -n '2,25p' "$0" | sed 's/^# \?//'
}

case "${1:-help}" in
    init)     shift; cmd_init "$@" ;;
    save)     shift; cmd_save "$@" ;;
    load)     shift; cmd_load "$@" ;;
    list)     shift; cmd_list "$@" ;;
    resume)   shift; cmd_resume "$@" ;;
    complete) shift; cmd_complete "$@" ;;
    prune)    shift; cmd_prune "$@" ;;
    help|-h|--help) cmd_help ;;
    *) echo "unknown command: $1" >&2; cmd_help; exit 1 ;;
esac
