# Roadmap

Prioritized integration plan based on a survey of related projects (Aider, Cline, OpenHands, LangGraph, gitleaks, osv-scanner, promptfoo, OpenTelemetry GenAI semconv).

Each item cites the upstream source so contributors can lift code with attribution. Items are ordered by leverage — highest-impact first.

## External project research expansion — added 2026-04-25

**Status:** proposed backlog
**Goal:** push octopus-factory beyond a recipe/prompt bundle into a reproducible agent-ops platform: measurable, replayable, security-hardened, portable across developer machines, and strong enough to benchmark its own factory runs.

This pass surveyed current agent frameworks, coding-agent evaluation systems, prompt/security test harnesses, CI hardening tools, and context-retrieval projects. The best ideas are not "import a big framework"; the leverage is to lift their operating patterns into octopus-factory's bash-first architecture.

### Tier 0 — make factory runs measurable and replayable

#### 1. First-class trajectory ledger for every factory run

**Source:** [SWE-agent Agent docs](https://swe-agent.com/latest/reference/agent/) and [mini-SWE-agent runner](https://mini-swe-agent.com/latest/usage/mini/)
**Finding:** SWE-agent stores rich per-instance `.traj` data: history, environment state, model stats, replay config, and hooks around agent setup/steps. mini-SWE-agent defaults to a `last_mini_run.traj.json` output path, making trajectory capture a normal artifact rather than an afterthought.
**Why it matters:** octopus-factory already logs phases, state, costs, and commits, but the artifacts are split across status files, session logs, shadow checkpoints, and commit history. A single trajectory schema would make a failed run replayable, auditable, and comparable across models.
**Implementation:**
- Add `.factory/runs/<run_id>/trajectory.jsonl` as the canonical append-only event stream.
- Emit one normalized event for: prompt dispatch, model/provider choice, tool command, command output summary, file diff summary, checkpoint id, commit sha, cost delta, gate result, fallback, user interruption, and phase decision.
- Add `bin/factory-trajectory.sh show|summarize|export-eval|replay-plan`.
- Keep raw logs, but treat the trajectory as the machine-readable release artifact.

#### 2. Agent evaluation harness before prompt/recipe changes ship

**Source:** [Inspect](https://inspect.aisi.org.uk/), [OpenAI Evals](https://github.com/openai/evals), [promptfoo CI/CD docs](https://www.promptfoo.dev/docs/integrations/ci-cd/)
**Finding:** Inspect supports coding, agentic, tool-calling, multi-agent, and sandboxed evaluations, including external agents such as Claude Code, Codex CLI, and Gemini CLI. OpenAI Evals provides a registry/custom-eval pattern for private workflow-specific evals. promptfoo supports CI quality gates for prompts and red-team scans.
**Why it matters:** The factory modifies its own prompts, recipes, and directives. Today a prompt change is mostly validated by syntax and smoke tests; it needs behavioral regression tests that prove an updated recipe still performs the intended loop.
**Implementation:**
- Add `tests/agent-evals/` with small synthetic repos: broken Python CLI, stale UI app, vulnerable dependency app, malformed ROADMAP repo, dirty worktree repo.
- Add `just eval-agent` to run a local low-cost harness that checks final artifacts: commits made, tests run, ROADMAP updated, secret scan invoked, rollback on injected failure.
- Add `just eval-agent-nightly` for expensive multi-provider evaluation.
- Export factory trajectories into eval records so regressions can be inspected after CI.

#### 3. Coding-agent red-team suite as a release gate

**Source:** [promptfoo red-team coding-agent plugins](https://www.promptfoo.dev/docs/red-team/configuration/)
**Finding:** promptfoo now ships coding-agent red-team plugins covering repository prompt injection, terminal-output injection, secret handling, sandbox boundaries, network egress, procfs credentials, delayed CI exfiltration, generated vulnerabilities, automation poisoning, steganographic exfiltration, and verifier sabotage.
**Why it matters:** octopus-factory is specifically a coding-agent orchestrator. Its highest-risk failures are not normal unit-test regressions; they are malicious repo instructions, poisoned terminal output, tool sabotage, secret exfiltration, and CI changes that leak data after the run.
**Implementation:**
- Add `tests/redteam/promptfooconfig.yaml` with `coding-agent:core` for PRs and `coding-agent:all` for nightly/manual runs.
- Add a new Q-phase gate: "agent safety red-team clean or explicitly waived."
- Teach `factory-doctor.sh` to report whether promptfoo red-team support is installed.
- Store red-team HTML/JSON reports under `.factory/runs/<run_id>/redteam/`.

### Tier 1 — make execution portable, secure, and CI-grade

#### 4. Containerized verification path for Windows/macOS/Linux parity

**Source:** [Dagger CI workflow docs](https://docs.dagger.io/getting-started/quickstarts/ci/) and [Dev Container spec](https://github.com/devcontainers/spec)
**Finding:** Dagger turns CI workflows into portable containerized functions and recommends `dagger check` as a local/CI quality gate. Dev Containers standardize a complete development environment for local coding and CI/test use.
**Why it matters:** The repo is Windows-aware, but the current local verification path can break when `bash`, `bats`, `python3`, or `cygpath` resolve to missing WSL/MSYS components. A portable verification lane should not depend on the user's shell shape.
**Implementation:**
- Add optional `.dagger/` module with `check`, `test-bats`, `preset-verify`, `lint-directives`, and `prompt-builder-smoke` functions.
- Add `.devcontainer/devcontainer.json` for the repo's known-good toolchain: bash, Python 3.10+, jq, bats, shellcheck, just, git-filter-repo, gitleaks, osv-scanner.
- Add `just verify-native` for current-host checks and `just verify-container` for hermetic checks.
- Update `factory-doctor.sh` to recommend the containerized path when native Unix tooling is absent.

#### 5. CI supply-chain posture gate

**Source:** [OpenSSF Scorecard](https://github.com/ossf/scorecard) and [StepSecurity Harden-Runner](https://docs.stepsecurity.io/harden-runner)
**Finding:** Scorecard produces security-health checks and scores for open-source repos. Harden-Runner can audit or block network egress and monitor runtime activity in GitHub Actions.
**Why it matters:** The factory already scans target repos for secrets/dependencies, but its own CI and the target repo's CI can still become the attack path. A coding agent that edits workflows needs a workflow-level security posture check, not only source-level scans.
**Implementation:**
- Add `.github/workflows/scorecard.yml` using OpenSSF Scorecard with SARIF/code-scanning output.
- Add Harden-Runner in `audit` mode to CI first, then promote select jobs to `block` mode once the outbound allowlist is known.
- Add factory guidance: if a target repo has GitHub Actions, Q-phase inspects workflow permissions, pinned actions, Scorecard readiness, and unexpected outbound network needs.
- Add ROADMAP/release gate: no new release until workflow permissions are least-privilege and generated CI changes are reviewed.

#### 6. Toolchain manifest and self-healing doctor

**Source:** [mise dev tools docs](https://mise.jdx.dev/dev-tools/) and [mise task configuration](https://mise.jdx.dev/tasks/task-configuration.html)
**Finding:** mise can manage development tools, configure PATH/env, run tasks, and auto-install missing tools for a repo-local workflow.
**Why it matters:** `factory-doctor.sh` detects missing tools, but it does not yet provide a single machine-readable manifest that can bootstrap a developer from zero to verified. This is especially important on Windows where `bash`/`python3` can resolve to unusable shims.
**Implementation:**
- Add `mise.toml` with pinned tool requirements for Python, jq, shellcheck, bats, just, gitleaks, osv-scanner, syft, cosign, git-filter-repo.
- Add `factory-doctor.sh --fix-hints` output that prints exact install commands per OS and detects bad shims before invoking them.
- Prefer explicit executable discovery over assuming `python3` or `bash` means usable runtime.

### Tier 2 — improve orchestration semantics without a rewrite

#### 7. Explicit phase graph with idempotent side effects

**Source:** [LangGraph durable execution](https://docs.langchain.com/oss/python/langgraph/durable-execution), [Microsoft Agent Framework overview](https://learn.microsoft.com/en-us/agent-framework/overview/), [CrewAI docs](https://docs.crewai.com/)
**Finding:** LangGraph emphasizes durable execution, pause/resume, and idempotent operations. Microsoft Agent Framework combines agent abstractions with session state, middleware, telemetry, and graph workflows. CrewAI separates autonomous crews from structured flows with state, guardrails, callbacks, and human-in-the-loop triggers.
**Why it matters:** octopus-factory should keep the bash-first implementation, but its phase behavior should be explicit enough to inspect, resume, replay, and test. Today the recipe is the source of truth; a machine-readable graph would make the runtime safer and easier to evolve.
**Implementation:**
- Add `config/workflows/factory.graph.json` describing phase nodes, prerequisites, retry policy, idempotency key, side effects, rollback handler, and required artifacts.
- Add `bin/factory-graph.sh validate|next|mark|explain` so scripts and docs share one workflow model.
- Make phase commands idempotent by recording operation ids before side effects: branch creation, commit, push, tag, release, issue creation.
- Use graph interrupts for human approval gates: destructive history rewrite, force-push, release publishing, dependency upgrades with major-version drift.

#### 8. Context pack generator and repository map

**Source:** [Continue context providers](https://docs.continue.dev/customize/custom-providers) and [Model Context Protocol server concepts](https://modelcontextprotocol.io/docs/learn/server-concepts)
**Finding:** Continue exposes structured context providers for codebase snippets, folders, search, URL/docs, tree, terminal, problems, and repository maps. MCP servers expose tools, resources, and prompts as reusable context interfaces.
**Why it matters:** Factory prompts currently rely on the agent to rediscover repo shape every run. A deterministic context pack would reduce wasted tokens, make L1 research stronger, and make cross-provider handoffs less lossy.
**Implementation:**
- Add `bin/context-pack.sh <repo>` to produce `.factory/context/pack.md` and `.factory/context/repo-map.json`.
- Include: stack detection, top-level tree, dependency manifests, test commands, build scripts, public entry points, UI files, docs, recent ROADMAP/CHANGELOG, last 20 commits, and known risk hotspots.
- Add optional MCP export later, but keep the first version local-file based and allowlisted.
- Teach prompt-builder to include a "context pack required" toggle for high-risk runs.

#### 9. Guardrails and handoff contracts as data

**Source:** [OpenAI Agents SDK guardrails](https://openai.github.io/openai-agents-python/guardrails/), [OpenAI Agents SDK handoffs](https://openai.github.io/openai-agents-python/handoffs/), [AutoGen multi-agent conversation docs](https://microsoft.github.io/autogen/0.2/docs/Use-Cases/agent_chat/)
**Finding:** Modern agent frameworks make handoffs, guardrails, and conversable agent boundaries explicit. AutoGen distinguishes static and dynamic conversations; OpenAI Agents SDK documents separate input/output/tool guardrail behavior and handoff semantics.
**Why it matters:** octopus-factory already has roles and directives, but handoff contracts are mostly prose. Role-to-role transitions should have explicit inputs, output schemas, forbidden side effects, and failure codes.
**Implementation:**
- Add `config/roles/*.json` for implementer, critic, defender, security, UX, release, and researcher contracts.
- Define per-role allowed tools, required artifacts, output schema, escalation triggers, and no-go zones.
- Add `bin/validate-role-output.py` to enforce JSON/YAML contracts for machine-readable role outputs.
- Use contracts to improve fallback: if one provider fails mid-role, the next provider receives the same structured task and required output schema.

### Tier 3 — later differentiators

#### 10. Public benchmark board for factory capability

**Source:** [OpenAI Evals](https://github.com/openai/evals), [Inspect](https://inspect.aisi.org.uk/), [SWE-agent trajectories](https://swe-agent.com/latest/reference/agent/)
**Finding:** The serious agent projects expose repeatable evals and artifacts, not just demos. A benchmark board would make octopus-factory's claims falsifiable.
**Implementation:**
- Publish a small suite of fixture repos and expected outcomes.
- Track pass/fail, cost, wall-clock time, commits, tests run, rollback events, and human-intervention count per preset.
- Add README badges for latest benchmark pass, red-team pass, and Scorecard score.

#### 11. Optional MCP interface, but only after local security policy exists

**Source:** [MCP server concepts](https://modelcontextprotocol.io/docs/learn/server-concepts)
**Finding:** MCP can expose prompts, resources, and tools in a standard way. For octopus-factory, that could make recipes/directives discoverable to external IDEs and agents.
**Why not now:** MCP expands the tool trust boundary. Ship context packs, allowlists, red-team tests, and role contracts first.
**Implementation later:**
- `octopus-factory-mcp` exposes read-only recipes/directives/prompts/resources first.
- Write-capable tools require explicit allowlist and human approval.
- MCP tool calls are logged into the same trajectory ledger as native commands.

### Frameworks surveyed but not worth adopting wholesale

- **LangGraph / Microsoft Agent Framework / CrewAI / AutoGen:** use their concepts for graphs, state, guardrails, and role contracts; do not replace the bash-first runtime unless the workflow graph outgrows shell scripts.
- **Dagger:** use as an optional hermetic verification path; do not require containers for basic usage.
- **MCP:** useful interoperability layer later; too much trust-boundary surface for v0.7 unless paired with allowlists and red-team gates.
- **[DeepEval](https://deepeval.com/):** strong LLM unit-test ecosystem, but promptfoo + Inspect + OpenAI Evals cover this repo's immediate needs with less overlap.

### What this research says the next release should be

**Recommended v0.7 theme:** "measurable factory runs."

Ship these first:
1. Trajectory ledger.
2. Native agent-eval fixture harness.
3. promptfoo coding-agent red-team gate.
4. Containerized verification fallback for Windows/macOS/Linux parity.
5. Scorecard + Harden-Runner CI posture audit.

Those five items compound: the factory becomes replayable, testable, security-audited, and portable before adding more autonomous power.

---

## v0.6.0 — shipped 2026-04-25

### Overnight execution mode + infrastructure consolidation

**Status:** shipped in v0.6.0
**Why:** User wanted to kick off the factory before bed and have it run for hours unattended. A single Claude Code session can't sustain 8+ hours due to context fragmentation, but the factory's persistent state design was already built for resumable atomic cycles — the missing piece was an external respawn loop. Plus nine post-v0.5.1 commits' worth of infrastructure landed (justfile, overlay preset system, pre-commit hooks, bats tests, GitHub Actions CI, directive linter) that all warranted a release.

**What shipped:**

*Overnight mode:*
- `bin/factory-overnight.sh` — round-robin wrapper. Spawns fresh `claude --print` per cycle (avoids context fragmentation). Wall-clock end (`--until 06:00`), duration (`--duration 8h`), per-cycle hard timeout (default 30 min), cumulative cost cap auto-distributed across cycles, convergence-rotation counter retires repos after N consecutive `no-op` cycles, multi-repo round-robin, sentinel-file halt (`~/.factory-overnight.stop`), live status file (`~/.factory-overnight.status`).
- `--overnight` recipe flag — forces Large-Repo Mode (one iteration, atomic per-task commits + push), disables stop-on-convergence within the cycle, suppresses Q3 release on routine cycles, writes `cycle_outcome` (advanced / researched / no-op) for the wrapper's rotation counter.
- `just overnight` recipe — pass-through to the wrapper.
- Recipe + prompt template gain dedicated Overnight Mode sections.

*Infrastructure consolidation:*
- `justfile` — discoverable task surface for every `bin/` script (preflight, phases, state, tools, dev groups).
- `config/presets/overlays/_base.json` + per-mode overlays + `build.sh` — DRY source of truth for the 6 routing presets. Edit shared fields once, regenerate every preset.
- `.githooks/pre-commit` — blocks preset drift + lints directive frontmatter on staged commits.
- `tests/bats/` — 29 automated tests (syntax / presets / justfile / directives).
- `.github/workflows/ci.yml` — Ubuntu / macOS / Windows matrix, runs preset-verify + lint + bats on every push.
- `bin/lint-directives.py` — stdlib-only YAML frontmatter validator with did-you-mean suggestions for typos. Closes the lazy-loader silent-fail gap.

**Closes:** the "single Claude session can't run for 8 hours" friction + nine commits' worth of post-v0.5.1 infrastructure that needed a release tag.

---

## v0.5.1 — shipped 2026-04-24

### Codex direct-dispatch + factory-doctor diagnostic

**Status:** shipped in v0.5.1
**Why:** User reported "codex/chatgpt isn't being used". Investigation across 6 recent runs confirmed: every `state.yaml` logged `mode: single-session` + `L3 audit: Claude only (no Codex dispatch)`. Two causes compounded — orchestrate.sh's Windows quality-gate timing forced single-session mode, and even when orchestrated would have run, the active `copilot-heavy` preset routes "Codex" phases to `copilot-codex` (Copilot's GPT-5.3-Codex), not the standalone `codex` CLI.

**What shipped:**
- `bin/codex-direct.sh` — wrapper around `codex exec --model gpt-5.4 --sandbox read-only`. Bypasses orchestrate.sh AND the preset routing. Phase-aware (audit/counter/ux/theming/review/security/self-audit/custom). JSONL transcript capture + last-message file. Exit codes classify auth/quota/timeout/refusal/internal so callers degrade gracefully.
- `bin/factory-doctor.sh` — pre-run diagnostic. Validates CLI auth + orchestrator + providers.json + image tooling + git/gh. Specifically catches the "audit phases route to copilot-codex" pattern that produced silent Claude-only audit runs.
- Recipe single-session mode rewritten — every phase that previously collapsed to Claude-only or got skipped now invokes `codex-direct.sh <phase>`. Three-role debate restored (sequential, but all three families present).
- Prompt adds mandatory PRE-FLIGHT (run doctor first) + CODEX DISPATCH (audit phases MUST shell out to codex-direct) sections.

**Closes:** the "factory ran 6 times without ever invoking Codex" failure mode user surfaced 2026-04-24.

---

## v0.5.0 — shipped 2026-04-24

### Five-phase roadmap research directive + tier taxonomy

**Status:** shipped in v0.5.0
**Why:** A user-authored "Roadmap Research Agent" prompt had research discipline the factory's L1 was missing. Lifting it formalizes quantity-first harvesting, explicit Rejected-tier-with-reasoning, source-citation as a commit gate, adversarial self-audit on a different model family, and reconciliation semantics on existing ROADMAPs.

**What shipped:**
- `memory/directives/directive-roadmap-research.md` — five-phase research protocol (Phase 0 repo recon → Phase 1 external with 9 source classes and 30-60 source floor → Phase 2 quantity-first harvest → Phase 3 six-dim scoring + five-tier bucketing → Phase 4 author/reconcile → Phase 5 seven-check self-audit on different model family).
- Recipe L1 rewritten to delegate to the directive. L1a/L1b collapsed into a single `L1. Apply directive-roadmap-research.md` step.
- Tier taxonomy (Now / Next / Later / Under Consideration / Rejected) introduced alongside existing priority (P0/P1/P2). Priority = urgency; tier = commitment state.
- Prompt, hard-caps table, and Large-Repo-Mode table all updated to the new taxonomy.
- Phase 5 self-audit routed to `copilot-codex` (different family than Phases 2-4's `copilot-sonnet`) — cross-family review catches what same-family self-review misses.

**Closes:** the "factory L1 dropped good ideas during extraction" failure mode + the "Rejected items silently resurrect on next run" pattern.

---

## v0.4.0 — shipped 2026-04-24

### Copilot-heavy canonical default + 9-dimension research scan + offload policy

**Status:** shipped in v0.4.0
**Why:** A factory run on the Images repo exited after finding 2 closed tasks and declaring the ROADMAP "clean". The pattern was: existing ROADMAP → skip research → no new work found → exit. User reported that runs should be "extremely involved" by default — research ambitious, heavy-lifting offloaded to Copilot so Claude Max quota is preserved for escalation, and the workflow should expand ROADMAPs even when they already have items.

**What shipped:**
- Default prompt (`prompts/factory-loop-prompts.txt`) rewritten with an explicit OFFLOAD POLICY (copilot-heavy mandatory, Claude Max reserved for escalation only) and RESEARCH EXPECTATION (9 dimensions always on iter 1).
- Recipe L1a expanded from "broad scan" to an explicit **9-dimension landscape audit** — competitor parity, upstream releases, CVEs, accessibility (WCAG 2.2 AA), performance regressions, UX polish, theme coverage, community asks, platform/ecosystem shifts. Output to `docs/research/iter-<N>-landscape.md`; tasks cite their source dimension for traceability.
- Provider Routing table rewritten to document copilot-heavy as canonical (balanced demoted to "specialized preset").
- Iteration defaults raised: existing repos with active ROADMAP go 3→4; clean repos go from `1 --audit-only` to `2 full iterations with research`.
- New flag: `--final-codex-pass` for release-day direct-ChatGPT-Pro-Codex audit.

**Offload policy enforcement:**
- Bulk research synthesis → Copilot Sonnet 4.6
- Bulk implementation → Copilot Sonnet 4.6
- Audit / UX / theming passes → Copilot GPT-5.3-Codex
- Weak-tier mechanical work → Copilot Haiku 4.5
- Claude Max (master session) only escalates on PEC UNCERTAIN ≥3, debate stalemate, security escalation, or novel architecture on new projects.

**Closes:** the "factory declared ROADMAP clean and exited without finding anything" bug pattern.

---

## v0.3.0 — shipped 2026-04-24

### G-phase logo/icon generation for existing projects (no OpenAI billing required)

**Status:** shipped in v0.3.0
**Why:** Preflight `P5` only runs on NEW repos — existing repos that joined the factory without a logo had no way to acquire one through the pipeline. The prior raster-first path also assumed a working `OPENAI_API_KEY`, which blocked runs whenever the key was missing or rate-limited. This phase gives existing repos a code path to a full icon set while making OpenAI billing strictly optional.

**What shipped:**
- `memory/directives/directive-logo.md` — three-path generation directive. **Path 1 (default): SVG-via-Copilot + ImageMagick rasterization** (no image API, no OpenAI billing — Copilot subscription covers it). Path 2: Codex `gpt-image-1` (opt-in via `--raster-logo` for photographic briefs). Path 3: Gemini image as last resort. Includes stack-specific wiring for Chrome MV3, Firefox, Android adaptive icons, WPF `.csproj`, Python `.spec`, Web/PWA.
- `memory/recipes/recipe-factory-loop.md` — new G-phase block (G0-G7) that runs between S-phase (scrub) and the main loop on existing repos. Auto-skips when icon set already present and fresh. Force override via `--force-logo`. Skip via `--skip-logo`. Raster opt-in via `--raster-logo`.
- `memory/recipes/recipe-factory-loop.md` — P5 (preflight, new projects) rewritten to delegate to the same directive so both new and existing projects follow one path.

**Gate logic:**
- Skips automatically when `assets/icons/icon.svg` + all raster sizes already exist AND CLAUDE.md doesn't flag as stale.
- Skips when repo declares "brand-less" in its CLAUDE.md.
- Runs on `--force-logo` even if icons exist (archives the old set first).
- Halts loud on missing ImageMagick — never silently degrades.

**Closes:** the "Images repo got no logo on first factory pass" bug the user hit 2026-04-24.

---

## Tier 1 — high leverage, ship soon

### 1. SQLite-backed checkpointing for crash recovery + resume

**Status:** shipped in v0.2.0
**Why:** Current state is YAML-only. A killed factory run has to restart from scratch. SQLite checkpoint lets runs resume from the last completed phase.

**Source:** [LangGraph checkpoint-sqlite](https://github.com/langchain-ai/langgraph/tree/main/libs/checkpoint-sqlite) — port the schema verbatim into `.factory/state.db`:

```sql
CREATE TABLE checkpoints (
  thread_id TEXT NOT NULL,        -- factory run_id
  checkpoint_ns TEXT DEFAULT '',  -- phase name (Q1/L3/U1/T1/D1)
  checkpoint_id TEXT NOT NULL,    -- iteration id
  parent_checkpoint_id TEXT,      -- previous iteration (resume chain)
  type TEXT,                      -- "json" or "msgpack"
  checkpoint BLOB, metadata BLOB,
  PRIMARY KEY (thread_id, checkpoint_ns, checkpoint_id));
```

**Implementation:** new `scripts/lib/state-store.sh` with `state_save / state_load / state_list_runs / state_resume`. `sqlite3` ships with Git Bash, no new deps. Replaces `.factory/state.yaml` (or layers on top — keep YAML for human inspection, use SQLite for resume).

**Effort:** ~150 LOC bash + 20 LOC SQL.

---

### 2. Shadow-git checkpoints for stop-on-regression rollback

**Status:** shipped in v0.2.0
**Why:** `directive-circuit-breakers.md` calls for stop-on-regression with `git reset --hard`. That works but touches user history. Shadow-git is cleaner: a separate `.git` directory with `core.worktree=<user_repo>` so snapshots never touch user history.

**Source:** [Cline `CheckpointGitOperations.ts`](https://github.com/cline/cline/blob/main/src/integrations/checkpoints/CheckpointGitOperations.ts) — port `initShadowGit`, `addCheckpointFiles`, `renameNestedGitRepos` (critical: rename nested `.git → .git_disabled` before `git add` to avoid submodule errors). Plus [`CheckpointTracker.ts`](https://github.com/cline/cline/blob/main/src/integrations/checkpoints/CheckpointTracker.ts)'s `commit()`, `getDiffSet()`, `resetHead()`.

**Implementation:** new `scripts/lib/checkpoint.sh` with three commands: `cp_init`, `cp_snapshot <phase>`, `cp_rollback <phase>`. Commit message format: `factory-${run_id}-${phase}-${iter}`.

**Effort:** ~200 LOC bash. Pairs naturally with item #1.

---

### 3. Replace regex secret-scan with Gitleaks

**Status:** shipped in v0.2.0
**Why:** Current `directive-secret-scan.md` is regex-based — usual false-positive/miss tradeoff. Gitleaks is one binary, TOML config, has `.pre-commit-hooks.yaml` standard, supports `git`/`dir`/`stdin` modes, has a `SKIP=gitleaks` escape hatch.

**Source:** [Gitleaks](https://github.com/gitleaks/gitleaks)

**Implementation:**
1. Bundle `gitleaks` binary install in `bin/install.sh` (homebrew + apt + scoop).
2. Replace the regex implementation in `directive-secret-scan.md` with: `gitleaks dir --no-git --report-format json --report-path .factory/gitleaks.json --exit-code 1`.
3. Keep our directive as the orchestration wrapper that interprets results + applies the same halt/quarantine logic.

**Effort:** ~100 LOC + install.sh additions.

---

### 4. Standardize dep scan on osv-scanner

**Status:** shipped in v0.2.0
**Why:** `directive-dependency-scan.md` branches per-ecosystem (npm/cargo/dotnet/pip/go). osv-scanner is one binary that walks any tree, supports 19+ lockfile types, uses the open OSV.dev DB, has experimental guided remediation for npm + Maven.

**Source:** [osv-scanner](https://github.com/google/osv-scanner)

**Implementation:** Replace per-ecosystem branching with `osv-scanner scan source -r . --format json`, parse JSON for severity counts, gate Q3 release on no-CRITICAL.

**Effort:** ~50 LOC bash to replace ~200 LOC of per-ecosystem detection.

---

### 5. Aider's commit-message prompt — drop-in

**Status:** shipped in v0.2.0
**Why:** No canonical commit-message prompt currently. Aider's is battle-tested and conventional-commits compliant.

**Source:** [`Aider-AI/aider/aider/prompts.py`](https://github.com/Aider-AI/aider/blob/main/aider/prompts.py) — `commit_system` constant. Pair with `aider/repo.py:get_commit_message()` for the model-fallback loop pattern.

**Implementation:** lift verbatim into `prompts/commit-message.md` (with attribution + Apache-2.0 notice, since Aider is Apache-licensed).

**Effort:** ~30 minutes.

---

## Tier 2 — meaningful improvement, plan post-v0.1

### 6. Aider's `weak_model` / `editor_model` tier separation

**Status:** shipped in v0.2.0
**Why:** Routing presets currently pick one model per role globally. Aider's `Model(model, weak_model, editor_model)` lets you cheap out on commit msgs, lint summaries, holdout grading.

**Source:** [`Aider-AI/aider/aider/models.py`](https://github.com/Aider-AI/aider/blob/main/aider/models.py)

**Implementation:** Add a third tier to `config/presets/*.json`: `primary / weak / editor`. Default `weak ← primary` if unset (backward-compat). Update `dispatch.sh` to consult the tier when routing.

**Effort:** ~80 LOC across presets + dispatch.

---

### 7. Aider's `ChatSummary` — recursive head-tail compression

**Status:** shipped in v0.2.0
**Why:** Factory loop has no in-loop context compression. Multi-iteration runs hit `/compact` interruptions. Aider splits at 50% token boundary, summarizes head with weak model, recurses if combined still oversized.

**Source:** [`Aider-AI/aider/aider/history.py`](https://github.com/Aider-AI/aider/blob/main/aider/history.py) — `ChatSummary.summarize / summarize_real / summarize_all`

**Implementation:** Port to `scripts/lib/context-compress.sh` invoked between phases when token estimate > 70% of model window.

**Effort:** ~80 LOC bash.

---

### 8. OpenTelemetry GenAI semconv for state + session log

**Status:** shipped in v0.2.0
**Why:** Stop inventing field names. Use the published spec across all logging — makes session logs greppable by every otel-aware tool.

**Source:** [OpenTelemetry GenAI agent spans](https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/), [GenAI metrics](https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-metrics/)

**Mapping to adopt:**
| Our field | OTel semconv |
|---|---|
| `provider` | `gen_ai.provider.name` (`anthropic` / `openai` / `google` / `github_copilot`) |
| `agent_role` | `gen_ai.agent.name` (`grader` / `critic` / `defender` / `implementer`) |
| `model` | `gen_ai.request.model` + `gen_ai.response.model` |
| `tokens_in/out` | `gen_ai.usage.input_tokens` / `gen_ai.usage.output_tokens` |
| `cache_read/write` | `gen_ai.usage.cache_read.input_tokens` / `gen_ai.usage.cache_creation.input_tokens` |
| `run_id` | `gen_ai.conversation.id` |
| `cost.usd` | (custom — spec is silent on cost) |

**Effort:** ~3-5 hours rewriting log emitters + state schemas.

---

### 9. Cline's tiered-pricing cost function

**Status:** shipped in v0.2.0
**Why:** Octo plugin already has `cost.sh` but it doesn't handle tiered pricing, thinking-budget output price overrides, or the cache-creation/cache-read split correctly.

**Source:** [`cline/cline/src/utils/cost.ts`](https://github.com/cline/cline/blob/main/src/utils/cost.ts) — `calculateApiCostInternal`

**Implementation:** Port the four-component sum into `scripts/lib/cost-estimate.sh`:
```
cost = (cacheWritesPrice/1e6)*cacheCreate
     + (cacheReadsPrice/1e6)*cacheRead
     + (inputPrice/1e6)*input
     + (outputPrice/1e6)*output
```
Plus the Anthropic/OpenAI input-token-counting wrapper distinction.

**Effort:** ~100 LOC bash.

---

### 10. OpenHands microagent format for directives

**Status:** shipped in v0.2.0
**Why:** Directives are plain markdown. Adopting OpenHands' YAML-frontmatter `triggers:` field would let directives self-declare keyword activation instead of recipes hard-coding which to load.

**Source:** [OpenHands microagents docs](https://docs.openhands.dev/usage/prompting/microagents-overview)

**New directive frontmatter:**
```markdown
---
name: directive-secret-scan
type: knowledge
triggers: [secret, leak, api key, credential, .env]
agents: [grader, critic]
---
```

**Implementation:** New `scripts/lib/directive-loader.sh` parses frontmatter, matches against phase prompt, lazy-loads only matching directives. Eliminates recipe→directive coupling.

**Effort:** ~150 LOC bash + frontmatter migration of all 8 directives.

---

## Tier 3 — nice-to-have, ship later

### 11. promptfoo regression tests for prompts

**Status:** shipped in v0.2.0
**Why:** Prompts get patched often with no regression net. promptfoo runs (prompt × provider × test case × assertion) matrices.

**Source:** [promptfoo](https://github.com/promptfoo/promptfoo)

**Implementation:** Add `tests/prompts/promptfooconfig.yaml` covering each directive's expected output structure (e.g., L3 audit must produce `Severity: HIGH|MED|LOW` rows). Cheap CI gate before shipping prompt changes.

**Effort:** ~4-6 hours initial setup + ongoing maintenance.

---

### 12. Beta-Binomial adaptive stopping — actual implementation

**Status:** shipped in v0.2.0
**Why:** `directive-debate.md` describes adaptive stopping but ships no implementation. The math is small enough to ship.

**Source:** [arXiv 2510.12697](https://arxiv.org/abs/2510.12697) (paper has no public code; we ship the implementation)

**Implementation:** ~30 lines of Python in `scripts/lib/debate-stability.py`:
- After each round, build histogram `S_t` = count of rounds where each judge agreed with majority
- Fit Beta-Binomial via EM (`scipy.stats.betabinom`) or hand-rolled MoM estimator
- KS distance `D_t` between consecutive round distributions (`scipy.stats.ks_2samp` or hand-rolled CDF diff)
- Stop when `D_t < 0.05` for 2 consecutive rounds OR round ≥ max_rounds (currently 7)

Ships as the only Python file in the repo so the directive can call it via `python3 -c` from bash.

**Effort:** ~2-3 hours including tests.

---

## Skipped — surveyed but not worth integrating

- **TruffleHog** — overlaps Gitleaks; pick one (Gitleaks has cleaner pre-commit story).
- **BFG / reposurgeon** — `ai-scrub.sh` already uses `git-filter-repo` (the modern pick); only add BFG if a user reports >1GB history pain.
- **DSPy / LangSmith** — too heavy for a bash-first project; promptfoo is the right tier.
- **MetaGPT / GPT-Engineer prompts** — preprompts are aging and were designed for one-shot codegen; the factory loop already does better via debate. Skip unless someone builds a `recipe-greenfield.md`.
- **OpenHands runtime sandbox (Docker/Modal/Runloop)** — overkill; Claude Code's tool sandboxing + circuit-breakers + freeze mode already cover it.
- **RA.Aid / Roo Code / Continue.dev** — overlap with Aider/Cline; their unique value (MCP integration) lives at the Claude Code layer, not ours.

---

## What octopus-factory does that none of these have

These are the differentiators worth protecting + advertising in the README:

1. **Three-role debate (Grader / Critic / Defender) with provider-rotation pinning.** Aider, Cline, OpenHands are all single-model. Octo's existing `debate.sh` has 2-role cross-critique; the factory formalizes the 3-role asymmetric pattern with adaptive stopping and cross-family pinning.
2. **Cross-provider quota fallback chain at the role level.** `copilot-fallback.sh` + per-role Copilot model selection patches. Aider has model fallback within a single provider call; nobody chains across Claude → Codex → Gemini → Copilot per role with subscription/auth awareness.
3. **Recipe + lazy-loaded directive split.** Aider/Cline/OpenHands have monolithic system prompts. The recipe-calls-directive indirection is closest to OpenHands microagents, but goes further: directives are role-scoped, not just keyword-triggered.
4. **Holdout-scenario integrity check.** `factory.sh:split_holdout_scenarios` (deterministic-shuffle 20% holdout, cross-model evaluator). None of the agent tools have an integrity firewall against the implementer seeing tests.
5. **Cost-gated phase progression with auth-mode awareness.** `cost.sh:estimate_workflow_cost` distinguishing API-billed vs subscription-included providers, then gating Q3 release on running total. Cline tracks cost; doesn't gate on it. Nobody else does both.

## How to pick something to work on

Open issues are tagged `tier-1` / `tier-2` / `tier-3` matching the sections above. Tier 1 items are the highest-leverage; pick those if you want maximum impact per hour. Tier 2/3 are good for incremental contributors.

Each item above has enough source detail (file paths, function names, schema) that you should be able to start without reading this whole doc — the citation is the spec.
