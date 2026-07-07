# Runner / Execution Prompt

Read and follow the execution handoff instructions from:

* `.ai/.ogre/prompts/execution-handoff.md`

Use this source plan:

* Source plan path will be provided by Ogre.

## Task

* Execute the next incomplete checklist item only.
* Do not execute more than one checklist item.
* Follow the handoff rules exactly.
* Use a fresh context/session when possible.
* Update the checklist item status in the source plan only after the work and validation are complete.
* Write a concise execution log to the log path provided by Ogre.
* Stop after reporting changed files and validation result.

## Safety

* Stop if the working tree contains unrelated changes that are not part of the plan.
* Stop if validation fails.
* Stop if a `NEEDS INSPECTION` item cannot be verified from real code.
* Stop if blocker dependency is missing or incompatible.
