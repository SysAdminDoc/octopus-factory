---
name: Secret Scan Directive
description: Pre-commit secret leak scan referenced by factory loop L7 + U* + T* + every commit gate. Greps the staged diff for API keys, tokens, private keys, .env contents, and common secret patterns. Halts the commit on match. Load lazily — only when a commit is about to be made.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
triggers: [secret, leak, api key, credential, .env, pat, token, private key]
agents: [orchestrator, critic]
---
# Secret Scan Directive

Referenced by every commit gate in the factory loop (L7, U* commits, T* commits, D* commits, Q* commits). Runs **before every `rtk git commit`**. Halts the commit on any match.

## What to check

Staged diff only (not the working tree — unstaged noise doesn't matter). Use `rtk git diff --cached --no-color`.

## Patterns (case-sensitive where indicated)

| Pattern | Matches | Example |
|---|---|---|
| `sk-[a-zA-Z0-9_-]{20,}` | OpenAI classic key | `sk-abc123...` |
| `sk-proj-[a-zA-Z0-9_-]{20,}` | OpenAI project key | `sk-proj-...` |
| `sk-ant-[a-zA-Z0-9_-]{20,}` | Anthropic API key | `sk-ant-...` |
| `ghp_[a-zA-Z0-9]{36}` | GitHub classic PAT | `ghp_...` |
| `github_pat_[a-zA-Z0-9_]{80,}` | GitHub fine-grained PAT | `github_pat_...` |
| `gho_[a-zA-Z0-9]{36}` | GitHub OAuth token | `gho_...` |
| `ghs_[a-zA-Z0-9]{36}` | GitHub server-to-server | `ghs_...` |
| `AKIA[0-9A-Z]{16}` | AWS access key ID | `AKIA...` |
| `AIza[0-9A-Za-z_-]{35}` | Google API key | `AIza...` |
| `ya29\.[0-9A-Za-z_-]+` | Google OAuth access token | `ya29....` |
| `xox[baprs]-[0-9a-zA-Z-]{10,}` | Slack token | `xoxb-...` |
| `glpat-[0-9a-zA-Z_-]{20}` | GitLab PAT | `glpat-...` |
| `npm_[a-zA-Z0-9]{36}` | npm token | `npm_...` |
| `dop_v1_[a-f0-9]{64}` | DigitalOcean token | `dop_v1_...` |
| `-----BEGIN [A-Z ]*PRIVATE KEY-----` | PEM-format private key | RSA/OpenSSH |
| `"password"\s*[:=]\s*"[^"]{8,}"` | Literal password strings | only if non-placeholder |

## Additional checks

- **File-type triggers:** halt if the diff adds any of these (regardless of pattern match): `.env`, `.env.local`, `.env.production`, `.pem`, `.p12`, `.pfx`, `.jks`, `.keystore`, `credentials.json`, `service-account*.json`, `*.kdbx`, `*.kdb`, `id_rsa`, `id_ed25519`, `id_ecdsa`.
- **High-entropy strings:** any staged string longer than 40 characters with Shannon entropy > 4.5 AND not matching a known-safe pattern (git hash, uuid, lock-file hash). Flag for review, don't auto-halt.

## Behavior on match

1. **Halt the commit** — do not stage, do not retry with `--no-verify`.
2. **Print the matching file + line + redacted match** to stderr.
3. **Offer three paths**:
   - Remove the secret from the diff → re-stage → re-run the scan.
   - Add the file/line to `.gitignore` if it's a local-only file that was accidentally staged.
   - If the match is a false positive (e.g., a regex in security-scan code itself), add an `# secret-scan: allow <reason>` comment on the line; scanner respects inline allowances.
4. **Never bypass** without the user explicitly typing the allowance or fixing the diff.

## Implementation sketch

```bash
secret_scan() {
    local diff
    diff=$(rtk git diff --cached --no-color)
    [[ -z "$diff" ]] && return 0

    local -a patterns=(
        'sk-[a-zA-Z0-9_-]{20,}'
        'sk-proj-[a-zA-Z0-9_-]{20,}'
        'sk-ant-[a-zA-Z0-9_-]{20,}'
        'ghp_[a-zA-Z0-9]{36}'
        'github_pat_[a-zA-Z0-9_]{80,}'
        'gho_[a-zA-Z0-9]{36}'
        'ghs_[a-zA-Z0-9]{36}'
        'AKIA[0-9A-Z]{16}'
        'AIza[0-9A-Za-z_-]{35}'
        'ya29\.[0-9A-Za-z_-]+'
        'xox[baprs]-[0-9a-zA-Z-]{10,}'
        'glpat-[0-9a-zA-Z_-]{20}'
        'npm_[a-zA-Z0-9]{36}'
        'dop_v1_[a-f0-9]{64}'
        '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    )

    for p in "${patterns[@]}"; do
        if echo "$diff" | grep -qE "$p"; then
            echo "SECRET SCAN: pattern /$p/ matched in staged diff — halting commit" >&2
            echo "$diff" | grep -nE "$p" | head -5 | sed 's/\(sk-[a-zA-Z0-9_-]\{8\}\).*/\1.../' >&2
            return 1
        fi
    done

    local -a forbidden_files=(
        '\.env$' '\.env\.local$' '\.env\.production$'
        '\.pem$' '\.p12$' '\.pfx$' '\.jks$' '\.keystore$'
        'credentials\.json$' 'service-account.*\.json$'
        '\.kdbx$' '\.kdb$'
        '(^|/)id_rsa$' '(^|/)id_ed25519$' '(^|/)id_ecdsa$'
    )
    local added_files
    added_files=$(rtk git diff --cached --name-only --diff-filter=A)
    for f in "${forbidden_files[@]}"; do
        if echo "$added_files" | grep -qE "$f"; then
            echo "SECRET SCAN: sensitive file type matched /$f/ — halting commit" >&2
            echo "$added_files" | grep -E "$f" >&2
            return 1
        fi
    done

    return 0
}
```

## Gate wiring

The factory-loop invocations MUST call `secret_scan` (or an equivalent invocation) before every `rtk git commit`. If the scan returns non-zero, the loop:

1. Aborts the commit.
2. Logs the incident to the session log.
3. Surfaces the finding to the user (if interactive) or halts the run (if autonomous and the allowance isn't already on file).

This gate is non-negotiable and applies to L7, U* commits, T* commits, D* commits, and the Q3 release commit.
