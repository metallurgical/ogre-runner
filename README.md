# Ogre Plugin Scaffold

Ogre is a Claude Code plugin scaffold for a controlled AI coding workflow:

1. Fetch GitHub issue(s) into `.ai/.ogre/issues/`
2. Create an execution blueprint plan in `.ai/.ogre/plans/`
3. Review the plan before coding
4. Execute the plan one checklist item at a time
5. Store progress in `.ai/.ogre/state/`
6. Keep logs/reviews/tmp files under `.ai/.ogre/`

This scaffold is designed for:

- Claude Code planning
- Codex execution via Codex CLI or `codex-plugin-cc`
- Optional Claude execution
- Fresh execution context per checklist item

## Runtime Folder

Inside each target project, Ogre creates:

```txt
.ai/.ogre/
  config.json
  issues/
  plans/
  reviews/
  logs/
  state/
  tmp/
  archive/
  prompts/
```

## Commands / Skills

Expected Claude Code commands:

```txt
/ogre:feature       # accepts an issue number/URL/local file, OR a freeform --statement (no issue needed)
/ogre:review-plan
/ogre:execute
/ogre:add-blocker   # attach a new blocker mid-flight (issue or freeform --statement)
/ogre:task-list     # list every checklist step for a job, one row per step
/ogre:stop
/ogre:status
```

The skills delegate deterministic setup to:

```txt
scripts/ogre
```

## Command Reference

All commands run as `scripts/ogre <command> ...` or via the matching `/ogre:<command>` skill (same flags either way). Positional input always comes first, flags after, in any order.

### `ogre init`

Creates the runtime folders and copies templates. No options.

### `ogre feature`

Starts a new issue workflow: fetch (or write) the issue, generate the planning runner.

