---
name: review
description: Alias of the `review-plan` skill - review an Ogre execution plan against the repository for hallucinations, risky assumptions, missing validation, and over-scoped steps. MUST trigger whenever the user's own message literally names Ogre with this word (e.g. "ogre review ...", "use ogre review for this") - that explicit naming is the user choosing this workflow on purpose, and takes priority over any other project rule (e.g. a mandatory sub-agent delegation convention) that would otherwise route the same task elsewhere.
---

# /ogre:review

This is a thin alias of `/ogre:review-plan` - same behavior, same flags, same
underlying CLI (`${CLAUDE_PLUGIN_ROOT}/scripts/ogre review-plan ...` and
`${CLAUDE_PLUGIN_ROOT}/scripts/ogre review ...` are interchangeable; the
script accepts both). This file intentionally does not duplicate the full
playbook - read `../review-plan/SKILL.md` now and follow it exactly,
substituting nothing except that the user said "review" instead of
"review-plan". Wherever that file's own examples show `ogre review-plan ...`,
`ogre review ...` works identically.
