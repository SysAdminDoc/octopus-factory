# Execution Modes

The factory recipe runs in one of three modes depending on infrastructure and repo scale. Auto-detected on entry; declared in the session log so you always know what you got.

## Orchestrated Mode

**Triggered when:** orchestrate.sh + provider CLIs + providers.json all present and valid.

**What it does:** each phase runs as a separate agent process with its own context. Multi-provider parallel dispatch. Real three-role debate (Critic and Defender are different model families). Image generation calls `gpt-image-1` directly.

**Pros:** highest fidelity to the recipe spec. Real verification rigor. Parallel research breadth.

**Cons:** heavier setup, more moving parts, still has rough edges on Windows (synchronization timing on quality gates).

## Single-Session Mode

**Triggered when:** orchestrator unavailable (one or more prerequisites missing).

**What it does:** one Claude session executes every phase serially. Several phases collapse:

| Phase | Orchestrated | Single-Session |
|---|---|---|
| Research | Gemini broad scan + Claude augment (parallel) | Claude does both passes (no Gemini context separation) |
| Audit (Critic) | Codex with rubric | Claude with rubric (no model-family diversity) |
| Audit (Defender) | Claude (different family from L3) | **SKIPPED** — same-model duplication has no value |
| UX polish first pass | Codex | Claude |
| UX counter-pass | Claude | **SKIPPED** |
| Theming first pass | Codex | Claude |
| Theming counter-pass | Claude | **SKIPPED** |
| Three-role debate | Grader + Critic + Defender (heterogeneous) | Single-pass rubric check by Claude |
| Logo (P5) | `codex:image` (gpt-image-1) | Deferred — write logo brief, user generates manually |

**Pros:** works without the full octopus orchestrator. Lower cost. Lower setup overhead.

**Cons:** lower verification rigor. No model-family diversity in audit. Image gen requires manual step.

**What still works at full fidelity in single-session:**

- All circuit breakers (per-agent budget caps, loop detector, sacred-cow gate, stop-on-regression, cooldown)
- Secret scan on every commit
- W-phase WIP adoption
- S-phase AI-reference scrub
- D-phase dependency/CVE scan
- Q3 release recipe (project-type-aware build + sign + release)
- L5 doc drift sync, L7 commit gate
- Stop-early on convergence
- Session log + continuation brief
- PEC rubric pre-declaration in L2

## Large-Repo Mode (auto-engaged)

**Triggered when (within single-session mode):** any of:
- Tracked source LOC > 50,000
- Tracked file count > 500
- Test count > 1,000
- Open ROADMAP unchecked items > 30

**What it does:** recipe self-modifies for repos too big to process in one session. Each invocation makes finite, productive progress and persists state so the next run picks up where this one left off.

| Setting | Default | Large-Repo Mode |
|---|---|---|
| Iterations per run | 3-5 | **1** |
| L1 ROADMAP replenish | up to 10 NEW tasks | up to **5 NEW tasks** |
| L2 implementation cap | top 10 P0/P1 | top **3 P0/P1** |
| L3/L4 audit cadence | full every 1st/last/3rd | full **only on iteration that closes the last roadmap item**; smoke pass otherwise |
| U-phase | runs once after loop | **rotated** — runs only if not run in last 5 invocations OR a UI task closed |
| T-phase | runs once after UX | **rotated** — runs only after U-phase ran recently |
| D-phase | runs once before postflight | **rotated** — runs only if last successful dep scan > 14 days OR new deps |
| Q3 release | runs once at end | **only on minor/major bumps** OR `--release` flag |
| Anchored summarization compaction | 85% context fill | **60%** context fill (aggressive) |
| Per-task atomic commits | end of L7 | **after every closed task** |
| File read scope | as needed | **only files in active task's blast radius** |

**Persistent state:** `.factory/large-repo-state.yaml` per project. Records task progress, phase rotation history, context high-watermark, breaker events.

**N-runs-to-drain estimate:** stored in state; updated each run.

## Mode flags (override auto-detect)

| Flag | Effect |
|---|---|
| `--single-session` | Force single-session mode even if orchestrator available |
| `--require-orchestrator` | Refuse to run if orchestrator unavailable; exit with diagnostic |
| `--halt-on-scale` | Disable Large-Repo Mode auto-engage; halt with options instead |
| `--lr-tasks <N>` | Override per-run task cap in Large-Repo Mode (default 3, min 3) |
| `--release` | Force Q3 release even on patch-only Large-Repo runs |
| `--force-ux` / `--force-theming` / `--force-dep-scan` | Force a phase to run regardless of rotation |

## How to know what mode you got

Every run records the mode + degradations to `.factory/state.yaml` and the session log. The continuation brief (Q4) opens with the active mode.

Example log entry:

```yaml
mode: single-session
large_repo_engaged: true
degradations:
  - L3 audit: Claude only (no Codex), no model-family diversity
  - L4 counter-audit: skipped (same-model duplication)
  - P5 logo: deferred to manual generation
scale_gate: triggered (LOC=72K, files=389, tests=412, roadmap=18)
caps_applied:
  iterations: 1
  l2_tasks: 3
  l1_replenish: 5
phase_rotation:
  ux_run: skipped (last run 2 invocations ago)
  theming_run: ran (UI task closed this run)
  dep_scan_run: skipped (last scan 4 days ago)
```
