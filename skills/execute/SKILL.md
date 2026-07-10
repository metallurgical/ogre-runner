---
name: execute
description: Execute the next incomplete checklist item from an approved Ogre plan using Claude or Codex, one step at a time.
---

# /ogre:execute

Use this skill after the plan is reviewed and approved.

## Inputs

Accept:

- Issue number, e.g. `107`
- Plan name, e.g. `issue-107`
- Plan path, e.g. `.ai/.ogre/plans/issue-107.md`
- `--job <job-id>` instead of any of the above, e.g. `/ogre:execute --job job-6d7715e4-...`

Optional flags:

- `--executor codex|claude`
- `--model MODEL`
- `--reasoning LEVEL` — reasoning effort for the executor (`claude -p` gets `--effort LEVEL`, `codex exec` gets `-c model_reasoning_effort=LEVEL`). Omit it to use the CLI's own default; Ogre never forces one.
- `--task <task-id>` — target one specific seeded step out of order
- `--step <n>` — target step N (1-based) out of order
- `--retry` — re-run the lowest `failed` step in a fresh session. The failed attempt's exit code and log tail are injected into the runner prompt so the new session diagnoses the failure instead of repeating the same approach blindly. Prefer this over asking the user to explain what went wrong. Not combinable with `--all`.
- `--all` — chain through every remaining step automatically. Each session hands off to a fresh one (cleanly, via `task-complete --status passed`, not as an error) at the `--max-steps` cap or once it estimates ~50%+ of its context used, whichever comes first — so simple steps can share one session while a heavier one splits off on its own. Works with `--main`/`--background` too. Browser-check steps run isolated in the chain when the executor has a browser MCP; only if none is detected does the chain stop on one — see "`[BROWSER-CHECK]` Steps" below, and handle it yourself rather than relaying the error.
- `--max-steps N` — hard cap on checklist items per chained `--all` session (default: 3). Self-assessed context estimates are unreliable, so the cap is the authoritative limit.
- `--fresh`
- `--resume`
- `--main` — run inline in the current Claude Code session instead of spawning a new isolated codex/claude session. Opt-in only: Ogre never forces it, except as the automatic fallback for a `[BROWSER-CHECK]` step when no browser MCP is detected (and it says so). Use it deliberately only when the user explicitly wants the edit made in this conversation — it defeats the whole point of Ogre (keeping the main context clean) if used as a habit.
- `--mcp-config PATH` — browser MCP config handed to the spawned `claude` session so `[BROWSER-CHECK]` steps run isolated instead of falling back to `--main`. Also settable persistently as `"browser_mcp"` in `.ai/.ogre/config.json`. **Applies to the `claude` executor only.** A headless `codex exec` spawn cannot drive a browser (Codex's browser surface is its desktop-app in-app browser, which has no session in a spawned exec), so with `--executor codex` a `[BROWSER-CHECK]` step always falls back to `--main` — verified, not a config gap.
- `--background` — same isolation as default (new session) but detached/non-blocking
- `--yes` — required to proceed non-interactively (e.g. from this agent) when the target step/job was previously `stopped`, or when jumping to an out-of-order step whose earlier steps aren't `passed` yet. Only pass this after the user has explicitly confirmed.

## Default

Default behavior is the isolated mode Ogre exists for:

- executor: `codex`
- target: the lowest-numbered step still `pending` (no `--task`/`--step` needed for normal sequential use)
- freshness: `fresh`
- isolation: **foreground, brand-new codex/claude session** — this actually runs the executor now (no `--run` needed anymore; that flag still works as a harmless no-op alias for this default). Main conversation context is untouched.
- Pass `--main` to instead do the edit inline in this session (no subprocess), or `--background` to run the new session detached/non-blocking.
- Pass `--all` to chain through every remaining step automatically instead of just the next one — combine with `--main`/`--background` as needed. Ogre keeps spawning fresh sessions for you as long as each one reports `passed` and steps remain; it stops the chain on the first `failed` or once nothing is left.

## Job / Task Tracking

Every feature is a **job** (1:1 with the issue, id `job-<uuid>`, stored as `job_id` in `.ai/.ogre/state/issue-<issue>.json`). Every checklist step in the approved plan is seeded as a **task** the moment the plan is synced (id `task-<uuid>`, recorded in the shared ledger `.ai/.ogre/state/tasks.json`, `step`/`step_index` fields hold the checklist text and its 1-based position) — this happens automatically on `status`/`task-list`/`execute`, not only when `execute` runs. So `ogre task-list <job-id>` shows every step from planning onward, `pending` for ones never attempted, not just the ones someone has already run. Task status is one of: `pending`, `running`, `passed`, `failed`, `stopped`.

`ogre execute` no longer creates a fresh task per invocation (except `--all`, see below) — it finds the matching seeded task and updates it in place. `--task <id>`/`--step <n>` let you jump to any step out of order; without them it takes the lowest pending `step_index`. `sync_state_from_plan` also reconciles both directions every time it runs: if a checklist item shows `[x]` in the plan but its task isn't `passed` yet, the task is force-flipped to `passed` — the plan file is the source of truth for "done," so ledger and checklist can never drift apart for long. `--all` is the one exception: it still creates an ad-hoc, unlinked task covering every remaining step in one runner call, for cases where you deliberately want the old bulk behavior.

**`--run`/`--background` auto-mark the task `passed`/`failed` when the subprocess exits.** Every other path — a human running the printed `codex exec` command by hand, a `/codex:rescue` handoff, or (most common) the live Claude Code session executing the checklist item directly in this conversation — does NOT touch the ledger on its own. In all of those cases, the executing agent must run `scripts/ogre task-complete <task-id> --status passed|failed` as the last step (the exact command and task id are embedded in the generated runner file and in `templates/execution-handoff.md`'s "After Editing" section). Skipping it leaves the task stuck `pending` forever even though the real work is done — do not skip it.

- `scripts/ogre status --task <id>` — show one task's full record (status, pid, exit_code, timestamps, log path).
- `scripts/ogre status --tasks [issue]` — list all tasks, optionally filtered to one issue.
- `scripts/ogre status --job <job-id>` — same as `ogre status <issue>`, addressed by job id instead of issue slug.
- `scripts/ogre status <issue>` — also lists tasks for that issue below the state json.
- `scripts/ogre stop <issue>` / `scripts/ogre stop --job <job-id>` — stops the whole job: kills any `running` task's pid and marks all pending/running tasks for that issue `stopped`.
- `scripts/ogre stop --task <id>` — stops just that one task (kills its pid if running). Sibling tasks and the job/issue state are untouched. Use this to kill one misbehaving background attempt without aborting the whole feature.

Use this when the user asks "what's still running", "did step N pass or fail", "show me task \<id\>", or "stop just that one background run".

## Native LLM Session Resume

Every `--run`/`--background` task also records the underlying CLI's own session id in the task's `session_id` field, so the user can drop into that exact session in their own terminal afterward:

- `--executor claude`: Ogre pre-generates a uuid and passes it as `claude -p --session-id <uuid> ...`, so it's known and printed immediately. Resume with `claude --resume <session_id>`.
- `--executor codex`: Codex prints its own `session id: <uuid>` in its startup banner; Ogre parses it out of the task's log after the run (foreground) or when the background task is reaped. Resume with `codex resume <session_id>` (TUI) or `codex exec resume <session_id>` (CLI).

Always report `session_id` and the exact resume command back to the user after a task finishes (execute output shows it; `ogre status --task <id>` shows it too, once captured). For background codex tasks, it may be `null` until the process finishes — check status again after.

## `[BROWSER-CHECK]` Steps

A step tagged `[BROWSER-CHECK]` needs a real rendered browser to verify (visual layout, interactive behavior). **By default these now run ISOLATED like any other step** — Ogre keeps main context clean whenever it can. What happens depends on whether the executor has a browser MCP:

- **Browser MCP available** — `claude` executor only, with a Playwright/browser MCP configured (ambient project/user MCP shown in `claude mcp list`, `browser_mcp` in `.ai/.ogre/config.json`, or `--mcp-config PATH`): the spawned `claude -p` session verifies the step with its own browser tools (verified: it inherits the ambient MCP and drives a real headless browser). Nothing special for you to do — single steps and `--all` chains run straight through, main context untouched. This is the goal state; prefer configuring a browser MCP so browser-check never touches this session. **Note:** `--executor codex` can never reach this branch — a headless `codex exec` has no browser session — so codex browser-check always takes the fallback below.
- **No browser MCP detected**: Ogre falls back so the step still completes automatically (no manual retrigger):
  1. **Single-step**: `ogre execute` auto-switches that one step to `--main` and prints a NOTE saying why. Just do the check as instructed in this session, then `task-complete`.
  2. **`--all` foreground (no `--background`)**: the chain stops at the browser-check with a message. This is a mechanical continuation, not a question for the user — resolve it in the same turn: run `scripts/ogre execute <issue> --main`, do that one step's real browser check yourself, `scripts/ogre task-complete <task-id> --status passed|failed`, then re-run `scripts/ogre execute <issue> --all` (same executor/model/reasoning) to resume. Loop until the chain reports `completed`/`failed`/nothing left.
  3. **`--all --background`**: first grep the plan's remaining unchecked items for `[BROWSER-CHECK]`. None tagged → just kick off `--background` and stop; nothing will pause. At least one tagged → the detached run can't call back into this session, so the moment you launch it, launch a fork (`Agent`, `subagent_type: "fork"`) to supervise:
     - Poll with **one single Bash tool call** running a real shell `while`+`sleep` loop (e.g. `while :; do scripts/ogre status <issue>; sleep 20; done` breaking on `completed`/`stopped`/`failed`/`[BROWSER-CHECK]`). Never poll across separate assistant turns — one grounded shell loop only.
     - Never report a step number/`current_step`/count from memory — always quote the most recent `ogre status` output.
     - Whenever `current_step` contains `[BROWSER-CHECK]` and the job isn't `completed`/`stopped`, resolve it like case 2 (`--main`, real check, `task-complete`, resume with `--all --background` preserving flags).
     - Loop until `completed`/`stopped`/`failed` for a real reason, then return one final summary from the last real status read.

The cleanest fix for all of this is to give the executor a browser MCP once — then every case above collapses to "runs isolated, nothing to supervise."

   The fork's completion generates a `task-notification`, which reliably wakes a fresh turn in this session when it's done - so nothing is missed even with zero other interaction in between. Report that summary to the user when it arrives.

   Do **not** use a fork for cases 1-2 above - those already resolve synchronously within the same turn, so forking would only inherit the whole conversation for no benefit.

## Behavior

1. Run:
   - `scripts/ogre execute <issue-or-plan> [flags]`
   - **If this exits non-zero because the next step is `[BROWSER-CHECK]`** (only possible with `--all`, see "Auto-Resolving `[BROWSER-CHECK]` Pauses" above): that's a mechanical continuation, not a confirmation case - handle it per that section, do not stop and ask the user.
   - **If it exits non-zero for any other reason, or prints `ERROR: Refusing to proceed non-interactively without confirmation...`**: STOP HERE. Do not read the runner file, do not edit any files, even if a runner file already exists from a prior attempt (it may be stale). Relay the exact warning to the user (e.g. "step/job was previously stopped, may depend on unfinished earlier steps") and ask whether to proceed. Only re-run with `--yes` after the user explicitly confirms.
   - **Without `--main`, this call blocks and actually runs codex/claude in a new isolated session** — wait for it to finish; don't do the edit yourself in parallel.
2. Read the generated runner (mainly relevant when `--main` was used, or to review what the isolated session was told to do):
   - `.ai/.ogre/tmp/issue-<number>/run-next.md`
3. If `--main` was NOT passed (default): the command above already invoked codex/claude in its own session and reported pass/fail — nothing further to execute yourself.
4. If `--main` was passed: execute only the target checklist item named in the runner (usually the next pending one, or whichever `--task`/`--step` picked) yourself, in this current Claude Code session, then run `task-complete` per the "After Execution" section below.
5. Stop after that one checklist item unless `--all` is explicitly requested.

## Rules

- Execute one checklist item only.
- Inspect relevant files before editing.
- Do not implement `NEEDS INSPECTION` items until verified.
- Do not invent files, methods, routes, tables, columns, config keys, or APIs.
- Do not add unrelated refactors.
- Do not change behavior outside the issue scope.
- Do not add packages unless the plan explicitly says so.
- Preserve existing project style.
- Prefer the smallest safe change.
- Stop if validation fails.

## After Execution

Before reporting anything, mandatory, unless this run used `--run`/`--background` (those already do it): run `scripts/ogre task-complete <task-id> --status passed|failed` for the task id `ogre execute` printed. Do this yourself — don't ask the user to run it, don't skip it because the work is "obviously done." This is the step that keeps `ogre status`/`ogre task-list` accurate; the user should never need to know it exists.

Add `--notes "..."` to that command whenever the step surfaced something the next step's fresh session must know — an actual signature/route/schema that differs from the plan, a deviation made, a gotcha. One or two sentences. Notes are injected into every later runner prompt for the issue; they are the only way mid-step knowledge survives the session that discovered it.

Then report:

- Checklist item completed.
- Files changed.
- Reason for each changed file.
- Validation commands run.
- Validation result.
- Remaining `NEEDS INSPECTION` items.
