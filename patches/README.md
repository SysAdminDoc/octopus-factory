# Patches

Optional patches to the [Claude Octopus](https://github.com/nyldn/claude-octopus) plugin that enable two features octopus-factory uses:

1. **Per-role Copilot model selection** — invoke Copilot CLI with `--model gpt-5.3-codex` or `--model claude-haiku-4.5` per phase, instead of always using Copilot's default model.
2. **Cross-provider fallback chain** — when Copilot quota exhausts, transparently fall back to Codex (or any other available provider) for the same prompt.

## Apply

```bash
bash apply.sh
```

The script:
- Locates your Claude Octopus plugin install
- Backs up the original files (`*.bak.<date>`)
- Applies both patches
- Verifies they took
- Prints rollback instructions

Idempotent — safe to re-run.

## Manual application

If `apply.sh` doesn't work for your setup, both patches are documented as find/replace blocks:

- [`dispatch-copilot-models.md`](dispatch-copilot-models.md) — patch for `scripts/lib/dispatch.sh`
- [`provider-routing-copilot-fallback.md`](provider-routing-copilot-fallback.md) — patch for `scripts/lib/provider-routing.sh`

## Rollback

```bash
# Find the backup (created automatically on apply)
ls ~/.claude/plugins/cache/nyldn-plugins/octo/<version>/scripts/lib/*.bak.*

# Restore
cp ~/.claude/plugins/cache/nyldn-plugins/octo/<version>/scripts/lib/dispatch.sh.bak.<date> \
   ~/.claude/plugins/cache/nyldn-plugins/octo/<version>/scripts/lib/dispatch.sh

cp ~/.claude/plugins/cache/nyldn-plugins/octo/<version>/scripts/lib/provider-routing.sh.bak.<date> \
   ~/.claude/plugins/cache/nyldn-plugins/octo/<version>/scripts/lib/provider-routing.sh
```

## Persistence across plugin updates

When octo plugin updates (e.g., 9.23.0 → 9.24.0), the patches will be lost — the plugin install dir is recreated. Re-run `apply.sh` after each octo update. Future work: package this as a proper plugin override or upstream the changes to octo.
