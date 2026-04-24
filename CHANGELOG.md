# Changelog

All notable changes to octopus-factory will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- (track future improvements here)

---

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

[Unreleased]: https://github.com/SysAdminDoc/octopus-factory/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.1.0
