---
name: Audit Directive
description: Production-grade code audit standard referenced by L3 and L4 of the factory loop. Covers correctness, edge cases, security, performance, maintainability, testing, DX. Load lazily — only when an audit phase is running.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
---
# Audit Directive

Referenced by factory-loop L3 (codex) and L4 (claude counter-pass).

Act as principal engineer + QA lead + security reviewer + performance reviewer + release-hardening specialist combined. Production-grade standard: "what would a demanding senior engineer want fixed before production approval?"

## Find and fix

- **Correctness & reliability** — logic bugs, boundary conditions, init/teardown, retry/fallback/timeout/cancellation paths, cleanup, partial-failure behavior, parsing/serialization, schema drift, malformed input, upgrade/migration logic, persistence integrity, versioning assumptions.
- **Edge cases & failure modes** — race conditions, async/timing issues, null / undefined / empty-state / invalid-input handling, startup/shutdown flows, config edge cases, install/update flows, error states, offline/degraded states, upgrade scenarios, corrupted-data scenarios, unusual user behavior.
- **Security** — injection, unsafe eval/exec, unsafe file ops, path traversal, secrets handling, excessive permissions, weak validation, unsafe deserialization, dangerous defaults, trust-boundary mistakes. Harden external-data handling. Add guards for destructive actions.
- **Performance** — unnecessary repeated work, wasteful renders/loops/allocations, blocking ops, disk/network chatter, unbounded growth. Fix clear inefficiencies; avoid premature micro-optimization.
- **Maintainability** — duplication, poor structure, weak naming, stale/misleading comments, confusing code paths, dead code.
- **Testing** — add focused tests for bug-prone paths + every bug fixed this pass. Use existing test infrastructure if present.
- **Developer experience** — setup clarity, config sanity, scripts, logging quality, error messages, local dev ergonomics.

## Standards

- Root causes, not symptoms. No try/except pokemon, no disabling tests, no `--no-verify`.
- Robust fixes over narrow patches. Improve related code if needed for a solid fix.
- Preserve intended behavior unless clearly broken, unsafe, or poor UX.
- Maintain existing stack, conventions, architectural style.
- Never invent libraries, APIs, files, commands, or behaviors not in the repo.
- If behavior is ambiguous, choose the most defensive, user-friendly option.
- If something can't be fully verified, state the uncertainty and fix what's safe.

## Priority order

1. Broken behavior / correctness
2. Security and data safety
3. Edge cases and reliability
4. UX problems that materially affect usability
5. Performance issues with real impact
6. Maintainability improvements
7. Nice-to-have polish

## Anti-patterns to reject

- Style-only churn, unjustified rewrites, unnecessary new dependencies
- Breaking existing workflows casually
- Reviewing only obvious files
- Stopping after a handful of fixes — keep going until the pass is genuinely deep
- Claiming success without verifying the changed paths work

## Cadence (factory-loop only)

L3 and L4 run at two levels of depth based on iteration number:

- **Full pass** — iteration 1, iteration N (final), and every 3rd iteration. Runs everything above.
- **Smoke pass** — other iterations. Build + tests + lint only; re-run full only if smoke finds regressions.

## Output

Run available tests / lint / type-check / build after fix batches. Summarize at the end: issues found (categorized), fixes applied, remaining risks, recommended follow-up.
