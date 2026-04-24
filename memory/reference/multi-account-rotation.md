---
name: Multi-Account Provider Rotation
description: User has four AI subscriptions (ChatGPT Pro, Claude Max, Gemini Pro, GitHub Copilot). octo is configured with preset-based routing to spread load across all four quotas and avoid hammering any single account. Rotation via ~/.claude-octopus/bin/octo-route.sh.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
---
# Multi-Account Provider Rotation

## Accounts in play

| Account | Access | Home role in octo |
|---|---|---|
| **ChatGPT Pro** | Direct (Codex CLI, OAuth auth.json, accepts gpt-5/gpt-5-codex/o3/gpt-image-1) | review + security + UX + theming + logo (primary) |
| **Claude Max** | Direct (built-in to Claude Code) | define + develop + counter-audit (everywhere) + research augment pass + builder |
| **Gemini Pro** | Direct (Gemini CLI) | research primary (Claude augments after) + logo fallback + web exploration |
| **GitHub Copilot** | CLI with multi-backend routing (gpt-5 / claude / gemini internally) | deliver + universal fallback safety net |

## Routing flow (balanced mode)

```
research / discover  →  Gemini        →  Claude Max augments (two-pass)
define / develop     →  Claude Max
counter-audit        →  Claude Max    (follows every codex pass)
review / security    →  Codex
UX polish            →  Codex         →  Claude Max counter-pass
theming              →  Codex         →  Claude Max counter-pass
deliver              →  Copilot
image / logo         →  Codex (gpt-image-1, transparent PNG)  →  Gemini fallback
fallback safety net  →  Copilot       (octo auto-cascade on any failure)
```

## How octo routes work

octo reads `~/.claude-octopus/config/providers.json`. The `routing.phases` block maps workflow phases to providers. Whichever account owns that provider gets billed.

octo has **automatic cross-provider fallback** built in — if a phase's primary provider errors or rate-limits, it cascades to an alternate (usually Copilot, since Copilot itself fans out across claude/gpt-5/gemini). See `~/.claude-octopus/provider-fallbacks.log` for fallback history.

## Preset modes

Five presets live in `~/.claude-octopus/config/presets/`:

| Mode | When to use |
|---|---|
| **balanced** | Default. Each direct account gets its home role, Copilot handles deliver + fallback. Spreads load naturally. |
| **copilot-heavy** | **Cost-optimization mode.** Routes routine work to Copilot Sonnet 4.6 (build/define/counter-audit) + Copilot gpt-5.3-codex (audit/UX/theming/security). Offloads Claude Max Opus 4.7 + ChatGPT Pro Codex direct. Use as default for ROUTINE factory runs to preserve premium quotas. Escalates to direct Opus only on hard reasoning. |
| **claude-heavy** | Claude Max quota is fresh and you want to burn it first. Claude handles build + audit + deliver. |
| **codex-heavy** | ChatGPT Pro quota is fresh. Codex handles build + audit + deliver. |
| **direct-only** | Copilot quota is low. Everything routes through direct accounts (Codex / Claude / Gemini). |
| **copilot-only** | Direct quotas are low. Everything routes through Copilot's multi-backend (uses Copilot's settings.json default model only — no per-role model selection). |

## Per-role Copilot models (copilot-heavy mode)

octo's `dispatch.sh` was patched (2026-04-24) to support `--model` for Copilot via agent-type aliases:

| Agent type | Maps to Copilot model |
|---|---|
| `copilot` (default) | uses `~/.copilot/settings.json` "model" field (currently Sonnet 4.6) |
| `copilot-sonnet` | `--model claude-sonnet-4.6` |
| `copilot-haiku` | `--model claude-haiku-4.5` |
| `copilot-opus` | `--model claude-opus-4.7` |
| `copilot-gpt5` | `--model gpt-5.4` |
| `copilot-codex` | `--model gpt-5.3-codex` |
| `copilot-gpt5mini` | `--model gpt-5.4-mini` |

