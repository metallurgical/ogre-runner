# ogre-plugin

## Testing

`scripts/ogre` has a bats-core suite under `tests/` (one file per subcommand, see `tests/README.md`).

- Any change to `scripts/ogre` (new subcommand, modified flag, changed state/ledger logic) must run the related `tests/cmd_<name>.bats` file before considering the change done.
- If the change touches shared helpers (`sync_state_from_plan`, `finalize_link_status`, `task_update`, etc.) or you're not sure which command files are affected, run the full suite: `bats tests/`.
- Add or update tests for the behavior you changed in the same commit as the fix - don't land a logic change without a test that would have caught it.
- This repo's bats (1.13) only fails a test on its **last** command - a false `[[ ]]`/`[ ]` anywhere earlier is silently ignored, `set -e` doesn't change that. Write every assertion as `<assertion> || return 1`, not just the final one, or the test proves nothing about its non-final checks.
- Before wiring a new flag into a `<tool> <subcommand> ...` invocation (e.g. `codex exec ...`), verify it against that subcommand's own `--help`, not the parent command's - clap/argparse-style CLIs commonly scope flags per-subcommand, and a flag existing on the parent says nothing about the subcommand's own parser. The bats mocks for `codex`/`claude` won't catch an invalid-flag regression either (they don't validate real flag support) - do one real, non-mocked invocation as a smoke test for any new CLI flag before considering it verified.
- `cmd_execute.bats`'s "execute --background prints the finish summary and Boom line once the job completes" test is known-flaky/pre-existing (fails on a clean `git stash` of `main` too) - if it fails while you're verifying an unrelated change, confirm via stash/pop that it fails the same way on main before treating it as a regression you caused.

## Releasing

Don't bump the version on your own initiative just because a commit changes plugin behavior - wait for the user to explicitly say to bump/release. Commits can land on `main` unbumped; that's fine.

Once the user does say to bump, bump all three locations together in that same action, every time:

- `.claude-plugin/plugin.json`'s `version`
- `.claude-plugin/marketplace.json`'s `plugins[].version` (easy to miss - it's a separate field from `plugin.json` and has gone stale for several releases in a row before)
- `OGRE_VERSION` in `scripts/ogre`

All three must match. Claude Code's plugin cache (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`) only redeploys on a version bump - `/plugin marketplace update` alone only refreshes the marketplace git clone, not the installed cache, so missing even one of the three leaves users silently running old/broken code while believing they're on the latest. Grep all three in one pass before considering a bump done: `grep -rn '"version"' .claude-plugin/*.json; grep -n OGRE_VERSION scripts/ogre`.

## Orchestrating `ogre execute` from a driving Claude Code session

If you (Claude Code) are the one invoking `ogre feature`/`ogre execute`/etc. on behalf of a user, not just editing `scripts/ogre`'s source - this section is for you.

- **Never spawn an `Agent` subagent (fork or otherwise) just to supervise an `ogre execute --all --background` chain.** The background driver is self-contained: it drives every remaining step, writes to `.ai/.ogre/state/tasks.json` and `state/issue-<x>.json`, and exits on its own once done or blocked. A supervising subagent adds no value and - if it's a `fork` - always runs on the Claude model regardless of which executor (`codex`/`claude`) the actual steps use, silently burning Claude quota for pure babysitting.
- **Don't use the Monitor/continuous-event-stream tool either** for a one-shot "tell me when this finishes" - it's built for tail -f/inotify-style ongoing streams, not a single wait-until-done, and behaves flakily when misused that way.
- Pick one of two plain waiting strategies, based on whether ogre's own `--background` flag was passed:
  - **No ogre `--background` flag** (default `new`/foreground isolation, or `--main`): wrap the whole blocking `ogre execute ... --all` call in a plain backgrounded shell command (e.g. Bash tool's `run_in_background: true`). It blocks on that one child process - any step count, since `--all` chains all of them inside it - and you get a single completion signal the moment it exits. No polling, lowest CPU/RAM/token overhead. Use this by default.
  - **ogre's own `--background` flag** (self-detaches into its own process group, no PID left to block on): wrap a small status-poll loop instead, e.g. `until [ "$(ogre status --task <id>)" = ... ]; do sleep 10; done`, backgrounded the same way. Slightly more overhead (periodic wake/sleep) but survives the driving session/machine going away mid-run - use this only when that survival actually matters (long unattended runs), not by default.
- Either way, report results only once the job is actually done (real completion signal), never based on an assumed/predicted outcome.
- **Never silently swap `--main`/`--background` or the executor (`claude`/`codex`) the user asked for**, even when resuming a capped/stalled chain. Resume it the exact same way it started (`ogre execute --job <id> --all --background`, not a bare `--main` retry) - a step needing different tooling is not license to switch quietly. The only acceptable reason to deviate is a genuine hard blocker (e.g. no browser MCP available), and even then say so loudly *before* switching, not after.
- **`[BROWSER-CHECK]` tagging is opt-in, not automatic.** `ogre feature` only tags steps for real-browser verification when called with `--browser-check`; the default plan has zero such steps and the user is expected to verify the feature themselves. Don't pass `--browser-check` unless the user actually asked for automated browser verification, and don't assume a plan without it is incomplete.
- **`--codex-unsandboxed-browser-check` (or `codex_unsandboxed_browser_check` in config.json) is a real security tradeoff, not a convenience flag.** It removes ALL sandboxing (filesystem+shell+network) for the one spawn covering that `[BROWSER-CHECK]` step, because codex's own sandbox otherwise blocks the browser subprocess entirely - `claude` needs no such opt-in and isolates fine by default. Never enable it without telling the user what it trades away first.
- When hitting the `[BROWSER-CHECK]` `auto_fix_cap` on a failure, don't stop to ask the user which of several options to pick. Resolve it yourself (create a minimal real file if genuinely missing, revert stray half-finished edits from failed attempts, mark the step passed with notes on what changed) and report afterward. Only actually stop-and-ask for a genuine irreversible/destructive action or a real product-decision ambiguity - "another error came up" is not by itself a reason to escalate.
- `ogre execute <issue> --all --background` chains can occasionally die mid-run with no trace in their own log (root cause still open). `ogre status <issue>` self-heals this - detects a dead driver with pending steps left and auto-relaunches - so if a chain looks stuck, re-run `ogre status <issue>` before assuming something is broken.
