# Ogre Plugin Build Brief

## Purpose

Build a Claude Code plugin named `ogre` that helps manage AI-assisted feature delivery with low hallucination, low context waste, and better code quality.

The plugin should support this workflow:

1. Fetch/download GitHub issue details into project-local Ogre runtime files.
2. Fetch/download blocking issue details, if any.
3. Generate a compact execution blueprint/plan using Claude or Codex.
4. Review the plan against the repository before implementation.
5. After user approval, execute the plan step by step.
6. Each execution step should run in a fresh Claude/Codex context where possible.
7. Track all progress in project-local state files so Claude and Codex can resume accurately.
8. Allow stopping, pausing, archiving, or deleting issue-specific Ogre runtime data.

This plugin is intended for daily coding work, especially Laravel/PHP projects, but should not hardcode Laravel-only behavior unless placed in optional templates or validation prompts.

---

## Main Design Decision

Ogre should be a plugin with a small command surface, not many separate user-facing skills.

User-facing commands:

- `/ogre:feature`
- `/ogre:review-plan`
- `/ogre:execute`
- `/ogre:stop`
- `/ogre:status`

Behind the scenes, Ogre can contain:

- skills
- templates
- shell scripts
- optional hooks
- runtime state files

The user should not need to manually manage many skills.

---

## Preferred Runtime Folder

All project-specific Ogre files must live under:

```txt
.ai/.ogre/
```

Do not scatter runtime files directly under `.ai/`.

Recommended runtime structure:

```txt
.ai/
  .ogre/
    config.json

    issues/
      issue-107.md
      issue-101.md
      issue-102.md

    plans/
      issue-107.md

    reviews/
      issue-107/
        plan-review.md
        diff-review-step-1.md
        diff-review-step-2.md

    logs/
      issue-107/
        feature.log
        execute-step-1.log
        execute-step-2.log
        stop.log

    state/
      issue-107.json
      active.json

    tmp/
      issue-107/
        plan-runner.md
        review-plan-runner.md
        execute-next-runner.md
        diff-review-runner.md

    archive/
      issue-107-YYYYMMDD-HHMMSS/
```

Runtime files and plugin installation files are separate concepts:

```txt
ogre-plugin/     = reusable Claude Code plugin package
.ai/.ogre/       = project-specific Ogre runtime state/data
```

---

## Plugin Package Structure

Recommended plugin scaffold:

```txt
ogre-plugin/
  .claude-plugin/
    plugin.json

  skills/
    feature/
      SKILL.md
    review-plan/
      SKILL.md
    execute/
      SKILL.md
    stop/
      SKILL.md
    status/
      SKILL.md

  scripts/
    ogre

  templates/
    execution-blueprint-prompt.md
    execution-handoff.md
    plan-review-prompt.md
    plan-runner-prompt.md
    run-next-prompt.md
    diff-review-prompt.md

  README.md
```

Important: use the neutral template name:

```txt
templates/execution-handoff.md
```

Do not use `codex-execution-handoff.md` because the handoff can be used by either Claude or Codex.

---

## Existing MVP Scaffold

A first scaffold was created as `ogre-plugin.zip`. It includes:

```txt
ogre-plugin/
  .claude-plugin/plugin.json
  skills/feature/SKILL.md
  skills/review-plan/SKILL.md
  skills/execute/SKILL.md
  skills/stop/SKILL.md
  skills/status/SKILL.md
  scripts/ogre
  templates/execution-blueprint-prompt.md
  templates/execution-handoff.md
  templates/plan-review-prompt.md
  templates/plan-runner-prompt.md
  templates/run-next-prompt.md
  templates/diff-review-prompt.md
  README.md
```

The next agent should inspect this scaffold and improve/fix it rather than start from scratch, unless the scaffold is broken beyond repair.

---

## Core Workflow

### 1. Feature Planning

Command:

```txt
/ogre:feature 107 --blocks 101,102
```

Or interactive:

```txt
/ogre:feature
```

The command should ask for missing values:

- current issue number, GitHub issue URL, or local issue file path
- blocking issues: none, one, or many issue numbers/URLs/file paths
- plan name, default `issue-<number>.md`
- planner provider: `claude` or `codex`, default `claude`
- model, optional

Expected behavior:

