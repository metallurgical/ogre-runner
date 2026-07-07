---
name: task-list
description: List every checklist step under one job/issue as a task, one row per step, from .ai/.ogre.
---

# /ogre:task-list

Use this skill when the user wants to see all steps/tasks that belong to one job, not just a single task or the whole-runtime status.

## Inputs

- `/ogre:task-list <job-id>` — e.g. `/ogre:task-list job-abc123`

Job id required. If the user gives an issue slug/number instead, run `/ogre:status <issue>` first to read its `Job Id` row, then call this with that job id.

## Behavior

Run:

- `scripts/ogre task-list <job-id>`

This also re-syncs the plan first, so every checklist step shows up here — including ones nobody has run `execute` against yet (those show `pending`, `Executor: -`).

## Output

```
Job Id: job-<uuid>   Issue: <slug>
+---+----------+---------+-----------------+--------------------------+
| # | Task Id  | Status  | Executor        | Step                     |
+---+----------+---------+-----------------+--------------------------+
| 1 | task-... | passed  | codex (gpt-5.5) | Step one: create file A… |
| 2 | task-... | pending | -               | Step two: create file B  |
+---+----------+---------+-----------------+--------------------------+
View one:  ogre status --task <task-id>
```

Sorted by `#` (`step_index`, the checklist's own order) — step 1 first, not newest-first. One row per checklist item in the plan, always, whether or not it's been executed. Status one of `pending`/`running`/`passed`/`failed`/`stopped`. Long step text shortened to ~60 chars with a trailing `…`. If the job has no checklist synced yet, prints `No tasks yet for this job.` Errors out if the job id doesn't resolve to any issue.

**Show the table verbatim, in a code block, exactly as the helper printed it** — same rule as `/ogre:status`: do not paraphrase rows into prose, do not drop columns. Add commentary after the block, not instead of it.
