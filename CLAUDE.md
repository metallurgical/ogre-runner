# ogre-plugin

## Testing

`scripts/ogre` has a bats-core suite under `tests/` (one file per subcommand, see `tests/README.md`).

- Any change to `scripts/ogre` (new subcommand, modified flag, changed state/ledger logic) must run the related `tests/cmd_<name>.bats` file before considering the change done.
- If the change touches shared helpers (`sync_state_from_plan`, `finalize_link_status`, `task_update`, etc.) or you're not sure which command files are affected, run the full suite: `bats tests/`.
- Add or update tests for the behavior you changed in the same commit as the fix - don't land a logic change without a test that would have caught it.
