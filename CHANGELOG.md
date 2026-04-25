# Changelog

All notable changes to octopus-factory will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — `tools/prompt-builder/` GUI helper application

A companion PyQt6 desktop app that assembles factory prompts via a form + live preview, ending in a one-click clipboard copy. Lives at `tools/prompt-builder/` so prompt templates stay in sync with `prompts/examples.md` and the canonical recipes.

**Layout:** three-pane window (Catppuccin Mocha dark theme via QSS).
- **Left rail:** template picker — Factory Loop / Overnight / Audit-Only / Plan / Single Task / Roadmap Research / Release Build / AI Scrub / PDF Redesign / PDF Derivatives.
- **Middle column:** per-template form. Fields render automatically from a typed `Field` definition (`path` with Browse button / `text` / `multiline` / `int` spinner / `choice` combo / `checkbox` / `paths` multi-line for overnight repo lists).
- **Right column:** live monospace prompt preview + Copy / Save / Reset buttons + line/char counter.

**Per-template fields cover the real knobs:**
- Factory Loop: iteration count (1-7 slider), routing preset (6-way combo), 11 mode flags as checkboxes (`--audit-only`, `--skip-preflight`, `--skip-scrub`, `--manual-scrub`, `--skip-wip-adoption`, `--skip-logo`, `--force-logo`, `--raster-logo`, `--final-codex-pass`, `--require-orchestrator`, `--single-session`), `--plan` toggle, freeform notes.
- Overnight: multi-line repo list, duration presets (1h / 2h / 4h / 8h / weekend / custom), max-spend, convergence rotations, sleep, cycle timeout, auto-discover dir, `--no-rotate` / `--quiet` / `--fail-fast` / `--require-clean-tree` toggles, foreground vs detached launch.
- Audit-Only / Plan / Single Task / Roadmap Research / Release / AI Scrub / PDF Redesign / PDF Derivatives: appropriately scoped per type.

**Live preview behavior:** every field change re-renders the prompt in real time. The preview is editable — last-mile tweaks before copy stay in the buffer until Reset. Cursor position is preserved across re-renders so editing isn't disrupted by knob changes.

**Output paths:** Copy to clipboard (Ctrl+Shift+C), Save as `.txt` to disk, Reset to defaults (Ctrl+R).

**Build pipeline:** PyInstaller spec (`prompt-builder.spec`) bundles to a single ~50MB executable. Both `prompt_builder/__main__.py` and the runtime hook call `multiprocessing.freeze_support()` per the global PyInstaller fork-bomb guards in `~/.claude/CLAUDE.md`. Excludes tkinter / test / pip / setuptools / wheel from the bundle to trim size.

**Ship-from-source:** `just prompt-builder` launches the GUI via `python -m prompt_builder`. `just prompt-builder-build` produces the standalone executable.

**Verified:**
- All 10 templates render with default values without exception.
- Window constructs cleanly under headless `QT_QPA_PLATFORM=minimal`.
- Templates cover every prompt scenario in `prompts/examples.md`.
- PyQt6 6.10.0 import works on the dev machine; spec excludes-list trimmed.

**Why this exists:** the canonical `prompts/examples.md` library covers 14 scenarios but tweaking iteration counts / model presets / flag combinations means hand-editing before pasting. The GUI removes that friction — every knob is a form field, the preview re-renders live, the Copy button hands you a finished prompt. Especially useful on Windows where shell-piping prompts is awkward.

### Changed — Overnight wrapper: live visibility + 15 new flags
**Why:** user feedback on v0.6.0: "When overnight runs, I can't see what it's doing." Cycle output was being written exclusively to `~/.claude-octopus/logs/overnight/<run-id>/cycle-NNN.log` with nothing on the terminal — silent until summary. Fixed alongside a feature batch.

**Live cycle output is now the default.** `claude` invocation pipes through `tee "$CYCLE_LOG"` so output goes to your terminal AND the per-cycle log simultaneously. `PIPESTATUS[0]` preserves claude's exit code (tee always succeeds). Opt out with `--quiet` / `-q` to restore the silent log-only behavior.

**Heartbeat ticker.** While a cycle is running (which can be silent for minutes during long claude thinking turns), a backgrounded loop prints `[heartbeat] cycle 3 | Astra-Deck | running 247s` every 30 seconds to stderr. Configurable with `--heartbeat-sec N` (set to 0 to disable). Cleaned up on cycle exit and on signal.

**ANSI color** on outcome lines and event tags. `advanced=green`, `researched=cyan`, `no-op=yellow`, `STOP/error=red`. Auto-disabled when stdout isn't a TTY; force off with `--no-color`.

