# Isolated + backgroundable planning/review (feature, review-plan, add-blocker)

## Problem

`ogre feature`, `ogre review-plan`, and `ogre add-blocker` only have one mode
today: the *current* Claude Code session does the planning/review work
directly (reads the runner prompt written by `scripts/ogre`, then does the
actual reasoning/file-reads/writes itself). This is architecturally the
equivalent of what `execute --main` means - no isolation, and no way to run
it in the background. Two consequences:

- The plugin's own pitch ("main session stays clean") is false for planning -
  every `/ogre:feature`/`/ogre:review-plan` call spends main-session context,
  same as if you'd asked Claude to do it with no plugin at all.
- No way to kick off a plan/review and keep using the main session for
  something else while it runs - you either wait, or you don't get isolation.

`execute` already solves both problems for execution steps via an isolated
subprocess spawn (`claude -p` / `codex exec`), with three modes: default
(isolated + foreground + blocking), `--main` (opt out of isolation, inline in
current session), `--background` (isolated + detached).

## Decision

Match `execute`'s three-mode model exactly, for all three commands:

- **Default**: spawn an isolated `claude -p`/`codex exec` subprocess (new,
  empty context - only sees the runner prompt file), block until it finishes.
  Main session's context untouched.
- **`--main`**: today's current behavior, preserved as an explicit opt-in -
  current session does the planning/review itself, inline.
- **`--background`**: same isolated spawn as default, detached
  (disown'd, own process group) - returns immediately.

This is a deliberate behavior change on the default for `feature`/
`review-plan`/`add-blocker` (today's only behavior moves behind `--main`).

## Architecture

Reuse `execute`'s existing spawn machinery rather than duplicating it:

- `run_link_foreground` / `run_link_background_body` (scripts/ogre) already
  know how to spawn `claude -p --permission-mode bypassPermissions` or
  `codex exec --dangerously-bypass-approvals-and-sandbox`, stream to a log,
  write an exit sentinel, and (background only) disown into their own
  process group. Generalize these to accept any runner file, not just an
  execute-step runner - they don't need to change signature, just be called
  from `cmd_feature`/`cmd_review_plan`/`cmd_add_blocker` too.
- `task_create`/`task_update`/`task_get`/`reap_task`/`reap_all_tasks`
  (scripts/ogre:209-438) are already generic over the ledger's `type` field
  (no schema change needed) and already reap any `status=running` task by
  exit-sentinel-or-dead-pid, regardless of type. New `type` values: `plan`
  (feature), `review` (review-plan), `replan` (add-blocker).
- Completion signal: the spawned planner/reviewer's runner prompt instructs
  it to call `ogre task-complete <id> --status passed|failed` as its last
  step, same fail-closed pattern `execute` uses (a run that exits 0 without
  calling task-complete counts as failed, not silently passed - mirrors the
  existing "execute foreground fails closed when codex exits 0 but never
  calls task-complete" test). For `passed`, additionally require the
  plan/review file to actually exist at the expected path - a model can't
  self-report success without having produced the file.

## Self-heal

`maybe_resume_stalled_chain` (scripts/ogre:451+) is specific to `--all`
execution chains (`mode == "all"`, `pending_steps` semantics) - not reusable
as-is for a one-shot plan/review task. New sibling function,
`maybe_resume_stalled_plan(issue)`, called from the same `ogre status` path
right after `reap_all_tasks`/`sync_state_from_plan`:

- Look at the most recent ledger task for this issue whose `type` is
  `plan`/`review`/`replan` and `mode == "background"`.
- If its status was reaped to `failed` (dead pid, no exit sentinel - the
  existing `reap_task` dead-process branch already produces this) and the
  expected output file (plan path, or review path) still doesn't exist,
  relaunch the same planner/reviewer call with the same executor/model/
  reasoning, same as the original invocation.
- Idempotent the same way the execute version is: the relaunch's own new
  task shows up "running" with a live pid immediately, so a status call
  moments later sees that and does nothing.

## Flags

Add `--main` and `--background` to `feature`, `review-plan`, and
`add-blocker`, matching `execute`'s existing flag names/semantics exactly
(no new flag vocabulary). `--all`, `--retry`, `--task`, `--step`,
`--max-steps` stay execute-only - none of them have a meaning for a single
one-shot planning/review call.

## Skill changes

`skills/feature/SKILL.md`, `skills/review-plan/SKILL.md`,
`skills/add-blocker/SKILL.md` currently instruct the driving session to do
the planning/review work itself (feature step 4: "Create the plan exactly as
requested by that runner"). Rewritten so that, by default, the skill:

1. Runs the ogre helper as today.
2. Helper spawns the isolated subprocess itself (foreground: blocks until
   done; background: returns immediately with a task id).
3. Skill reads the *result* (plan file / review file / task status) rather
   than producing it - own tool calls only happen when `--main` is passed,
   preserving today's exact step-4/5 behavior for that opt-in path.

Job Summary verbatim-output requirements (feature SKILL.md step 2/6) are
unaffected - same summary block, just reflecting isolated-mode status
fields (task id, running/passed/failed) when not `--main`.

## Testing

- `tests/cmd_feature.bats`, `tests/cmd_review_plan.bats`,
  `tests/cmd_add_blocker.bats`: default now spawns (foreground blocking),
  `--main` preserves every existing inline-mode test as-is, `--background`
  gets new coverage mirroring `cmd_execute.bats`'s background tests
  (detached pid, own process group, self-heal on a killed driver, fail-closed
  on exit-0-without-task-complete).
- Full suite (`bats tests/`) before considering done, since this touches
  shared helpers (`task_create`, `reap_task`, `maybe_resume_stalled_chain`
  neighbor).

## Out of scope

- `--all`/chaining concepts for planning (no equivalent - one-shot call).
- Knowledge-base integration for planning (execute-only concept, unchanged).
- Changing `[BROWSER-CHECK]`/browser-MCP handling (execute-only).
