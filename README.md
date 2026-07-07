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
