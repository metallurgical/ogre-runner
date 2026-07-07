---
name: status
description: Show Ogre runtime status, plans, state files, and active issue progress from .ai/.ogre.
---

# /ogre:status

Use this skill when the user wants to see current Ogre workflow progress.

## Inputs

Examples:

- `/ogre:status`
- `/ogre:status 107`
- `/ogre:status --job <job-id>` (issue state, addressed by job id instead of issue slug)
- `/ogre:status --tasks` (all tasks across all jobs/issues)
- `/ogre:status 107 --tasks` (tasks for one issue/job)
- `/ogre:status --task <task-id>` (single task record)
- `/ogre:status --watch` (live-refresh, run standalone in another terminal while a task is executing — Ctrl-C to quit)
- `/ogre:status --watch --interval 5` (custom refresh seconds, default 2)

## Concepts

- **Job** = one feature/issue workflow, 1:1 with the issue. Id `job-<uuid>`, stored as `job_id` in that issue's state json.
- **Task** = one checklist step under a job's plan. Id `task-<uuid>`, in the shared ledger `.ai/.ogre/state/tasks.json`, `step`/`step_index` hold the checklist text and its 1-based position. Seeded automatically the moment the plan is synced (on any `status`/`task-list`/`execute` call) — exists and shows `pending` even before anyone runs `execute` against it.

## Behavior

Run:

- `scripts/ogre status [issue] [--job <job-id>] [--tasks] [--task <id>] [--watch] [--interval <seconds>]`

`--watch` is meant to be run directly in a plain terminal (not through the agent) so the user has a live-updating view while a long `ogre execute` task runs in this or another session — since status only reads state off disk, it doesn't need the agent to be free. It clears and reprints the same Job/Task Summary block every `--interval` seconds (default 2) until Ctrl-C.

## Output

For a specific issue (or `--job <job-id>`, which resolves to the same issue), the helper prints a structured **Job Summary** first, then that issue's tasks, then the raw state JSON for anyone who wants full detail:

```
+--------------+-------------------------------------+
| Job Id       | job-<uuid>                           |
| Issue        | <slug>                               |
| Status       | planning|executing|completed|stopped |
| Plan         | <path>  (not written yet if missing) |
| Steps Completed | <n>                                |
| Steps Remaining | <n>                                |
| Steps Total     | <n>                                |
| View status  | ogre status <issue>                  |
| Review plan  | ogre review-plan <issue>   <- only if plan exists and status != completed
| Execute next | ogre execute <issue>       <- only if plan exists and status != completed
| Stop         | ogre stop <issue>          <- only if status != completed/stopped
| Archive/Delete/List files: ...            <- only if status == completed
+--------------+-------------------------------------+
Steps (<n>):                 <- one row per checklist step, in order, every one seeded as a task
+---+-----------+---------------+---------+
| # | Status    | Task Id       | Step    |
+---+-----------+---------------+---------+
```

One merged table now holds the id/status/progress fields *and* the valid commands as rows (no separate "Commands:" block). The Steps table below it has exactly one row per checklist item (`step_index` order), status one of `pending`/`running`/`completed`/`failed` — sourced straight from each step's task record, not a separate completed/pending split. Step text is shortened to ~40 chars with a trailing `…` — full text is still in the raw state JSON printed after.

**Tasks and steps are now the same thing, 1:1** — every checklist item is seeded as a task the moment the plan is synced, so `Steps Total` in the top table always equals the row count in the Steps table and in `/ogre:task-list <job-id>`. If a checklist item shows `[x]` in the plan but its task status lagged behind, `sync_state_from_plan` force-flips the task to `passed` on every call — the plan file is the source of truth, so this can't drift for long. (`--all`-mode execute calls are the one exception: they create an extra, unlinked task not tied to a single step_index.)

For `--task <id>`, prints a **Task Summary** as one merged table (tasks never show Review/Execute — they don't have their own; `Stop task` only appears while status is `pending`/`running`):

```
+-------------+------------------------------------------+
| Task Id     | task-<uuid>                                |
| Job Id      | job-<uuid>  (resolved from the parent issue's state; "(unknown)" if that state file is gone)
| Issue       | <issue-slug>                               |
| Status      | pending|running|passed|failed|stopped      |
| Executor    | codex|claude (model)                       |
| Log         | <path>                                     |
| Session id  | <uuid>                     <- only once captured
| View status | ogre status --task <id>                    |
| Stop task   | ogre stop --task <id>      <- only if status is pending/running
+-------------+------------------------------------------+
```

No-arg `/ogre:status` (no issue/job/task) shows: Ogre runtime path, then the full **Job Summary** block (same fields/format as above) for every issue with state on disk, then the full **Task Summary** block for every pending/running task across all jobs. Same fields every time — no abbreviated one-liners.

Task status is auto-refreshed (reaped) from the background sentinel before display, so a `running` background task that finished since the last check will show as `passed`/`failed` here without needing another `execute` call.

**Show the Job/Task Summary block verbatim, in a code block, exactly as the helper printed it** — table, Steps Completed/Remaining lists, and Commands included. Do not paraphrase it into prose, do not compress multiple fields into one sentence, do not drop fields or rows (Plan path, job_id, Steps Completed/Remaining/Total, Session id, etc. must all show if the helper printed them). This has actually happened before — a session summarized the output into a single line like "Status: executing, 1/4 tasks" / "Current step: X" and silently dropped the Plan path, job_id, and every other field, which is exactly the failure mode to avoid. If you want to add commentary, add it *after* the verbatim block, don't replace the block with commentary.

Don't just dump the raw JSON instead of the summary either. The command list already reflects what's actually valid for the current status; don't suggest an action that's hidden (e.g. don't offer "execute" once completed, don't offer "stop" on a task that's already `passed`).
