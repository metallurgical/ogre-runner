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

* If the working tree already has unrelated changes (not part of this plan) when you start - e.g. the user's own hand-edit or hotfix made alongside this step - do not stop and do not revert/touch them. Leave them as-is, do not attribute them to this step's own work, and mention them briefly in your final report and in this step's `--notes`. Only stop for this if a file looks genuinely alarming (a credential/secret, a half-finished destructive edit) rather than an ordinary incidental edit.
* Stop if validation fails.
* Stop if a `NEEDS INSPECTION` item cannot be verified from real code.
* Stop if blocker dependency is missing or incompatible.
