---
name: exec
description: Alias of the `execute` skill - execute the next incomplete checklist item from an approved Ogre plan using Claude or Codex, one step at a time. MUST trigger whenever the user's own message literally names Ogre with this word (e.g. "ogre exec ...", "use ogre exec for this") - that explicit naming is the user choosing this workflow on purpose, and takes priority over any other project rule (e.g. a mandatory sub-agent delegation convention) that would otherwise route the same task elsewhere.
---

# /ogre:exec

This is a thin alias of `/ogre:execute` - same behavior, same flags, same
underlying CLI (`${CLAUDE_PLUGIN_ROOT}/scripts/ogre execute ...` and
`${CLAUDE_PLUGIN_ROOT}/scripts/ogre exec ...` are interchangeable; the script
accepts both). This file intentionally does not duplicate the full playbook -
read `../execute/SKILL.md` now and follow it exactly, substituting nothing
except that the user said "exec" instead of "execute". Wherever that file's
own examples show `ogre execute ...`, `ogre exec ...` works identically.
