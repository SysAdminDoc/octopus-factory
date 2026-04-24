# Architecture

How the pieces fit together.

## Layers

```
┌──────────────────────────────────────────────────────────────────────────┐
│  USER INTERFACE                                                           │
│  - Single copy-paste prompt from prompts/factory-loop-prompts.txt        │
│  - "Pull up <repo>" + paste; everything else auto-detects                │
└──────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  RECIPES (memory/recipes/)                                                │
│  - recipe-factory-loop.md       (the master pipeline)                    │
│  - recipe-ai-scrub.md           (git history rewrite)                    │
│  - recipe-pdf-redesign.md       (single PDF improvement)                 │
│  - recipe-pdf-derivatives.md    (mine PDFs for sub-guides + blog posts)  │
│  - recipe-release-build.md      (project-type-aware build + release)     │
└──────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  DIRECTIVES (memory/directives/) — loaded lazily per phase                │
│  - directive-audit.md           L3/L4 single-pass audit (fallback)       │
│  - directive-debate.md          L3/L4 three-role rubric debate (primary) │
│  - directive-circuit-breakers.md  Non-AI safeguards (every phase)        │
│  - directive-modularization.md  M-phase decomposition                    │
│  - directive-ux-polish.md       U1/U2 design polish                      │
│  - directive-theming.md         T1/T2 token/contrast audit               │
│  - directive-dependency-scan.md D1/D2 CVE scan                           │
│  - directive-secret-scan.md     Pre-commit secret leak detection         │
└──────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  ORCHESTRATION (config/)                                                  │
│  - providers.json + presets/    Routing per phase to specific providers  │
│  - workflows/factory-loop.yaml  YAML bridge to octo's orchestrate.sh     │
└──────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  EXECUTION (bin/)                                                         │
│  - octo-route.sh         Swap routing presets                            │
│  - ai-scrub.sh           git-filter-repo wrapper                         │
│  - copilot-fallback.sh   Copilot CLI wrapper with auto-fallback to Codex │
└──────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  PROVIDER CLIs (external)                                                 │
│  Claude Code (built-in) | Codex CLI | Gemini CLI | Copilot CLI           │
└──────────────────────────────────────────────────────────────────────────┘
```

## Phase pipeline (recipe-factory-loop.md)

```
PREFLIGHT (P)        WIP ADOPTION (W)     SCRUB (S)
P0  init session log  W0  gate            S0  gate
P1  session ritual    W1  halt-on-merge   S1  detect AI refs
P2  scaffold (NEW)    W2  inventory       S2  branch on results
P3a gemini research   W3  classify        S3  dry-run scrub
P3b claude augment    W4  commit gates    S4  apply (if found)
P4  seed ROADMAP      W5  per-group       S5  state update
P5  logo (codex:image) W6  quarantine
P6  git init + repo   W7  stash report
                      W8  push unpushed
                      W9  state record
                      W10 verify clean

LOOP (L) — N iterations              MODULARIZATION (M)
L1a gemini delta scan                 M0  gate
L1b claude ROADMAP replenish          M1  apply directive
L2  PEC rubric + implementation       M2  counter-pass
L3  three-role audit (Critic)         M3  full test suite
L4  three-role audit (Defender)       M4  state record
L5  doc drift sync (CHANGELOG only)
L6  screenshots (deferred)            UX POLISH (U)
L7  COMMIT GATE (secret scan)         U0  gate
L8  stop-on-regression                U1  apply directive (codex)
    + stop-on-convergence             U2  counter-pass (claude)
                                      U3  re-capture screenshots
THEMING (T)                           U4  CHANGELOG entry
T0  gate
T1  apply directive (codex)           DEPENDENCY SCAN (D)
T2  counter-pass (claude)             D0  gate
T3  re-capture per theme              D1  apply directive (codex)
T4  CHANGELOG entry                   D2  counter-pass (claude)

POSTFLIGHT (Q)
Q1  /octo:security adversarial pass
Q2  /octo:review final multi-LLM review
Q3  release-build.md (build + sign + SBOM + provenance + smoke test + rollback)
Q4  continuation brief
```