1. Initialize `.ai/.ogre/` if missing.
2. Download/fetch current GitHub issue into `.ai/.ogre/issues/issue-<number>.md`.
3. Download/fetch blocker issues into `.ai/.ogre/issues/issue-<number>.md`.
4. Create a plan runner prompt in `.ai/.ogre/tmp/<issue>/plan-runner.md`.
5. Use `templates/execution-blueprint-prompt.md` as the planning template.
6. Generate final plan at `.ai/.ogre/plans/<plan-name>.md`.
7. Create/update `.ai/.ogre/state/issue-<number>.json`.
8. Stop. Do not implement code.

If the issue already exists, prompt user:

```txt
Issue <number> already exists.
Choose:
1. Continue existing work
2. Replace plan only
3. Archive existing and create new
4. Delete all Ogre data for this issue and start fresh
5. Cancel
```

Default should be `Continue existing work`.

Never delete or overwrite automatically.

---

### 2. Plan Review

Command examples:

```txt
/ogre:review-plan 107
/ogre:review-plan 107 --reviewer claude --model sonnet-5
/ogre:review-plan 107 --reviewer codex --model gpt-5.5
```

Expected behavior:

1. Read `.ai/.ogre/plans/issue-107.md`.
2. Review it against the current repository/codebase.
3. Check for:
   - hallucinated files/classes/routes/tables
   - missing validation steps
   - risky assumptions
   - over-scoped work
   - steps that should be split smaller
4. Do not edit code.
5. Return only problems and suggested corrections.
6. Write review to `.ai/.ogre/reviews/issue-107/plan-review.md`.
7. Update state.
8. Stop.

Reviewer runner prompt should be based on:

```txt
Review this implementation plan `<file path>` against the repository/codebase.

Find:
- hallucinated files/classes/routes/tables
- missing validation steps
- risky assumptions
- over-scoped work
- steps that should be split smaller

Do not edit code.
Return only problems and suggested corrections.
```

---

### 3. Execute Approved Plan

Command examples:

```txt
/ogre:execute 107
/ogre:execute 107 --executor codex --model gpt-5.5
/ogre:execute 107 --executor claude --model sonnet-5
/ogre:execute 107 --all --executor codex --model gpt-5.5
/ogre:execute 107 --fresh
/ogre:execute 107 --resume
```

Safe default:

```txt
/ogre:execute 107
```

Equivalent default behavior:

```txt
/ogre:execute 107 --next --executor codex --fresh
```

Expected behavior for `--next`:

1. Read state file.
2. Read approved plan.
3. Find next incomplete checklist item.
4. Generate runner prompt in `.ai/.ogre/tmp/<issue>/execute-next-runner.md`.
5. Run executor, preferably fresh session/context.
6. Execute only one checklist item.
7. Run validation commands from the plan when possible.
8. Save execution log under `.ai/.ogre/logs/<issue>/`.
9. Update state.
10. Stop.

Expected behavior for `--all`:

Loop until complete, but stop immediately if:

- validation fails
- executor reports uncertainty
- blocker dependency is missing
- diff review has Must Fix findings
- working tree has unexpected unrelated changes
- user requested stop

Default should not be `--all`. Manual step-by-step execution is safer.

---

### 4. Stop / Pause / Cleanup

Command examples:

```txt
/ogre:stop
/ogre:stop 107
/ogre:stop 107 --current
/ogre:stop --all
/ogre:stop 107 --archive
/ogre:stop 107 --delete
```

Default behavior:

```txt
/ogre:stop 107
```

Means:

- pause/stop current Ogre workflow for the issue
- do not delete files
- do not revert code
- keep plan, logs, reviews, issues, and state

For Codex background jobs through `codex-plugin-cc`, Ogre should attempt to cancel active Codex jobs if possible.

For Claude itself, stopping a currently-running Claude response from inside the same process may not be possible. Use cooperative stop:

- set state status to `stop_requested` or `stopped`
- every future Ogre command must check state before continuing

Delete behavior must confirm first:

```txt
This will delete Ogre runtime data for issue <number>.
It will not revert code changes.
Continue? yes/no
```

Archive behavior should move issue runtime files to:

```txt
.ai/.ogre/archive/issue-<number>-YYYYMMDD-HHMMSS/
```

---

### 5. Status

Command examples:

```txt
/ogre:status
/ogre:status 107
```

Expected output:

```txt
Issue: 107
Status: executing
Plan: .ai/.ogre/plans/issue-107.md
Planner: claude sonnet-5
Reviewer: claude sonnet-5
Executor: codex gpt-5.5
Completed steps: 2/6
Current step: 3
Last validation: passed
Last log: .ai/.ogre/logs/issue-107/execute-step-2.log
Active job: <job id if any>
Next command: /ogre:execute 107
```

