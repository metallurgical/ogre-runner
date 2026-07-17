---
name: add-blocker
description: Attach a new blocker (GitHub issue, URL, local file, or freeform statement) to an already-started Ogre issue, and force the plan to be revised to account for it.
---

# /ogre:add-blocker

Use this skill when the user wants to add a blocker to an issue Ogre is already tracking, discovered after `/ogre:feature` ran (not just at feature-creation time via `--blocks`).

## Inputs

- The target issue number (required, must already have Ogre state).
- The blocker itself, same input types as `/ogre:feature` — one of:
  - GitHub issue number (GitHub-only, resolved via `gh` + the project's git remote)
  - Full issue/page URL — GitHub, GitLab, self-hosted GitLab, Bitbucket, Jira, or any other tracker. Non-GitHub links are fetched generically as page text (no API client), not via `gh`.
  - Local file path — `.md`/`.txt` copied verbatim, `.docx` text-extracted
  - Freeform statement via `--statement "..."` (no issue/URL/file needed)
- Optional `--name blocker-slug` (only used with `--statement`).
- Optional `--remarks "..."` — a freeform note on this blocker's status (e.g. `"PR merged"`, `"under review"`, `"blocking, not started"`). It's tied to this specific blocker and travels with it into planning. Omit it and the blocker is stored plain, with no remark. If the user mentions a status when adding the blocker, capture it here.
- Optional `--planner claude|codex`, `--model MODEL`, `--reasoning LEVEL` — defaults to whichever planner `/ogre:feature` already seeded for this issue if omitted.
- `--main` — revise the plan inline in this session instead of spawning an isolated subprocess (loses context isolation; only pass when the user explicitly wants that).
- `--background` — spawn the isolated subprocess detached; returns immediately instead of waiting for the revision to finish.

## Behavior

**Hard requirement, every completion message this skill produces, no exception:** must literally contain `Job Id:`, `Issue:` (number + name), `Plan:`, and `Steps:` lines with their real values. A terse summary sentence is fine, even under caveman/ultra/terse mode — but it must not be the *only* thing shown; the `Job Id:`/`Issue:`/`Plan:`/`Steps:` lines still have to appear alongside it, every time.

1. Run: `${CLAUDE_PLUGIN_ROOT}/scripts/ogre add-blocker <issue> <blocker> [--statement "..."] [--name slug] [--remarks "status note"] [flags]`
2. The helper:
   - Fetches/writes the blocker into `.ai/.ogre/issues/`.
   - Appends it to `blocker_paths` in `.ai/.ogre/state/issue-<issue>.json`.
   - If `--remarks` given: stores it in `blocker_remarks` (keyed by the blocker's path), prepends it as a header to the blocker's `.md` file, and shows it inline next to the blocker in the planning runner — so the planner sees the status without you restating it.
   - Resets state status to `planning`.
   - Regenerates `.ai/.ogre/tmp/issue-<issue>/plan-runner.md` as a **revision** runner: it points at the existing plan and instructs the planner to update it for the new blocker, not start over.
   - By default spawns an isolated re-planner subprocess itself and the `ogre add-blocker` call blocks until it finishes (same isolation model as `ogre execute`/`ogre feature`) - you do not read the runner or revise the plan yourself. Never invoke it as a plain synchronous Bash call - always wrap it in **one single Bash tool call with `run_in_background: true`** around that same command, even though it's usually a single quick revision. This keeps the main conversation free the whole run and makes it visible in `/tasks` instead of hard-blocking the turn. The harness delivers one completion notification straight to this session the moment the command exits - read its "Task ... finished: passed|failed" line from that output. Do not poll for this case; the notification itself is the signal.
3. Pass `--background` to spawn detached and return immediately (this quick returning call doesn't itself need the `run_in_background` wrapper) - report the task id to the user, then immediately start a poll loop yourself in this same session: **one single Bash tool call with `run_in_background: true`** around a real shell loop, e.g. `while :; do ${CLAUDE_PLUGIN_ROOT}/scripts/ogre status --task <tid> | grep -qE '^\| Status +\| (passed|failed) ' && break; sleep 20; done`. The harness delivers a completion notification straight to this session the moment that loop exits - read the final `ogre status --task <tid>` output and report pass/fail to the user then. Never poll across separate assistant turns, and never hand this off to a fork/subagent (a fork always burns Claude quota regardless of which planner executor was used, for zero benefit - the background subprocess already does all the work itself).
4. Pass `--main` only if the user explicitly wants the revision done inline in this session (spends this session's own context, loses isolation) - in that case, and only then, read that runner and revise the plan file in place yourself, keeping sections the new blocker doesn't affect. If feeding Codex manually (no repo access of its own), pipe the assembled prompt straight into `codex exec -` — don't write it to disk first. Only `plan-runner.md` belongs under `.ai/.ogre/tmp/issue-<issue>/`.
5. If the run failed (or `--background` is still running), do not treat the revision as ready - check `.ai/.ogre/logs/issue-<issue>/` for the planner's own log before deciding what to do next.
6. Do not implement code.

## Guardrail: execution must not have started

The helper refuses to add a blocker once execution has begun for the issue (detected via existing `execute-*.log` files or non-empty `completed_steps`/`current_step` in state). In that case it prints an error telling the user to:

- run `/ogre:stop <issue>` first, or
- pass `--force` to override — but warn the user explicitly that already-completed steps will not be retroactively revised, so this is a manual-risk override, not a safe default.

Never pass `--force` silently on the user's behalf; surface the warning and let them decide.
