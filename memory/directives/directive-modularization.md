---
name: Modularization Directive
description: Decompose monolithic codebases into well-organized modules with clear seams, single responsibility, and explicit boundaries. Referenced by factory loop M-phase. Behavior-preserving — no functional changes, structural only.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
---
# Modularization Directive

Referenced by factory-loop M-phase (modularization, runs once after main loop, before UX/theming/dep-scan/postflight). Decomposes monolithic code into maintainable modules without changing functionality.

## Why

Monolithic files (>1000 LOC), fat classes, god-objects, and shotgun-surgery-prone modules slow every future iteration. Every audit, every UX pass, every refactor pays the monolith tax. A focused modularization pass that runs periodically (rotated, like UX/theming/dep) keeps the codebase navigable as it grows.

This directive is **behavior-preserving by mandate**. No new features, no API changes, no logic changes. Only structural reorganization with verified equivalence (tests must pass identically before and after).

## Gate

Skip the M-phase if:

- Repo is small (< 5K LOC) — modularization premium not worth it
- Repo already has good module structure (heuristic: average file size < 300 LOC, no file > 800 LOC, clear directory hierarchy)
- This invocation is `--audit-only` (modularization is a structural change, not an audit)
- M-phase ran in the last 5 invocations per `.factory/state.yaml` (rotation — don't re-modularize too often)

Otherwise the phase runs.

## Phase 1 — Monolith detection

Scan the repo for monolith signals. Record findings to `.factory/modularization-report.md`:

| Signal | Threshold | Severity |
|---|---|---|
| File LOC | > 1500 lines | critical (must split) |
| File LOC | 800-1500 lines | high (should split) |
| File LOC | 500-800 lines | medium (review for split) |
| Class LOC | > 500 lines | high (god class) |
| Function LOC | > 100 lines | medium (extract methods) |
| Cyclomatic complexity | > 20 per function | high (decompose logic) |
| Imports per file | > 30 distinct imports | medium (likely doing too much) |
| Public API per file | > 15 exported symbols | medium (multiple responsibilities) |
| Coupled changes | files that change together >60% of commits | medium (move to same module) |
| Cross-cutting concerns | logging / auth / config woven through business logic | medium (extract to middleware) |

Use language-appropriate tools:

- `cloc --by-file <repo>` for LOC per file
- `radon cc -a` (Python), `eslint complexity` (JS), `gocyclo` (Go), `tokei` for cross-language sizing
- `git log --pretty=format: --name-only \| sort \| uniq -c \| sort -rg` for hot files
- AST-based tools where available (tree-sitter queries for cross-language symbol extraction)

## Phase 2 — Module boundary proposal

For each critical/high finding, propose a module split. Write to `.factory/modularization-plan.md`:

For each proposed split:

```yaml
file: src/big_thing.py
current_loc: 2400
proposed_split:
  - path: src/big_thing/core.py        # main orchestration (~400 LOC)
  - path: src/big_thing/parser.py       # input parsing (~300 LOC)
  - path: src/big_thing/validators.py   # validation logic (~200 LOC)
  - path: src/big_thing/storage.py      # persistence (~500 LOC)
  - path: src/big_thing/__init__.py     # re-exports public API (preserves imports)
rationale: |
  Currently mixes orchestration, parsing, validation, and storage. Splitting
  by responsibility lets future audits scope to one concern. Public API
  preserved via __init__.py re-exports — no caller changes needed.
public_api_preserved: yes
external_imports_preserved: yes
test_coverage_preexisting: 78%
risk: low (no logic moved, only file boundaries)
```

**Boundary heuristics — what makes a good module:**

- Single responsibility (one reason to change)
- Cohesive (functions inside relate to each other more than to outsiders)
- Loose coupling (few imports of other internal modules; depends on stable abstractions)
- Stable interface (public API stays small and changes rarely)
- Testable in isolation (can unit-test without spinning up the whole app)
- Named by what it does, not by what it is (`order_pricing.py` beats `utils.py`)

**Anti-patterns to reject:**

- Splitting purely by file type (`models/`, `views/`, `controllers/` directories with no domain logic) — that's framework-shaped, not domain-shaped.
- Creating a `utils.py` or `helpers.py` — that's a junk drawer. Each utility belongs with the thing it helps.
- Splitting by lines-of-code only without semantic basis — that creates arbitrary cuts.
- Premature abstractions for "future flexibility" — only extract what's actually shared.
- One-off interface/protocol files for things with one implementation — wait until two implementations exist.

## Phase 3 — Apply the split (per-module atomic)

For each proposed split in the plan:

1. **Create the new module structure** with empty files.
2. **Move code in chunks**, not in one giant diff:
   - Move a cohesive group of functions/classes from the monolith to the new file.
   - Update imports inside the moved code.
   - Add re-exports to the original file so external callers still find the symbols (`from .new_module import *` style, or explicit re-exports).
   - Run tests. Must pass.
   - Commit: `refactor: extract <thing> from <monolith> to <new module>` (per L7 commit gate — secret scan + sacred-cow + role-based message).
3. **Repeat for next chunk** until the monolith is decomposed.
4. **Final pass:** once all logic is moved, the original file becomes a re-export shim. Either keep it as a stable public-API shim, OR remove it and update callers (only if there are few callers — count first).
5. **Run full test suite** to confirm no regressions. Run the linter to confirm imports are clean.

**Per-chunk commit cadence is non-negotiable.** Splitting a 2000-line file in one commit is reviewable by no one. Each commit moves one cohesive unit.

## Phase 4 — Verification

Before marking the M-phase complete, verify:

- **All tests pass** (same count, same results as before — bit-identical test output if possible).
- **Public API surface unchanged** — diff `git ls-files` exports before/after. Any signature change is a behavioral change and violates the directive.
- **No imports broken** — language-appropriate import check (`python -c "import <pkg>"`, `tsc --noEmit`, `cargo check`, `go build`).
- **Build artifacts identical** — for compiled languages, verify the output binary's behavior on a smoke test matches the pre-modularization binary.
- **No new dependencies introduced** — modularization doesn't justify adding libraries. If a split needs new libs, defer the split.
- **File-by-file LOC distribution improved** — write before/after stats to the report.

If any check fails: rollback the M-phase commits via `rtk git reset --hard <pre-M-phase-head>` and log the failure to session log. Do NOT push partial modularization.

## Phase 5 — Documentation

Update on success:

- **Repo CLAUDE.md** — add a "Module map" section describing the new structure.
- **README.md** — if architecture diagram exists, update it. If not, add a brief module-overview section.
- **CHANGELOG.md** — append "Refactor: <module> split into <N> modules" entry to "Unreleased".
- **`.factory/modularization-report.md`** — final report with before/after stats and rationale.

## Non-Negotiable Rules

- **Behavior-preserving only.** No new features, no bug fixes, no API changes during the M-phase. Save those for L2.
- **Tests must pass identically.** Same count, same results. Any test change requires the change be a separate non-modularization commit.
- **Per-chunk atomic commits.** No mega-commits. One cohesive split per commit.
- **No new dependencies.** Modularization isn't license to add libraries.
- **Public API preserved.** Use re-exports / shims to keep external callers unchanged. If you must change the API, that's a separate L2 task with a PEC rubric.
- **Sacred-cow files protected.** The directive-circuit-breakers.md sacred-cow gate applies. LICENSE, signing workflows, etc. are not in scope.
- **Skip junk-drawer destinations.** Never extract code into `utils.py`, `helpers.py`, `common.py`, `misc.py`. Name modules by what they do.
- **Stop on regression.** If a split increases test failures, breaks the build, or trips a circuit breaker, rollback that split and log.

## Cadence (factory loop)

- **Default:** rotated, runs at most once every 5 factory invocations on a given repo.
- **Forced:** `--force-modularization` flag on the factory invocation.
- **Auto-trigger:** if the audit phase (L3/L4) flags maintainability findings related to file size or coupling > 5 times across the last 3 runs, M-phase auto-engages on the next run.
- **Skip:** small repos (<5K LOC), already-modular repos (avg file <300 LOC, max <800 LOC), audit-only runs.

## Output

Session log entry at phase end:

```yaml
phase: modularization
files_analyzed: 287
monolith_findings:
  critical: 2
  high: 5
  medium: 12
splits_applied:
  - file: src/big_thing.py (2400 LOC) → 5 modules (~400 LOC avg)
  - file: src/old_handler.py (1800 LOC) → 3 modules
splits_deferred:
  - file: src/legacy_loop.py — too coupled to safely split this pass; flagged for next M-phase
tests_before: 412 pass / 0 fail
tests_after: 412 pass / 0 fail
public_api_diff: 0 symbols changed
new_dependencies: 0
commits: 8 atomic refactor commits
```

This information feeds the continuation brief so future runs see the structural state.