## Routing modes (config/presets/)

| Mode | When to use |
|---|---|
| `balanced` | Default. Each direct account gets its home role; Copilot handles deliver + fallback. |
| `copilot-heavy` | **Cost-optimized.** Routes routine work through Copilot's Sonnet 4.6 + gpt-5.3-codex; reserves direct Claude Max + ChatGPT Pro for escalations only. |
| `claude-heavy` | Burn Claude Max quota first (when fresh). |
| `codex-heavy` | Burn ChatGPT Pro Codex quota first. |
| `direct-only` | Skip Copilot entirely (when Copilot quota is low). |
| `copilot-only` | Everything via Copilot (when direct accounts are exhausted). |

## Execution modes (recipe-factory-loop.md)

```
                    ┌─────────────────────────────┐
                    │ orchestrator available?     │
                    │ - orchestrate.sh present    │
                    │ - providers.json configured │
                    │ - all CLIs authenticated    │
                    └─────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              │                               │
            YES                             NO
              │                               │
              ▼                               ▼
    ┌─────────────────────┐         ┌─────────────────────────┐
    │ ORCHESTRATED MODE   │         │ SINGLE-SESSION MODE     │
    │ Multi-provider      │         │ One Claude session      │
    │ parallel dispatch   │         │ Sequential phases       │
    │ Real 3-role debate  │         │ Debate degrades to      │
    │ Async coordination  │         │   rubric check          │
    └─────────────────────┘         │ L4/U2/T2 collapse       │
                                    │   (same-model dup)      │
                                    │ Logo deferred to manual │
                                    └─────────────────────────┘
                                              │
                                              ▼
                                    ┌─────────────────────────┐
                                    │ Repo scale check        │
                                    │ >50K LOC OR >500 files  │
                                    │ OR >1K tests OR >30 RM  │
                                    └─────────────────────────┘
                                              │
                              ┌───────────────┴───────────────┐
                              │                               │
                          UNDER cap                       OVER cap
                              │                               │
                              ▼                               ▼
                    ┌──────────────────┐         ┌────────────────────────┐
                    │ Run normally     │         │ LARGE-REPO MODE        │
                    │ 3-5 iter, 10     │         │ 1 iter, 3 tasks        │
                    │ tasks per iter   │         │ Per-task atomic commits│
                    └──────────────────┘         │ U/T/D phases ROTATED   │
                                                 │ Persistent state file  │
                                                 │ N runs to drain ROADMAP│
                                                 └────────────────────────┘
```

## Circuit breakers (directive-circuit-breakers.md)

Deterministic safeguards that fire alongside every phase. None are AI-judged.

| Breaker | Trips when | Action |
|---|---|---|
| Per-agent budget | Token/wall-clock cap exceeded | Halt phase, report |
| Loop detector | >70% of last 20 tool calls are duplicates | Halt phase, log fingerprint |
| Same-action cooldown | 3 consecutive failures of same action | Cool down for the phase |
| Sacred-cow file gate | Diff touches `LICENSE` / signing keys / etc. | Reject commit |
| Stop-on-regression | Iteration metrics worse without spec saying so | Auto-revert iteration |
| Cross-run cooldown | File edited >20 times across 5 runs without test improvement | Mark suspicious, surface to user |

## Provider fallback chain (bin/copilot-fallback.sh)

```
Copilot call
     │
     ▼
Lockout file present? ──YES──> Skip Copilot, route to Codex
     │
     NO
     │
     ▼
Try Copilot
     │
     ▼
stderr matches quota patterns?
(quota exceeded, rate limit, premium request limit, monthly limit, 429, etc.)
     │
     YES
     │
     ▼
Write lockout file (60-min TTL)
Log to provider-fallbacks.log
Replay prompt via Codex CLI (mapped model)
Return Codex output
```