Override per-call: `OCTOPUS_COPILOT_MODEL_OVERRIDE=<model>` env var.

**Patch backup:** `~/.claude/plugins/cache/nyldn-plugins/octo/9.23.0/scripts/lib/dispatch.sh.bak.YYYYMMDD`. Re-apply if octo plugin updates and overwrites.

## Auto-fallback when Copilot quota exhausts

octo's `dispatch.sh` was patched to route Copilot calls through `~/.claude-octopus/bin/copilot-fallback.sh` instead of invoking `copilot` directly. The wrapper:

1. Checks the lockout file (`~/.claude-octopus/state/copilot-lockout`) on entry. If Copilot was rate-limited within the last 60 minutes (TTL: `OCTOPUS_COPILOT_LOCKOUT_TTL`, default 3600s), skips Copilot entirely and routes to Codex.
2. Otherwise tries Copilot first.
3. On quota / rate-limit error in Copilot's stderr (matches: `quota.exceeded`, `rate.limit`, `premium.request.limit`, `monthly.limit`, `out.of.quota`, `429`, `RESOURCE_EXHAUSTED`, etc.):
   - Writes the lockout file with timestamp
   - Logs the event to `~/.claude-octopus/provider-fallbacks.log`
   - Replays the same prompt (cached in tempfile) via `codex exec --skip-git-repo-check --full-auto --model <fallback>`
   - Returns Codex's output as if it were Copilot's
4. The fallback Codex model is chosen based on the requested Copilot model:
   - `gpt-5.3-codex` / `gpt-5.2-codex` → `gpt-5.3-codex`
   - `gpt-5.4-mini` / `gpt-5-mini` → `gpt-5.4-mini`
   - `gpt-5.4` / `gpt-5.2` → `gpt-5.4`
   - Claude variants (no Codex equivalent) → `gpt-5.4`
   - Override: `OCTOPUS_FALLBACK_CODEX_MODEL=<model>`

octo's in-process `get_alternate_provider` was also patched to add a Copilot case so workflow-level rerouting (not just per-call wrapper retry) works when Copilot is locked.

**Patch backups:**
- `~/.claude/plugins/cache/nyldn-plugins/octo/9.23.0/scripts/lib/dispatch.sh.bak.YYYYMMDD`
- `~/.claude/plugins/cache/nyldn-plugins/octo/9.23.0/scripts/lib/provider-routing.sh.bak.YYYYMMDD`

**Wrapper script:** `~/.claude-octopus/bin/copilot-fallback.sh` (executable, 600).

### How to verify the chain works

```bash
# Force-trigger lockout for testing (bypasses Copilot, uses Codex)
echo "$(date +%s) test-trigger" > ~/.claude-octopus/state/copilot-lockout
echo "say OK" | ~/.claude-octopus/bin/copilot-fallback.sh --no-ask-user --model claude-sonnet-4.6
# Should see: "INFO: Copilot lockout active... using Codex gpt-5.4" + "OK" from Codex
rm ~/.claude-octopus/state/copilot-lockout

# Check fallback history
tail -20 ~/.claude-octopus/provider-fallbacks.log

# Manually clear an active lockout
rm ~/.claude-octopus/state/copilot-lockout
```

### Quota status visibility

GitHub Copilot Premium quota: <https://github.com/settings/copilot> (Account → Settings → Copilot → Usage). No CLI surface for live quota check — the wrapper only learns Copilot is out from the error response on a real call.

## Model availability (verified 2026-04-24)

**Via Copilot CLI** (`copilot --model X`):
- Claude family: Sonnet 4.6, Sonnet 4.5, Sonnet 4, Haiku 4.5, Opus 4.7
- GPT family: GPT-5.4, GPT-5.3-Codex, GPT-5.2-Codex, GPT-5.2, GPT-5.4 mini, GPT-5 mini, GPT-4.1