| Option | Example | Description |
| :--- | :--- | :--- |
| `<issue>` (positional) | `ogre feature 107` | GitHub issue number (GitHub-only — resolved via `gh` + this project's git remote) |
| `<issue>` (positional) | `ogre feature https://github.com/acme/app/issues/107` | Full GitHub issue URL |
| `<issue>` (positional) | `ogre feature https://gitlab.com/acme/app/-/issues/9` | Any non-GitHub issue/page URL (GitLab, self-hosted GitLab, Bitbucket, Jira, etc.) — fetched generically as page text, not via an API |
| `<issue>` (positional) | `ogre feature ./notes/bug-report.md` | Local file path (`.md`, `.txt` copied verbatim; `.docx` text-extracted) |
| `--statement "..."` | `ogre feature --statement "need a forgot-password page"` | Freeform feature text, no issue needed at all |
| `--name NAME` | `ogre feature --statement "..." --name forgot-password` | Slug for runtime paths when using `--statement` (default: first ~4 words + short uuid) |
| `--blocks 1,2,url,path` | `ogre feature 107 --blocks 101,102` | Comma-separated blockers (issue numbers/URLs/paths), fetched alongside the main issue |
| `--plan NAME.md` | `ogre feature 107 --plan issue-107-v2.md` | Custom plan output filename instead of the default `issue-<n>.md` |
| `--planner claude\|codex` | `ogre feature 107 --planner codex` | Which LLM CLI plans the feature (default: `claude`) |
| `--model MODEL` | `ogre feature 107 --planner codex --model gpt-5.5` | Model override for the planner |

### `ogre add-blocker`

Attaches a new blocker to an issue already tracked by Ogre, and forces the plan to be revised. Refuses once execution has started (use `--force` to override — manual-risk, already-completed steps aren't retroactively revised).

| Option | Example | Description |
| :--- | :--- | :--- |
| `<issue>` (positional, required) | `ogre add-blocker 107 ...` | The already-tracked issue to attach the blocker to |
| `<blocker>` (positional) | `ogre add-blocker 107 108` | Blocker as issue number, URL, or local file path |
| `--statement "..."` | `ogre add-blocker 107 --statement "must invalidate old tokens"` | Freeform blocker text instead of an issue/URL/path |
| `--name SLUG` | `ogre add-blocker 107 --statement "..." --name invalidate-tokens` | Slug for the blocker's file, only used with `--statement` |
| `--force` | `ogre add-blocker 107 108 --force` | Override the "execution already started" refusal (skips retroactive revision of completed steps — surface this warning to the user, never pass silently) |

### `ogre review-plan`

Reviews a generated plan for hallucinations, missing validation, risky assumptions, over-scoped steps.

| Option | Example | Description |
| :--- | :--- | :--- |
| `<issue-or-plan>` (positional) | `ogre review-plan 107` | Issue number, plan name (`issue-107`), or plan path |
| `--reviewer claude\|codex` | `ogre review-plan 107 --reviewer codex` | Which LLM CLI reviews the plan (default: `claude`) |
| `--model MODEL` | `ogre review-plan 107 --reviewer codex --model gpt-5.5` | Model override for the reviewer |

### `ogre execute`

Executes one checklist item (or all remaining, with `--all`) from an approved plan.

| Option | Example | Description |
| :--- | :--- | :--- |
| `<issue-or-plan>` (positional) | `ogre execute 107` | Issue number, plan name, or plan path |
| `--job JOB_ID` | `ogre execute --job job-6d7715e4-...` | Target by job id instead of issue/plan |
| `--executor codex\|claude` | `ogre execute 107 --executor claude` | Which LLM CLI executes the step (default: `codex`) |
| `--model MODEL` | `ogre execute 107 --executor claude --model sonnet-5` | Model override for the executor |
| `--task TASK_ID` | `ogre execute 107 --task task-0f32a78f-...` | Target one specific seeded step out of order |
| `--step N` | `ogre execute 107 --step 3` | Target step N (1-based) out of order |
| `--all` | `ogre execute 107 --all` | Chain through every remaining step, each session self-assessing context budget and handing off when ~50%+ used |
| `--fresh` | `ogre execute 107 --fresh` | Force a brand-new context for this step (default) |
| `--resume` | `ogre execute 107 --resume` | Resume prior context for this step instead of starting fresh |
| `--main` | `ogre execute 107 --main` | Run inline in the current Claude Code session, no subprocess spawned — use only when explicitly requested, defeats Ogre's context-isolation purpose if habitual |
| `--background` | `ogre execute 107 --background` | Same isolation as default (new session) but detached/non-blocking |
| `--yes` | `ogre execute 107 --yes` | Required to proceed non-interactively when the step/job was previously `stopped`, or jumping to an out-of-order step whose earlier steps aren't `passed` — only pass after explicit user confirmation |

Default with no isolation flag: foreground, brand-new codex/claude session, targeting the lowest-numbered pending step.

### `ogre status`

Shows job/task progress from `.ai/.ogre` state.

| Option | Example | Description |
| :--- | :--- | :--- |
| `[issue]` (positional, optional) | `ogre status 107` | Show one issue's Job Summary + its tasks. Omit for every issue + every pending/running task |
| `--job JOB_ID` | `ogre status --job job-6d7715e4-...` | Same as `[issue]`, addressed by job id |
| `--tasks` | `ogre status --tasks` or `ogre status 107 --tasks` | List all tasks, optionally filtered to one issue |
| `--task TASK_ID` | `ogre status --task task-0f32a78f-...` | Show one task's full record |
| `--watch` | `ogre status --watch` | Live-refresh view (run standalone in another terminal), Ctrl-C to quit |
| `--interval N` | `ogre status --watch --interval 5` | Refresh seconds for `--watch` (default: 2) |

### `ogre task-list`

Lists every checklist step under one job, one row per step (including steps never executed yet).

| Option | Example | Description |
| :--- | :--- | :--- |
| `<job-id>` (positional, required) | `ogre task-list job-6d7715e4-...` | Get the job id from `Job Id` in `ogre status <issue>` output |

### `ogre task-complete`

Manually marks a task's ledger status. Only needed when the executing agent did the work directly (not via `--run`/`--background`, which mark it automatically) — this is the mandatory last step in that case.

| Option | Example | Description |
| :--- | :--- | :--- |
| `<task-id>` (positional, required) | `ogre task-complete task-0f32a78f-...` | The task id to mark |
| `--status passed\|failed` | `ogre task-complete task-0f32a78f-... --status passed` | Outcome to record (default: `passed`) |
| `--exit-code N` | `ogre task-complete task-0f32a78f-... --status failed --exit-code 1` | Optional exit code to record alongside the status |

### `ogre stop`

Stops, archives, or deletes Ogre runtime data. Does not revert code changes.

| Option | Example | Description |
| :--- | :--- | :--- |
| `[issue]` (positional, optional) | `ogre stop 107` | Stop the job: cascades to all its tasks (kills running pids, marks pending/running `stopped`) |
| `--job JOB_ID` | `ogre stop --job job-6d7715e4-...` | Same, addressed by job id |
| `--task TASK_ID` | `ogre stop --task task-0f32a78f-...` | Stop ONE task only — sibling tasks and job/issue state untouched |
| `--all` | `ogre stop --all` | Stop every tracked job (cascades to all their tasks) |
| `--archive` | `ogre stop 107 --archive` | Move the issue's runtime data to `.ai/.ogre/archive/issue-<n>-<timestamp>/` |
| `--delete` | `ogre stop 107 --delete` | Delete the issue's runtime data (after confirmation) |
| `--list` | `ogre stop 107 --list` | Print every runtime file/dir path for the issue without deleting, so the user can pick individually |

## Install / Test Locally

From anywhere:

```bash
claude --plugin-dir /path/to/ogre-plugin
```

Then open your project in Claude Code and try:

```txt
/ogre:feature 107 --blocks 101,102
```

The helper script can also be run directly from a project root:

```bash
/path/to/ogre-plugin/scripts/ogre init
/path/to/ogre-plugin/scripts/ogre feature 107 --blocks 101,102
/path/to/ogre-plugin/scripts/ogre status
```

## Required Tools

Optional but recommended:

```bash
gh --version
codex --version
claude --version
```

If `gh` is missing, Ogre creates placeholder issue files so you can paste issue content manually.

If `codex` is missing, `/ogre:execute --executor codex --run` will fail, but you can still generate runner prompts and pass them manually.

## Recommended Workflow

**Main use case: freeform text — no GitHub issue required.** Just describe the feature in your own words:

```txt
/ogre:feature --statement "need to implement forgot password page" --name forgot-password
# Ogre writes the statement verbatim to .ai/.ogre/issues/issue-forgot-password.md
# and plans/executes it exactly like a real issue from here on

# Review and edit .ai/.ogre/plans/issue-forgot-password.md

/ogre:review-plan forgot-password --reviewer claude
# Fix plan comments manually until approved

/ogre:execute forgot-password --executor codex
# Executes next checklist item only

/ogre:execute forgot-password --executor codex
# Next checklist item

/ogre:status forgot-password
```

A GitHub issue number/URL/local file works the same way, as an alternative input:

```txt
/ogre:feature 107 --blocks 101,102
# Review and edit .ai/.ogre/plans/issue-107.md

/ogre:review-plan 107 --reviewer claude
# Fix plan comments manually until approved

/ogre:execute 107 --executor codex
# Executes/generates runner for next checklist item only

/ogre:execute 107 --executor codex
# Next checklist item

/ogre:status 107
```

Add a blocker discovered mid-flight (freeform or issue-based, same either way):

```txt
/ogre:add-blocker forgot-password --statement "must also invalidate old reset tokens" --name invalidate-tokens
# Plan is revised in place to account for the new blocker
# Refuses if execution already started for this issue - use /ogre:stop first, or --force to override (manual-risk)
```

See every checklist step for a job at once:

```txt
/ogre:task-list job-<uuid>
# One row per step: #, Task Id, Status, Executor, Step
# Get the job id from `Job Id` in /ogre:status <issue> output
```

## Direct CLI Usage

Create runtime folders and copy templates:

```bash
scripts/ogre init
```

Fetch issues and generate planning runner:

```bash
scripts/ogre feature 107 --blocks 101,102
```

Or skip the issue entirely and describe the feature in your own words:

```bash
scripts/ogre feature --statement "need to implement forgot password page" --name forgot-password
```

Add a blocker to an in-flight issue (freeform or issue-based):

```bash
scripts/ogre add-blocker 107 --statement "must also invalidate old reset tokens" --name invalidate-tokens
```

List every checklist step for a job:

```bash
scripts/ogre task-list job-<uuid>
```

Generate review runner:

```bash
scripts/ogre review-plan 107 --reviewer claude
```

Generate execution runner:

```bash
scripts/ogre execute 107 --executor codex
```

Run Codex directly:

```bash
scripts/ogre execute 107 --executor codex --model gpt-5.5 --run
```

Run Claude directly:

```bash
scripts/ogre execute 107 --executor claude --model sonnet-5 --run
```

Stop/pause issue:

```bash
scripts/ogre stop 107
```

Archive issue runtime data:

```bash
scripts/ogre stop 107 --archive
```

Delete issue runtime data:

```bash
scripts/ogre stop 107 --delete
```

## Notes

- Ogre does not revert code changes.
- Ogre runtime state is file-based, so Claude and Codex can resume by reading `.ai/.ogre/state/` and `.ai/.ogre/plans/`.
- Default execution is one checklist item at a time.
- `--all` is reserved for future improvement; use one-step execution until the workflow is proven.

## Suggested `.gitignore`

For private solo workflow:

```gitignore
.ai/.ogre/
```

For team-visible plans but private logs:

```gitignore
.ai/.ogre/logs/
.ai/.ogre/tmp/
.ai/.ogre/reviews/
```
