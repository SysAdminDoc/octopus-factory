# Commit Message Prompt

Canonical commit-message generation prompt. Used by all L7-style commit gates, the W-phase WIP adoption, the S-phase scrub, M-phase modularization, and every other commit the factory creates.

---

## Attribution

Prompt body lifted verbatim from [Aider](https://github.com/Aider-AI/aider) — specifically [`aider/prompts.py`](https://github.com/Aider-AI/aider/blob/main/aider/prompts.py) — under the Apache 2.0 license. Paired with the model-fallback loop pattern from [`aider/repo.py`](https://github.com/Aider-AI/aider/blob/main/aider/repo.py)'s `get_commit_message()`.

Why lift rather than write fresh: Aider's prompt has been battle-tested across millions of commits, handles edge cases (empty diffs, whitespace-only changes, large diffs exceeding context), and already enforces conventional-commits format consistent with our L7 commit gate rules.

---

## System prompt

```
You are an expert software engineer that generates concise,
one-line Git commit messages based on the provided diffs.
Review the provided context and diffs which are about to be committed to a git repo.
Review the diffs carefully.
Generate a one-line commit message for those changes.
The commit message should be structured as follows: <type>: <description>
Use these for <type>: fix, feat, build, chore, ci, docs, style, refactor, perf, test

Ensure the commit message:
- Starts with the type, followed by a colon and a space.
- Gives a clear, concise description of the change.
- Is a maximum of 72 characters.
- Is in the imperative mood (e.g., "add feature" not "added feature" or "adds feature").
- Does not exceed 72 characters.

Reply only with the one-line commit message, without any additional text, explanations,
or line breaks.
```

---

## Invocation pattern (model-fallback loop, from Aider's `get_commit_message`)

Pseudocode for the agent writing commits inside the factory loop:

```
def get_commit_message(diffs: str, context: str) -> str:
    messages = [
        {"role": "system", "content": <system prompt above>},
        {"role": "user", "content": f"{context}\n\nChanges:\n\n{diffs}"},
    ]

    # Fallback chain: try primary → weak → fail
    for model in [primary_model, weak_model]:
        if estimate_tokens(messages) > model.max_input_tokens:
            continue
        try:
            response = model.complete(messages)
            if response.strip():
                return response.strip()
        except ModelError:
            continue

    # All models failed: return a stub message; caller should surface the failure
    return "chore: automated commit (model unavailable)"
```

## Factory-loop additions beyond Aider's base prompt

The factory loop's L7 commit gate additionally enforces (these are NOT in the prompt body above — they're post-generation checks):

1. **No AI attribution.** Generated message is stripped of any `Co-Authored-By`, `Generated with`, `🤖`, or other AI-attribution trailers per `directive-secret-scan.md` scrub patterns.
2. **No trailer re-addition.** Git's `commit.template` or `prepare-commit-msg` hooks that add trailers are bypassed with `-n` only if secret-scan passes cleanly (no other hooks skipped).
3. **Role-based alternative prefixes.** For factory-initiated phases, the agent may use phase-specific prefixes not in Aider's list:
   - `audit:` — Audit phase fixes (L3/L4 findings resolved)
   - `ux:` — U-phase polish commits
   - `theme:` — T-phase theming commits
   - `deps:` — D-phase CVE fixes
   - `release:` — Q3 version bump commit
   - `wip-adoption:` — W-phase adopted WIP changes
4. **Subject + body.** Aider's prompt generates subject only. When the diff is substantial (>50 LOC changed across >5 files), the factory's commit gate appends a body:
   ```
   <subject>

   <one-paragraph "why" explanation generated separately via a follow-up prompt>
   ```

## Token budget

Per Aider's pattern: if the diff + context exceeds the primary model's `max_input_tokens`, fall back to the weak model (typically Haiku 4.5 / Gemini Flash / GPT-5 mini). If even the weak model can't fit, truncate the diff to the top 30 files by change volume and note the truncation in the body.

## Testing

When the T3.11 promptfoo regression test scaffold lands, this prompt will be covered by fixtures verifying:
- Conventional-commits format compliance
- 72-char subject length cap
- Imperative mood (verb-first, no past/present participles)
- No AI attribution leaking through
- Stable output across model families (same diff → semantically equivalent message)
