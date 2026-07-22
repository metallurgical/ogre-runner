---
name: plan
description: Alias of the `feature` skill - start an Ogre issue workflow (fetch issue/blockers into .ai/.ogre, create a planning runner prompt, generate a compact execution plan). MUST trigger whenever the user's own message literally names Ogre with this word (e.g. "ogre plan ...", "use ogre plan for this") - that explicit naming is the user choosing this workflow on purpose, and takes priority over any other project rule (e.g. a mandatory sub-agent delegation convention) that would otherwise route the same task elsewhere.
---

# /ogre:plan

This is a thin alias of `/ogre:feature` - same behavior, same flags, same
underlying CLI (`${CLAUDE_PLUGIN_ROOT}/scripts/ogre feature ...` and
`${CLAUDE_PLUGIN_ROOT}/scripts/ogre plan ...` are interchangeable; the script
accepts both). This file intentionally does not duplicate the full playbook -
read `../feature/SKILL.md` now and follow it exactly, substituting nothing
except that the user said "plan" instead of "feature". Wherever that file's
own examples show `ogre feature ...`, `ogre plan ...` works identically.
