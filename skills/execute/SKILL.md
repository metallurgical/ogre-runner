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

- `--executor codex|claude` — **every codex spawn runs fully unsandboxed** (`--dangerously-bypass-approvals-and-sandbox`: no filesystem/shell/network confinement, no approval prompts), unconditional, not just `[BROWSER-CHECK]` steps. There is no opt-in flag for this anymore (`--codex-unsandboxed-browser-check`/`codex_unsandboxed_browser_check` are retired) — it's simply how codex always runs in Ogre now, because codex's own sandbox otherwise blocks things Ogre needs outright (real registry/network access, spawning a real browser). Ogre is a dev-only tool as a result. `claude` isolates fine by default (`--permission-mode bypassPermissions`) and needs no such tradeoff. If you see the `WARNING: codex steps run UNSANDBOXED` log line, that is expected on every codex step now, not a bug or a sign something was misconfigured — do not stop the chain over it.
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
- `--mcp-config PATH` — browser MCP config-file handed to the spawned `claude` session so `[BROWSER-CHECK]` steps run isolated. Also settable persistently as `"browser_mcp"` in `.ai/.ogre/config.json`. **`claude`-only.** Codex gets its browser MCP from its own `~/.codex/config.toml` `mcp_servers` instead — codex `[BROWSER-CHECK]` also runs isolated when an external Playwright/Puppeteer MCP is in `codex mcp list` (Ogre's codex runner forces the external MCP over Codex's desktop in-app browser, which can't run headless — verified). No such MCP → `--main` fallback.
- `--background` — same isolation as default (new session) but detached/non-blocking
- `--yes` — required to proceed non-interactively (e.g. from this agent) when the target step/job was previously `stopped`, or when jumping to an out-of-order step whose earlier steps aren't `passed` yet. Only pass this after the user has explicitly confirmed.
- `--live` — opt-in, off by default. Runs the executor with `--json` (codex) or `--output-format stream-json --verbose` (claude) instead of plain text, writing raw JSONL to the log path. Only use this when the user explicitly wants to watch the executor's activity live (commands it runs, files it touches) inside this same Claude Code conversation — it changes nothing about the edit itself, purely a visibility option. Passing `--live` alone does nothing beyond changing the log format; see `/ogre:rescue`'s "Watching a `--live` rescue live" section for the Monitor+jq recipe that actually surfaces it as it happens (same recipe applies here, just against `execute`'s own log path).
  - **Combined with `--all`**: every hand-off link normally rotates to a brand-new log file, which would leave a Monitor armed on link 1 stale the moment link 2 starts. `--live --all` together avoids that automatically — every link appends to the *same* log path for the life of the chain (announced as `Live + --all: every hand-off link appends to this same log path...` right after launch) instead of rotating. Arm Monitor on that one path once, right after launch — it keeps delivering events across every hand-off with no re-arming, no polling for a new path. This is the only combination where the log path is stable across a chain; `--live` without `--all` (single link, nothing to rotate) and `--all` without `--live` (per-link rotation, plain text) are unaffected. Once the whole chain's own completion signal fires (the backgrounded/polled `execute --all` call itself finishes or blocks), `TaskStop` that Monitor right away — same reasoning as rescue's: `tail -f` never exits on its own, so it otherwise sits open in the TUI until timeout or a manual `(x)`.

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

**`--run`/`--background` auto-mark the task `passed`/`failed` when the subprocess exits.** Every other path — a human running the printed `codex exec` command by hand, a `/codex:rescue` handoff, or (most common) the live Claude Code session executing the checklist item directly in this conversation — does NOT touch the ledger on its own. In all of those cases, the executing agent must run `${CLAUDE_PLUGIN_ROOT}/scripts/ogre task-complete <task-id> --status passed|failed` as the last step (the exact command and task id are embedded in the generated runner file and in `templates/execution-handoff.md`'s "After Editing" section). Skipping it leaves the task stuck `pending` forever even though the real work is done — do not skip it.

- `${CLAUDE_PLUGIN_ROOT}/scripts/ogre status --task <id>` — show one task's full record (status, pid, exit_code, timestamps, log path).
- `${CLAUDE_PLUGIN_ROOT}/scripts/ogre status --tasks [issue]` — list all tasks, optionally filtered to one issue.
- `${CLAUDE_PLUGIN_ROOT}/scripts/ogre status --job <job-id>` — same as `ogre status <issue>`, addressed by job id instead of issue slug.
- `${CLAUDE_PLUGIN_ROOT}/scripts/ogre status <issue>` — also lists tasks for that issue below the state json.
- `${CLAUDE_PLUGIN_ROOT}/scripts/ogre stop <issue>` / `${CLAUDE_PLUGIN_ROOT}/scripts/ogre stop --job <job-id>` — stops the whole job: kills any `running` task's pid and marks all pending/running tasks for that issue `stopped`.
- `${CLAUDE_PLUGIN_ROOT}/scripts/ogre stop --task <id>` — stops just that one task (kills its pid if running). Sibling tasks and the job/issue state are untouched. Use this to kill one misbehaving background attempt without aborting the whole feature.

Use this when the user asks "what's still running", "did step N pass or fail", "show me task \<id\>", or "stop just that one background run".

## Native LLM Session Resume

Every `--run`/`--background` task also records the underlying CLI's own session id in the task's `session_id` field, so the user can drop into that exact session in their own terminal afterward:

- `--executor claude`: Ogre pre-generates a uuid and passes it as `claude -p --session-id <uuid> ...`, so it's known and printed immediately. Resume with `claude --resume <session_id>`.
- `--executor codex`: Codex prints its own `session id: <uuid>` in its startup banner; Ogre parses it out of the task's log after the run (foreground) or when the background task is reaped. Resume with `codex resume <session_id>` (TUI) or `codex exec resume <session_id>` (CLI).

Always report `session_id` and the exact resume command back to the user after a task finishes (execute output shows it; `ogre status --task <id>` shows it too, once captured). For background codex tasks, it may be `null` until the process finishes — check status again after.

## `[BROWSER-CHECK]` Steps

Whether a plan has any `[BROWSER-CHECK]` steps at all is decided at planning time, not execution time: `ogre feature` only tags steps this way when `--browser-check` was passed (see `/ogre:feature`). By default a plan has none, and the user is expected to verify the feature themselves — nothing below applies. Everything in this section only matters for a plan that opted in.

A step tagged `[BROWSER-CHECK]` needs a real rendered browser to verify (visual layout, interactive behavior). **By default these now run ISOLATED like any other step** — Ogre keeps main context clean whenever it can. What happens depends on whether the executor has a browser MCP:

- **Browser MCP available** — `claude` executor: with a Playwright/browser MCP configured (ambient project/user MCP shown in `claude mcp list`, `browser_mcp` in `.ai/.ogre/config.json`, or `--mcp-config PATH`), the spawned `claude -p` session verifies the step with its own browser tools (verified: it inherits the ambient MCP and drives a real headless browser). Nothing special for you to do — single steps and `--all` chains run straight through, main context untouched. This is the goal state; prefer configuring a browser MCP so browser-check never touches this session.
  - `codex` executor: now the same shape as `claude` — since every codex spawn already runs fully unsandboxed (see the `--executor` note above), a confirmed playwright/puppeteer entry in `codex mcp list` is sufficient on its own. No opt-in flag needed or checked anymore. Without a browser MCP present, codex `[BROWSER-CHECK]` still falls back to `--main`, correctly, every single time — that is expected behavior, not flakiness.
- **No browser MCP detected**: Ogre falls back so the step still completes automatically (no manual retrigger):
  1. **Single-step**: `ogre execute` auto-switches that one step to `--main` and prints a NOTE saying why. Just do the check as instructed in this session, then `task-complete`.
  2. **`--all` foreground (no `--background`)**: the chain stops at the browser-check with a message. This is a mechanical continuation, not a question for the user — resolve it in the same turn: run `${CLAUDE_PLUGIN_ROOT}/scripts/ogre execute <issue> --main`, do that one step's real browser check yourself, `${CLAUDE_PLUGIN_ROOT}/scripts/ogre task-complete <task-id> --status passed|failed`, then re-run `${CLAUDE_PLUGIN_ROOT}/scripts/ogre execute <issue> --all` (same executor/model/reasoning) to resume. Loop until the chain reports `completed`/`failed`/nothing left.
  3. **`--all --background`**: first decide, at launch time, whether this run is **isolated-capable** for `[BROWSER-CHECK]` — `claude` executor with a browser MCP actually configured (ambient `claude mcp list`, `browser_mcp` in config, or `--mcp-config`), or `codex` executor with a confirmed playwright/puppeteer entry in `codex mcp list` (check it yourself — codex is always unsandboxed now, so the MCP presence alone is the only signal, no flag to check). This is a property of the whole run, decided once, not something to re-derive per step.
     - **Isolated-capable**: grep for `[BROWSER-CHECK]` doesn't matter — the background driver handles every step, browser-check or not, the exact same way, fully inside itself. **Do not treat `current_step` containing `[BROWSER-CHECK]` as a signal to intervene.** That's the normal, expected state while the driver is actively (successfully) working the step in isolation — jumping in with a manual `--main` at that moment doesn't rescue anything, it races and duplicates work the background chain is already doing correctly. This is the actual cause of "worked before, now it doesn't" reports: the driver silently finishes the step fine while you're mid-poll, or you catch it mid-flight and stomp on it — pure timing luck, not the chain being broken. Poll exactly like a chain with no browser-check steps at all: wait for `completed`/`stopped`/`failed`, nothing else.
     - **Not isolated-capable** (no MCP found): grep the plan's remaining unchecked items for `[BROWSER-CHECK]`. None tagged → just kick off `--background` and stop; nothing will pause. At least one tagged → the detached run can't call back into this session on its own, so the moment you launch it, start a poll loop yourself in this same session. Whenever `current_step` contains `[BROWSER-CHECK]` and the job isn't `completed`/`stopped`, resolve it like case 2 (`--main`, real check, `task-complete`, resume with `--all --background` preserving flags), then start the poll loop again the same way.
     - Either way: **never spawn an `Agent` (fork or otherwise) to supervise this** — the background driver is already self-contained (drives every remaining step, writes to the ledger, exits on its own), and a supervising subagent adds no value while a `fork` specifically always runs on the Claude model regardless of which executor (`codex`/`claude`) the actual steps use, silently burning Claude quota for pure babysitting. Run **one single Bash tool call with `run_in_background: true`** around a real shell `while`+`sleep` loop (e.g. `while :; do ${CLAUDE_PLUGIN_ROOT}/scripts/ogre status <issue>; sleep 20; done` breaking on the condition that actually applies per the branch above). The harness delivers a completion notification straight to this same session the moment the loop exits — that's the entire mechanism, no subagent needed to relay it. Never poll across separate assistant turns, and never hand the polling off to a fork/subagent.
     - Never report a step number/`current_step`/count from memory — always quote the most recent `ogre status` output.
     - Loop until `completed`/`stopped`/`failed` for a real reason, then return one final summary from the last real status read. **If `--live` was used and a Monitor is armed on the log path, `TaskStop` it right here, before that final summary** — `tail -f` never exits on its own, so it stays open in the TUI until timeout or a manual `(x)` if you don't.

The cleanest fix for all of this is to give the executor a browser MCP once — then every case above collapses to "runs isolated, nothing to poll for."

`ogre status <issue>` also self-heals a chain whose `--background` driver died outright (observed in the wild: no crash trace, process just gone, pending steps left with nothing running) — it detects a dead pid on the last `mode=all` chain task with steps still pending and auto-relaunches `--all --background` with the same executor/model/reasoning/mcp-config (whichever of those were set on the original invocation, read back off that task's own ledger record). This means the poll loop above (which already calls `ogre status`) recovers from that case for free; no separate dead-process detection needed.

   Do **not** spawn any subagent for any of cases 1-3 above — cases 1-2 already resolve synchronously within the same turn, and case 3's backgrounded poll loop already delivers its own completion notification straight to this session. A subagent would only inherit the whole conversation (or, for a fork, burn Claude quota) for zero added benefit.

### Auto-Fix Cap Exceeded

When `[BROWSER-CHECK]` keeps failing and the ad-hoc `[AUTO-FIX]` attempts hit `auto_fix_cap`, `ogre execute` marks the task `failed` and exits non-zero with `[BROWSER-CHECK] still failing after N ad-hoc [AUTO-FIX] attempts`. This is **not** an automatic "stop and ask the user" case like line 98's generic rule — decide it yourself:

1. Read the last verification failure (printed, and in the task's `notes`) and the plan's `[AUTO-FIX]` entries to see what was actually tried.
2. Judge scope: is the failure caused by (or squarely inside) what this plan's steps are building, or is it a pre-existing, site-wide condition unrelated to the feature (e.g. a global asset like `favicon.ico` that 404s on every page, not just the ones this plan touches)?
   - **Pre-existing / out-of-scope**: resolve it yourself, don't ask the user to pick between options:
     - Prefer the smallest fix that actually clears the check. If that means creating a small, self-contained file the site/feature is genuinely missing (e.g. a real `favicon.ico` at the site root so the browser's default request stops 404ing), create it — a minimal, real, working file, not a fake stub that only silences the checker.
     - Revert any half-finished edits the failed `[AUTO-FIX]` attempts left behind that are outside the plan's intended file scope (e.g. a stray `<link>` edit) if they didn't actually fix it.
     - Mark the original step `passed` via `task-complete --status passed --notes "..."` naming exactly what was created/changed to resolve it, that it's a minimal out-of-scope fix, and that the underlying condition predates this plan.
     - Report to the user afterward what file(s) you created or reverted, that they're minimal/temporary in nature, and that the blast radius is low (e.g. "created a real `favicon.ico`, one small binary file at the project root, doesn't touch any of the 12 pages' existing icon links"). Tell, don't ask.
   - **In-scope**: the plan's own change caused it, or fixing it is what the step exists to verify. Still don't open a multi-option menu for the user to pick a fix. Diagnose it yourself from the failure log and the plan's intent, apply the smallest correct fix, and re-verify. Only actually stop and ask when the fix requires a real judgment call outside what the plan already specifies — a genuine product/business decision (which of two valid UX behaviors is wanted), or an irreversible/destructive action (deleting data, dropping a migration, overwriting something not created by this plan). If you can't safely determine the fix and it's neither of those, mark the step `failed` with a note giving the concrete diagnosis and what you tried — report the failure plainly, that's not the same thing as pausing to ask which option to pick.
3. This same distinction — decide and act vs. stop-and-ask only for irreversible/ambiguous calls — applies to *any* new error that surfaces while resolving one of these, not just the first one. Don't ratchet back to asking just because a second or third error showed up; keep diagnosing and fixing within the cap, and only escalate per the actual escalation criteria above.
4. Whatever the path, never leave a stray out-of-scope edit (like a partial favicon link change or an orphaned asset file) sitting in the working tree just because the cap was hit — clean it up as part of resolving the step, in the same commit/session, not as a follow-up ask.

## Behavior

1. Run:
   - `${CLAUDE_PLUGIN_ROOT}/scripts/ogre execute <issue-or-plan> [flags]`
   - **If this exits non-zero because the next step is `[BROWSER-CHECK]`** (only possible with `--all`, see "Auto-Resolving `[BROWSER-CHECK]` Pauses" above): that's a mechanical continuation, not a confirmation case - handle it per that section, do not stop and ask the user.
   - **If this exits non-zero because the AUTO-FIX cap was exceeded** (`[BROWSER-CHECK] still failing after N ad-hoc [AUTO-FIX] attempts`): not a confirmation case either - handle it per "Auto-Fix Cap Exceeded" above, do not stop and ask the user.
   - **If it exits non-zero for any other reason, or prints `ERROR: Refusing to proceed non-interactively without confirmation...`**: STOP HERE. Do not read the runner file, do not edit any files, even if a runner file already exists from a prior attempt (it may be stale). Relay the exact warning to the user (e.g. "step/job was previously stopped, may depend on unfinished earlier steps") and ask whether to proceed. Only re-run with `--yes` after the user explicitly confirms.
   - **Without `--main`, this call blocks and actually runs codex/claude in a new isolated session** — don't do the edit yourself in parallel. Always run it via a Bash tool call with `run_in_background: true` instead of a plain synchronous call, even for a single step: this keeps the main conversation free while it runs and makes it visible in `/tasks`, rather than hard-blocking the turn on a plain wait. The harness delivers one completion notification straight to this session the moment the command exits — read the printed pass/fail from that output. This matters even more for `--all` (no ogre `--background`), where the chain runs every remaining step sequentially inside this one call and can run long enough to exceed the Bash tool's own synchronous timeout (~10 min) if left unwrapped. This is a different thing from ogre's own `--background` flag (see the `[BROWSER-CHECK]` `--all --background` case above): here ogre itself stays in its default blocking foreground mode, it's only the Bash-level call wrapping it that's backgrounded. **If `--live` was used and a Monitor is armed on the log path, `TaskStop` it right here, before reporting** — `tail -f` never exits on its own, so it stays open in the TUI until timeout or a manual `(x)` if you don't.
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

Before reporting anything, mandatory, unless this run used `--run`/`--background` (those already do it): run `${CLAUDE_PLUGIN_ROOT}/scripts/ogre task-complete <task-id> --status passed|failed` for the task id `ogre execute` printed. Do this yourself — don't ask the user to run it, don't skip it because the work is "obviously done." This is the step that keeps `ogre status`/`ogre task-list` accurate; the user should never need to know it exists.

Add `--notes "..."` to that command whenever the step surfaced something the next step's fresh session must know — an actual signature/route/schema that differs from the plan, a deviation made, a gotcha. One or two sentences. Notes are injected into every later runner prompt for the issue; they are the only way mid-step knowledge survives the session that discovered it.

Then report:

- Checklist item completed.
- Files changed.
- Reason for each changed file.
- Validation commands run.
- Validation result.
- Remaining `NEEDS INSPECTION` items.
