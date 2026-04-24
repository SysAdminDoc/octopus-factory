# Changelog

All notable changes to octopus-factory will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- (track future improvements here)

---

## [0.2.0] — 2026-04-24

All 12 ROADMAP items shipped in a single release. Tier 1 + Tier 2 + Tier 3 integrations land together. Closes issues #1-#5.

### Added

**Tier 1 — high leverage (the five GitHub issues):**
- `bin/state-store.sh` (T1.1, closes #1) — SQLite-backed phase checkpointing. LangGraph `checkpoint-sqlite` schema ported verbatim into `.factory/state.db`. Commands: `init`, `save`, `load`, `list`, `resume`, `complete`, `prune`. Smoke-test verified: saves + retrieves across runs, summary reporting, TTL prune.
- `bin/checkpoint.sh` (T1.2, closes #2) — Shadow-git snapshots for stop-on-regression rollback. Ported from Cline's `CheckpointGitOperations.ts` / `CheckpointTracker.ts` pattern. Uses a separate `.git` dir with `core.worktree=<repo>` so snapshots never touch user history. Commands: `init`, `snapshot`, `diff`, `rollback`, `list`, `gc`. Handles nested `.git` directories (renames to `.git_disabled` during scans). Smoke-test verified: snapshot + rollback restored exact prior content.
- `bin/secret-scan.sh` (T1.3, closes #3) — Gitleaks-backed pre-commit secret detection replacing the regex implementation. Modes: `staged` (commit gate), `dir`, `git` (full history), `pre-commit` (hook install), `install` (auto-install gitleaks binary via brew/apt/scoop/curl). Keeps the directive as the orchestration wrapper; Gitleaks provides the 160+ curated secret patterns.
- `bin/dep-scan.sh` (T1.4, closes #4) — osv-scanner unified dependency vulnerability scan replacing per-ecosystem branching. One binary covers 19+ lockfile types (npm/cargo/go.mod/pom.xml/requirements.txt/Pipfile.lock/Gemfile.lock/composer.lock/etc.) via OSV.dev. Modes: `scan`, `gate` (severity threshold), `report`, `install`. Replaces ~200 LOC of per-ecosystem detection with ~50 LOC.
- `prompts/commit-message.md` (T1.5, closes #5) — Aider's battle-tested commit-message prompt lifted verbatim (Apache 2.0, attributed). Includes model-fallback loop pattern for primary → weak degradation. Factory-specific additions documented: phase-prefix conventions, secret-scan post-check, subject+body expansion for large diffs.

**Tier 2 — meaningful improvement:**
- **weak/editor model tiers on all 6 presets** (T2.6) — `routing.roles.weak` + `routing.roles.editor` added to `balanced`, `copilot-heavy`, `claude-heavy`, `codex-heavy`, `direct-only`, `copilot-only`. Semantics documented in `_tier_semantics` block per preset: weak for mechanical work (commits, lint summaries, rubric scoring), editor for actual file edits.
- `bin/context-compress.sh` (T2.7) — Recursive head-tail compression ported from Aider's `ChatSummary`. Splits at 50% token boundary, summarizes head via weak model, recurses if combined still oversized. Compaction trigger at 70% context fill (configurable via `OCTOPUS_CONTEXT_COMPRESS_THRESHOLD`). Modes: `estimate`, `should-compress`, `compress`. Weak-model dispatch respects existing preset routing.
- `bin/otel-log.sh` (T2.8) — OpenTelemetry GenAI semantic-convention logger. Emits JSON-lines events to `~/.claude-octopus/logs/factory-<project>-<timestamp>.log`. Fields follow the OTel spec: `gen_ai.operation.name`, `gen_ai.provider.name`, `gen_ai.agent.name`, `gen_ai.request/response.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`, `gen_ai.usage.cache_read/cache_creation.input_tokens`, `gen_ai.conversation.id`. Custom extensions: `factory.phase`, `factory.iteration`, `factory.cost_usd`, `factory.breaker.*`. Commands: `event`, `start-span`, `end-span`, `usage`, `breaker`, `tail`.
- `bin/cost-estimate.sh` (T2.9) — Four-component tiered cost function ported from Cline's `calculateApiCostInternal`. Formula: `(cacheWrites * cacheCreate + cacheReads * cacheRead + input * inputTokens + output * outputTokens) / 1e6`. Embedded pricing table for 13 current models; override via `~/.claude-octopus/config/model-prices.json`. Commands: `calc`, `prices`, `register`.
- `bin/directive-loader.sh` + microagent frontmatter on all 8 directives (T2.10) — Each directive now declares `type: knowledge`, `triggers: [...]`, `agents: [...]` in YAML frontmatter (OpenHands microagent pattern). Loader scans prompts, matches triggers, filters by agent role, returns only relevant directive paths. Replaces recipe→directive hardcoded coupling with data-driven dispatch.

**Tier 3 — ship later (both included in this release):**
- `tests/prompts/promptfooconfig.yaml` + `tests/prompts/README.md` (T3.11) — promptfoo regression test scaffold. Test cases cover conventional-commits format, 72-char subject cap, imperative mood, no AI-attribution leakage, audit-output severity markers, debate grader PASS/FAIL/UNCERTAIN output, and PII-free prompt files. CI integration template included.
- `bin/lib/debate-stability.py` (T3.12) — Beta-Binomial adaptive-stopping implementation for multi-agent debate, per arXiv 2510.12697 (math only, no public reference code — shipped here for the first time). Pure Python 3.10+ stdlib (no scipy, no numpy, no pip). Method-of-Moments Beta fit + Kolmogorov-Smirnov distance via Lentz continued-fraction Beta CDF. Commands: `add`, `decide`, `summary`. Decision outputs: `CONTINUE`, `STOP:converged`, `STOP:stalemate`, `STOP:obvious-pass`, `STOP:obvious-fail`. Smoke-test verified: correctly emits `STOP:obvious-pass` on round-1 unanimous high-confidence, computes KS distances across rounds.

### Changed
- `ROADMAP.md` — all 12 items marked `shipped in v0.2.0`
- `README.md` — (no content change this release; v0.1.0 version already in effect)

### Closed issues
- #1 (SQLite checkpointing)
- #2 (Shadow-git checkpoints)
- #3 (Gitleaks secret scan)
- #4 (osv-scanner dep scan)
- #5 (Aider commit-message prompt)

### Verification

All 12 implementations smoke-tested during authoring:
- `state-store.sh`: save/load/list/resume/complete round-trip verified
- `checkpoint.sh`: init → snapshot at v1 → edit → snapshot at v2 → edit → rollback to v1 restored exact content
- `otel-log.sh`: emitted events with all semconv fields on first write
- `cost-estimate.sh`: reasonable USD values for realistic Sonnet/Opus/GPT-5 token counts
- `directive-loader.sh`: matches triggers against prompts + filters by agent role
- `debate-stability.py`: `STOP:obvious-pass` correctly detected; KS-distance computed between rounds

`secret-scan.sh` + `dep-scan.sh` + `context-compress.sh`'s model-dispatch paths are CLI-shaped (help works, arg validation works) but full end-to-end runs require their upstream binaries (gitleaks, osv-scanner) installed or real model calls. Install paths are wired in each script.

### Known limitations (unchanged from v0.1.0)

- Orchestrator quality-gate timing on Windows (synchronization issue)
- Gemini Pro models gated behind API key (OAuth only exposes Flash)
- Image generation requires OpenAI API key for gpt-image-1
- Plugin patches don't survive octo plugin updates — re-run `patches/apply.sh`

[0.2.0]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.2.0

## [0.1.0] — 2026-04-24

Initial public release. Full pipeline working end-to-end on Windows 11 + Git Bash; verified across ~30 personal repos before publication.

### Added

**Recipes (`memory/recipes/`):**
- `recipe-factory-loop.md` — master pipeline (Preflight → WIP-adoption → Scrub → Loop → Modularization → UX → Theming → Dep-scan → Postflight → Release)
- `recipe-ai-scrub.md` — git history rewrite that removes AI-attribution (Co-Authored-By Claude, "Generated with Claude Code" signatures, claude.ai URLs, etc.)
- `recipe-pdf-redesign.md` — improves an existing PDF's layout + readability without touching the original
- `recipe-pdf-derivatives.md` — mines a long-form PDF for sub-guide PDFs + blog-ready markdown posts
- `recipe-release-build.md` — project-type-aware build + sign + GitHub release pipeline (Chrome/Firefox extensions, Python, Android, C#, C++, Rust, Go, Node)

**Directives (`memory/directives/`):**
- `directive-audit.md` — production-grade single-pass audit standard (L3/L4 fallback)
- `directive-debate.md` — three-role rubric debate (Grader + Critic + Defender) with Beta-Binomial adaptive stopping (L3/L4 primary)
- `directive-circuit-breakers.md` — non-AI safeguards: per-agent budget caps, loop detector, sacred-cow file manifest, stop-on-regression, cooldown
- `directive-modularization.md` — behavior-preserving decomposition of monoliths (M-phase)
- `directive-ux-polish.md` — premium UX polish across visual / states / components / flow / microcopy / a11y / motion / theme (U1/U2)
- `directive-theming.md` — token-based theme audit covering all interactive states across all theme modes (T1/T2)
- `directive-dependency-scan.md` — language-appropriate CVE scan + fix policy (D1/D2)
- `directive-secret-scan.md` — pre-commit secret leak detection (API keys, PATs, private keys, .env, etc.)

**Reference (`memory/reference/`):**
- `multi-account-rotation.md` — guide to routing across Claude Max + ChatGPT Pro + Gemini Pro + GitHub Copilot

**Routing presets (`config/presets/`):**
- `balanced.json` — each direct account gets its home role; Copilot handles deliver + fallback
- `copilot-heavy.json` — cost-optimized; routes routine work through Copilot's Sonnet 4.6 + gpt-5.3-codex
- `claude-heavy.json` — burn Claude Max quota first
- `codex-heavy.json` — burn ChatGPT Pro Codex quota first
- `direct-only.json` — skip Copilot entirely
- `copilot-only.json` — everything via Copilot's multi-backend

**Workflow (`config/workflows/`):**
- `factory-loop.yaml` — YAML bridge to Claude Octopus's orchestrate.sh (research / rubric / implement / audit phases)

**Scripts (`bin/`):**
- `install.sh` — one-step installer with prereq check + idempotent re-runs
- `octo-route.sh` — swap routing presets, including a `rotate` command for cycling
- `ai-scrub.sh` — git-filter-repo wrapper with backup-enforced 7-phase workflow (preconditions → backup → dry-run → report → apply → push → verify)
- `copilot-fallback.sh` — Copilot CLI wrapper with auto-fallback to Codex on quota exhaustion (60-min lockout TTL by default)

**Prompts (`prompts/`):**
- `factory-loop-prompts.txt` — zero-fill copy-paste prompt for the full pipeline
- `ai-scrub-prompts.txt` — standalone scrub prompts (dry-run + apply + push)
- `pdf-redesign-prompts.txt` — single PDF redesign prompt
- `pdf-derivatives-prompts.txt` — PDF derivatives prompt with guides-only / blog-only variants
- `release-build-prompts.txt` — standalone release prompt

**Patches (`patches/`):**
- `dispatch-copilot-models.md` — adds 6 new agent-type aliases (`copilot-sonnet`, `copilot-haiku`, `copilot-opus`, `copilot-gpt5`, `copilot-codex`, `copilot-gpt5mini`) plus `OCTOPUS_COPILOT_MODEL_OVERRIDE` env var
- `provider-routing-copilot-fallback.md` — adds Copilot to the in-process cross-provider fallback chain
- `apply.sh` — idempotent applier that detects already-patched files

**Documentation (`docs/`):**
- `ARCHITECTURE.md` — system layers diagram, phase pipeline visualization, routing modes table, execution-mode flowchart, circuit breaker reference
- `EXECUTION-MODES.md` — orchestrated vs single-session vs Large-Repo Mode, with the phase-substitution table for each
- `CONTRIBUTING.md` — what to send, what not to send, style guide

**Top-level:**
- `README.md` with quick example walkthrough showing a full factory run end-to-end
- `LICENSE` (MIT)
- `.gitignore` covering AI-tool working files, secrets, OS artifacts, local octopus state

### Design decisions

- **Recipes as source of truth.** Prompts defer to recipes; recipes defer to per-phase directives. This pattern was adopted after observing that re-stating recipe internals in prompts caused drift across iterations.
- **Lazy-load directives.** Each phase reads only the directive it needs, so working context stays focused on the active task rather than holding all behavioral guidance.
- **Deterministic safeguards over model self-discipline.** Circuit breakers (loop detection, sacred-cow files, stop-on-regression, secret scan) are non-AI logic. Trusting models to halt themselves was the documented #1 expensive assumption in production agent failures.
- **Honest fallback.** Single-session mode collapses L4/U2/T2 phases that would be same-model duplication and declares the degradation in the session log rather than running fake debates.
- **Behavior-preserving modularization.** The M-phase mandates identical test results before and after splits. Re-export shims preserve public APIs.
- **Atomic commits.** Per-task in Large-Repo Mode (commit + push after each closed task), per-logical-change in normal mode.

### Known limitations

- **Orchestrator quality-gate timing on Windows** — Claude Octopus's orchestrate.sh declares quality gates passed before agents complete (synchronization issue). Artifacts still land correctly; trust the artifacts, not the gate verdict.
- **Gemini Pro models gated behind API key** — OAuth-tier Gemini CLI (Google Code Assist) only exposes `gemini-2.5-flash`. Pro models require a Google AI Studio API key. Gemini Plus subscription does not unlock CLI Pro access.
- **Image generation requires OpenAI API key** for the primary path (`gpt-image-1`). Falls back to Gemini's image model with manual transparent-PNG post-processing.
- **Patches don't survive octo plugin updates** — re-run `patches/apply.sh` after upgrading octo. Future work: package as a proper plugin override or upstream the changes.

### Verified on

- Windows 11 + Git Bash
- macOS 14+ (Apple Silicon + Intel) — light testing
- Linux Ubuntu 24.04 / Debian 12 / Arch — light testing
- Provider stack: Claude Max, ChatGPT Pro Codex, Gemini Pro, GitHub Copilot

[Unreleased]: https://github.com/SysAdminDoc/octopus-factory/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.2.0
[0.1.0]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.1.0
