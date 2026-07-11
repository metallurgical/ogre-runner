---
name: config
description: Show every .ai/.ogre/config.json key Ogre actually reads (dot path, current value/source, CLI override), or reset config.json back to fresh-install defaults.
---

# /ogre:config

Use this skill when the user wants to inspect `.ai/.ogre/config.json` — what it currently affects, whether a value is really being read or silently ignored — or wants to reset it back to a clean/fresh-install state (e.g. after hand-editing it into a confusing state, or because they want to remove a `codex_unsandboxed_browser_check`/`browser_mcp` override they no longer want).

## Concepts

`config.json` has no schema of its own. A key set in the wrong place (e.g. top-level instead of nested under `"defaults"`) silently does nothing — this command exists specifically so the user (or you) doesn't have to guess. Precedence for every value it reports: **CLI flag on the command itself wins, then config.json, then a hardcoded fallback** (`claude`/`claude-sonnet-5` for planner/plan_reviewer/executor/diff_reviewer).

## Inputs

Examples:

- `/ogre:config` (show current values)
- `/ogre:config --reset` (back up to `config.json.bak`, restore fresh-install defaults)

## Behavior

Run:

- `${CLAUDE_PLUGIN_ROOT}/scripts/ogre config [--reset]`

### Show (no flag)

Prints `config.json`'s actual nested JSON shape (not a flattened list), each line annotated with its source (`config.json` vs `fallback`) and the CLI flag/command that overrides it for one invocation:

```jsonc
{
  "defaults": {
    "planner": { "provider": "claude", "model": "claude-sonnet-5" },        # config.json | override: --planner PROVIDER / --model MODEL (ogre feature)
    "plan_reviewer": { "provider": "claude", "model": "claude-sonnet-5" },  # config.json | override: --reviewer PROVIDER / --model MODEL (ogre review-plan)
    "executor": { "provider": "claude", "model": "claude-sonnet-5" },       # config.json | override: --executor PROVIDER / --model MODEL (ogre execute)
    "diff_reviewer": { "provider": "claude", "model": "claude-sonnet-5" }   # config.json | not read by any command yet
  },
  "browser_mcp": null,                                                     # fallback | override: --mcp-config PATH (ogre execute, [BROWSER-CHECK] steps)
  "codex_unsandboxed_browser_check": false                                 # fallback | override: --codex-unsandboxed-browser-check (ogre execute, codex [BROWSER-CHECK] only)
}
```

### Reset (`--reset`)

Backs up the current `config.json` to `config.json.bak` (never silently discarded), then overwrites `config.json` with the fresh-install defaults — same file `ensure_runtime` would write for a brand-new project. This removes any custom `browser_mcp` path and `codex_unsandboxed_browser_check` override, and resets `defaults.*` back to `claude`/`claude-sonnet-5` across the board.

Tell the user what got backed up and where, so they can restore an intentional override (e.g. `codex_unsandboxed_browser_check: true`) from `config.json.bak` if the reset was more than they wanted.
