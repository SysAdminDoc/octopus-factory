# octopus-factory

Recipe-driven autonomous coding pipeline for [Claude Code](https://claude.ai/code) + [Claude Octopus](https://github.com/nyldn/claude-octopus). Spec-in, software-out — with build gates, secret scans, multi-provider routing, and rollback on failure.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey.svg)](#install)
[![Status](https://img.shields.io/badge/status-alpha-orange.svg)](#status)

---

## What this is

A pack of recipes, directives, scripts, configs, and prompts that turn Claude Code + the [Claude Octopus](https://github.com/nyldn/claude-octopus) plugin into a multi-agent autonomous coding pipeline. You hand it a repo path and one prompt; it runs:

```
Preflight  →  WIP-adoption  →  AI-history scrub  →  Loop (research → rubric →
implement → audit-debate → doc-sync → commit)  →  Modularization  →  UX polish
→  Theming  →  CVE/dep scan  →  Security review  →  Multi-LLM review  →
Release (project-type-aware build + sign + SBOM + provenance)  →  Continuation brief
```

Across **four AI subscriptions** (Claude Max + ChatGPT Pro Codex + Gemini Pro + GitHub Copilot) with auto-fallback when any quota exhausts.

## Why

Three problems this solves:

1. **One-shot prompts blow up on real repos.** A 50K LOC codebase doesn't fit in one Claude session. This pack chunks work into finite per-run iterations with persistent state across runs.
2. **Single-model verification has blind spots.** The audit phase runs a three-role debate (Grader + Critic + Defender, different model families) instead of trusting one model to grade its own work.
3. **Provider quotas exhaust unpredictably.** Cost-balanced routing across four AI subscriptions with auto-fallback when any single quota runs out.

## Status

**Alpha.** Used in production by the author across ~30 repos. APIs and config formats may change before v1.0. PRs welcome.

Verified working on:
- Windows 11 + Git Bash
- macOS (Apple Silicon + Intel)
- Linux (Ubuntu / Debian / Arch)

Provider stack tested:
- Claude Max (Sonnet 4.6 / Opus 4.7 via Claude Code)
- ChatGPT Pro (Codex CLI, gpt-5.4 / gpt-5.3-codex)
- Gemini (CLI, gemini-2.5-flash on free tier; Pro requires API key)
- GitHub Copilot (CLI, all Sonnet/Opus/Haiku/GPT-5.x models)

## Install

### Prerequisites

- [Claude Code](https://claude.ai/code) installed and authenticated
- [Claude Octopus plugin](https://github.com/nyldn/claude-octopus) installed in Claude Code
- At least one of: ChatGPT Pro (Codex CLI), Gemini Pro (Gemini CLI), GitHub Copilot subscription
- `git`, `bash` (or Git Bash on Windows), `python` 3.10+, `jq`
- Optional but recommended: `git-filter-repo` (for AI-scrub recipe), `cloc` (for modularization scale checks)

### One-line install (macOS / Linux / Git Bash)

```bash
git clone https://github.com/<your-username>/octopus-factory.git ~/octopus-factory && \
  bash ~/octopus-factory/bin/install.sh
```

### Manual install

1. **Clone:**
   ```bash
   git clone https://github.com/<your-username>/octopus-factory.git ~/octopus-factory
   ```

2. **Drop recipes/directives into Claude Code's memory:**
   ```bash
   # Path varies by OS; this is the Claude Code memory dir for your active project
   cp -r ~/octopus-factory/memory/* ~/.claude/projects/<your-project>/memory/
   ```

3. **Drop scripts into your octopus bin:**
   ```bash
   mkdir -p ~/.claude-octopus/bin
   cp ~/octopus-factory/bin/*.sh ~/.claude-octopus/bin/
   chmod +x ~/.claude-octopus/bin/*.sh
   ```

4. **Drop config into your octopus config:**
   ```bash
   mkdir -p ~/.claude-octopus/config/{presets,workflows}
   cp ~/octopus-factory/config/presets/* ~/.claude-octopus/config/presets/
   cp ~/octopus-factory/config/workflows/* ~/.claude-octopus/config/workflows/
   # Pick a preset to start
   cp ~/octopus-factory/config/presets/balanced.json ~/.claude-octopus/config/providers.json
   ```

5. **Apply the optional patches** (for per-role Copilot model selection + auto-fallback to Codex):
   ```bash
   bash ~/octopus-factory/patches/apply.sh
   ```

6. **Drop prompts where you'll find them:**
   ```bash
   mkdir -p ~/repos/ai-prompts
   cp ~/octopus-factory/prompts/* ~/repos/ai-prompts/
   ```

### Verify

```bash
~/.claude-octopus/bin/octo-route.sh status
# Should show your active routing mode + list of available presets
```

## Use

### First run (one prompt, zero fill-in)

In a Claude Code session, type:

```
Pull up ~/repos/<your-project>
```

Then paste the contents of `prompts/factory-loop-prompts.txt`. Send. The factory does its thing.

The prompt auto-detects:
- New project (no `.git`) vs existing
- Stack from build files
- Goal from ROADMAP / pending releases / open audit findings
- Iteration count from project state
- Scope guards from your repo's `CLAUDE.md`

Nothing else to fill in.

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
  recipes/        — workflow specs (factory-loop, ai-scrub, pdf-redesign, etc.)
  directives/     — phase-specific behavior (audit, debate, ux-polish, theming,
                    dep-scan, secret-scan, modularization, circuit-breakers)
  reference/      — multi-account-rotation guide
bin/
  octo-route.sh        — swap routing presets
  ai-scrub.sh          — git history rewrite (removes AI attribution)
  copilot-fallback.sh  — Copilot wrapper with auto-fallback to Codex on quota error
config/
  presets/             — 6 routing modes (balanced, copilot-heavy, claude-heavy,
                         codex-heavy, direct-only, copilot-only)
  workflows/           — YAML workflow bridge for octo's orchestrate.sh
prompts/
  *.txt                — copy-paste-ready zero-fill prompts
patches/
  *.patch              — small patches to octo plugin for per-role Copilot
                         model selection + cross-provider fallback chain
docs/
  ARCHITECTURE.md      — how the pieces fit together
  EXECUTION-MODES.md   — orchestrated vs single-session vs Large-Repo modes
  CONTRIBUTING.md      — how to extend
```

## Key design principles

- **Recipe is the source of truth.** Prompts are short and defer to recipes; recipes defer to per-phase directives. Directives are loaded lazily so context stays focused.
- **Behavior-preserving where possible.** Modularization phase mandates identical test results before/after. Audit phase root-causes bugs instead of suppressing.
- **Deterministic safeguards over model self-discipline.** Loop detector, per-agent budgets, sacred-cow file manifest, secret scan, stop-on-regression — all non-AI gates.
- **Honest fallback.** When the orchestrator isn't available the recipe runs in single-session mode and declares the degradation in the log. When a provider quota exhausts, the wrapper transparently routes to a fallback.
- **Atomic commits.** Per-task in Large-Repo Mode. Per-logical-change in normal mode. Never mega-commits.
- **No AI-attribution in committed code.** L7 commit gate enforces role-based commit messages; the AI-scrub recipe rewrites history of repos that already have attribution.

## Caveats

- **Premium AI subscriptions assumed.** The default `balanced` mode expects Claude Max + ChatGPT Pro + Copilot. The `copilot-only` preset works on Copilot alone. `direct-only` works without Copilot.
- **Image generation** requires either an OpenAI API key (for `gpt-image-1`) or fallback to Gemini's image model (free tier sufficient for most uses).
- **Windows quirks documented**, but most testing happened on Windows 11 + Git Bash. macOS / Linux paths exist but get less rotation.
- **Quotas burn.** A typical factory run consumes roughly $1-3 in API usage (or equivalent Claude Max / Copilot Premium Requests). Heavy multi-iteration runs can hit $10+. Monitor `OCTOPUS_FACTORY_MAX_SPEND` env var.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

Built on top of [Claude Octopus](https://github.com/nyldn/claude-octopus) by nyldn. Concepts borrowed from:

- [LangGraph](https://github.com/langchain-ai/langgraph) (durable execution + checkpointing patterns)
- ICLR 2026 — "Rethinking LLMs as Verifiers" (rubric-conditioned debate)
- arXiv 2510.12697 — "Multi-Agent Debate for LLM Judges with Adaptive Stability Detection"
- Factory's anchored summarization pattern
- SLSA framework + Sigstore (release supply-chain hardening)

## Contributing

PRs welcome. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines. Specific areas where help is wanted:

- macOS / Linux portability fixes
- Additional preset configurations for other AI subscription combos
- Stack-specific build recipes for languages not yet covered (Elixir, Swift, Kotlin/Native, etc.)
- Investigation of the orchestrator's quality-gate timing on Windows
- Bridge work to make `factory-loop.yaml` invokable directly via `orchestrate.sh --workflow <name>`

## Related projects

- [Claude Octopus](https://github.com/nyldn/claude-octopus) — the orchestration framework this builds on
- [Claude Code](https://claude.ai/code) — Anthropic's CLI/IDE for Claude
- [Codex CLI](https://github.com/openai/codex-cli) — OpenAI's CLI
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) — Google's CLI
- [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) — GitHub's CLI
