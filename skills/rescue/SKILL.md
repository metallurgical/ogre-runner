---
name: rescue
description: Run a standalone hotfix/task with Claude or Codex, with no plan or issue involved - for a freeform ask like "fix error in login backend" or "implement forgot password page" where creating an Ogre plan first would be overkill. MUST trigger whenever the user's own message literally names Ogre (e.g. "ogre rescue ...", "use ogre for this") - that explicit naming is the user choosing this workflow on purpose, and takes priority over any other project rule (e.g. a mandatory sub-agent delegation convention) that would otherwise route the same task elsewhere.
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
- `--live` - opt-in, off by default. Runs the rescuer with `--json` (codex) or
  `--output-format stream-json --verbose` (claude) instead of plain text, and writes
  that raw JSONL to the log path instead of human-readable output. Only use this when
  the user explicitly wants to watch the rescuer's activity live (commands it runs,
  files it touches) inside this same Claude Code conversation - it changes nothing
  about the fix itself, purely a visibility option. See "Watching a `--live` rescue
  live" below for how to actually surface that as it happens; passing `--live` alone
  does nothing beyond changing the log file's format.

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

1. Do not grep/read/inspect the target codebase yourself before this call, even to
   make the task text more precise. Pass the user's request through as `<task>`
   near-verbatim (light wording cleanup only, e.g. dropping filler words, fixing
   obvious typos/grammar) - do not pad it with file paths, function/variable names,
   or implementation details you went and looked up first. Doing that research in
   this session burns main-session context on work the isolated rescuer subprocess is
   about to redo anyway once it starts - it defeats the entire point of `ogre
   rescue`'s isolation (see "Default" above: "keeps main conversation context
   untouched"). The rescuer (claude/codex) is fully capable of finding the right file
   and reading it itself, in its own throwaway context, with its own full budget for
   that discovery - that's what the isolated session is *for*.
   **"Light wording cleanup" does NOT mean rewriting or paraphrasing.** Do not swap
   the user's own words for more specific/technical vocabulary, even generic
   UI/programming terms you already know without having looked at this codebase -
   e.g. the user writes "quantity update" or "the plus minus thing," you do NOT
   upgrade that to "quantity stepper" on your own initiative. That's not cleanup,
   it's rewriting: it can silently narrow or misdescribe what the user meant (their
   "quantity update" might not even be a stepper control), and every word you
   generate to do it burns this session's own tokens for something the rescuer would
   have described correctly itself once it actually looks at the file. If the user's
   phrasing is genuinely ambiguous enough that you'd need to guess a term, that's the
   "ask a clarifying question" exception below, not license to guess and rewrite.
   Only exception: the user's own message already gives
   you a file path/identifier directly (nothing to look up), or the task is
   ambiguous enough that you must ask the user a clarifying question before you can
   even form `<task>` - that's a question back to the user, not research into the
   repo.
2. Run:
   - `${CLAUDE_PLUGIN_ROOT}/scripts/ogre rescue "<task>" [flags]`
