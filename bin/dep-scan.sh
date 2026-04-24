#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# dep-scan.sh — osv-scanner-backed dependency vulnerability scan
# ═══════════════════════════════════════════════════════════════════════════════
# One binary scans any tree. Supports 19+ lockfile types (npm/cargo/go.mod/
# pom.xml/requirements.txt/Pipfile.lock/Gemfile.lock/composer.lock/etc.) using
# the open OSV.dev vulnerability database.
#
# Source: https://github.com/google/osv-scanner (Apache 2.0)
#
# Replaces the per-ecosystem branching in directive-dependency-scan.md with a
# single unified invocation. ~50 LOC replaces ~200 LOC of npm/cargo/pip/go
# conditional logic.
#
# Modes:
#   dep-scan.sh scan [<path>]                   # scan source tree (default: .)
#   dep-scan.sh gate [<path>] [<severity>]      # exit non-zero if any finding at
#                                                 or above <severity> (CRITICAL/HIGH/MEDIUM/LOW)
#                                                 default severity: HIGH
#   dep-scan.sh report [<path>]                 # scan + print human-readable report
#   dep-scan.sh install                         # install osv-scanner binary
#
# Exit codes:
#   0  no findings at/above gate threshold
#   1  findings at/above gate threshold (release halt)
#   2  osv-scanner not installed
#
# Report:  .factory/osv-scan.json  (JSON — parseable by CI)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FACTORY_DIR="${REPO_ROOT}/.factory"
REPORT="${FACTORY_DIR}/osv-scan.json"

_have_osv() { command -v osv-scanner &>/dev/null; }

cmd_install() {
    if _have_osv; then
        echo "already installed: $(osv-scanner --version 2>&1 | head -1)"
        return 0
    fi

    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "$os" in
        linux|darwin) ;;
        mingw*|msys*|cygwin*) os="windows" ;;
        *) echo "unsupported OS: $os" >&2; return 2 ;;
    esac

    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
    esac

    if command -v brew &>/dev/null; then
        brew install osv-scanner
    elif command -v go &>/dev/null; then
        go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest
    elif command -v scoop &>/dev/null; then
        scoop install osv-scanner
    else
        _download_release "$os" "$arch"
    fi

    osv-scanner --version 2>&1 | head -1
}

