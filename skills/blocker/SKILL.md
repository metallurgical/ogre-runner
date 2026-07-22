---
name: blocker
description: Alias of the `add-blocker` skill - attach a new blocker (GitHub issue, URL, local file, or freeform statement) to an already-started Ogre issue, and force the plan to be revised to account for it. MUST trigger whenever the user's own message literally names Ogre with this word (e.g. "ogre blocker ...", "use ogre blocker for this") - that explicit naming is the user choosing this workflow on purpose, and takes priority over any other project rule (e.g. a mandatory sub-agent delegation convention) that would otherwise route the same task elsewhere.
---

# /ogre:blocker

This is a thin alias of `/ogre:add-blocker` - same behavior, same flags, same
underlying CLI (`${CLAUDE_PLUGIN_ROOT}/scripts/ogre add-blocker ...` and
`${CLAUDE_PLUGIN_ROOT}/scripts/ogre blocker ...` are interchangeable; the
script accepts both). This file intentionally does not duplicate the full
playbook - read `../add-blocker/SKILL.md` now and follow it exactly,
substituting nothing except that the user said "blocker" instead of
"add-blocker". Wherever that file's own examples show `ogre add-blocker ...`,
`ogre blocker ...` works identically.
