# Roadmap

Prioritized integration plan based on a survey of related projects (Aider, Cline, OpenHands, LangGraph, gitleaks, osv-scanner, promptfoo, OpenTelemetry GenAI semconv).

Each item cites the upstream source so contributors can lift code with attribution. Items are ordered by leverage — highest-impact first.

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
