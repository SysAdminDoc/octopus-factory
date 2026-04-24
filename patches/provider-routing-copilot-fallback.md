# provider-routing.sh — add Copilot to cross-provider fallback chain

**Target file:** `~/.claude/plugins/cache/nyldn-plugins/octo/<version>/scripts/lib/provider-routing.sh`

## What this changes

octo's `get_alternate_provider` function picks a backup provider when the primary is locked out (rate-limit, API failure, etc.). The default version handles `codex`, `gemini`, and `claude-sonnet` cases but has no `copilot` case — so when Copilot fails, no fallback fires from the in-process router.

This patch adds a `copilot|copilot-*` case that prefers Codex first, then Claude Sonnet, then Gemini.

(Note: even without this patch, the `copilot-fallback.sh` wrapper in `bin/` already does per-call fallback at the CLI level. This patch enables workflow-level rerouting — when the entire workflow phase wants to swap agent type for subsequent calls.)

## Find this block

In `scripts/lib/provider-routing.sh`, search for:

```bash
        claude-sonnet|claude*)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "gemini"; then
                echo "gemini"
            else
                echo "$locked_provider"
            fi
            ;;
        *)
            echo "$locked_provider"
            ;;
    esac
}
```

(Around line 410 in octo v9.23.0.)

## Replace with

```bash
        claude-sonnet|claude*)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "gemini"; then
                echo "gemini"
            else
                echo "$locked_provider"
            fi
            ;;
        copilot|copilot-*)
            # octopus-factory patch: Copilot fallback chain.
            # On Copilot quota exhaustion, prefer Codex (direct ChatGPT Pro Codex CLI)
            # because copilot-fallback.sh wrapper already does the same fallback at
            # CLI level. This in-process alternate is for cases where octo's workflow
            # graph wants to reroute the whole agent type for subsequent calls.
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "claude-sonnet"; then
                echo "claude-sonnet"
            elif ! is_provider_locked "gemini"; then
                echo "gemini"
            else
                echo "$locked_provider"
            fi
            ;;
        *)
            echo "$locked_provider"
            ;;
    esac
}
```

## Verify after applying

```bash
# Should print "codex" if codex is unlocked
bash -c 'source ~/.claude/plugins/cache/nyldn-plugins/octo/<version>/scripts/lib/provider-routing.sh && get_alternate_provider copilot'
```

## Rollback

```bash
cp <plugin-path>/scripts/lib/provider-routing.sh.bak.<date> <plugin-path>/scripts/lib/provider-routing.sh
```