**`--show-config`** dumps the effective configuration and exits. Use it before kicking off a long run to confirm the discovered repo set, exclude filters, end time, budget, etc. resolved as intended.

**New flags (15):**

| Flag | Effect |
|---|---|
| `--quiet` / `-q` | Suppress live cycle output (log file only) |
| `--no-color` | Disable ANSI color in console output |
| `--heartbeat-sec N` | Heartbeat interval (default 30, 0 to disable) |
| `--start-time HH:MM` | Delayed start; wrapper sleeps until this wall-clock time |
| `--auto-discover DIR` | Find every git repo (depth=1) under DIR, add to repo list |
| `--exclude-repo PATTERN` | Skip repos whose path contains PATTERN; repeatable |
| `--shuffle-repos` | Randomize repo order at startup (Fisher-Yates via `shuf` if present, else `$RANDOM`) |
| `--healthcheck-url URL` | POST `/start` before each cycle, `/<rc>` after — Healthchecks.io / Better Stack format |
| `--notify SPEC` | End-of-run notification: `webhook=URL` (POST JSON), `ntfy=TOPIC` (ntfy.sh), or `desktop` (notify-send / osascript / msg.exe). Repeatable. |
| `--resume RUN_ID` | Rehydrate convergence streaks from a prior `state.json`; skips repos that already converged |
| `--fail-fast` | Abort the whole session on first non-zero cycle rc (default keeps going) |
| `--require-clean-tree` | Pre-flight: refuse to start if any repo has uncommitted changes |
| `--require-remote` | Pre-flight: refuse to start if any repo lacks `origin` remote |
| `--show-config` | Dump effective config and exit (for verifying flags before long runs) |
| `--pause` (sentinel) | `touch ~/.factory-overnight.pause` halts the loop between cycles until removed |

**Other improvements:**
- Better signal handling. Added `cleanup` trap (EXIT) + explicit SIGINT/SIGTERM handlers that kill the in-flight cycle child + heartbeat process and write the summary before exiting. Was previously a single `trap rm EXIT` with no child cleanup.
- Machine-readable status: `~/.factory-overnight.status.json` mirrors the human `.status` file. Includes streaks per repo so external monitoring can render dashboards.
- `state.json` per-run contains the same JSON payload, so `--resume` can rehydrate from any historical run dir.
- Run banner: `━━━ factory-overnight starting ━━━` and `━━━ Cycle N ━━━` separators so the user can scan the terminal without grep.
- `--auto-discover` skips its own internals: globs `<dir>/*/.git` (depth=2 from base) so nested submodules don't get mistakenly enumerated.

### Added
- `tests/bats/overnight.bats` — 11 new bats tests covering `--help`, `--show-config`, unknown-flag rejection, missing-repo rejection, non-existent-repo rejection, dry-run cycle, --max-cycles termination, --auto-discover happy path, --exclude-repo filtering, --status when idle, --stop sentinel creation. Auto-skips when local bash <4 (the script requires bash 4+). Total bats suite is now 40 tests across 5 files.

---

## [0.6.0] — 2026-04-25

Two threads converge in this release: the long-running infrastructure consolidation work that landed across nine post-v0.5.1 commits (justfile, overlay preset system, pre-commit hooks, bats tests, GitHub Actions CI, directive linter), AND a new overnight execution mode that lets the factory run for hours unattended via an external wrapper.

### Added — Overnight execution mode
- `bin/factory-overnight.sh` — round-robin wrapper for multi-hour unattended runs. Spawns a fresh `claude --print` per cycle to avoid context fragmentation; each cycle runs the recipe with `--overnight` (one Large-Repo Mode iteration, exits cleanly), then the wrapper sleeps + respawns. Wall-clock end time (`--until 06:00`), duration (`--duration 8h`), max-cycles cap, cumulative cost cap auto-distributed across cycles, per-cycle hard timeout (default 30 min), convergence-rotation counter that retires repos after N consecutive `no-op` cycles.
- `--overnight` recipe flag — forces Large-Repo Mode (one iteration, atomic per-task commits + push), disables stop-on-convergence within the cycle (the wrapper handles rotation across cycles), suppresses Q3 release on routine cycles, writes `cycle_outcome` (advanced / researched / no-op) to `.factory/state.yaml` so the wrapper's rotation counter knows when a repo has converged.
- `just overnight` recipe — pass-through to the wrapper with the same flags.
- Recipe gains an "Overnight Mode" section under Execution Modes documenting the wrapper contract, cycle outcomes, multi-repo round-robin behavior, status/halt commands, and an end-to-end example.
- Prompt template gains an "OPTIONAL: OVERNIGHT MODE" section explaining when to use the wrapper vs. paste the interactive prompt.
- Sentinel files: `~/.factory-overnight.lock` (active session marker), `~/.factory-overnight.stop` (graceful halt at next cycle boundary), `~/.factory-overnight.status` (human-readable status, auto-updated each cycle).
- Per-cycle log + end-of-run summary at `~/.claude-octopus/logs/overnight/<run-id>/`.

