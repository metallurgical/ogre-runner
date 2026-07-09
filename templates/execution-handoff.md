# Execution Handoff Prompt

Execute the approved execution plan exactly.

## Source Plan

Follow:

* Source plan path will be provided by the runner prompt.

# Main Goal

* Implement only the work described in the source plan.
* Do not re-plan the feature from scratch.
* Do not use `repo_map.md` as proof of implementation details. Use it only for orientation.

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
* If something is uncertain, mark it as `NEEDS INSPECTION` and stop before editing that part.

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
* Any remaining `NEEDS INSPECTION` items.

Then, mandatory, update the issue's knowledge base (the runner prompt gives its exact path, `.ai/.ogre/state/issue-<issue>-knowledge.md`). Follow the rules inside that file: revise the durable sections in place if you confirmed anything structural (stack, conventions, project structure, a real signature/route/column, a validation command, a gotcha), and append exactly one line to its Step Log describing what this step did plus the single most useful thing it learned. Revise in place, respect the per-section caps, don't append duplicates. Do this even if the step failed - the reason it failed is the most valuable gotcha for the next attempt. This file is read first by every later step, so it is how your knowledge reaches them without them re-deriving it.

Then, mandatory, run the task-id completion command given in the runner prompt (`ogre task-complete <task-id> --status passed|failed`) so the ledger reflects what actually happened. Do this even if you are the live Claude Code session doing the work directly, not just when running via a separate `codex`/`claude` CLI invocation. Skipping this step leaves the task stuck `pending` forever.

`--notes "..."` on that command is optional: it records a one-liner in the task ledger (shown in `ogre status`), useful as a per-attempt marker. The knowledge base above is what carries knowledge forward, so prefer updating that.

Then stop.
