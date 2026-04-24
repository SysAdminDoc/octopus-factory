# dispatch.sh — per-role Copilot model selection + fallback wrapper hookup

**Target file:** `~/.claude/plugins/cache/nyldn-plugins/octo/<version>/scripts/lib/dispatch.sh`

## What this changes

Adds support for these new agent type aliases:

| Agent type | Maps to Copilot model |
|---|---|
| `copilot` (existing) | uses `~/.copilot/settings.json` "model" field |
| `copilot-sonnet` | `--model claude-sonnet-4.6` |
| `copilot-haiku` | `--model claude-haiku-4.5` |
| `copilot-opus` | `--model claude-opus-4.7` |
| `copilot-gpt5` | `--model gpt-5.4` |
| `copilot-codex` | `--model gpt-5.3-codex` |
| `copilot-gpt5mini` | `--model gpt-5.4-mini` |

Plus per-call override via `OCTOPUS_COPILOT_MODEL_OVERRIDE` env var.

Also routes all `copilot*` calls through the `copilot-fallback.sh` wrapper if it exists at `~/.claude-octopus/bin/copilot-fallback.sh` — enables auto-fallback to Codex on Copilot quota errors.

## Find this block

In `scripts/lib/dispatch.sh`, search for:

```bash
        copilot|copilot-research)  # v9.9.0: GitHub Copilot CLI — copilot -p (Issue #198)
            echo "copilot --no-ask-user"
            ;;
```

(Around line 102 in octo v9.23.0; line number may shift in other versions.)

## Replace with

```bash
        copilot|copilot-research|copilot-sonnet|copilot-haiku|copilot-opus|copilot-gpt5|copilot-codex|copilot-gpt5mini)
            # v9.9.0: GitHub Copilot CLI — copilot -p (Issue #198)
            # octopus-factory patch: per-role model selection.
            # Model resolution priority:
            #   1. agent_type alias maps to specific model (copilot-sonnet → claude-sonnet-4.6, etc.)
            #   2. OCTOPUS_COPILOT_MODEL_OVERRIDE env var (per-call override)
            #   3. Default: omit --model flag (copilot uses settings.json default)
            local _copilot_model=""
            case "$agent_type" in
                copilot-sonnet)    _copilot_model="claude-sonnet-4.6" ;;
                copilot-haiku)     _copilot_model="claude-haiku-4.5" ;;
                copilot-opus)      _copilot_model="claude-opus-4.7" ;;
                copilot-gpt5)      _copilot_model="gpt-5.4" ;;
                copilot-codex)     _copilot_model="gpt-5.3-codex" ;;
                copilot-gpt5mini)  _copilot_model="gpt-5.4-mini" ;;
            esac
            if [[ -n "${OCTOPUS_COPILOT_MODEL_OVERRIDE:-}" ]]; then
                _copilot_model="${OCTOPUS_COPILOT_MODEL_OVERRIDE}"
            fi
            # octopus-factory patch: route through copilot-fallback.sh wrapper if installed
            local _copilot_cmd="copilot"
            if [[ -x "${HOME}/.claude-octopus/bin/copilot-fallback.sh" ]]; then
                _copilot_cmd="${HOME}/.claude-octopus/bin/copilot-fallback.sh"
            fi
            if [[ -n "$_copilot_model" ]]; then
                echo "${_copilot_cmd} --no-ask-user --model ${_copilot_model}"
            else
                echo "${_copilot_cmd} --no-ask-user"
            fi
            ;;
```

## Verify after applying

```bash
# Should output: /home/<you>/.claude-octopus/bin/copilot-fallback.sh --no-ask-user --model claude-sonnet-4.6
bash -c 'source ~/.claude/plugins/cache/nyldn-plugins/octo/<version>/scripts/lib/dispatch.sh && get_agent_command copilot-sonnet'
```

## Rollback

The `apply.sh` installer creates a `.bak.<date>` file. Restore with:

```bash
cp <plugin-path>/scripts/lib/dispatch.sh.bak.<date> <plugin-path>/scripts/lib/dispatch.sh
```
