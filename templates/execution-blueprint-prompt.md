# Execution Blueprint Prompt

## Context

* Current issue: the issue/feature description will be provided by the runner prompt - a GitHub/GitLab/Bitbucket issue, a local file, or a freeform `--statement`. A freeform statement has no numeric issue number; that is expected, not a sign the issue is missing - treat the runner prompt's "Current Issue" content as the complete problem statement regardless of source.
* Blocked by:
  * Same as above, if any blockers were provided by the runner prompt.
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
* Keep output compact for execution handoff.

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

## Step Granularity

* Each execution step runs in its own fresh session (cold start + repo re-inspection), so a step whose real work is smaller than that overhead should be merged with an adjacent one.
* Merge adjacent steps into one ONLY when all of them are trivially small (a single line-level change, no new logic, no new file) AND touch the same file or a tightly coupled pair (e.g. bump a constant and update its one call site).
* Never merge steps that touch unrelated files, carry a `NEEDS INSPECTION` marker, are tagged `[BROWSER-CHECK]`, or would produce a diff too large to validate or revert as one unit.
* When unsure, keep them separate - small, auditable diffs matter more than saving a session.

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
* [ ] `[BROWSER-CHECK]` Any step whose validation requires actually rendering the page/app in a real browser (visual layout, interactive behavior) - not just reading the markup/CSS/JS. Tag it with this exact literal prefix. `ogre execute` runs a `[BROWSER-CHECK]` step in an isolated spawn like any other step, expecting the executor to verify it with a browser MCP (e.g. Playwright); if no browser MCP is detected for the executor it auto-falls back to `--main` so the step still completes in the current session. Steps that only need static inspection (grep the file, read the diff) are not `[BROWSER-CHECK]` - don't over-tag.

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