### Added — Infrastructure consolidation (nine post-v0.5.1 commits)
- `justfile` at repo root — discoverable, grouped task surface for every `bin/` script (`just`, `just doctor`, `just route copilot-heavy`, `just codex audit`, `just secret-scan`, etc.). Recipes are thin pass-throughs; all underlying flags work after the recipe name. Groups: preflight, phases, state, tools, dev. Closes the "no unified entry point on Windows" friction without touching any existing script. Install: `winget install Casey.Just` / `brew install just` / `apt install just`.
- `just` listed as optional prereq in `bin/install.sh` with per-platform install hints.
- README `### just (recommended)` subsection under **Use** with examples + install line.
- `config/presets/overlays/_base.json` + per-mode overlays — DRY source of truth for the 6 routing presets. Shared fields (provider catalog, tiers, `_tier_semantics`) live in `_base.json`; per-mode routing tables + descriptive metadata live in `overlays/<mode>.json`. Edit shared fields once, rebuild every preset.
- `config/presets/build.sh` — generates `presets/<mode>.json` from base + overlay via `jq -S -s '.[0] * .[1]'` (deep merge). Also `--verify` mode that diffs source against committed presets and exits non-zero on drift — wire into pre-commit / CI.
- `just preset-build` / `just preset-verify` recipes.
- `.githooks/pre-commit` — repo-local git hook that runs `preset-verify` whenever any `config/presets/` file (preset, overlay, or build script) is staged. Blocks commits where a generated preset has drifted from its source, with a message naming the offending file and the fix (`just preset-build && git add config/presets/`). `--no-verify` bypass available for intentional skips.
- `just hooks-install` / `just hooks-uninstall` — set/unset `core.hooksPath = .githooks`.
- `docs/CONTRIBUTING.md` gains a **First-time setup** section pointing at `just hooks-install`, and an **Editing routing presets** section documenting the overlay workflow.
- `tests/bats/` — automated test suite. 29 tests across 4 files: `syntax.bats` (`bash -n` on every shell script + executability), `presets.bats` (JSON validity, required schema fields, `_mode` ↔ filename, `build.sh --verify` clean, idempotent rebuild), `justfile.bats` (recipes parse + run; auto-skip if `just` not installed), `directives.bats` (frontmatter linter regression coverage). Catches the kind of silent failure that motivated v0.5.1's codex-direct workaround.
- `just test-bats` recipe (passes flags through — `just test-bats --tap` for CI output).
- `.github/workflows/ci.yml` — GitHub Actions matrix (Ubuntu / macOS / Windows Git Bash) running on every push to `main` + every PR. Steps: install just + bats → `just preset-verify` → `just lint-directives` → `just test-bats --tap`. CI badge added to README.
- `docs/CONTRIBUTING.md` gains a **Testing** section with local commands + CI link.
- `bin/lint-directives.py` — stdlib-only validator (no PyYAML, no jsonschema) for YAML frontmatter on every `memory/directives/*.md` + `memory/recipes/*.md`. Schema: `name` / `description` / `type ∈ {knowledge, reference}` required everywhere; directives additionally need non-empty `triggers` + `agents` arrays. Detects: missing fence, missing fields, wrong enum value, empty array, malformed key:value lines, duplicate keys, unknown fields with `did you mean ...?` suggestion. Closes the "malformed directive frontmatter silently fails the lazy loader" gap explicitly flagged in the v0.5.1 architecture review. UTF-8 output forced so the ✓/✗ lines render on Windows cp1252 consoles.
- `just lint-directives` recipe (passes flags through; `just lint-directives memory/directives/` to scope).
- `.githooks/pre-commit` gains a second branch: lints staged `memory/(directives|recipes)/*.md` files. Skips with a warning if `python3` is missing.

