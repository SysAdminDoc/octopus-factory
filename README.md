# octopus-factory

A recipe-driven autonomous coding pipeline for [Claude Code](https://claude.ai/code) + [Claude Octopus](https://github.com/nyldn/claude-octopus). Hand it a repo path and one prompt; it researches, builds, audits, releases — across four AI subscriptions, with build gates, secret scans, cost caps, and rollback on failure.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey.svg)](#install)
[![Status](https://img.shields.io/badge/status-alpha-orange.svg)](#status)

---

## Quick example

You have an existing repo. Code's a bit messy. Open ROADMAP. No release in months. You want it cleaned up, audited, and shipped.

**You type:**

```
Pull up ~/repos/my-cli-tool
```

then paste the contents of `prompts/factory-loop-prompts.txt`. Send.

**What happens (single-session mode, ~25 minutes, ~$2 in API spend):**

```
[1] Session log started: ~/.claude-octopus/logs/factory-my-cli-tool-20260424-153022.log
[2] Detected: existing repo, Python CLI, 12K LOC, 84 tests, 7 ROADMAP items
[3] Mode: single-session (no orchestrator). Below scale gate (Large-Repo Mode not engaged).

[W-phase] WIP adoption
    - 3 untracked files classified: 1 lockfile, 1 test, 1 src
    - 3 atomic commits + push (secret scan + sacred-cow gate passed)

[S-phase] AI-reference scrub
    - Scanned 142 commit messages
    - Found 18 with "Co-Authored-By: Claude" trailers
    - Backup: ~/repos/backups/my-cli-tool-20260424-153211.bundle
    - Backup branch: origin/pre-ai-scrub-20260424-153211
    - Rewrite + force-push complete

[L-phase] 3 iterations
    Iteration 1:
        L1a research: Gemini scanned recent CLI patterns, OSS competitors
        L1b augment: Claude added 5 ROADMAP tasks based on gap analysis
        L2 implement: closed 8 P0/P1 items (PEC rubrics + atomic commits)
        L3+L4 audit: Claude rubric check (single-session mode), 2 fixes applied
        L5 doc sync: CHANGELOG "Unreleased" updated
        L7 commits: 11 atomic commits + push (all secret-scan passed)
    Iteration 2: closed 4 more items, audit clean
    Iteration 3: ROADMAP empty + audit clean → stop-early triggered

[M-phase] Modularization
    - Found 1 monolith: src/main.py (1,847 LOC)
    - Split into: src/cli.py + src/parser.py + src/commands.py + src/io.py
    - Tests pass identically (84/84)
    - 4 atomic refactor commits + push

[U-phase] Skipped (CLI tool, no UI)
[T-phase] Skipped (no UI)

[D-phase] Dependency scan
    - pip-audit: 2 medium CVEs found in transitive deps
    - Updated requests 2.31.0 → 2.32.3, urllib3 1.26.18 → 2.2.3
    - Tests still pass

[Q-phase] Postflight + release
    Q1 /octo:security: 0 critical, 1 medium (input validation) — fixed
    Q2 /octo:review: pass
    Q3 release v0.4.0:
        - Single version bump applied (manifest, README badge, CHANGELOG)
        - Tagged v0.4.0, pushed
        - GitHub Actions release.yml ran matrix build (win/mac/linux)
        - Artifacts: my-cli-tool-v0.4.0-{win-x64.exe,macos-arm64,linux-x64} + SHA256SUMS
        - Smoke-test: each artifact's --version returns "0.4.0" ✓
        - SBOM (syft) + cosign-signed provenance attached
    Q4 continuation brief appended to repo CLAUDE.md

[Done] 19 commits, 1 release shipped, ~12 minutes wallclock, $1.87 spent.
```

You went from a messy WIP repo to a signed, multi-platform release with clean history. No prompt re-iteration. No babysitting.

---

## What this is

A pack of recipes, directives, scripts, configs, and prompts that turns Claude Code + the [Claude Octopus](https://github.com/nyldn/claude-octopus) plugin into a multi-agent autonomous coding pipeline. The full lifecycle in one prompt:

```
Preflight  →  WIP-adoption  →  AI-history scrub  →  Loop (research → rubric →
implement → audit-debate → doc-sync → commit)  →  Modularization  →  UX polish
→  Theming  →  CVE/dep scan  →  Security review  →  Multi-LLM review  →
Release (project-type-aware build + sign + SBOM + provenance)  →  Continuation brief
```

Across **four AI subscriptions** — Claude Max, ChatGPT Pro Codex, Gemini Pro, GitHub Copilot — with auto-fallback when any quota exhausts.

## What problems this solves

Three real problems with single-prompt AI coding:

1. **One-shot prompts blow up on real repos.** A 50K LOC codebase doesn't fit in one Claude session. The factory chunks work into finite per-run iterations with persistent state across runs (`Large-Repo Mode`).

2. **Single-model verification has blind spots.** The audit phase runs a three-role debate (Grader + Critic + Defender, different model families) instead of trusting one model to grade its own work.

3. **Provider quotas exhaust unpredictably.** Six routing presets spread cost across four subscriptions; if Copilot hits its monthly cap mid-run, the wrapper transparently falls back to Codex without aborting.

## Status

**Alpha.** Used in production by the author across ~30 repos. APIs and config formats may change before v1.0. PRs welcome (see [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)).

Verified working on:
- Windows 11 + Git Bash
- macOS (Apple Silicon + Intel)
- Linux (Ubuntu / Debian / Arch)

Provider stack tested:
- Claude Max (Sonnet 4.6 / Opus 4.7 via Claude Code)
- ChatGPT Pro (Codex CLI: gpt-5.4, gpt-5.3-codex)
- Gemini Pro (CLI: gemini-2.5-flash on free tier; Pro models require API key)
- GitHub Copilot (CLI: all Sonnet/Opus/Haiku/GPT-5.x backends)

## Install

### Prerequisites

- [Claude Code](https://claude.ai/code) installed and authenticated
- [Claude Octopus plugin](https://github.com/nyldn/claude-octopus) installed in Claude Code
- At least one of: ChatGPT Pro (Codex CLI), Gemini Pro (Gemini CLI), GitHub Copilot subscription
- `git`, `bash` (or Git Bash on Windows), `python` 3.10+, `jq`
- Optional but recommended: `git-filter-repo` (AI-scrub), `cloc` (modularization scale checks), `syft` (SBOM), `cosign` (artifact signing), [`just`](https://github.com/casey/just) (unified task runner — see [Use → just](#just-recommended))

### One-line install

```bash
git clone https://github.com/SysAdminDoc/octopus-factory.git ~/octopus-factory && \
  bash ~/octopus-factory/bin/install.sh
```

The installer:
- Drops `bin/` scripts into `~/.claude-octopus/bin/` (made executable)
- Drops `config/presets/` and `config/workflows/` into `~/.claude-octopus/config/`
- Initializes `providers.json` to the `balanced` preset (if not already present)
- Drops `prompts/` into `~/repos/ai-prompts/`
- Tells you where to copy `memory/recipes/` and `memory/directives/` (project-specific)
- Suggests applying the optional Claude Octopus patches via `bash patches/apply.sh`

### Manual install

See `bin/install.sh` for the exact steps if you'd rather copy them by hand.

### Verify

```bash
~/.claude-octopus/bin/octo-route.sh status
```

Should print the active routing mode and a list of available presets.

## Use

### The default invocation (one prompt, zero fill-in)

In a Claude Code session, type:

```
Pull up ~/repos/<your-project>
```

Then paste the contents of `prompts/factory-loop-prompts.txt`. Send.

The prompt auto-detects:
- **New project (no `.git`)** vs existing
- **Stack** from build files
- **Goal** from ROADMAP / pending releases / open audit findings
- **Iteration count** from project state
- **Scope guards** from your repo's `CLAUDE.md`
- **Execution mode** based on whether the orchestrator is available
- **Large-Repo Mode** auto-engages if scale exceeds 50K LOC / 500 files / 1K tests / 30 ROADMAP items

Nothing else to fill in.

### just (recommended)

If you have [`just`](https://github.com/casey/just) installed, every `bin/` script is exposed as a discoverable, grouped recipe. From the repo root:

```bash
just                          # list all recipes (grouped: preflight / phases / state / tools / dev)
just doctor                   # pre-flight diagnostic
just route copilot-heavy      # swap routing preset
just codex audit              # dispatch the audit phase to direct Codex
just secret-scan              # gitleaks pass on working tree
just dep-scan                 # osv-scanner CVE pass
just checkpoint cp_init       # initialize shadow-git checkpoint store
just version                  # show version + dependency status
```

Recipes are thin pass-throughs to `bin/<script>.sh` — every flag the underlying script accepts works after the recipe name (`just doctor --json`, `just codex audit --model gpt-5.4`, etc.). No magic, just discoverability.

Install: `brew install just` / `apt install just` / `winget install Casey.Just`.

### Routing modes

```bash
~/.claude-octopus/bin/octo-route.sh                # show current mode + list presets
~/.claude-octopus/bin/octo-route.sh balanced       # spread load across all 4 quotas
~/.claude-octopus/bin/octo-route.sh copilot-heavy  # offload Claude Max + ChatGPT Pro to Copilot
~/.claude-octopus/bin/octo-route.sh claude-heavy   # burn Claude Max quota first
~/.claude-octopus/bin/octo-route.sh codex-heavy    # burn ChatGPT Pro quota first
~/.claude-octopus/bin/octo-route.sh direct-only    # skip Copilot entirely
~/.claude-octopus/bin/octo-route.sh copilot-only   # everything via Copilot
~/.claude-octopus/bin/octo-route.sh rotate         # cycle to next mode
```

Pick `copilot-heavy` if you want to preserve Claude Max + ChatGPT Pro quotas. Pick `balanced` for the default mix. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for what each preset routes where.

**Authoring or modifying presets.** Each preset is generated from `config/presets/overlays/_base.json` (fields shared across every mode — provider catalog, tiers, semantics) plus `config/presets/overlays/<mode>.json` (mode-specific routing + descriptive metadata). To change the codex catalog or tier semantics for every preset, edit `_base.json` once and run `just preset-build`. To add a new preset, drop a new `overlays/<name>.json` and rebuild. `just preset-verify` exits non-zero if any committed `presets/<mode>.json` has drifted from its source — wire it into pre-commit / CI to keep base+overlay the single source of truth.

### Other recipes

| Recipe | Trigger | What it does |
|---|---|---|
| **Factory loop** | Paste `prompts/factory-loop-prompts.txt` | Full autonomous pipeline (default) |
| **AI-reference scrub** | Paste `prompts/ai-scrub-prompts.txt` | Removes "Co-Authored-By: Claude" + AI signatures from git history (with backups) |
| **PDF redesign** | Paste `prompts/pdf-redesign-prompts.txt` | Improves an existing PDF's layout + readability without modifying the original |
| **PDF derivatives** | Paste `prompts/pdf-derivatives-prompts.txt` | Mines a long-form PDF for sub-guide PDFs + blog-ready markdown posts |
| **Release build** | Paste `prompts/release-build-prompts.txt` | Project-type-aware build + sign + GitHub release (Chrome/Firefox extensions, Python, Android, C#, Rust, Go, Node) |

## What's inside

```
memory/
  recipes/        — workflow specs (factory-loop, ai-scrub, pdf-redesign,
                    pdf-derivatives, release-build)
  directives/     — phase-specific behavior (audit, debate, ux-polish, theming,
                    dep-scan, secret-scan, modularization, circuit-breakers)
  reference/      — multi-account-rotation guide
bin/
  octo-route.sh        — swap routing presets
  ai-scrub.sh          — git history rewrite (removes AI attribution)
  copilot-fallback.sh  — Copilot wrapper with auto-fallback to Codex on quota error
  install.sh           — one-step installer
config/
  presets/             — 6 routing modes (balanced, copilot-heavy, claude-heavy,
                         codex-heavy, direct-only, copilot-only) — generated from
                         overlays/_base.json + overlays/<mode>.json via build.sh
  presets/overlays/    — source of truth: shared base + per-mode delta. Edit here.
  presets/build.sh     — rebuild presets / verify drift (`just preset-build`,
                         `just preset-verify`)
  workflows/           — YAML workflow bridge for octo's orchestrate.sh
prompts/
  *.txt                — copy-paste-ready zero-fill prompts
patches/
  *.md / apply.sh      — optional patches to octo plugin for per-role Copilot
                         model selection + cross-provider fallback chain
docs/
  ARCHITECTURE.md      — how the pieces fit together
  EXECUTION-MODES.md   — orchestrated vs single-session vs Large-Repo modes
  CONTRIBUTING.md      — how to extend
```

## Design principles

- **Recipe is the source of truth.** Prompts are short and defer to recipes; recipes defer to per-phase directives. Directives load lazily so context stays focused.
- **Behavior-preserving where it matters.** The modularization phase mandates identical test results before and after. The audit phase root-causes bugs instead of suppressing them.
- **Deterministic safeguards over model self-discipline.** Loop detector, per-agent budgets, sacred-cow file manifest, secret scan, stop-on-regression — all non-AI gates.
- **Honest fallback.** When the orchestrator isn't available the recipe runs in single-session mode and declares the degradation in the log. When a provider quota exhausts, the wrapper transparently routes to a fallback.
- **Atomic commits.** Per-task in Large-Repo Mode. Per-logical-change in normal mode. Never mega-commits.
- **No AI-attribution in committed code.** The L7 commit gate enforces role-based commit messages; the AI-scrub recipe rewrites history of repos that already have attribution.

## What this does that nothing else does

A survey of related projects (Aider, Cline, OpenHands, RA.Aid, Continue, MetaGPT, LangGraph) found these to be the genuine differentiators:

1. **Three-role debate with cross-family pinning.** Aider/Cline/OpenHands are single-model. The factory's audit phase runs Grader (cheap) + Critic (one premium family) + Defender (different premium family) with adaptive Beta-Binomial stopping.
2. **Cross-provider quota fallback chain at the role level.** `copilot-fallback.sh` chains Claude → Codex → Gemini → Copilot per role with subscription/auth awareness. Aider has model fallback within one provider call; nobody else chains across providers per role.
3. **Recipe + lazy-loaded directive split.** Closest to OpenHands microagents, but goes further: directives are role-scoped, not just keyword-triggered. Working context stays focused on the active phase rather than holding all behavioral guidance.
4. **Holdout-scenario integrity check** (inherited from Octopus's `factory.sh`). Deterministic-shuffle 20% holdout with a cross-model evaluator. None of the agent tools have an integrity firewall against the implementer seeing the tests.
5. **Cost-gated phase progression with auth-mode awareness.** Distinguishes API-billed vs subscription-included providers, then gates Q3 release on running total. Cline tracks cost; doesn't gate on it.

See [ROADMAP.md](ROADMAP.md) for the prioritized list of integrations from those same projects (12 specific items with source citations and effort estimates).

## Caveats

- **Premium AI subscriptions assumed.** The default `balanced` mode expects Claude Max + ChatGPT Pro + Copilot. The `copilot-only` preset works on Copilot alone. The `direct-only` preset works without Copilot.
- **Image generation** requires either an OpenAI API key (for `gpt-image-1`) or fallback to Gemini's image model (free tier sufficient for most uses).
- **Windows quirks documented**, but most testing happened on Windows 11 + Git Bash. macOS / Linux paths exist but get less rotation.
- **Quotas burn.** A typical factory run consumes roughly $1-3 in API usage (or equivalent Claude Max / Copilot Premium Requests). Heavy multi-iteration runs can hit $10+. Monitor via `OCTOPUS_FACTORY_MAX_SPEND` env var.

## Acknowledgments

Built on top of [Claude Octopus](https://github.com/nyldn/claude-octopus) by nyldn. Concepts borrowed from:

- [LangGraph](https://github.com/langchain-ai/langgraph) (durable execution + checkpointing patterns)
- ICLR 2026 — "Rethinking LLMs as Verifiers" (rubric-conditioned debate)
- arXiv 2510.12697 — "Multi-Agent Debate for LLM Judges with Adaptive Stability Detection"
- Factory's anchored summarization pattern
- SLSA framework + Sigstore (release supply-chain hardening)

## Related projects

- [Claude Octopus](https://github.com/nyldn/claude-octopus) — the orchestration framework this builds on
- [Claude Code](https://claude.ai/code) — Anthropic's CLI/IDE for Claude
- [Codex CLI](https://github.com/openai/codex-cli) — OpenAI's CLI
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) — Google's CLI
- [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) — GitHub's CLI

## Contributing

PRs welcome. See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md). Specific areas where help is wanted:

- macOS / Linux portability fixes
- Additional preset configurations for other AI subscription combos
- Stack-specific build recipes for languages not yet covered (Elixir, Swift, Kotlin/Native, Tauri, Flutter, etc.)
- Investigation of the orchestrator's quality-gate timing on Windows
- Bridge work to make `factory-loop.yaml` invokable directly via `orchestrate.sh --workflow <name>`

## License

MIT — see [LICENSE](LICENSE).