**NOT available via Copilot:**
- Gemini (any version) — Copilot catalog is GPT + Claude only
- GPT-5.5 — does not exist; latest GPT family is GPT-5.4 / GPT-5.3-Codex
- OpenAI o3 — direct ChatGPT Pro / API only

**Via Gemini CLI (OAuth tier):**
- gemini-2.5-flash (works, rate-limited)
- gemini-2.5-pro / gemini-3.x — REQUIRE Google AI Studio API key (Gemini Plus subscription does NOT grant CLI Pro access)

**Via Codex CLI (ChatGPT Pro OAuth):**
- gpt-5.4, gpt-5.4-mini, gpt-5.3-codex, gpt-5.2, o3 (Pro tier required)

## Commands

```bash
# Show current mode + list all presets
~/.claude-octopus/bin/octo-route.sh
~/.claude-octopus/bin/octo-route.sh status

# Swap to a specific preset
~/.claude-octopus/bin/octo-route.sh balanced
~/.claude-octopus/bin/octo-route.sh claude-heavy
~/.claude-octopus/bin/octo-route.sh copilot-only

# Cycle to next mode in rotation order
# Order: balanced → claude-heavy → codex-heavy → direct-only → copilot-only → balanced
~/.claude-octopus/bin/octo-route.sh rotate
```

Every swap backs up the current config to `providers.json.bak` before overwriting.

## When to rotate

- **Before a long factory loop run** — check which quota is freshest, swap to that mode
- **When you hit a rate limit** — `octo-route.sh rotate` cycles off the stuck provider
- **Daily / weekly cadence** — run `octo-route.sh rotate` via a scheduled task or manually to spread load over time
- **Task-specific** — use `codex-heavy` for pure audit work, `claude-heavy` for pure build work, `balanced` for full factory-loop runs

## Shell alias (add to your profile for convenience)

```bash
alias route='~/.claude-octopus/bin/octo-route.sh'
# Then: route status | route balanced | route rotate
```

## Verification

```bash
route status                                          # see current mode
jq '.routing.phases' ~/.claude-octopus/config/providers.json   # see active routing
tail -20 ~/.claude-octopus/provider-fallbacks.log     # see recent fallbacks
```

## Image generation caveat

Primary logo/image path is OpenAI `gpt-image-1` via `codex:image`. **This requires an `OPENAI_API_KEY`** (separate from ChatGPT OAuth). Codex CLI currently authenticates via OAuth only (`auth.json` has no API key field populated), so direct API calls to the images endpoint will fail.

**Options:**
1. **Add an API key** (recommended) — generate at https://platform.openai.com/api-keys → export `OPENAI_API_KEY=sk-...` in your shell profile. This unlocks the primary image path.
2. **Use Playwright + ChatGPT web** — the recipe can drive ChatGPT web via Playwright MCP to generate images using the OAuth session. Slower + more fragile than API, but no key required.
3. **Accept the fallback** — routing falls through to Gemini `gemini-3-pro-image-preview`. If Gemini's transparent-background support is degraded on your tier, the recipe notes it in the changelog and post-processes to remove the background.

Transparent-background PNGs at 16/32/48/128/512 are mandatory regardless of which path runs.

## Gotchas

- **Copilot internal model** — Copilot CLI's model selection is controlled inside Copilot (`/model` in the CLI), not via octo. If you want Copilot to prefer a specific backend (e.g., always claude-sonnet), set it there.
- **Codex on ChatGPT Plus (pre-Pro)** — rejected gpt-5. With Pro the restriction is gone; if you see a gpt-5 rejection again, verify `~/.codex/auth.json` is still the Pro-tier auth (re-run `codex login` if unsure).
- **Rate limits are per-account, not per-CLI** — Copilot quota is measured in Premium Requests from your GitHub subscription; each CLI call = 1 Premium Request regardless of which internal model Copilot picks.
- **Don't edit `providers.json` by hand when using presets** — your edits will be overwritten on the next swap. Edit the preset file in `~/.claude-octopus/config/presets/<mode>.json` instead, then re-apply via `route <mode>`.