---

## Shared State Requirement

Do not rely on Claude or Codex memory.

Use `.ai/.ogre/state/issue-<number>.json` as source of truth.

Example:

```json
{
  "issue": "107",
  "status": "planned",
  "planner": {
    "provider": "claude",
    "model": "sonnet-5"
  },
  "reviewer": {
    "provider": "claude",
    "model": "sonnet-5"
  },
  "executor": {
    "provider": "codex",
    "model": "gpt-5.5"
  },
  "plan_path": ".ai/.ogre/plans/issue-107.md",
  "issue_path": ".ai/.ogre/issues/issue-107.md",
  "blocker_paths": [
    ".ai/.ogre/issues/issue-101.md",
    ".ai/.ogre/issues/issue-102.md"
  ],
  "completed_steps": [],
  "current_step": null,
  "active_job": null,
  "last_log": null,
  "last_validation": null,
  "created_at": "2026-07-06T14:30:00+08:00",
  "updated_at": "2026-07-06T14:30:00+08:00"
}
```

Use `.ai/.ogre/state/active.json` to track active jobs:

```json
{
  "active_issue": "107",
  "active_jobs": [
    {
      "issue": "107",
      "type": "execute",
      "provider": "codex",
      "job_id": "abc123",
      "status": "running",
      "started_at": "2026-07-06T14:35:00+08:00"
    }
  ]
}
```

---

## Provider and Model Options

Commands should support provider/model options eventually:

```txt
/ogre:feature 107 --planner claude --model sonnet-5
/ogre:feature 107 --planner codex --model gpt-5.5

/ogre:review-plan 107 --reviewer claude --model sonnet-5
/ogre:review-plan 107 --reviewer codex --model gpt-5.5

/ogre:execute 107 --executor codex --model gpt-5.5
/ogre:execute 107 --executor claude --model sonnet-5
```

Do not hardcode model names too strictly. Model names can change.

Use config defaults:

```json
{
  "defaults": {
    "planner": {
      "provider": "claude",
      "model": "sonnet-5"
    },
    "plan_reviewer": {
      "provider": "claude",
      "model": "sonnet-5"
    },
    "executor": {
      "provider": "codex",
      "model": "gpt-5.5"
    },
    "diff_reviewer": {
      "provider": "codex",
      "model": "gpt-5.5"
    }
  }
}
```

If a provider is `codex`, check whether Codex CLI/plugin wrapper is available.

If a provider is `claude`, use Claude Code/Claude CLI where appropriate.

---

## Codex / Claude Execution Direction

Primary MVP direction:

```txt
Claude Code TUI -> Ogre plugin -> Codex execution through codex-plugin-cc or Codex CLI
```

This supports:

```txt
Claude plans.
Codex executes.
Claude/Codex reviews.
```

Reverse direction can be added later:

```txt
Codex plans.
Claude executes.
```

Do not build reverse direction first unless explicitly requested. Keep MVP focused.

---

## Codex Plugin CC Integration

User wants to execute Codex inside Claude Code using:

```txt
https://github.com/openai/codex-plugin-cc
```

Ogre should expect this wrapper/plugin to already be installed when using `--executor codex` inside Claude Code.

If possible, Ogre should support both:

1. Direct Codex CLI:

```bash
codex exec -m <model> - < .ai/.ogre/tmp/<issue>/execute-next-runner.md
```

2. Claude Code Codex plugin workflow:

```txt
/codex:rescue --fresh --background <task>
/codex:status
/codex:result
/codex:cancel
```

Do not assume background job cancellation is available unless using codex-plugin-cc.

---

## Planning Template

Use this exact file name:

```txt
templates/execution-blueprint-prompt.md
```

Current content:

```md
# Execution Blueprint Prompt

## Context

* Current issue: GitHub issue will be provided by the runner prompt.
* Blocked by:
  * GitHub issue will be provided by the runner prompt.
* Attached: `repo_map.md`

## Task

Create an execution blueprint only.

Do not implement.

You must:

* Read current issue fully.
* Read blocker issues fully, if provided.
* Understand blocker impact before planning.
* Use `repo_map.md` only for orientation, not as proof that implementation details exist.
* Compare the plan against the current codebase if file contents are available.
* Use exact relative paths only.
* Do not invent missing files, classes, methods, routes, tables, columns, config keys, or package APIs.
* If a file, method, route, table, or column is not proven by inspected content, mark it as `NEEDS INSPECTION`.
* Prefer the smallest safe change.
* Avoid unrelated refactors.
* Preserve existing project style.
* (Codex only) Keep output compact for Codex handoff.

## Planning Rules

* Every file action must be based on repo evidence or marked `NEEDS INSPECTION`.
* Do not propose new abstractions unless required by the issue.
* Do not add new packages unless explicitly required.
* Do not change database schema unless the issue clearly requires it.
* Do not create tests unless the project already has a matching test pattern, or mark as `NEEDS INSPECTION`.
* Interface contracts must be marked as:

  * `EXISTING` if verified from code.
  * `NEW` if the plan requires creating it.
  * `NEEDS INSPECTION` if not verified.

## Output Rules

* No code blocks.
* No boilerplate.
* No long reasoning.
* Keep bullets concise.
* Include only useful handoff details.
* Mark new files with `CREATE:`.
* Mark uncertain files or symbols with `NEEDS INSPECTION`.
* Mention blocker dependency clearly.
* Output only the format below.

---

# Execution Plan

## 1. Blocker Understanding

* Issue `#`: Short dependency impact.
* Issue `#`: Short dependency impact.
* Dependency note: What executor must wait for, preserve, or avoid.

## 2. Repo Evidence Used

* `path/file`: What was confirmed from this file.
* `repo_map.md`: Orientation only; not proof of implementation details.

## 3. Assumptions / Needs Inspection

* `NEEDS INSPECTION`: Exact file, area, or symbol that must be checked before coding.
* Risk if skipped: Short explanation.

## 4. Files to Modify / Create

* [ ] `path/file`: Short action. Expected outcome. Evidence: `path/file` or `NEEDS INSPECTION`.
* [ ] `CREATE: path/file`: Short action. Expected outcome.
* [ ] `NEEDS INSPECTION`: Area needing confirmation.

## 5. Interface Contracts

* `EXISTING: path/file` -> `name(param: type): returnType`

  * Purpose: One short sentence.
* `NEW: path/file` -> `name(param: type): returnType`

  * Purpose: One short sentence.
* `NEEDS INSPECTION` -> Contract depends on existing code confirmation.

## 6. Execution Order

* [ ] Step one.
* [ ] Step two.
* [ ] Step three.

## 7. Acceptance Criteria

* [ ] Current issue behavior works.
* [ ] Blocker compatibility preserved.
* [ ] Existing behavior unchanged.
* [ ] No unrelated refactors.
* [ ] Relevant tests pass.

## 8. Terminal Commands & Validation

* Setup: `command`
* Test: `command`
* Lint: `command`
* Build: `command`
* Manual: Short verification step.

## 9. Guardrails

* Execute one checklist item at a time.
* Inspect files before editing.
* Do not implement `NEEDS INSPECTION` items until verified.
* Do not continue if blocker implementation is missing.
* After each item, report changed files and validation result.
```

---

## Execution Handoff Template

Use this exact file name:

```txt
templates/execution-handoff.md
```

Current content:

```md
# Execution Handoff Prompt

Execute the approved execution plan exactly.

## Source Plan

Follow:

* Follow from source plan: will be provided by runner prompt

# Main Goal

* Implement only the work described in the source plan.
* Do not re-plan the feature from scratch.
* Do not use repo_map.md as proof of implementation details. Use it only for orientation.

## Rules

* Execute one checklist item at a time.
* Inspect relevant files before editing.
* Do not implement items marked `NEEDS INSPECTION` until verified.
* Do not invent files, methods, routes, tables, columns, config keys, or APIs.
* Do not add unrelated refactors.
* Do not change behavior outside the issue scope.
* Do not add packages unless the plan explicitly says so.
* Preserve existing project style.
* Prefer the smallest safe change.
* Stop if blocker dependency is missing or incompatible.

## Before Editing

* Confirm which checklist item you are executing.
* List files inspected.
* Confirm whether the required files, methods, routes, tables, or columns exist.
* If something is uncertain, mark it as NEEDS INSPECTION and stop before editing that part.

## During Editing

* Modify only the files required for the current checklist item.
* Keep changes small.
* Do not continue to the next checklist item.
* Do not perform formatting-only changes outside touched code.
* Do not rename existing classes, methods, files, or variables unless required by the plan.

## After Editing
Report:

* Checklist item completed.
* List changed files.
* Explain each change in one short bullet.
* Run the validation commands from the plan.
* Report validation result.
* Stop after the current checklist item.
* Any remaining NEEDS INSPECTION items.

Then stop.
```

---

## Runner Prompt for Execution

Use/update this as `templates/run-next-prompt.md`:

```md
# Runner / Execution Prompt

Read and follow the execution handoff instructions from:

* `<path to execution-handoff.md>`

Use this source plan:

* `<path to reviewed issue plan .md>`

Task:

* Execute the next incomplete checklist item only.
* Do not execute more than one checklist item.
* Follow the handoff rules exactly.
* Inspect relevant files before editing.
* Do not implement unresolved `NEEDS INSPECTION` items until verified.
* Stop if blocker dependency is missing or incompatible.
* Run validation commands from the plan when applicable.
* Stop after reporting changed files and validation result.

Runtime tracking:

* Write execution notes/log to `<path to .ai/.ogre/logs/<issue>/execute-step-N.log>` if possible.
* Update `<path to .ai/.ogre/state/issue-<number>.json>` if the implementation environment allows it.

Do not re-plan the feature.
Do not execute later checklist items.
```

---

## Diff Review Prompt

Use/update this as `templates/diff-review-prompt.md`:

```md
# Diff Review Prompt

Review only the current git diff.

Find:

- real bugs
- broken tests
- missing imports
- wrong method names
- wrong database columns
- security issues
- backward compatibility problems
- edge cases
- unrelated refactors

Rules:

- Do not review the entire project.
- Do not suggest unrelated refactors.
- Prioritize bugs over style.
- Check if implementation matches the approved plan.
- Check if tests cover the changed behavior where applicable.

Return findings grouped as:

## Must Fix

## Should Fix

## Optional

If no serious issues are found, say: `No Must Fix findings.`
```

---

## Quality Rules for Agent Implementation

Agents working on this plugin must follow these rules:

- Do not invent Claude Code plugin fields without checking existing scaffold/docs/project examples.
- Do not invent Codex CLI flags unless verified locally.
- Keep shell scripts POSIX-friendly where possible.
- Avoid Bash features that break on macOS default shell unless script uses `#!/usr/bin/env bash`.
- Do not delete user files automatically.
- Never revert user code changes unless user explicitly asks.
- Always quote paths.
- Treat `.ai/.ogre/` as project-local mutable runtime state.
- Treat `ogre-plugin/` as reusable plugin source.
- Keep commands safe and inspectable.
- Prefer small, testable increments.

---

## Script Requirements

Main helper script:

```txt
scripts/ogre
```

Expected commands:

```bash
scripts/ogre init
scripts/ogre feature <issue> [--blocks 1,2] [--planner claude|codex] [--model MODEL] [--plan NAME]
scripts/ogre review-plan <issue> [--reviewer claude|codex] [--model MODEL]
scripts/ogre execute <issue> [--executor claude|codex] [--model MODEL] [--next|--all] [--fresh|--resume]
scripts/ogre stop [issue] [--all] [--archive] [--delete]
scripts/ogre status [issue]
```

MVP can start smaller:

```bash
scripts/ogre init
scripts/ogre feature <issue> [--blocks 1,2]
scripts/ogre status [issue]
scripts/ogre stop [issue]
scripts/ogre execute <issue>
```

The script should create directories if missing:

```bash
.ai/.ogre/issues
.ai/.ogre/plans
.ai/.ogre/reviews
.ai/.ogre/logs
.ai/.ogre/state
.ai/.ogre/tmp
.ai/.ogre/archive
```

For GitHub issue fetch:

- use `gh issue view <number> --comments` when issue is a number
- if issue is URL, parse number where possible or save with a safe name
- if issue is a local path, copy/read it into `.ai/.ogre/issues/`
- if `gh` is missing, tell user what to run manually

---

## Slash Command Skill Behavior

Each Claude Code skill should call or instruct use of `scripts/ogre`.

### `/ogre:feature`

- Collect missing issue/blocker/plan info.
- Initialize runtime folders.
- Fetch/copy issue files.
- Create plan runner prompt.
- Ask Claude to create plan using template.
- Save plan to `.ai/.ogre/plans/`.
- Stop.

### `/ogre:review-plan`

- Read plan.
- Review against repository.
- Save review to `.ai/.ogre/reviews/<issue>/plan-review.md`.
- Stop.

