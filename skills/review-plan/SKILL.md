---
name: review-plan
description: Review an Ogre execution plan against the repository for hallucinations, risky assumptions, missing validation, and over-scoped steps.
---

# /ogre:review-plan

Use this skill after an execution plan exists and before implementation starts.

## Inputs

Accept:

- Issue number, e.g. `107`
- Plan name, e.g. `issue-107`
- Plan path, e.g. `.ai/.ogre/plans/issue-107.md`

Optional flags:

- `--reviewer claude|codex`
- `--model MODEL`
- `--reasoning LEVEL` (reasoning effort for the reviewer; omit to use the CLI's own default)
- `--main` — run the review inline in this session instead of spawning an isolated subprocess (loses context isolation; only pass when the user explicitly wants that).
- `--background` — spawn the isolated subprocess detached; returns immediately instead of waiting for the review to finish.

## Behavior

1. Run:
   - `${CLAUDE_PLUGIN_ROOT}/scripts/ogre review-plan <issue-or-plan> [flags]`
2. By default the helper spawns an isolated reviewer subprocess itself and blocks until it finishes (same isolation model as `ogre execute`) - you do not read the runner or perform the review yourself. Wait for the command to return, then read its "Task ... finished: passed|failed" line.
   - Pass `--background` to spawn detached and return immediately - report the task id to the user, then immediately start a poll loop yourself in this same session: **one single Bash tool call with `run_in_background: true`** around a real shell loop, e.g. `while :; do ${CLAUDE_PLUGIN_ROOT}/scripts/ogre status --task <tid> | grep -qE '^\| Status +\| (passed|failed) ' && break; sleep 20; done`. The harness delivers a completion notification straight to this session the moment that loop exits - read the final `ogre status --task <tid>` output and report pass/fail to the user then. Never poll across separate assistant turns, and never hand this off to a fork/subagent (a fork always burns Claude quota regardless of which reviewer executor was used, for zero benefit - the background subprocess already does all the work itself).
   - Pass `--main` only if the user explicitly wants the review done inline in this session (spends this session's own context, loses isolation) - in that case, and only then, read `.ai/.ogre/tmp/issue-<number>/plan-review-runner.md` yourself: if reviewer is `claude`, perform the review directly; if reviewer is `codex`, either use `codex exec -m MODEL -c model_reasoning_effort=LEVEL - < runner` (omit `-c model_reasoning_effort=...` if the user gave no `--reasoning`), or ask the user to run it through `codex-plugin-cc` if they prefer same Claude Code TUI. Write output to `.ai/.ogre/reviews/issue-<number>/plan-review.md`.
3. If the run failed (or `--background` is still running), do not treat the review as ready - check `.ai/.ogre/logs/issue-<number>/` for the reviewer's own log before deciding what to do next.
4. Do not edit code.
5. Do not rewrite the plan unless the user explicitly asks.

## Review Focus

Find:

- Hallucinated files/classes/routes/tables/columns/methods/config keys/package APIs.
- Missing validation steps.
- Risky assumptions.
- Over-scoped work.
- Steps that should be split smaller.
- Blocker dependency problems.
- `NEEDS INSPECTION` items that should block execution.

## Output

Use the plan review format from:

- `.ai/.ogre/prompts/plan-review-prompt.md`
