#!/usr/bin/env python3
"""lint-directives.py — validate YAML frontmatter on memory/*.md files.

Why: directives + recipes are loaded lazily by the recipe runner via
`directive-loader.sh`, which extracts the frontmatter via grep. A malformed
heading (missing closing `---`, non-list value where a list is required, wrong
`type` enum value) silently fails — the directive just doesn't load and the
phase proceeds without its guidance. This linter makes that failure loud.

Schema (intentionally tiny — no external deps):

  name         (str, required)        Human-readable title. Must end with the
                                      word matching the file's directory:
                                      "Directive" for memory/directives/*.md,
                                      "Recipe" for memory/recipes/*.md.
  description  (str, required)        One-paragraph summary
  type         (enum, required)       One of: knowledge | reference

  Directives only (memory/directives/*.md):
    triggers   (list[str], required)  Keyword/phrase triggers for lazy load
    agents     (list[str], required)  Roles that consume this directive

  Recipes (memory/recipes/*.md): triggers + agents not required.

  Optional everywhere:
    originSessionId  (str)            UUID of the session that authored it
    version          (str)            SemVer-style version string

  Unknown fields are rejected with a "did you mean ...?" suggestion. This
  catches the bug class the linter exists to prevent: a misspelled field
  name (e.g. `agent:` instead of `agents:`) makes the directive loader's
  YAML parser silently drop the value, and the recipe runs without that
  guidance with no warning.

Usage:
  lint-directives.py [PATH...]   # lint specific files
  lint-directives.py             # default: lint memory/directives/ + memory/recipes/

Exit:
  0  every file passes
  1  one or more files failed; details printed to stderr
  2  bad arguments / no files found

Stdlib only (no PyYAML). Frontmatter parser handles the flat-key:value shape
used by every existing directive — values are scalars or JSON-style arrays
(`[a, b, c]`). Nested objects are out of scope; if a future directive needs
them, swap the parser for PyYAML in one place.
"""

from __future__ import annotations

import difflib
import json
import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DIRS = [REPO_ROOT / "memory" / "directives", REPO_ROOT / "memory" / "recipes"]

VALID_TYPES = {"knowledge", "reference"}
REQUIRED_EVERYWHERE = ("name", "description", "type")
REQUIRED_DIRECTIVE_ONLY = ("triggers", "agents")
ALLOWED_EVERYWHERE = {"name", "description", "type", "originSessionId", "version"}
ALLOWED_DIRECTIVE = ALLOWED_EVERYWHERE | {"triggers", "agents"}

# Map directory name → required suffix on the human-readable `name` field.
NAME_SUFFIX_BY_DIR = {"directives": "Directive", "recipes": "Recipe"}


class LintError(Exception):
    """Per-file lint failure with a short, fixable message."""


def extract_frontmatter(text: str) -> dict[str, object]:
    """Pull the leading `---`-fenced YAML block, return a dict.

    Accepts the flat shape directives use today: scalar values + JSON-style
    arrays. Raises LintError on anything malformed.
    """
    if not text.startswith("---\n"):
        raise LintError("file must begin with `---` on line 1")
    end = text.find("\n---\n", 4)
    if end < 0:
        raise LintError("missing closing `---` for frontmatter block")

    body = text[4:end]
    out: dict[str, object] = {}
    for lineno, raw in enumerate(body.splitlines(), start=2):
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            raise LintError(f"line {lineno}: expected `key: value`, got {line!r}")
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()

        if not key:
            raise LintError(f"line {lineno}: empty key")
        if key in out:
            raise LintError(f"line {lineno}: duplicate key {key!r}")

        # JSON-style array: [a, b, c] — parse via json after quoting bare words.
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            items: list[str] = []
            if inner:
                # Split on commas not inside quotes; keep it simple — directives
                # don't currently use commas inside trigger phrases.
                for raw_item in inner.split(","):
                    item = raw_item.strip().strip("'\"")
                    if not item:
                        raise LintError(
                            f"line {lineno}: empty list item in {key!r}"
                        )
                    items.append(item)
            out[key] = items
            continue

        # Strip optional surrounding quotes on scalars.
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        out[key] = value
    return out