### `/ogre:execute`

- Read state and plan.
- Generate execute-next runner prompt.
- Delegate to selected executor.
- Default executor should be Codex if configured.
- Default mode should execute next incomplete checklist item only.
- Stop after one step unless `--all` is used.

### `/ogre:stop`

- Pause current issue or all issues.
- Optionally archive/delete with confirmation.
- Do not revert code.

### `/ogre:status`

- Read `.ai/.ogre/state/`.
- Show issue status, completed steps, current step, last log, next command.

---

## Acceptance Criteria for Plugin MVP

MVP is acceptable when:

1. Plugin loads in Claude Code with local plugin directory.
2. `/ogre:feature` command is visible/usable.
3. `/ogre:status` command is visible/usable.
4. `scripts/ogre init` creates `.ai/.ogre/` structure.
5. `scripts/ogre feature 107 --blocks 101,102` creates/fetches issue files and state file.
6. A plan runner prompt is generated under `.ai/.ogre/tmp/issue-107/`.
7. Plan can be saved to `.ai/.ogre/plans/issue-107.md`.
8. `scripts/ogre status 107` displays progress.
9. `scripts/ogre stop 107` marks state as stopped without deleting files.
10. No source code files outside `.ai/.ogre/` are modified unless explicitly requested by user.

---

## Acceptance Criteria for Execution MVP

Execution MVP is acceptable when:

1. `scripts/ogre execute 107` reads `.ai/.ogre/plans/issue-107.md`.
2. It creates `.ai/.ogre/tmp/issue-107/execute-next-runner.md`.
3. The runner prompt points to `templates/execution-handoff.md`.
4. It instructs executor to execute only the next incomplete checklist item.
5. It does not auto-run all steps by default.
6. It logs result to `.ai/.ogre/logs/issue-107/`.
7. It updates state.
8. It stops safely on validation failure or uncertainty.

---

## Recommended Implementation Order

Do not build everything at once.

Recommended order:

1. Verify current scaffold structure.
2. Fix `plugin.json` so Claude Code recognizes `ogre` plugin.
3. Fix all `SKILL.md` files so slash commands are clear.
4. Implement `scripts/ogre init`.
5. Implement `scripts/ogre status`.
6. Implement `scripts/ogre feature` with local state creation.
7. Add GitHub issue fetching via `gh`.
8. Generate plan runner prompt.
9. Implement `review-plan` prompt generation.
10. Implement `execute` prompt generation.
11. Add direct Codex CLI execution option.
12. Add codex-plugin-cc integration notes/optional behavior.
13. Implement `stop` pause behavior.
14. Implement `archive` and `delete` with confirmation.
15. Add model/provider options.
16. Add `--all` mode last.
17. Update README with install/test commands.

---

## Recommended Local Test Commands

From plugin source folder:

```bash
chmod +x scripts/ogre
```

From target project root:

```bash
/path/to/ogre-plugin/scripts/ogre init
/path/to/ogre-plugin/scripts/ogre feature 107 --blocks 101,102
/path/to/ogre-plugin/scripts/ogre status 107
/path/to/ogre-plugin/scripts/ogre stop 107
```

Claude Code plugin test:

```bash
claude --plugin-dir /path/to/ogre-plugin
```

Then inside Claude Code:

```txt
/ogre:feature 107 --blocks 101,102
/ogre:status 107
/ogre:review-plan 107
/ogre:execute 107 --executor codex
/ogre:stop 107
```

Codex direct test, if supported by local setup:

```bash
codex exec -m gpt-5.5 - < .ai/.ogre/tmp/issue-107/execute-next-runner.md
```

---

## Non-Goals for MVP

Do not implement these first:

- complex TUI UI
- full reverse direction Codex TUI -> Claude execution
- multi-repository orchestration
- automatic PR creation
- automatic branch/worktree management
- automatic destructive cleanup
- advanced background job manager
- deep Laravel-specific static analysis

These can be added later.

---

## Final Principle

Ogre should make AI coding safer by enforcing this rule:

```txt
Plan with evidence.
Review the plan.
Execute one checklist item in a fresh context.
Validate.
Review the diff.
Repeat.
```

Do not let one long agent session plan, implement, review, and fix everything without checkpoints.

The shared memory is not Claude memory or Codex memory.

The shared memory is:

```txt
.ai/.ogre/state/
.ai/.ogre/plans/
.ai/.ogre/logs/
.ai/.ogre/reviews/
```
