# Contributing

Thanks for considering a contribution. Quick guidelines below; see `ARCHITECTURE.md` for how the pieces fit together.

## Structure

- **`memory/recipes/`** — workflow specifications (the master plans)
- **`memory/directives/`** — phase-specific behavior loaded lazily
- **`memory/reference/`** — non-recipe reference docs
- **`bin/`** — executable shell scripts
- **`config/presets/`** — provider routing presets (JSON)
- **`config/workflows/`** — YAML workflow bridges
- **`prompts/`** — copy-paste-ready prompts users send to Claude
- **`patches/`** — find/replace patches for the upstream Claude Octopus plugin
- **`docs/`** — architecture + contribution + execution-mode docs

## What to keep in mind

### Recipes are the source of truth

Prompts defer to recipes; recipes defer to per-phase directives. When adding a feature:

1. Update the relevant recipe's spec section
2. Update or add a directive if the new behavior is phase-specific
3. **Don't** restate recipe internals in the prompt. Drift comes from re-stating things in multiple places.

### Behavior-preserving where it matters

The modularization directive is mandate-bound to behavior preservation (tests must pass identically before/after). The audit directive must root-cause bugs, not suppress them. Breaking these contracts breaks user trust in the pipeline.

### Deterministic safeguards over AI self-discipline

Loop detector, secret scan, sacred-cow gate, stop-on-regression — all non-AI. AI agents are not reliable enforcers of their own halting conditions. Add new breakers as deterministic logic in `directive-circuit-breakers.md` or `bin/` scripts, not as instructions in prompts.

### Atomic commits

Per-task in Large-Repo Mode. Per-logical-change in normal mode. Never mega-commits. Reviewability matters even when the committer is an agent.

### Honest fallback

When something doesn't work as designed, the recipe should declare the degradation in the session log — not pretend it ran the full version. Single-session mode collapsing L4/U2/T2 is documented; same-model "debate" is not real debate and the log says so.

## What we'd love help with

### High-leverage

- **macOS / Linux portability** — most testing is on Windows 11 + Git Bash. Path handling, signal handling, and process spawning behave differently elsewhere; bug reports + PRs welcome.
- **Stack-specific build recipes** — `recipe-release-build.md` covers Chrome/Firefox/Python/Android/C#/C++/Rust/Go/Node. Missing: Elixir, Swift (iOS / macOS native), Kotlin Native, Flutter, Tauri, Rust WASM, native shared libraries.
- **Orchestrator bridge work** — currently the recipe runs in single-session mode by default. The `factory-loop.yaml` workflow exists but isn't wired into a custom `orchestrate.sh --workflow <name>` invocation. Bridge work to make this seamless is a real win.
- **Quality-gate timing fix** — on Windows, octo's quality gates fire before agents complete (synchronization issue). Investigation + fix would unlock orchestrated mode.
- **Better Gemini support** — Gemini's free tier (Flash) works. Pro models require an API key. Documented but no automation around getting that key.

### Medium-leverage

- **More routing presets** — covering more subscription combos (e.g., "claude-only" for users with just Claude Max, "no-anthropic" for users without Claude Max).
- **Documentation** — more end-to-end walkthroughs for first-time users.
- **Tests** — there's a smoke-test layer in some scripts but no comprehensive test suite. Bash test harnesses welcome.

### Low-leverage but appreciated

- Typo fixes, copyediting in recipes/directives.
- README badge updates as the project matures.
- Translating recipes to other languages.

## How to submit

1. Fork the repo.
2. Create a branch: `git checkout -b feat/<short-description>` or `fix/<short-description>`.
3. Make the change. Per-logical-change atomic commits, no `Co-Authored-By` trailers.
4. Test it on your own setup if you can. If not, say so in the PR.
5. Open a PR with:
   - What you changed
   - Why
   - How you tested (or noted you couldn't)
   - Any breaking changes

## Style

- Markdown: GitHub-flavored. Tables for structured info. No HTML.
- Bash: `set -euo pipefail` at the top. Comments explaining non-obvious flag combinations.
- Python: 3.10+. Type hints if non-trivial.
- JSON: 2-space indent, sorted keys where order doesn't matter semantically.
- Commit messages: imperative mood, ~72-char subject, role-based prefixes (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).

## What not to submit

- Anything that adds AI-attribution to the codebase (we explicitly scrub these via the AI-scrub recipe).
- Anything that loosens the secret-scan or sacred-cow gates without strong justification.
- Anything that calls premium APIs from default code paths without an explicit cost note in the docs.
- Anything that depends on a non-portable Windows / Mac / Linux feature without a fallback.

## License

By submitting a PR you agree your contribution is licensed under MIT (see [LICENSE](../LICENSE)).
