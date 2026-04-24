#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# secret-scan.sh — Gitleaks-backed pre-commit secret detection
# ═══════════════════════════════════════════════════════════════════════════════
# Replaces the regex-based implementation in directive-secret-scan.md with the
# industry-standard scanner. One binary, TOML config, curated ruleset covering
# 160+ secret patterns with far fewer false positives than hand-rolled regexes.
#
# Source: https://github.com/gitleaks/gitleaks (MIT)
#
# Modes:
#   secret-scan.sh staged                       # scan staged diff only (commit gate)
#   secret-scan.sh dir [<path>]                 # scan working tree (default: .)
#   secret-scan.sh git [<path>]                 # scan full git history
#   secret-scan.sh pre-commit                   # install as pre-commit hook
#   secret-scan.sh install                      # install gitleaks binary
#
# Exit codes:
#   0  clean
#   1  secrets found (commit halts)
#   2  gitleaks not installed
#   3  allowance file present; user must resolve manually
#
# Config: .factory/gitleaks.toml (generated on first run, user-editable)
# Report: .factory/gitleaks-report.json (JSON, one entry per finding)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FACTORY_DIR="${REPO_ROOT}/.factory"
CONFIG="${FACTORY_DIR}/gitleaks.toml"
REPORT="${FACTORY_DIR}/gitleaks-report.json"

_have_gitleaks() { command -v gitleaks &>/dev/null; }

cmd_install() {
    if _have_gitleaks; then
        echo "already installed: $(gitleaks version 2>&1 | head -1)"
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
        x86_64|amd64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
    esac

    # Try package managers first (cleanest); fall back to GitHub release tarball
    if command -v brew &>/dev/null; then
        brew install gitleaks
    elif command -v apt-get &>/dev/null; then
        # Debian/Ubuntu: via go-install or direct release download
        echo "apt doesn't package gitleaks; downloading release binary"
        _download_release "$os" "$arch"
    elif command -v scoop &>/dev/null; then
        scoop install gitleaks
    elif command -v choco &>/dev/null; then
        choco install gitleaks
    else
        _download_release "$os" "$arch"
    fi

    gitleaks version 2>&1 | head -1
}

_download_release() {
    local os="$1"
    local arch="$2"
    local latest
    latest=$(curl -sL https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep -oE '"tag_name":\s*"v[0-9.]+' | grep -oE '[0-9.]+' | head -1)
    [[ -z "$latest" ]] && { echo "could not resolve latest gitleaks version" >&2; return 2; }

    local url="https://github.com/gitleaks/gitleaks/releases/download/v${latest}/gitleaks_${latest}_${os}_${arch}.tar.gz"
    local tmp
    tmp=$(mktemp -d)
    curl -sL "$url" | tar -xz -C "$tmp"

    local dest="${HOME}/.local/bin"
    mkdir -p "$dest"
    mv "${tmp}/gitleaks" "${dest}/gitleaks" 2>/dev/null || mv "${tmp}/gitleaks.exe" "${dest}/gitleaks.exe"
    chmod +x "${dest}/gitleaks"* 2>/dev/null

    echo "installed to: ${dest}/gitleaks"
    echo "ensure ${dest} is on your PATH"
    rm -rf "$tmp"
}

_ensure_config() {
    mkdir -p "$FACTORY_DIR"
    if [[ -f "$CONFIG" ]]; then return 0; fi

    # Generate a minimal config that extends gitleaks defaults + adds octopus-factory specifics
    cat > "$CONFIG" <<'TOML'
# octopus-factory gitleaks config
# Extends the default gitleaks ruleset with project-specific additions.
# Edit this file to add allowances for known-safe patterns.

[extend]
useDefault = true

# Project-specific allowances (add regex patterns here to skip matches)
[allowlist]
description = "octopus-factory allowances"
paths = [
    '''\.factory/gitleaks-report\.json$''',         # our own report file
    '''(^|/)tests?/fixtures?/''',                    # test fixtures often contain fake secrets
    '''(^|/)(examples?|samples?)/''',                # example/sample dirs
    '''directive-secret-scan\.md$''',                # documents the patterns themselves
    '''\.md$'''                                      # markdown docs may reference patterns
]

# Add project-specific rules here. Example:
# [[rules]]
# id = "custom-internal-token"
# description = "Internal token format"
# regex = '''OCTO_[A-Z0-9]{32}'''
# tags = ["octopus-factory", "internal"]
TOML
    echo "generated config: $CONFIG"
}

