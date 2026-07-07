---
name: stop
description: Stop, pause, archive, or delete Ogre runtime data for an issue without reverting code changes.
---

# /ogre:stop

Use this skill when the user wants to stop an active Ogre workflow (whole job or a single task), stop all workflows, archive runtime data, or delete runtime data.

## Concepts

- **Job** = one feature/issue workflow, 1:1 with the issue. Id `job-<uuid>`. Stopping a job cascades: kills every `running` task under it and marks all its pending/running tasks `stopped`.
- **Task** = one `ogre execute` attempt under a job. Id `task-<uuid>`. Stopping a single task kills just that pid/marks just that task `stopped` — sibling tasks and the job/issue state are untouched.

Use job-level stop to abandon/pause the whole feature. Use task-level stop to kill one misbehaving background attempt (e.g. a hung `--background` execute) without aborting the rest of the workflow.

## Inputs

Examples:

- `/ogre:stop 107` (stop the job — cascades to all its tasks)
- `/ogre:stop --job <job-id>` (same, addressed by job id)
- `/ogre:stop --task <task-id>` (stop ONE task only)
- `/ogre:stop --all`
- `/ogre:stop 107 --archive`
- `/ogre:stop 107 --delete`
- `/ogre:stop 107 --list`

## Behavior

Run:

- `scripts/ogre stop [issue] [--job <job-id>] [--task <task-id>] [--all] [--archive] [--delete] [--list]`

## Modes

### Stop current job (issue)

Marks the issue state as `stopped` and cascades to all its tasks (kills running pids, marks pending/running tasks `stopped`).

Keeps:

- `.ai/.ogre/issues/`
- `.ai/.ogre/plans/`
- `.ai/.ogre/reviews/`
- `.ai/.ogre/logs/`
- `.ai/.ogre/state/`

Does not revert code.

### Stop one task

`--task <task-id>` kills that task's pid (if running) and marks only that task `stopped`. Does not touch the job/issue status or any other task. Look up the task id via `/ogre:status --tasks <issue>` if the user doesn't have it.

### Stop all

Marks all Ogre issue (job) states as `stopped`, cascading to every task under each.

### Archive

Moves the issue data to:

- `.ai/.ogre/archive/issue-<number>-YYYYMMDD-HHMMSS/`

### Delete

Deletes Ogre runtime data for that issue only after confirmation.

Does not revert code changes.

### List

Prints every runtime file/dir path for the issue (`.ai/.ogre/issues/`, `plans/`, `reviews/`, `logs/`, `state/`, `tmp/`) without deleting anything. Use this when the user wants to clean up **individually** instead of all at once — show them the list, let them pick, then delete the chosen paths yourself (normal `rm` with confirmation, per usual safety rules) rather than running `--delete`.

## Completion Cleanup Prompt

`/ogre:status <issue>` reports when an issue's plan is fully checked off (`status: completed`). When you see that, ask the user what to do with the issue's Ogre runtime data — don't decide for them and don't delete automatically:

- Keep it (no action)
- Archive it (`scripts/ogre stop <issue> --archive`)
- Delete all at once (`scripts/ogre stop <issue> --delete`)
- Delete individually (`scripts/ogre stop <issue> --list`, then remove the specific paths they choose)