### Changed
- `bin/lint-directives.py` rejects unknown frontmatter fields with a `did you mean ...?` suggestion (`difflib.get_close_matches`). Catches the bug class the linter exists to prevent — `agent:` (singular typo) instead of `agents:` (plural correct) was previously accepted, and the directive loader silently dropped the value. Now: hard fail with `unknown field 'agent' — did you mean 'agents'?`. Allowed fields are whitelisted by directory: directives may use `name / description / type / originSessionId / version / triggers / agents`; recipes may use the same minus `triggers` + `agents`.
- `bin/lint-directives.py` enforces filename↔name suffix convention every existing file already follows: directives must end with `Directive`, recipes must end with `Recipe`. Catches "I copied a directive into recipes/ and forgot to rename" mistakes.
- Routing presets `claude-heavy`, `codex-heavy`, `copilot-only`, `direct-only` now include `providers.codex.image: "gpt-image-1"` in their provider catalog (was previously only in `balanced` + `copilot-heavy`). Semantically a no-op since image-routing decisions live in `routing.roles.image`, not the catalog — but consistent with the other two presets and matches what `_base.json` defines. Catalog drift fixed by build pipeline.
- All preset JSONs are now alphabetically key-sorted (jq `-S` output). One-time cosmetic reorder; semantically equivalent.
- Recipe mode-flags table adds `--overnight` row.
- Recipe Single-Session Mode section adds an "Overnight Mode" subsection above the existing mode-flags reference.

### Why overnight mode

User asked: "How can I make this run for hours? I want to kick it off before bed and let it run." Three constraints made longer single-invocation runs impractical:

1. **Single-session mode caps itself** — Large-Repo Mode is built for finite per-invocation work (1 iteration, 3 tasks, exit) and that's the right pattern for stability. But it directly conflicts with multi-hour intent.
2. **Stop-on-convergence fires fast** — once the `Now` tier is empty + debate verdicts pass + no breakers, the recipe terminates. Even with the v0.5.0 9-dim research expanding the ROADMAP, on smaller repos this exhausts in 1-2 hours.
3. **Master Claude session context death** — even with auto-compact at 85%, an 8-hour conversation eventually fragments. The factory's persistent state.yaml + atomic commits are designed precisely so a *new* session can resume — but you have to actually start one.

The overnight wrapper turns the third constraint into the solution: it explicitly respawns fresh sessions per cycle. Cumulative state lives in the repos themselves (state.yaml, atomic commits, ROADMAP.md, docs/research/iter-N-*.md) so each fresh session resumes where the prior left off. Multi-hour runs become a sequence of finite, atomic, recoverable cycles instead of one fragile long-running session.

### Verification

- factory-overnight.sh: dry-run with --max-cycles 2 produces full event log + status file + summary; passes `bash -n` syntax check.
- justfile: `just --list` shows the new `overnight` recipe under preflight group.
- Recipe + prompt cross-references: `--overnight` flag appears in (1) recipe mode-flags table, (2) Overnight Mode section's wrapper contract, (3) Phase substitution semantics, (4) prompt template optional-variant section. All consistent.
- `just lint-directives` passes 15/15 directives + recipes after the recipe edit.
- Full bats suite (29 tests) passes after the changes.
- Pre-commit hook catches my recipe modification through the linter; manual `python3 bin/lint-directives.py` confirms clean.

### Note on testing the overnight wrapper

User asked to test the overnight wrapper themselves on real repos rather than have me burn quota on smoke runs. The wrapper is verified at the loop-logic + argument-parsing + dry-run layer. Live multi-hour invocation will be exercised on the user's first overnight run; convergence-rotation behavior + per-cycle budget distribution + sentinel-file halt will be validated against real cycle outputs.

[0.6.0]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.6.0

## [0.5.1] — 2026-04-24

Bug fix release: every recent factory run was logging `mode: single-session`
+ `L3 audit: Claude only (no Codex dispatch)` + `Three-role debate: collapsed
to single rubric check` because there was no path from the master Claude
session to the standalone `codex` CLI without going through orchestrate.sh
(which has a known quality-gate timing issue on Windows). User-reported.

The fix shells the master session out to `codex exec` directly via a thin
wrapper. Independent of orchestrate.sh, independent of the active preset's
phase routing. Restores cross-family audit signal on every single-session run.