cmd_staged() {
    _have_gitleaks || { echo "gitleaks not installed; run: secret-scan.sh install" >&2; exit 2; }
    _ensure_config

    # gitleaks protect = scan staged changes (pre-commit mode)
    if gitleaks protect --staged \
        --config="$CONFIG" \
        --report-format json \
        --report-path "$REPORT" \
        --exit-code 1 \
        --no-banner \
        --verbose 2>&1 | tail -20; then
        echo "SECRET SCAN: staged diff clean"
        return 0
    else
        local count
        count=$(jq 'length' "$REPORT" 2>/dev/null || echo "?")
        echo "SECRET SCAN: ${count} findings in staged diff — commit BLOCKED" >&2
        echo "  report: $REPORT" >&2
        echo "  resolve: remove the secrets from staged files and re-stage," >&2
        echo "  OR add an allowance to $CONFIG [allowlist] and re-run." >&2
        return 1
    fi
}

cmd_dir() {
    local path="${1:-$REPO_ROOT}"
    _have_gitleaks || { echo "gitleaks not installed; run: secret-scan.sh install" >&2; exit 2; }
    _ensure_config

    if gitleaks dir "$path" \
        --config="$CONFIG" \
        --report-format json \
        --report-path "$REPORT" \
        --exit-code 1 \
        --no-banner 2>&1 | tail -10; then
        echo "SECRET SCAN: directory clean"
        return 0
    else
        local count
        count=$(jq 'length' "$REPORT" 2>/dev/null || echo "?")
        echo "SECRET SCAN: ${count} findings in directory $path" >&2
        return 1
    fi
}

cmd_git() {
    local path="${1:-$REPO_ROOT}"
    _have_gitleaks || { echo "gitleaks not installed; run: secret-scan.sh install" >&2; exit 2; }
    _ensure_config

    # Scan full git history — used before publishing / major audits
    gitleaks git "$path" \
        --config="$CONFIG" \
        --report-format json \
        --report-path "$REPORT" \
        --exit-code 1 \
        --no-banner 2>&1 | tail -15 || {
        local count
        count=$(jq 'length' "$REPORT" 2>/dev/null || echo "?")
        echo "SECRET SCAN: ${count} findings in git history" >&2
        echo "  Consider running the AI-scrub recipe or git-filter-repo to purge" >&2
        return 1
    }
    echo "SECRET SCAN: git history clean"
}

cmd_pre_commit() {
    local hook_dir
    hook_dir="$(git rev-parse --git-path hooks)"
    local hook="${hook_dir}/pre-commit"

    if [[ -f "$hook" ]] && grep -q "octopus-factory secret-scan" "$hook" 2>/dev/null; then
        echo "pre-commit hook already installed"
        return 0
    fi

    cat >> "$hook" <<'EOF'
#!/usr/bin/env bash
# octopus-factory secret-scan pre-commit hook
if [[ -x "${HOME}/.claude-octopus/bin/secret-scan.sh" ]]; then
    "${HOME}/.claude-octopus/bin/secret-scan.sh" staged
elif command -v gitleaks &>/dev/null; then
    gitleaks protect --staged --exit-code 1 --no-banner
fi
EOF
    chmod +x "$hook"
    echo "installed pre-commit hook: $hook"
}

cmd_help() {
    sed -n '2,25p' "$0" | sed 's/^# \?//'
}

case "${1:-help}" in
    staged)     shift; cmd_staged "$@" ;;
    dir)        shift; cmd_dir "$@" ;;
    git)        shift; cmd_git "$@" ;;
    pre-commit) shift; cmd_pre_commit "$@" ;;
    install)    shift; cmd_install "$@" ;;
    help|-h|--help) cmd_help ;;
    *) echo "unknown command: $1" >&2; cmd_help; exit 1 ;;
esac
