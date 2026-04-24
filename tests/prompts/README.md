# Prompt regression tests

Uses [promptfoo](https://github.com/promptfoo/promptfoo) to verify that prompt changes don't silently regress output quality. Runs locally and in CI before shipping any prompt change.

## Install

```bash
npm install -g promptfoo
# or
pnpm install -g promptfoo
```

## Run

From this directory:

```bash
promptfoo eval
promptfoo view    # web UI with results
```

## What gets tested

Each test case in `promptfooconfig.yaml` pairs input variables with assertions about the output:

- **Format checks** — conventional-commits regex, character limits, imperative mood
- **Negative checks** — no `Co-Authored-By`, no AI-attribution emoji, no PII
- **Semantic checks** — audit outputs must contain severity markers, debate outputs must produce PASS/FAIL/UNCERTAIN verdicts
- **Structural checks** — prompt files themselves must not contain personal identifiers

## Adding tests

When you add or modify a prompt:

1. Add a test case to `promptfooconfig.yaml` under `tests:` with `vars:` (input) and `assert:` (expected properties).
2. Run `promptfoo eval` locally. Fix regressions before committing.
3. If your change is model-specific, add a new `providers:` entry and scope the test to that provider only.

## CI integration

Add to `.github/workflows/ci.yml`:

```yaml
- name: Install promptfoo
  run: npm install -g promptfoo
- name: Run prompt regression tests
  run: cd tests/prompts && promptfoo eval --no-cache
  env:
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

Only run this on PRs that touch `prompts/` or `memory/directives/` — the tests hit real providers and cost tokens.

## Cost

Each full `promptfoo eval` invocation costs roughly $0.05-0.20 depending on which providers you enable and how many test cases run. Scope to changed prompts only via `promptfoo eval --filter-tests-by-prompt <path>`.

## Provider setup

By default the config uses Copilot CLI via `exec:` provider. To test across families, uncomment the Codex provider in `providers:`. To add Claude direct, set `ANTHROPIC_API_KEY` and add:

```yaml
- id: anthropic:claude-sonnet-4-5-20241022
  config:
    apiKey: ${ANTHROPIC_API_KEY}
```
