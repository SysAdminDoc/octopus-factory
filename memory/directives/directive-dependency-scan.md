---
name: Dependency & CVE Scan Directive
description: Dependency vulnerability scan referenced by factory loop pre-postflight phase D1/D2. Runs language-appropriate CVE audit, fixes high + critical, documents deferred lows. Load lazily — only when the dependency phase is running.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
---
# Dependency & CVE Scan Directive

Referenced by factory-loop D1 (codex) and D2 (claude counter-pass). Runs once per factory run, between the theming phase and the postflight release.

## Gate

Skip if no dependency manifest exists (pure scripts, docs-only repos). Otherwise always runs — CVE exposure is never an acceptable ship state.

## Language-appropriate scan

Run the scan matching the repo's primary package manager. If multiple exist (e.g., Rust + Node for a Tauri app), run each.

| Manifest | Command | Notes |
|---|---|---|
| `package.json` / `package-lock.json` | `rtk npm audit --audit-level=high` | Focus on high + critical |
| `yarn.lock` | `rtk yarn npm audit --severity high` | |
| `pnpm-lock.yaml` | `rtk pnpm audit --audit-level=high` | |
| `Cargo.toml` / `Cargo.lock` | `rtk cargo audit` | Install via `cargo install cargo-audit` if missing |
| `*.csproj` / `packages.config` | `rtk dotnet list package --vulnerable --include-transitive` | |
| `requirements.txt` / `pyproject.toml` | `rtk pip-audit` or `rtk safety check` | |
| `go.mod` / `go.sum` | `rtk govulncheck ./...` | |
| `Gemfile` / `Gemfile.lock` | `rtk bundle-audit check --update` | |
| `composer.json` | `rtk composer audit` | |
| `build.gradle` / `build.gradle.kts` | `rtk gradle dependencyCheckAnalyze` (OWASP plugin) | Android / JVM |

## Fix policy

**Critical + High:** must fix before release. Update to patched version. If no patched version exists, pin to known-safe alternative, add workaround, or document why the vulnerability is non-exploitable in this context.

**Medium:** fix if patch exists and update is non-breaking. Otherwise defer to changelog with target date.

**Low / informational:** defer to changelog unless trivial to fix.

## Non-negotiable rules

- **Never `--force` a vulnerable version back in** — if an update breaks, fix the breakage or find an alternative package.
- **Never disable the scanner** or add ignore rules without explicit rationale in a committed `.audit-ignore` / `deny.toml` / equivalent with a reference link (CVE ID or advisory URL) and an expiry date.
- **Transitive deps count** — a direct dep with a safe version but a vulnerable transitive child still fails the gate.
- **Ship-blockers:** any unpatched critical in the final dependency graph halts the release.

## Output

A short report at `docs/security/dependency-scan-<date>.md`:

```markdown
# Dependency Scan — <date>

## Fixed this pass
- <pkg> <old> → <new> (CVE-YYYY-NNNNN, severity)

## Deferred
- <pkg> <version> (CVE-YYYY-NNNNN, severity) — reason, expiry

## Clean
- <count> packages scanned, <count> clean
```

Commit as `deps: CVE audit + fixes (YYYY-MM-DD)`.
