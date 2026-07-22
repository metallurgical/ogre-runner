---
name: prune
description: Bulk-delete finished Ogre runtime data (rescue logs/tmp by default, optionally whole completed/stopped feature issues too) instead of targeting one issue at a time with /ogre:stop --delete.
---

# /ogre:prune

Use this skill when the user wants to clean up accumulated Ogre runtime data
in bulk - most commonly the ad-hoc `.ai/.ogre/{logs,tmp}/issue-rescue-<slug>/`
directories every `/ogre:rescue` call creates, which have no other cleanup
path (`/ogre:stop --delete` targets one issue at a time, and nothing runs
automatically). Alias: `/ogre:purge` (identical, same flags).

## Inputs

- `--all` - also sweeps completed/stopped feature/execute issues, not just
  rescues. Without it, only `rescue-*` ledger tasks are ever considered.
- `--older-than N` - age safety margin in days (default `1`). Only tasks/
  issues finished more than N days ago are eligible. `--older-than 0`
  overrides for immediate cleanup.
- `--yes` - actually deletes. Without it, `ogre prune` only previews what's
  eligible and deletes nothing (dry-run is the default, not opt-in).

## Behavior

Run:

- `${CLAUDE_PLUGIN_ROOT}/scripts/ogre prune [--all] [--older-than N] [--yes]`

Two-step by default - **always run it once without `--yes` first and show the
user the preview** (issue, finished date, reclaimable size) before adding
`--yes`. This is a bulk-delete operation; do not skip straight to `--yes`
just because the user said "clean it up" or "prune the old stuff" - show them
what's eligible, get their go-ahead on the specific list (not just the idea
in the abstract), then re-run with `--yes`. Exception: if the user's own
message already specifies age and scope precisely enough that the eligible
set is unambiguous (e.g. "purge everything --all --yes older than 7 days"),
running it directly is fine - they've already made the call.

## What's eligible

- **Default (rescue-only)**: a `rescue-*` ledger issue is eligible only if
  *every* task under it is fully terminal (`passed`/`failed`/`stopped` -
  never touches one with any `pending`/`running` task) and its most recent
  finish timestamp is older than `--older-than` days.
- **`--all`**: also considers regular feature/execute issues, but only ones
  whose own `state.json` status is `completed` or `stopped` - the same
  terminal states `/ogre:status` already flags as ready for
  `/ogre:stop --archive`/`--delete`. Never touches a mid-plan or
  mid-execution issue.
- Deletion itself reuses the same primitive `/ogre:stop <issue> --delete`
  uses (files + ledger rows together) - there is exactly one deletion
  implementation, prune just applies it to a bulk-selected set.

## When NOT to suggest this

Don't proactively suggest pruning unless the user brings up disk usage,
clutter, or asks for cleanup - it's not something to run as a matter of
routine maintenance on their behalf.