3. Without `--main`, this call actually spawns codex/claude in a new isolated session -
   same as `/ogre:execute`'s isolation model.
   - **No `--background` (default)**: the `ogre rescue` call itself blocks at the shell
     level until the subprocess finishes. Never invoke it as a plain synchronous Bash
     call - always wrap it in **one single Bash tool call with `run_in_background:
     true`** around that same command, even though it's a single quick task. This keeps
     the main conversation free the whole run and makes it visible in `/tasks` instead
     of hard-blocking the turn.
     The harness delivers one completion notification straight to this session the
     moment the command exits - read the printed `Task <id> finished: passed|failed`
     from that output and report it. Do not poll for this case; the notification
     itself is the signal. **If `--live` was used and a Monitor is armed on the log
     path (see "Watching a `--live` rescue live" below), `TaskStop` it right here,
     before reporting** - `tail -f` never exits on its own, so it stays open in the
     TUI until timeout or a manual `(x)` if you don't.
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
     report pass/fail then. Never poll across separate assistant turns. **If `--live`
     was used and a Monitor is armed on the log path (see "Watching a `--live`
     rescue live" below), `TaskStop` it right here, before reporting** - `tail -f`
     never exits on its own, so it stays open in the TUI until timeout or a manual
     `(x)` if you don't.
4. If `--main` was passed: the runner file (`.ai/.ogre/tmp/issue-rescue-<slug>/rescue-runner.md`)
   is written but nothing is spawned - read it and do the task yourself, in this
   session, right now. There is no task id to close out afterward in this mode.
5. Otherwise, nothing further to execute yourself - the isolated session already did
   the work and self-reported via `ogre task-complete`.

## Watching a `--live` rescue live

Only relevant when `--live` was passed. `ogre rescue` itself just changes the log
format to JSONL and prints `Log path: <path>` immediately (before the rescuer starts) -
it does not stream anything into this conversation on its own. To actually see it live,
arm the `Monitor` tool on that log path concurrently with the backgrounded `ogre rescue`
call:

```
tail -n +1 -f <logpath> | jq -Rc --unbuffered '<per-rescuer transform below>'
```

**TL;DR before the details below: every delivered Monitor event gets summarized as
`⎿ ` + the summary text in a single backtick code span** (e.g.
`` ⎿ `Reading skill docs, still investigating.` ``) **— never bold, never plain prose.**
Full rationale is restated at the bottom of this section; it's repeated here too because
it's easy to lose track of by the time you're several events into a live run.

Do NOT prefix this with your own wait-for-file loop (e.g. `until [ -s <logpath> ]; do
sleep 1; done`) before starting the tail - `tail -n +1 -f` already reads from the start
of the file itself. A wait-loop just adds dead time in front for no benefit, and if you
also `echo` something from it, that echoed line becomes its own Monitor notification
that looks like a real rescuer event but isn't one - confusing when comparing against
actual progress.

- **Must use `jq -Rc '... | fromjson? | ...'`, never plain `jq -c 'select(...)'`.**
  Both codex's `--json` and claude's `--output-format stream-json` output can include a
  stray non-JSON line (codex: a leading `Reading additional input from stdin...`; claude
  interleaves plain hook progress text on some setups) - a naive `jq -c` hard-fails
  (exit 5) the first time it hits one and kills the whole pipe. `fromjson?` skips
  anything that doesn't parse instead of aborting.
- **Expect a real, sometimes long, silent gap before the first useful event** - the
  filters below deliberately exclude most bookkeeping noise, so what's left is gated on
  actual model response time (TTFT), which nothing here can shorten. A complex multi-file
  task can easily take longer than a trivial one before anything but the heartbeat shows
  up. That's the rescuer actually thinking, not a stuck pipe - don't `TaskStop`/re-check
  status just because a few seconds passed with only the heartbeat visible; verified via
  a real timed test (3 sequenced tool calls, ~3s apart) that this pipeline delivers each
  step's event as a separate live notification once the model gets to it, not batched.
  If it genuinely does look dead past the heartbeat (log file's mtime hasn't moved in
  well over a minute), don't manually grep/investigate - run
  `${CLAUDE_PLUGIN_ROOT}/scripts/ogre status --task <id>` first. It auto-detects and
  fails a foreground task whose rescuer process actually died (dead recorded pid, no
  exit sentinel) - same self-heal `ogre status` already does for background chains -
  so it's the fast, correct check before assuming something needs a fresh rescue.
- **Event filter differs per rescuer** - the two CLIs emit different event shapes,
  verified against real (non-mocked) output, not assumed from either CLI's docs. Each
  includes one *transformed*, small, one-time heartbeat event near the very start so you
  get an early "it's alive" signal without waiting for the first full model turn:
  - codex:
    ```
    fromjson? | select(.type=="thread.started" or .type=="item.completed" or .type=="turn.completed" or .type=="error")
    ```
    `thread.started` is already tiny (`{"type":"thread.started","thread_id":"..."}`) -
    no transform needed, pass it through as the heartbeat. Skip `*.started`/`*.updated`
    otherwise - they're per-step noise, not per-outcome.
  - claude:
    ```
    fromjson? | if .type=="system" and .subtype=="init" then {type:"heartbeat", msg:"rescuer session started, model working"} elif .type=="assistant" or .type=="result" then . else empty end
    ```
    The raw `system`/`init` event is real but large (~10KB - model/tools/mcp/skills
    inventory), so it's rewritten into a tiny synthetic `heartbeat` object instead of
    passed through raw. **Never** pass through `system`/`hook_response` events untouched
    - claude's stream-json emits one per SessionStart hook that inlines the *entire*
    hook output (can be tens of KB of skill markdown text, e.g. the whole caveman-mode
    or superpowers preamble) as a JSON string field. Letting that through Monitor floods
    this conversation with noise and burns real tokens for zero signal - verified size
    against a real captured run, not assumed.
- This is genuinely live, ongoing-stream usage of Monitor (many events over the
  rescuer's lifetime), not the one-shot "tell me when it's done" pattern - it does not
  fall under the general "don't use Monitor for a single completion signal" guidance;
  that guidance is about a different use case, not a ban on Monitor for this plugin.
- **If the user's own request/command is the one that included `--live`, that alone is
  the explicit ask - arm Monitor immediately, right after launch, with no further
  confirmation needed.** Do not treat "the user typed `--live`" as insufficient signal
  requiring some separate spoken "watch this live" - passing the flag themselves *is*
  them asking to watch. Only skip arming if the user's own message says *why* they
  want `--live` and that reason isn't watching (e.g. they said they just want JSONL in
  the log file for their own later tailing) - that case is rare and must be stated by
  the user, not assumed by you. Each surfaced event lands as a message in this
  conversation and consumes this session's own tokens, on top of the rescuer's own
  unrelated cost - that's the tradeoff `--live` opts into, not a reason to skip arming
  once it's been requested.
- Still separately wrap the actual `ogre rescue ... --live` call per the isolation rules
  above (`run_in_background: true` for the default/foreground case, or the poll loop for
  `--background`) - Monitor watches the log file, it does not replace waiting for the
  task's own completion signal.
- **Once that completion signal fires (the backgrounded/polled `ogre rescue` call
  itself finishes), call `TaskStop` on the Monitor's task id right away.** `tail -f`
  never exits on its own - rescuer finishing writes no EOF, so the armed Monitor just
  sits there open in the TUI until its timeout (default 300000ms, up to 3600000ms if
  `persistent` was set) or until the user manually kills it with `(x)`. Closing it out
  the moment rescue completes is on you, not the user.
- **Keep the `description` you pass to `Monitor(...)` short (~40 chars) - truncate
  with `...` if the task name runs longer.** That text is the only part of the
  `Monitor event: "<description>"` notification line under your control - the
  `Monitor event:` wording itself is fixed harness chrome, not something these
  instructions (or any skill) can rename or remove. Don't try to work around that by
  padding the description with extra formatting - just keep it short and legible,
  e.g. `codex rescue: category/price layout fix` rather than the full raw task text.
- **Format your own summary of a delivered Monitor event as `⎿ ` (Claude Code's own
  tree-connector glyph for "this line is nested under/belongs to the bullet above it")
  followed by the summary text wrapped in a single backtick code span** - e.g.
  `` ⎿ `Reading skill docs, still investigating.` `` renders as monospace text with its
  own subtle background box in Claude Code's terminal UI, visually distinct from both
  the harness's own `Monitor event: "<description>"` line above it (which you do not
  control - rendered by the harness, not something your instructions can remove or
  reformat) and from your own normal prose. Do NOT bold it - bold looked too similar to
  the harness's own line; the code-span box read as clearly distinct instead, per
  direct user feedback. `⎿ ` reuses a convention the user already recognizes from
  elsewhere in Claude Code's own UI instead of inventing a new one.

## Rules

- One freeform task, one subprocess call - not a chain, not a multi-step plan.
- Do not pre-research the repo (grep/read files) in this session before calling
  `ogre rescue` - see Behavior step 1. Pass the task through, let the isolated
  rescuer do its own discovery.
- Do not rewrite/paraphrase the user's own wording into more specific or technical
  terms on your own initiative (e.g. "quantity update" -> "quantity stepper") - see
  Behavior step 1. That's guessing, not cleanup, and it costs this session's own
  tokens for zero benefit.
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