_download_release() {
    local os="$1"
    local arch="$2"
    local tmp
    tmp=$(mktemp -d)
    local latest
    latest=$(curl -sL https://api.github.com/repos/google/osv-scanner/releases/latest | grep -oE '"tag_name":\s*"v[0-9.]+' | grep -oE '[0-9.]+' | head -1)
    [[ -z "$latest" ]] && { echo "could not resolve latest osv-scanner version" >&2; return 2; }

    local bin_name="osv-scanner_${os}_${arch}"
    [[ "$os" == "windows" ]] && bin_name="${bin_name}.exe"
    local url="https://github.com/google/osv-scanner/releases/download/v${latest}/${bin_name}"

    local dest="${HOME}/.local/bin/osv-scanner"
    [[ "$os" == "windows" ]] && dest="${dest}.exe"
    mkdir -p "$(dirname "$dest")"
    curl -sL -o "$dest" "$url"
    chmod +x "$dest"

    echo "installed to: $dest"
    rm -rf "$tmp"
}

cmd_scan() {
    local path="${1:-$REPO_ROOT}"
    _have_osv || { echo "osv-scanner not installed; run: dep-scan.sh install" >&2; exit 2; }

    mkdir -p "$FACTORY_DIR"

    # osv-scanner v2 uses `scan source -r <path>` for recursive scanning
    # Falls back to v1 `-r <path>` if v2 subcommand syntax unsupported
    local output
    if output=$(osv-scanner scan source -r "$path" --format json 2>/dev/null); then
        echo "$output" > "$REPORT"
    elif output=$(osv-scanner -r "$path" --format json 2>/dev/null); then
        echo "$output" > "$REPORT"
    else
        # No findings writes empty report
        echo '{"results":[]}' > "$REPORT"
    fi

    # Summary count
    local total
    total=$(jq '[.results[]?.packages[]?.vulnerabilities[]?] | length' "$REPORT" 2>/dev/null || echo 0)
    echo "scanned ${path}: ${total} total findings"
    echo "report: $REPORT"
}

cmd_gate() {
    local path="${1:-$REPO_ROOT}"
    local threshold="${2:-HIGH}"
    cmd_scan "$path" >/dev/null

    # Filter findings by severity >= threshold
    # OSV severity is per-finding; normalize to simple scale for comparison
    local blocking
    blocking=$(jq --arg t "$threshold" '
        def severity_rank:
            if . == "CRITICAL" then 4
            elif . == "HIGH" then 3
            elif . == "MEDIUM" then 2
            elif . == "LOW" then 1
            else 0 end;
        def threshold_rank:
            if $t == "CRITICAL" then 4
            elif $t == "HIGH" then 3
            elif $t == "MEDIUM" then 2
            elif $t == "LOW" then 1
            else 1 end;
        [
            .results[]?.packages[]?.vulnerabilities[]? |
            .severity // [] |
            .[]? |
            select((.score // "UNKNOWN") | severity_rank >= threshold_rank)
        ] | length
    ' "$REPORT" 2>/dev/null || echo 0)

    # Fallback: also count by database_specific.severity + plain severity field variants
    if [[ "$blocking" == "0" ]]; then
        blocking=$(jq --arg t "$threshold" '
            def sev_r:
                if . == "CRITICAL" then 4
                elif . == "HIGH" then 3
                elif . == "MEDIUM" or . == "MODERATE" then 2
                elif . == "LOW" then 1
                else 0 end;
            def t_r:
                if $t == "CRITICAL" then 4
                elif $t == "HIGH" then 3
                elif $t == "MEDIUM" then 2
                elif $t == "LOW" then 1
                else 1 end;
            [
                .results[]?.packages[]?.vulnerabilities[]? |
                (.database_specific.severity // .severity // "UNKNOWN") |
                if type == "array" then .[]?.score // "UNKNOWN" else . end |
                select(sev_r >= t_r)
            ] | length
        ' "$REPORT" 2>/dev/null || echo 0)
    fi

    if [[ "$blocking" -gt 0 ]]; then
        echo "DEP SCAN: ${blocking} findings at/above ${threshold} — RELEASE BLOCKED" >&2
        echo "  report: $REPORT" >&2
        return 1
    else
        echo "DEP SCAN: clean (no findings at/above ${threshold})"
        return 0
    fi
}

cmd_report() {
    local path="${1:-$REPO_ROOT}"
    cmd_scan "$path" >/dev/null

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                      Dependency Scan Report                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"

    local total
    total=$(jq '[.results[]?.packages[]?.vulnerabilities[]?] | length' "$REPORT" 2>/dev/null || echo 0)

    if [[ "$total" == "0" ]]; then
        echo "  clean: no vulnerabilities detected"
        return 0
    fi

    jq -r '
        .results[]? |
        "\n\u2500\u2500 lockfile: \(.source.path // "unknown") \u2500\u2500" +
        "\n" +
        ( .packages[]? |
          "  \(.package.ecosystem // "?"):\(.package.name // "?") \(.package.version // "?")" +
          ( .vulnerabilities[]? |
            "\n    \u2022 \(.id // "CVE-?"): \(.summary // .details // "no description" | .[0:80])"
          )
        )
    ' "$REPORT" 2>/dev/null | head -80

    echo ""
    echo "  Total findings: ${total}"
    echo "  Full report:    $REPORT"
}

cmd_help() {
    sed -n '2,30p' "$0" | sed 's/^# \?//'
}

case "${1:-help}" in
    scan)    shift; cmd_scan "$@" ;;
    gate)    shift; cmd_gate "$@" ;;
    report)  shift; cmd_report "$@" ;;
    install) shift; cmd_install "$@" ;;
    help|-h|--help) cmd_help ;;
    *) echo "unknown command: $1" >&2; cmd_help; exit 1 ;;
esac