def validate(path: Path) -> list[str]:
    """Return a list of error strings (empty if file is clean)."""
    errors: list[str] = []
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        return [f"cannot read: {exc}"]

    try:
        fm = extract_frontmatter(text)
    except LintError as exc:
        return [str(exc)]

    for field in REQUIRED_EVERYWHERE:
        if field not in fm:
            errors.append(f"missing required field {field!r}")
        elif not isinstance(fm[field], str) or not fm[field].strip():
            errors.append(f"field {field!r} must be a non-empty string")

    if "type" in fm and isinstance(fm["type"], str):
        if fm["type"] not in VALID_TYPES:
            errors.append(
                f"field 'type' must be one of {sorted(VALID_TYPES)}; got {fm['type']!r}"
            )

    is_directive = path.parent.name == "directives"
    if is_directive:
        for field in REQUIRED_DIRECTIVE_ONLY:
            if field not in fm:
                errors.append(f"directive missing required field {field!r}")
            elif not isinstance(fm[field], list) or not fm[field]:
                errors.append(
                    f"directive field {field!r} must be a non-empty list"
                )
            elif not all(isinstance(x, str) and x for x in fm[field]):
                errors.append(
                    f"directive field {field!r} entries must be non-empty strings"
                )

    # Reject unknown fields with a suggestion. Catches `agent:` vs `agents:`
    # typos that the YAML loader would otherwise drop silently.
    allowed = ALLOWED_DIRECTIVE if is_directive else ALLOWED_EVERYWHERE
    for key in fm.keys():
        if key in allowed:
            continue
        suggestions = difflib.get_close_matches(key, allowed, n=1, cutoff=0.6)
        if suggestions:
            errors.append(
                f"unknown field {key!r} — did you mean {suggestions[0]!r}?"
            )
        else:
            errors.append(
                f"unknown field {key!r} (allowed: {sorted(allowed)})"
            )

    # Enforce filename ↔ `name` suffix convention every existing file follows.
    suffix = NAME_SUFFIX_BY_DIR.get(path.parent.name)
    name = fm.get("name")
    if suffix and isinstance(name, str) and name.strip():
        if not name.strip().endswith(suffix):
            errors.append(
                f"name {name!r} must end with {suffix!r} "
                f"(every file under memory/{path.parent.name}/ follows this convention)"
            )

    return errors


def collect(paths: list[Path]) -> list[Path]:
    """Expand directories to *.md children; pass files through."""
    out: list[Path] = []
    for p in paths:
        if p.is_dir():
            out.extend(sorted(p.glob("*.md")))
        elif p.is_file():
            out.append(p)
        else:
            print(f"lint-directives: not found: {p}", file=sys.stderr)
            sys.exit(2)
    return out


def main(argv: list[str]) -> int:
    if argv and argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    targets = [Path(a) for a in argv] if argv else DEFAULT_DIRS
    files = collect(targets)
    if not files:
        print("lint-directives: no .md files found", file=sys.stderr)
        return 2

    failed = 0
    for f in files:
        # On Windows, relpath raises ValueError when f and REPO_ROOT live on
        # different drive letters (e.g. CI runner: repo on D:, tempfile on C:).
        # Fall back to the absolute path in that case.
        try:
            rel = os.path.relpath(f, REPO_ROOT)
        except ValueError:
            rel = str(f)
        errors = validate(f)
        if errors:
            failed += 1
            print(f"✗ {rel}", file=sys.stderr)
            for e in errors:
                print(f"    {e}", file=sys.stderr)
        else:
            print(f"✓ {rel}")

    print(
        f"\n{len(files) - failed}/{len(files)} passed",
        file=sys.stderr if failed else sys.stdout,
    )
    return 1 if failed else 0


if __name__ == "__main__":
    # Windows consoles default to cp1252, which can't encode ✓/✗ — force UTF-8
    # so the output matches every other tool in the repo. No-op on POSIX.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv[1:]))
