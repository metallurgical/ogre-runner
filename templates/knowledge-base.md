<!--
  Ogre living knowledge base for one issue/job.
  READ THIS FIRST, before touching any code, every step.
  Then UPDATE it as the mandatory closing move of your step (alongside `ogre task-complete`).

  This is a head-start, not a cage. It exists so you don't burn tokens re-discovering
  what an earlier step already learned. You are still free to read the codebase whenever
  the task genuinely needs it - use judgement. And if anything here disagrees with the
  real code in front of you, the real code wins: fix the stale line here as you go.

  Rules that keep this file small enough to never rot the next session's context:
  - REVISE in place, do not append blindly. A fact that changed → replace it. A fact
    already here → don't restate it.
  - Respect the per-section caps below. Over the cap? Drop or merge the lowest-value
    line, don't grow the file.
  - Only durable, verified facts belong in the top sections. Guesses do NOT go here -
    if you didn't confirm it from real code, leave it out.
  - The Step Log is one line per step. When it passes 15 lines, fold anything still
    useful up into the durable sections and delete the oldest raw lines.

  Delete these HTML comments only if you must; they cost the next reader tokens, so
  leaving them is fine - they're the operating manual.
-->

# Knowledge — <issue>

## Stack & Conventions
<!-- cap: 10 bullets. Language/framework + versions, and the patterns THIS repo chose
     (Livewire vs Blade, Action classes vs fat controllers, naming casing, formatter). -->
- (none recorded yet)

## Project Structure
<!-- cap: 10 bullets. Where things live and what NOT to touch. Only load-bearing dirs/
     files a next step would otherwise grep to find. -->
- (none recorded yet)

## Verified Contracts
<!-- cap: 14 bullets. Real, CONFIRMED-from-code signatures / routes / DB columns / enum
     values / base classes to extend. This is the anti-hallucination gold - a fact here
     means the next step never has to re-open the file to check. Mark each with its source
     file so it can be re-verified: `App\Models\User: uses uuid PK (app/Models/User.php)`. -->
- (none recorded yet)

## How to Validate
<!-- cap: 6 bullets. The commands that ACTUALLY work in this repo: test runner + real
     invocation, lint, typecheck, build, and any setup a test needs (DB, queue). -->
- (none recorded yet)

## Gotchas & Decisions
<!-- cap: 8 bullets. Traps already hit, and deviations from the plan + the reason. The
     "I wish someone had told me" list. -->
- (none recorded yet)

## Step Log
<!-- One line per completed step, newest at the bottom. Format:
     `- [step N ✓|✗] what this step did + the single most useful thing it learned.`
     Rolling window of 15 lines max. When it overflows, distil still-useful facts up into
     the sections above, then drop the oldest lines. This is how the NEXT step knows what
     the PREVIOUS steps already did and already know. -->
- (none recorded yet)
