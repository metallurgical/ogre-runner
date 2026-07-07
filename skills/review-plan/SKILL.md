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

## Behavior

1. Run:
   - `scripts/ogre review-plan <issue-or-plan> [flags]`
2. Read the generated runner:
   - `.ai/.ogre/tmp/issue-<number>/plan-review-runner.md`
3. If reviewer is `claude`, perform the review directly.
4. If reviewer is `codex`, either:
   - use `codex exec -m MODEL - < runner`, or
   - ask the user to run it through `codex-plugin-cc` if they prefer same Claude Code TUI.
5. Write output to:
   - `.ai/.ogre/reviews/issue-<number>/plan-review.md`
6. Do not edit code.
7. Do not rewrite the plan unless the user explicitly asks.

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
