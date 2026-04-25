# Prompt Builder

GUI helper for assembling octopus-factory prompts. Pick a project, pick a prompt type, tune the knobs, copy the result.

![Prompt Builder](assets/screenshot.png)

## What it does

Builds copy-paste-ready prompts for every scenario in `prompts/examples.md` without making you remember the exact wording. Live preview updates as you tweak; **Copy** sends the rendered prompt to your clipboard.

Supported prompt types:

- **Factory Loop** — interactive single-invocation runs
- **Overnight Loop** — 1h / 4h / 8h / weekend / custom presets
- **Audit-Only** — security + quality pass before release
- **Plan / Dry-Run** — preview without execution
- **Single Task** — scope to one ROADMAP item
- **Roadmap Research** — five-phase research, no implementation
- **Release Build** — version bump + sign + GitHub Release
- **AI Scrub** — git history rewrite removing AI attribution
- **PDF Redesign** — improve a single PDF in place
- **PDF Derivatives** — mine a PDF for sub-guides + blog posts

## Run

```bash
just prompt-builder           # from octopus-factory repo root
# or directly:
python -m prompt_builder      # from tools/prompt-builder/
```

## Build a standalone executable

PyInstaller bundle (single-file exe, ~50MB):

```bash
cd tools/prompt-builder
python -m pip install -r requirements.txt
python -m PyInstaller prompt-builder.spec --clean
# Output: dist/prompt-builder.exe (Windows) or dist/prompt-builder (Linux/macOS)
```

## Stack

- Python 3.11+ + PyQt6
- Catppuccin Mocha dark theme via QSS
- Templates as Python data structures with `{{placeholder}}` substitution
- PyInstaller bundling with mandatory fork-bomb guards (`multiprocessing.freeze_support()`, runtime hook, frozen-aware bootstrap)

## Why this exists

The factory's prompt library at `prompts/examples.md` covers 14 scenarios with full copy-paste blocks. Reading it every time is fine, but tweaking iteration counts / model presets / flag combinations means hand-editing the prompt before pasting. This GUI removes that friction: every knob is a form field, every change re-renders the preview, the Copy button hands you a finished prompt. Especially useful on Windows where shell-piping prompts is awkward.
