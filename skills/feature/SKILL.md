---
name: feature
description: Start an Ogre issue workflow: fetch issue/blockers into .ai/.ogre, create a planning runner prompt, and generate a compact execution plan.
---

# /ogre:feature

Use this skill when the user wants to start planning for a GitHub issue, a local issue file, or a feature they describe in their own words (no issue required).

## Inputs

Accept any of these:

- Issue number, e.g. `107`
- GitHub issue URL
- Local issue file path
- Freeform feature statement (no issue) via `--statement "..."`

If the user hasn't given an issue and hasn't said what to build, ask: "Do you have an issue number/URL, or do you want to just describe the feature?" Then pass whichever they give as the positional arg or as `--statement`.

Optional flags:

- `--blocks 101,102` — attach blockers with no status remark.
- `--blocker 101 --remarks "PR merged"` — attach one blocker with a freeform status remark tied to it. Repeatable: `--blocker 101 --remarks "merged" --blocker 102 --remarks "under review"`. `--remarks` always annotates the `--blocker` (or `--blocks`) immediately before it; a `--remarks` with no preceding blocker is an error. Mix freely with `--blocks`. Use this form whenever the user tells you each blocker's status (merged / under review / in progress / blocking) so the planner can reason about what's already landed vs still in flight.
- `--plan issue-107.md`
- `--planner claude|codex`
- `--model MODEL`
- `--reasoning LEVEL` (reasoning effort for the planner; omit to use the CLI's own default)
- `--statement "free text description of the feature"` (use instead of an issue)
- `--name my-feature` (slug for runtime paths when using `--statement`; default: first ~4 words of the statement + a short uuid suffix, e.g. "need to implement forgot password page" -> `need-to-implement-a1b2c3d4` — the suffix keeps it unique and ties the slug to that specific plan .md even if two features start with similar wording)
- `--browser-check` — opt-in. Without it, the generated plan never tags a step `[BROWSER-CHECK]`, even ones that render/change UI - the user verifies those themselves. Only pass it when the user actually says they want the feature verified in a real browser as part of execution. Don't ask about this on every `/ogre:feature` call; default (no flag) is correct unless the user brings it up.
- `--main` — run planning inline in this session instead of spawning an isolated subprocess (loses context isolation; only pass when the user explicitly wants that).
- `--background` — spawn the isolated subprocess detached; returns immediately instead of waiting for the plan to finish.

## Behavior

**Hard requirement, every completion message this skill produces, no exception:** must literally contain `Job Id:`, `Issue:` (number + name), `Plan:`, and `Steps:` lines with their real values. A terse summary sentence is fine (e.g. "Plan ready, 8 steps, issue 118 (Laporan Trend Analysis). Next: ogre review-plan 118 or ogre execute 118.") — even under caveman/ultra/terse mode — but it must not be the *only* thing shown; the `Job Id:`/`Issue:`/`Plan:`/`Steps:` lines still have to appear alongside it, every time.

1. Run the Ogre helper from the plugin:
   - `${CLAUDE_PLUGIN_ROOT}/scripts/ogre feature <issue> [flags]`
   - or `${CLAUDE_PLUGIN_ROOT}/scripts/ogre feature --statement "..." [--name my-feature] [flags]`
   - When `--statement` is used, the helper writes the statement verbatim into `.ai/.ogre/issues/issue-<name>.md` instead of fetching from GitHub. Everything downstream (plan runner, plan, state) works the same either way.
2. The helper will create or update:
   - `.ai/.ogre/issues/`
   - `.ai/.ogre/plans/`
   - `.ai/.ogre/logs/`
   - `.ai/.ogre/state/`
   - `.ai/.ogre/tmp/`
   - `.ai/.ogre/prompts/`
   - It also prints a **Job Summary** (Job Id, Issue, Status, Plan path, Commands) right after creation. Show this block **verbatim in a code block, one field per line** — do not paraphrase it into a sentence like "New job: \<slug\>" and do not drop fields (job_id and Plan path in particular must always be visible). At this point the plan doesn't exist yet, so Review/Execute are correctly absent from the command list; that's expected, not a bug.
3. By default the helper spawns an isolated planner subprocess itself and the `ogre feature` call blocks until it finishes (same isolation model as `ogre execute`) - you do not read the runner or write the plan yourself. Never invoke it as a plain synchronous Bash call - always wrap it in **one single Bash tool call with `run_in_background: true`** around that same command, even though it's usually a single quick plan. This keeps the main conversation free the whole run and makes it visible in `/tasks` instead of hard-blocking the turn. The harness delivers one completion notification straight to this session the moment the command exits - read its "Task ... finished: passed|failed" line from that output. Do not poll for this case; the notification itself is the signal.
   - Pass `--background` to spawn detached and return immediately (this quick returning call doesn't itself need the `run_in_background` wrapper) - report the task id to the user, then immediately start a poll loop yourself in this same session: **one single Bash tool call with `run_in_background: true`** around a real shell loop, e.g. `while :; do ${CLAUDE_PLUGIN_ROOT}/scripts/ogre status --task <tid> | grep -qE '^\| Status +\| (passed|failed) ' && break; sleep 20; done`. The harness delivers a completion notification straight to this session the moment that loop exits - read the final `ogre status --task <tid>` output and report pass/fail to the user then, then proceed to step 5 below. Never poll across separate assistant turns, and never hand this off to a fork/subagent (a fork always burns Claude quota regardless of which planner executor was used, for zero benefit - the background subprocess already does all the work itself).
   - Pass `--main` only if the user explicitly wants the planning done inline in this session (spends this session's own context, loses isolation) - in that case, and only then, read `.ai/.ogre/tmp/issue-<number>/plan-runner.md` yourself and create the plan exactly as it requests, same as before this flag existed. If `--planner codex` and Codex has no repo access of its own, you may need to assemble the template + issue + repo context into one prompt and pipe it into `codex exec -` yourself. Do this **without writing the assembled prompt to disk first** — pipe it straight through, e.g. `{ cat .ai/.ogre/prompts/execution-blueprint-prompt.md; echo; cat .ai/.ogre/issues/issue-<n>.md; } | codex exec -`. Carry through any `--model`/`--reasoning` the user gave: `-m <model>` / `-c model_reasoning_effort=<level>`. Don't create extra files like `codex-plan-input.md`/`codex-raw-output.txt` under `.ai/.ogre/tmp/` — only `plan-runner.md` belongs there. Write the final plan to `.ai/.ogre/plans/issue-<number>.md` or the custom plan path.
4. If the run failed (or `--background` is still running), do not treat the plan as ready - check `.ai/.ogre/logs/issue-<number>/` for the planner's own log before deciding what to do next.
5. Run `${CLAUDE_PLUGIN_ROOT}/scripts/ogre status <issue>` and show that Job Summary again, same format as step 2 (verbatim code block, one field per line). The plan now exists, so this second summary will differ from the first: `Plan` drops `(not written yet)`, `Steps Completed/Remaining/Total` are populated, `Review plan`/`Execute next` rows appear, and a `Steps (N):` checklist table is printed below it. Don't skip this just because you already showed a summary in step 2 — that one was necessarily incomplete.
   - This verbatim requirement (both step 2 and step 5) holds even under a response-compression mode (caveman, terse/brief settings, etc). Those modes govern your own prose, not tool output you're instructed to reproduce verbatim — never fold the Job Summary table or Steps checklist into a one-line paraphrase like "Plan ready: N steps - ..." to satisfy a brevity mode.
6. Do not implement code.
7. Do not modify application files.

## Existing Issue Behavior

If the plan already exists, the helper asks the user to choose:

1. Continue existing work
2. Replace plan only
3. Archive existing and create new
4. Delete all Ogre data for this issue and start fresh
5. Cancel

Default to continue existing work unless the user explicitly chooses otherwise.

## Guardrails

- Use `repo_map.md` only for orientation.
- Do not invent files/classes/routes/tables/columns/methods/config keys/APIs.
- Mark unverified symbols as `NEEDS INSPECTION`.
- Keep the plan compact for execution handoff.
