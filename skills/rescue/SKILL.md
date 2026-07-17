---
name: rescue
description: Run a standalone hotfix/task with Claude or Codex, with no plan or issue involved - for a freeform ask like "fix error in login backend" or "implement forgot password page" where creating an Ogre plan first would be overkill.
---

# /ogre:rescue

Use this skill when the user wants something done right now - a quick fix, a small
standalone feature, a one-off task - and does NOT want to go through `/ogre:feature`
(issue -> plan -> review -> execute) first. There is no plan, no job, no issue file.
If the user is already mid-plan on an existing Ogre issue and wants to add scope to
it, that's `/ogre:add-blocker`, not this.

## Inputs

Accept the task description either as a plain positional argument or via `--statement`:

- `/ogre:rescue "fix error in login backend"`
- `/ogre:rescue --statement "implement forgot password page"`

Optional flags (same shape as `/ogre:execute`'s):

- `--rescuer claude|codex` - who does the work. Omitted: falls back to
  `defaults.rescuer` in `.ai/.ogre/config.json`, then `claude`. `rescuer` is its
  own config role, separate from `defaults.executor` - a project can pin a
  different CLI/model for one-off rescues than for plan execution.
- `--model MODEL`
- `--reasoning LEVEL` - reasoning effort for the rescuer (`claude -p` gets
  `--effort LEVEL`, `codex exec` gets `-c model_reasoning_effort=LEVEL`). Omit it to
  use the CLI's own default; Ogre never forces one.
- `--name slug` - override the auto-derived slug used for this rescue's log/tmp
  paths (`.ai/.ogre/{tmp,logs}/issue-rescue-<slug>/`). Without it, Ogre derives one
  from the first few words of the task text plus a short uuid suffix, same scheme
  as `/ogre:feature --statement`'s auto-name.
- `--main` - run inline in the current Claude Code session instead of spawning an
  isolated codex/claude session. Opt-in only, same as `/ogre:execute --main`; use it
  deliberately when the user explicitly wants the fix made in this conversation.
- `--background` - same isolation as default (new session) but detached/non-blocking.

## Default

- rescuer: `claude`
- isolation: **foreground, brand-new codex/claude session** - keeps main conversation
  context untouched, same model as `/ogre:execute`'s default. The calling session must
  wrap this in `run_in_background: true` (see Behavior below) so it doesn't block the
  conversation while it runs. Pass `--main` to do it inline instead, or `--background`
  to detach.

Codex rescuers run fully unsandboxed, same as every other codex spawn in this plugin
(`--dangerously-bypass-approvals-and-sandbox`) - see `/ogre:execute`'s note on this if
the user hasn't already been through that tradeoff this session.

## What makes this different from `/ogre:execute`

- **No plan file, no job, no `state/issue-<x>.json`.** `ogre rescue` never creates or
  reads a plan; it writes one runner file and spawns exactly one subprocess call, never
  a chain (no `--all`, no `--task`/`--step`, no `--retry`).
- **Still ledger-tracked, just by task id alone.** A rescue task IS recorded in the
  shared ledger (`.ai/.ogre/state/tasks.json`, `type: "rescue"`, `issue:
  "rescue-<slug>"`) so it shows up like any other spawn - but there's no job/issue
  summary to go with it. Track and manage it purely via its task id:
  - `${CLAUDE_PLUGIN_ROOT}/scripts/ogre status --task <id>`
  - `${CLAUDE_PLUGIN_ROOT}/scripts/ogre stop --task <id>`
  `--main` runs (no subprocess spawned) create no task id at all - there's nothing
  to track since this session is the one doing the work, right now.

## Behavior

1. Run:
   - `${CLAUDE_PLUGIN_ROOT}/scripts/ogre rescue "<task>" [flags]`
2. Without `--main`, this call actually spawns codex/claude in a new isolated session -
   same as `/ogre:execute`'s isolation model.
   - **No `--background` (default)**: the `ogre rescue` call itself blocks at the shell
     level until the subprocess finishes. Never invoke it as a plain synchronous Bash
     call - always wrap it in **one single Bash tool call with `run_in_background:
     true`** around that same command, even though it's a single quick task. This keeps
     the main conversation free the whole run and surfaces it as a trackable/clickable
     background job in the harness's own job list instead of hard-blocking the turn.
     The harness delivers one completion notification straight to this session the
     moment the command exits - read the printed `Task <id> finished: passed|failed`
     from that output and report it. Do not poll for this case; the notification
     itself is the signal.
   - **`--background`**: the `ogre rescue ... --background` call returns almost
     immediately after starting the detached subprocess, so it doesn't itself need the
     `run_in_background: true` wrapper - but you do then need to poll for completion,
     since ogre self-detaches with nothing left for the harness to hold onto. Report
     the task id, then poll it yourself the same way
     `/ogre:execute --background`'s skill does - **never spawn an `Agent` (fork or
     otherwise) to supervise this.** One single Bash tool call with
     `run_in_background: true` around a real shell loop, e.g.:
     `while :; do ${CLAUDE_PLUGIN_ROOT}/scripts/ogre status --task <id> | grep -qE '^\| Status +\| (passed|failed) ' && break; sleep 15; done`.
     The harness delivers a completion notification straight to this session the
     moment that loop exits - read the final `ogre status --task <id>` output and
     report pass/fail then. Never poll across separate assistant turns.
3. If `--main` was passed: the runner file (`.ai/.ogre/tmp/issue-rescue-<slug>/rescue-runner.md`)
   is written but nothing is spawned - read it and do the task yourself, in this
   session, right now. There is no task id to close out afterward in this mode.
4. Otherwise, nothing further to execute yourself - the isolated session already did
   the work and self-reported via `ogre task-complete`.

## Rules

- One freeform task, one subprocess call - not a chain, not a multi-step plan.
- Do not invent files, methods, routes, tables, columns, config keys, or APIs.
- Do not add unrelated refactors or change behavior outside what was asked.
- Do not add packages unless the task clearly needs them.
- Preserve existing project style.
- Prefer the smallest safe change that fully addresses the task.
- Stop if validation fails. An already-dirty working tree at start (e.g. the user's
  own hand-edit/hotfix alongside this task) is NOT itself a reason to stop - leave
  those changes as-is, don't attribute them to this task, just mention them briefly
  in the report. Only stop over it if a file looks genuinely alarming (a
  credential/secret, a half-finished destructive edit), not for an ordinary
  incidental change.
- Stays on whatever branch is currently checked out. Rescue does not create or switch
  git branches on its own - if the user wants this done on a separate branch, they
  branch/stash themselves first.

## After Execution (only when a task id was created, i.e. no `--main`)

Report:

- Task completed (or failed) and its task id.
- Files changed.
- Reason for each changed file.
- Validation commands run.
- Validation result.