### Added
- `bin/codex-direct.sh` — wrapper around `codex exec --model gpt-5.4 --sandbox read-only`. Bypasses orchestrate.sh entirely. Phase-aware (audit/counter/ux/theming/review/security/self-audit/custom). Captures JSONL transcript + last-message file. Exit codes classify auth (2) / quota (3) / timeout (4) / refusal (5) / internal (6) so callers can degrade gracefully without halting the whole run. Default sandbox = read-only (audit phases don't need write access). Default timeout = 600s.
- `bin/factory-doctor.sh` — pre-run diagnostic. Validates each provider CLI is installed + authed (claude / codex / copilot / gemini), orchestrate.sh is reachable, providers.json is valid JSON, ImageMagick / git / gh present. **Specifically detects the "audit phases route to copilot-codex instead of direct codex" pattern** that produced silent Claude-only audit runs in v0.5.0 and earlier. Exit 0 ready / 2 warnings / 1 broken. Modes: `--quiet`, `--json`, `--route-only`.

### Changed
- `memory/recipes/recipe-factory-loop.md` "Single-Session Mode" section rewritten. Title changed from "(degraded fallback)" to "(Codex-augmented in v0.5.1+)". Phase substitution table updated:
  - L3 audit (Critic) was "Claude with rubric (no model-family diversity)" → now "`bin/codex-direct.sh audit` — direct codex exec"
  - L4 counter-audit was "**SKIPPED** — same-model duplication has no signal value" → now "Master Claude session — different family from Codex L3, so cross-family check holds"
  - U1 / T1 was "Claude does it" → now `bin/codex-direct.sh ux` / `theming`
  - U2 / T2 was "**SKIPPED**" → now "Master Claude session (different family than U1/T1's codex output)"
  - Q1 security / Q2 review now use `codex-direct.sh security` / `review`
  - Roadmap-research Phase 5 self-audit now uses `codex-direct.sh self-audit`
  - Three-role debate restored: Grader (Copilot Haiku) → Critic (codex-direct) → Defender (master Claude). Sequential not parallel, but all three families present.
- Recipe documents the codex-direct dispatch contract (caller writes prompt to temp file, wrapper returns last-message file path, exit codes classify failure modes).
- `prompts/factory-loop-prompts.txt` adds two new mandatory sections:
  - **PRE-FLIGHT** — invoke `factory-doctor.sh` before anything else; surface output once; hard failures halt, soft warnings proceed with acknowledgment.
  - **CODEX DISPATCH** — explicit instruction that audit phases MUST shell out to `codex-direct.sh` for real cross-family signal. Documents graceful-degradation contract (non-zero exit → log + continue with Claude audit, never halt the whole run).

### Why

User reported "I don't think codex or chatgpt is actually being used." Investigation confirmed it: every recent run on Astra-Deck, DefenderControl, Images, project-nomad-desktop, TeamStation, ZeusWatch logged `mode: single-session` with `L3 audit: Claude only`. Two compounding causes:

1. Single-session was the default fallback (orchestrator quality-gate issue on Windows), and single-session collapsed Codex phases to Claude-only because there was no documented path from the master session to the codex CLI.
2. The active `copilot-heavy` preset routes audit / security / UX / theming to `copilot-codex` (Copilot's GPT-5.3-Codex), NOT the standalone codex CLI. Even with orchestration working, "Codex" in the factory has meant Copilot-via-GPT, not direct ChatGPT Pro Codex.

`codex-direct.sh` fixes both — it bypasses the orchestrator AND bypasses the preset routing. The factory-doctor surfaces the routing analysis before the user wastes a 30-min run.

### Verification

- Both scripts parse cleanly + reject bad input (smoke-tested on Windows + Git Bash).
- factory-doctor against the user's actual environment correctly flags `audit phases route to copilot-codex (Copilot's GPT-5.3-Codex), NOT the standalone codex CLI` and lists three remediation options.
- Recipe + prompt cross-references consistent: every phase that single-session previously skipped or collapsed to Claude is now explicitly mapped to a `codex-direct.sh <phase>` invocation.
- Exit codes verified by reading codex CLI's actual output formats and rate-limit message patterns.

### Note on testing

User explicitly asked to test the fixes themselves rather than have me burn ChatGPT Pro quota smoke-testing `codex exec` from the factory. The wrapper is tested at the argument-parsing + auth-detection layer; the live dispatch path is what the user will exercise on the next factory run.

[0.5.1]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.5.1

## [0.5.0] — 2026-04-24

Promotes roadmap research from a single `L1a+L1b` scan to a full five-phase
protocol with its own directive, scoring rubric, tier taxonomy, and
cross-family self-audit. Lifts directly from a user-authored research prompt
that had battle-tested discipline the factory's L1 was missing (quantity-first
harvesting, explicit Rejected tier with reasoning, source-citation as a
commit gate, adversarial self-audit on a different model family).

### Added
- `memory/directives/directive-roadmap-research.md` — five-phase research protocol:
  - **Phase 0** — Repo reconnaissance + "State of the Repo" memo
  - **Phase 1** — External research with 30-60 source floor across 9 source classes (OSS competitors / commercial peers / adjacent-domain / awesome-lists / community signal / standards & RFCs / academic+conference / dependency changelogs / CVE databases)
  - **Phase 2** — Quantity-first feature harvesting (80-200+ raw items expected, filter NOTHING during extraction)
  - **Phase 3** — Six-dimension scoring (Fit / Impact / Effort / Risk / Dependencies / Novelty) + five-tier bucketing (Now / Next / Later / Under Consideration / Rejected). Dual-axis: priority (P0/P1/P2) and tier (commitment state).
  - **Phase 4** — Author or reconcile `ROADMAP.md` with preserve-useful / supersede-outdated semantics. Appendix citation for every Now/Next/Later/UC item is a commit gate.
  - **Phase 5** — Seven-check adversarial self-audit routed to `copilot-codex` (different family than Phases 2-4). Checks: source traceability, tier placement reasoning, category coverage (13 categories), internal consistency, adversarial review, charter alignment, file-on-disk.
- Directive includes a full routing table per phase (master session for Phase 0, gemini:flash for Phase 1 breadth, copilot-sonnet for depth/harvest/score/author, copilot-codex for Phase 5 audit).
- Directive supports standalone invocation outside a factory run: "Apply directive-roadmap-research.md to ~/repos/<name>".

### Changed
- `memory/recipes/recipe-factory-loop.md` L1 rewritten to delegate to the new directive. L1a (9-dimension scan) and L1b (synthesis) collapsed into a single `L1. Apply directive-roadmap-research.md` step that invokes all five phases with the recipe's iteration semantics (full on iter 1, delta on iter 2+).
- Recipe's directives table gains `directive-roadmap-research.md` row.
- L2 implementation step now says "top 10 items in the `Now` tier" (was "top 10 unchecked P0/P1"). P0/P1/P2 and Now/Next/Later/UC/Rejected coexist — priority captures urgency, tier captures commitment state.
- Hard-caps + Large-Repo-Mode tables updated to the tier taxonomy.
- `prompts/factory-loop-prompts.txt` RESEARCH EXPECTATION section rewritten to reference the directive, list the 9 source classes, document the 30-60 source floor, and explain the five artifact files that land in `docs/research/iter-<N>-*.md`.
- Prompt's lazy-load directives list includes the new directive.

### Why

User shared a battle-tested "Roadmap Research Agent" prompt they'd been using outside the factory. It had discipline the factory's L1 was missing:
- **Quantity-first harvest** (80-200+ raw items before filtering) — the old L1 filtered during extraction, losing good ideas for bad reasons.
- **Explicit Rejected tier with reasoning** — the old L1 silently dropped charter-incompatible items, inviting future runs to re-propose them.
- **Source-citation as a gate** — the old L1 asked tasks to cite the research dimension they came from but didn't require an Appendix URL.
- **Adversarial self-audit on a different model family** — the old L1 had the writer judge its own output.
- **Reconciliation semantics** — the old L1 replenished in-place without a protocol for preserving useful prior items.

The five-phase protocol fixes all of these while staying on `copilot-heavy` routing (Claude Max still reserved for PEC escalation).

### Verification

- Directive parses as valid microagent (YAML frontmatter: `name`, `description`, `type: knowledge`, `triggers: [...]`, `agents: [...]`).
- Recipe L1 delegates correctly — all five phase artifacts are listed in the recipe's L1 block AND in the directive's per-phase output sections. No drift.
- Prompt cross-references: directive appears in (1) lazy-load list, (2) RESEARCH EXPECTATION section. Recipe references match.
- Tier taxonomy (Now/Next/Later/UC/Rejected) consistent across directive Phase 3, recipe L2 cap, hard-caps block, Large-Repo-Mode table.

[0.5.0]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.5.0

## [0.4.1] — 2026-04-24

Hardens the logo/icon generation directive so transparent background + PNG
(RGBA) output is non-negotiable across all three paths. Every prompt now says
so explicitly, every rasterizer forces `PNG32:` + `png:color-type=6`, and
every path has a post-generation alpha-channel verification step that halts
on flattened output.

### Changed
- `memory/directives/directive-logo.md`:
  - Path 1 (SVG-via-Copilot) prompt rewritten with explicit NON-NEGOTIABLE
    output format block: transparent background, no full-canvas `<rect>`, no
    root `<svg>` fill, 75-85% content fill, stroke ≥ 24px in 512-space.
  - Post-SVG validation now rejects full-canvas background rectangles and
    fill-on-root-svg before rasterizing.
  - Rasterization block upgraded: `-density 384` for clean SVG→PNG downscale,
    `PNG32:` output prefix + `-define png:color-type=6` to guarantee RGBA,
    post-loop channel verification via `magick identify -format '%[channels]'`.
  - Path 2 (gpt-image-1) prompt rewritten: explicit PNG+RGBA + alpha=0
    outside glyph requirement, `output_format: png` added to API payload
    alongside existing `background: transparent`, post-download alpha
    verification.
  - Path 3 (Gemini) prompt rewritten with same PNG/RGBA/transparency
    requirements + optional salvage step (`-fuzz 5% -transparent white`)
    documented before halting.
  - "Why SVG first" section now declares the exact artifact set every path
    must produce (master SVG + 8 RGBA PNGs + `.ico` + `.icns` + favicon).
  - Non-Negotiable Rules expanded: transparency + PNG(RGBA) + alpha-channel
    verification are stated as three hard requirements instead of one soft
    one.

### Why

PNG output from image-generation APIs sometimes flattens to RGB when the
model interprets "transparent background" loosely. The prior directive
caught this only at the `magick identify` validation step with no
actionable remedy. This release strengthens every prompt to demand
transparent PNG explicitly, adds channel-verification at each rasterization
step, and documents a salvage path for near-solid backgrounds before
halting.

Also updates `~/CLAUDE.md` "Branding & Logo Generation" section (user's
global instructions, separate file) so every project — not just factory
runs — follows the same transparency + PNG(RGBA) contract.

[0.4.1]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.4.1

## [0.4.0] — 2026-04-24

Default workflow rebalanced: Copilot-heavy is now canonical, L1 research is
heavier and mandatory even when the ROADMAP already has items, and the
default prompt is explicit about offload policy and research scope. Bulk
research / synthesis / implementation / counter-passes / UX / theming /
audit all route through Copilot's Sonnet 4.6 and GPT-5.3-Codex. Claude Max
(this session) is reserved for escalation — PEC stalemates, debate
non-convergence, security escalation, novel architectural decisions.

### Added
- `prompts/factory-loop-prompts.txt` — rewritten default prompt with an
  explicit OFFLOAD POLICY section (copilot-heavy preset mandatory, escalation-
  only Claude Max), an explicit RESEARCH EXPECTATION section (9 dimensions
  always run on iter 1), and higher iteration defaults (EXISTING-clean went
  from `1 --audit-only` to `2 iterations with research`).
- **9-dimension research scan** in `memory/recipes/recipe-factory-loop.md`
  L1a: (1) competitor feature parity, (2) recent upstream releases, (3) CVE /
  security advisories, (4) accessibility gaps (WCAG 2.2 AA), (5) performance
  regressions, (6) UX / GUI polish opportunities, (7) theme coverage,
  (8) community asks, (9) platform / ecosystem shifts. Output lands in
  `docs/research/iter-<N>-landscape.md`. Each ROADMAP task added by L1b must
  cite its source dimension.
- `--final-codex-pass` flag: on the final iteration, run a direct-ChatGPT-Pro-
  Codex audit pass in addition to the Copilot audit. Release-day signal.

### Changed
- **`copilot-heavy` is now the canonical default preset.** `balanced` was
  the old default; use it via `octo-route.sh balanced` when you want every
  subscription to share load equally. The recipe's Provider Routing table
  now documents copilot-heavy as the reference, and the factory-loop prompt
  verifies/enforces the preset on entry.
- L1a RESEARCH is now heavy by default — the 9 dimensions run ALL on iter 1
  regardless of whether ROADMAP.md has items. Research EXPANDS existing
  ROADMAPs rather than bypassing when "already full". Delta-only mode on
  iter 2+.
- L1b SYNTHESIZE replenish now requires each new task cite which research
  dimension it came from (traceability). Duplicate detection added. Charter-
  incompatible tasks are tagged `CHARTER-REVIEW` and deferred, not silently
  dropped.
- Iteration-count defaults raised: EXISTING with active roadmap goes from
  3 to 4 iterations. EXISTING clean goes from 1 `--audit-only` to 2 full
  iterations with research (don't ship "nothing changed" runs).
- L3/L4 audit cadence docs now mention `--final-codex-pass` as a release-
  day option.

### Why

User hit a run on the Images repo where the factory found 2 completed tasks,
declared the roadmap clean, and exited. The pattern was: existing ROADMAP →
skip research → no new work found → exit. The fix is that research is
unconditional — even full ROADMAPs get the 9-dimension scan, and the scan's
job is to find what the current ROADMAP missed. Research output feeds
high-leverage additions, and the offload policy makes sure the heavy lift
lands on Copilot's Sonnet 4.6 / GPT-5.3-Codex instead of burning Claude Max
on bulk work it doesn't need to do.

### Verification

- Prompt round-trip: `factory-loop-prompts.txt` default section, audit-only
  section, plan section, and final-codex-pass section all parse as valid
  prompt bodies (no YAML frontmatter, markdown headings consistent).
- Recipe cross-references: L1a dimensions list + L1b citation requirement +
  provider routing table + mode-flags table + guardrail note all consistent.
- Flag `--final-codex-pass` documented in (1) provider routing table,
  (2) mode semantics flag table, (3) L3/L4 cadence note, (4) prompt
  optional-variant section.
- Routing check: copilot-heavy preset already had `research_augment:
  copilot-sonnet` + `review/security/ux/theming: copilot-codex` + `builder:
  copilot-sonnet` + `escalate-to-opus: claude` — no preset changes needed.

[0.4.0]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.4.0

## [0.3.0] — 2026-04-24

Adds a logo/icon generation phase for existing projects (G-phase) and makes SVG-via-Copilot the primary path so OpenAI billing is no longer a prerequisite for icon work. Closes the "Images repo got no logo on first factory pass" bug.

### Added
- `memory/directives/directive-logo.md` — three-path logo/icon generation directive. Path 1 (primary): SVG-via-Copilot + ImageMagick rasterization (no OpenAI billing). Path 2: Codex `gpt-image-1` (opt-in via `--raster-logo`, photographic briefs only). Path 3: Gemini image (last resort). Emits 16/32/48/64/128/256/512/1024 PNGs + multi-res `.ico` + optional `.icns`. Stack-specific wiring documented for Chrome MV3, Firefox, Android adaptive icons, WPF `.csproj`, Python `.spec`, Web/PWA, README header.
- **G-phase** in `memory/recipes/recipe-factory-loop.md` (between S-phase and the main loop). Runs on existing repos that lack an icon set. Steps G0-G7 cover gate, trigger detection, stack detection, directive application, wiring, atomic commit, state recording, and halt conditions.
- `--skip-logo` / `--force-logo` / `--raster-logo` flags added to mode semantics table.

### Changed
- `memory/recipes/recipe-factory-loop.md` P5 (preflight logo for new projects) rewritten to delegate to `directive-logo.md` so new and existing projects follow the same path.
- Provider routing table updated: icon/logo row now lists Copilot-SVG as primary, Codex `gpt-image-1` + Gemini as secondary fallbacks.
- `--audit-only` flag documentation updated to note G-phase is also skipped under audit-only.
- Single-session mode substitution table: P5/G-phase logo entry clarifies that Copilot-SVG works in single-session too (it shells out to `copilot --no-ask-user`), only the parallel fan-out is lost.
- Guardrails list adds a bullet for the G-phase invariants.

### Fixed
- **Factory on existing repos now generates logos.** Previously `P5` lived in preflight only, so any `--skip-preflight` or existing-repo run never had a code path to icon generation. The Images repo session on 2026-04-24 triggered this — `state.yaml` read `P5 logo: deferred` with no recovery path.
- **OpenAI billing is no longer a prerequisite for icon work.** Path 1 uses the Copilot subscription + ImageMagick for rasterization; `OPENAI_API_KEY` only matters if the user opts into `--raster-logo` for photographic briefs.

### Verification

- Recipe + directive + ROADMAP + CHANGELOG cross-references check: all six link anchors resolve.
- No unauthorized key material references (`gitleaks dir` pending full repo scan in the commit gate).
- Path 1 (SVG-via-Copilot) tested manually on the Images repo's CLAUDE.md brief during authoring — `copilot --no-ask-user --model claude-sonnet-4.6` produced a valid SVG that `xmllint --noout` accepted.
- ImageMagick rasterization loop tested end-to-end against a sample SVG — all 8 PNG sizes + multi-res `.ico` generated on Windows (`magick` from Scoop).

### Known limitations

- macOS `.icns` generation requires `iconutil` (macOS-native) — Linux/Windows runs skip the `.icns` build with a warning.
- Copilot CLI must be authenticated (`copilot auth login`) for Path 1. The G-phase does not re-authenticate silently; it halts with a diagnostic if the call returns unauthenticated.

[0.3.0]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.3.0

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

[Unreleased]: https://github.com/SysAdminDoc/octopus-factory/compare/v0.6.0...HEAD
[0.2.0]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.2.0
[0.1.0]: https://github.com/SysAdminDoc/octopus-factory/releases/tag/v0.1.0
