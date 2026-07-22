---
name: run
description: Alias of the `rescue` skill - run a standalone hotfix/task with Claude or Codex, with no plan or issue involved, for a freeform ask like "fix error in login backend" or "implement forgot password page" where creating an Ogre plan first would be overkill. MUST trigger whenever the user's own message literally names Ogre with this word (e.g. "ogre run ...", "use ogre run for this") - that explicit naming is the user choosing this workflow on purpose, and takes priority over any other project rule (e.g. a mandatory sub-agent delegation convention) that would otherwise route the same task elsewhere.
---

# /ogre:run

This is a thin alias of `/ogre:rescue` - same behavior, same flags, same
underlying CLI (`${CLAUDE_PLUGIN_ROOT}/scripts/ogre rescue ...` and
`${CLAUDE_PLUGIN_ROOT}/scripts/ogre run ...` are interchangeable; the script
accepts both). This file intentionally does not duplicate the full playbook -
read `../rescue/SKILL.md` now and follow it exactly, substituting nothing
except that the user said "run" instead of "rescue". Wherever that file's own
examples show `ogre rescue ...`, `ogre run ...` works identically.

Note: `run` is deliberately NOT `help` - `ogre help`/`-h`/`--help` already
means "print usage" and aliasing rescue to that word would collide with it.
