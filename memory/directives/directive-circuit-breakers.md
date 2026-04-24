---
name: Circuit Breakers & Safeguards Directive
description: Deterministic (non-AI) safeguards that run alongside every factory phase. Loop detection, per-agent budget caps, sacred-cow file manifest, stop-on-regression, cooldown states. Trusting a model to self-terminate is the single most expensive assumption — these gates are the hard stop.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
triggers: [breaker, loop, budget, sacred cow, regression, cooldown, halt]
agents: [orchestrator, implementer, critic]
---
# Circuit Breakers & Safeguards Directive

Referenced by the factory loop throughout. **Non-AI logic only** — the model does not decide when these fire. Deterministic code enforces the gates.

## Why

Production post-mortems of autonomous coding agents (Amazon Kiro Dec 2026, Claude Code issue #15909's 27M-token infinite loop, Ona's sandbox escape) all share a pattern: the global cost cap fired too late, the model didn't self-terminate, and damage occurred before a human noticed. Every circuit breaker below is the answer to an actual documented failure.

## 1. Per-agent budget caps

Not just a global cap. Each agent role has its own token + wall-clock ceiling:

| Agent role | Soft cap (warn at 75%) | Hard cap (kill at 100%) |
|---|---|---|
| Claude builder (L2) | 800K tokens / iteration | 1.2M tokens / iteration |
| Codex auditor (L3, U1, T1) | 400K tokens / phase | 600K tokens / phase |
| Claude counter-auditor (L4, U2, T2) | 300K tokens / phase | 500K tokens / phase |
| Gemini researcher (L1a, P3a) | 200K tokens / phase | 400K tokens / phase |
| Copilot deliver (Q-series) | 200K premium requests total | 400K premium requests total |

Implementation: every model invocation increments a per-role counter in the session log. Pre-dispatch, check soft → warn; check hard → refuse dispatch, surface error, halt phase.

Override: `OCTOPUS_FACTORY_BUDGET_OVERRIDE=<role>=<n>` env var at invocation time.

## 2. Loop detector

Every tool call the agent makes is hashed into a rolling window of the last 20. The hash key is `(tool_name, normalized_args_digest)` — small path normalization + arg canonicalization. If >70% of the window consists of ≤3 distinct hashes, the detector has identified a loop.

Behavior on trip:

1. Halt the current phase.
2. Emit the loop fingerprint to session log (which hashes, which tools, which args).
3. Roll back any uncommitted work in the current phase.
4. Resume at the next phase with a flag noting "loop detected in phase N, skipped remaining work."
5. If the same phase trips the loop detector twice in a run: kill the whole run.

## 3. Same-action cooldown

After an agent attempts the same action (e.g., edit the same file, run the same command) 3 times in a row with failures, the action is cooldown'd for the rest of the phase. The agent receives a short message: "action X has failed 3 times consecutively and is on cooldown for this phase; choose a different approach."

Implementation: a `cooldown_set` per phase; agent pre-dispatch hook rejects tool calls whose signature is in the set.

## 4. Sacred-cow file manifest

Every repo gets a `.factory/sacred-cows` file (create on first factory run; maintained by the user). Format: one glob or regex per line, comments allowed.

Example `.factory/sacred-cows`:

```
# Legal / licensing
LICENSE
LICENSE.*
COPYING

# Security-critical
.github/workflows/release.yml
.github/workflows/sign.yml
**/keystore/**
**/*.p12
**/*.pem
**/*.jks
**/signing.properties

# Irreversible migrations
db/migrations/v1_*_initial.sql

# Anything matching these suffixes — additive per project
*.kdbx
```

Pre-commit gate (deterministic):

1. Get list of files in the staged diff: `rtk git diff --cached --name-only`.
2. For each sacred-cow pattern, match against staged files.
3. On any match: reject the commit with the list of violating files. The agent must either (a) remove those files from staging, or (b) the task spec must explicitly contain `"allow-sacred-cow-modification": [<file>]` entries whose values match exactly.
4. Never override on a pattern without an explicit task-spec allowance; `--no-verify` does not work (the gate intercepts at pre-commit-hook level, not pre-push).

Override for factory-initiated changes (e.g., updating LICENSE year): the task spec declares the allowance upfront; the agent cannot grant itself the allowance mid-run.

## 5. Stop-on-regression

After every iteration of the loop (L8 point) AND after every audit / UX / theming pass, record:

- Test pass count
- Test fail count
- Build warning count
- Lint error count
- File size total (bytes) for the source tree
- Coverage percentage (if the repo has a coverage tool)
- Dependency count (direct + transitive)

Compare to the previous recorded snapshot. If any metric regressed AND the task spec did not declare that regression as intentional (e.g., "remove X, expect -5% coverage"):

1. Halt the phase.
2. Auto-revert the current iteration's commits: `rtk git reset --hard <prior-iteration-head>`.
3. Emit a regression report to session log.
4. The run continues at the next phase with a flag; the regressed iteration is not retried automatically.

Mirror of stop-on-convergence (L8): stop-on-convergence exits early because things are good; stop-on-regression rolls back because things got worse.

## 6. Cooldown state between runs

The session state file (`~/.claude-octopus/state.json` per-project) records per-file edit counts across runs. If a file has been edited >20 times across the last 5 factory runs without the test suite's pass rate improving, the file goes into a "suspicious" list — the agent is instructed (via session prompt injection at next run start) that modifications to this file are unlikely to help and require human review first.

## 7. Fail-open vs fail-closed policies

Each breaker declares its failure posture:

| Breaker | Policy | Rationale |
|---|---|---|
| Budget cap | Fail-closed (halt) | Money isn't recoverable |
| Loop detector | Fail-closed (halt + skip) | Time isn't recoverable |
| Sacred cow | Fail-closed (reject commit) | Data loss isn't recoverable |
| Stop-on-regression | Fail-closed (revert) | Ralph Wiggum loops waste all subsequent work |
| Cooldown | Fail-open (warn, allow) | Cooldown state is heuristic; don't block legitimate second attempts |
| Same-action | Fail-closed within phase | Retry loops burn budget fast |

## 8. Override syntax

Every circuit breaker is overridable at invocation time, but overrides must be explicit. No implicit escapes.

```bash
# Raise per-agent budget for this run
OCTOPUS_FACTORY_BUDGET_OVERRIDE='claude-builder=1.5M,codex-auditor=800K' /octo:factory ...

# Disable loop detector for this run (risky — only if debugging)
OCTOPUS_FACTORY_DISABLE_LOOP_DETECTOR=1 /octo:factory ...

# Disable sacred-cow gate (requires explicit ack)
OCTOPUS_FACTORY_DISABLE_SACRED_COWS=1 /octo:factory ...   # will refuse to run unless OCTOPUS_FACTORY_I_KNOW_WHAT_IM_DOING=1 also set
```

The agent cannot set these env vars itself; they must be set by the user at invocation time.

## Output

Every breaker event is appended to the session log and surfaced in the continuation brief (Q4). Pattern:

```
[BREAKER] timestamp=2026-04-24T05:30:22Z phase=L3 breaker=loop-detector
  fingerprint=[Read(src/foo.ts):x17, Edit(src/foo.ts):x12, Bash(npm test):x15]
  action=halted-phase
  rolled-back=0 commits
```

User reviewing the continuation brief sees "phase L3 halted by loop-detector" and can decide to re-run with different parameters.
