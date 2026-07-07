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

## Behavior

1. Run: `scripts/ogre add-blocker <issue> <blocker> [--statement "..."] [--name slug]`
2. The helper:
   - Fetches/writes the blocker into `.ai/.ogre/issues/`.
   - Appends it to `blocker_paths` in `.ai/.ogre/state/issue-<issue>.json`.
   - Resets state status to `planning`.
   - Regenerates `.ai/.ogre/tmp/issue-<issue>/plan-runner.md` as a **revision** runner: it points at the existing plan and instructs the planner to update it for the new blocker, not start over.
3. Read that runner and revise the plan file in place, keeping sections the new blocker doesn't affect.
   - If feeding Codex manually (no repo access of its own), pipe the assembled prompt straight into `codex exec -` — don't write it to disk first. Only `plan-runner.md` belongs under `.ai/.ogre/tmp/issue-<issue>/`.
4. Do not implement code.

## Guardrail: execution must not have started

The helper refuses to add a blocker once execution has begun for the issue (detected via existing `execute-*.log` files or non-empty `completed_steps`/`current_step` in state). In that case it prints an error telling the user to:

- run `/ogre:stop <issue>` first, or
- pass `--force` to override — but warn the user explicitly that already-completed steps will not be retroactively revised, so this is a manual-risk override, not a safe default.

Never pass `--force` silently on the user's behalf; surface the warning and let them decide.
