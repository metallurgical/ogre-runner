# Plan Review Prompt

Review this implementation plan against the repository/codebase.

## Source Plan

The plan path will be provided by the runner prompt.

## Review Goals

Find:

* Hallucinated files, classes, routes, tables, columns, methods, config keys, or package APIs.
* Missing validation steps.
* Risky assumptions.
* Over-scoped work.
* Steps that should be split smaller.
* Blocker dependency issues.
* Any `NEEDS INSPECTION` item that should block execution.

## Rules

* Do not edit code.
* Do not rewrite the full plan unless explicitly requested.
* Return only problems and suggested corrections.
* Keep output compact.
* Categorize findings as:
  * `MUST FIX`
  * `SHOULD FIX`
  * `OPTIONAL`

## Output Format

# Plan Review

## MUST FIX

* Finding: Short problem.
  * Evidence: `path/file` or source plan section.
  * Suggested correction: Short correction.

## SHOULD FIX

* Finding: Short problem.
  * Evidence: `path/file` or source plan section.
  * Suggested correction: Short correction.

## OPTIONAL

* Finding: Short suggestion.
  * Suggested correction: Short correction.
