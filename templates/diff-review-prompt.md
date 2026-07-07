# Diff Review Prompt

Review only the current git diff for the active Ogre issue.

## Goals

Find:

* Real bugs.
* Broken tests or missing validation.
* Missing imports or wrong namespaces.
* Wrong method names or signatures.
* Wrong database tables, columns, or relationships.
* Security issues.
* Behavior changes outside the plan.
* Edge cases introduced by the diff.

## Rules

* Review only the diff.
* Do not suggest unrelated refactors.
* Do not review the whole project.
* Prioritize correctness over style.
* Categorize findings as:
  * `MUST FIX`
  * `SHOULD FIX`
  * `OPTIONAL`

## Output Format

# Diff Review

## MUST FIX

* Finding: Short problem.
  * Evidence: File/path/changed area.
  * Suggested correction: Short correction.

## SHOULD FIX

* Finding: Short problem.
  * Evidence: File/path/changed area.
  * Suggested correction: Short correction.

## OPTIONAL

* Finding: Short suggestion.
  * Suggested correction: Short correction.
