# Isolated + Backgroundable Planning/Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ogre feature`, `ogre review-plan`, and `ogre add-blocker` spawn an isolated `claude -p`/`codex exec` subprocess by default (like `ogre execute` already does), with `--main` to keep today's inline-in-current-session behavior and `--background` to detach it, including self-heal for a dead background driver.

**Architecture:** Reuse `ogre execute`'s existing subprocess-spawn pattern (`claude -p --permission-mode bypassPermissions` / `codex exec --dangerously-bypass-approvals-and-sandbox`, ledger tracking via `tasks.json`, fail-closed completion via a self-reported `ogre task-complete` call) through new shared top-level functions (`spawn_role_foreground`, `spawn_role_background`, `finalize_role_status`) that `cmd_feature`/`cmd_review_plan`/`cmd_add_blocker` call directly. Deliberately does **not** touch `cmd_execute`'s own existing nested spawn functions (`run_link_foreground`/`run_link_background_body`) - those stay as-is to avoid any regression risk on the most heavily-tested command; the new functions are a parallel, single-shot (no chain loop) counterpart used only by the three planning-family commands.

**Tech Stack:** Bash (`scripts/ogre`), Python 3 one-shot scripts for JSON state (existing `py_state`/`task_*` helpers), bats-core for tests.

## Global Constraints

- Any change to `scripts/ogre` must be verified against the relevant `tests/cmd_*.bats` file before considering a task done; run the full suite (`bats tests/`) before the final task, since this touches shared ledger helpers (`task_create`, `reap_task`).
- Every non-final assertion inside a bats `@test` must be written as `assertion || return 1` - this repo's bats only fails a test on its last command.
- No version bump in this plan - that happens separately, only when the user asks.
- Every codex spawn must keep using `--dangerously-bypass-approvals-and-sandbox` unconditionally (matches `execute`'s existing behavior) - do not add any sandboxed path.
- New heredocs written with `cat > "$x" <<EOF2` (unquoted) must escape literal backticks as `` \` `` - bash performs command substitution inside unquoted heredocs, and this repo already had a real bug from forgetting this (see `scripts/ogre` around the `add-blocker`/`feature` runner Rules sections).

---

### Task 1: Shared spawn infra + `ogre feature` isolation (default spawn, `--main`, `--background`)

**Files:**
- Modify: `scripts/ogre` - add new top-level functions right before `cmd_feature()` (currently at line 1644); modify `cmd_feature()` (lines 1644-1828).
- Test: `tests/cmd_feature.bats`

**Interfaces:**
- Produces (used by Tasks 2 and 3 too):
  - `finalize_role_status <tid> <rc> <expected_output_file>` - no return value; updates the ledger row for `<tid>`.
  - `spawn_role_foreground <tid> <runner> <logpath> <session_id> <executor> <model> <reasoning> <mcp_config> <expected_output_file>` - blocks, returns the subprocess's exit code.
  - `spawn_role_background <tid> <issue> <logdir> <runner> <logpath> <session_id> <executor> <model> <reasoning> <mcp_config> <expected_output_file>` - returns immediately (no meaningful return code), leaves the ledger row `status=running` with a `pid` set.
  - New ledger task `type` value: `"plan"` (feature's planning task). New `mode` values on that same ledger row: `"new"` (default isolated foreground) or `"background"` - `--main` never creates a ledger task at all (matches today's no-ledger-entry behavior for inline planning).

- [ ] **Step 1: Add the three shared functions**

Insert immediately before `cmd_feature() {` (line 1644):

```bash
# finalize_role_status <tid> <rc> <expected_output_file> - fail-closed
# completion check for a one-shot plan/review/replan task, mirroring
# cmd_execute's finalize_link_status (rc==0 alone never proves success -
# the domain signal is the subprocess's own `ogre task-complete` self-report)
# with one addition: a self-reported "passed" is downgraded to "failed" if
# the expected output file was never actually written - a model can't claim
# success without producing the file.
finalize_role_status() {
  local tid="$1" rc="$2" expected_output_file="$3"
  local current_status
  current_status="$(task_field "$tid" status)"
  if [ "$current_status" = "passed" ] && [ -n "$expected_output_file" ] && [ ! -s "$expected_output_file" ]; then
    task_update "$tid" "status=failed" "exit_code=$rc" "notes=Reported passed but $expected_output_file was never written"
    return
  fi
  if [ "$current_status" = "passed" ] || [ "$current_status" = "failed" ]; then
    task_update "$tid" "exit_code=$rc"
  else
    task_update "$tid" "status=failed" "exit_code=$rc"
  fi
}

# spawn_role_foreground <tid> <runner> <logpath> <session_id> <executor>
# <model> <reasoning> <mcp_config> <expected_output_file> - single-shot,
# blocking counterpart to cmd_execute's run_link_foreground (no chain loop -
# a plan/review/replan is always exactly one subprocess call). Streams to
# stdout and the log file. Returns the subprocess's own exit code.
spawn_role_foreground() {
  local tid="$1" runner="$2" logpath="$3" session_id="$4"
  local executor="$5" model="$6" reasoning="$7" mcp_config="$8" expected_output_file="$9"
  local rc
  set +e
  case "$executor" in
    codex)
      local -a codex_args=(exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox)
      [ -n "$model" ] && codex_args+=(-m "$model")
      [ -n "$reasoning" ] && codex_args+=(-c "model_reasoning_effort=$reasoning")
      codex "${codex_args[@]}" - < "$runner" | tee "$logpath"
      ;;
    claude)
      local -a claude_args=(-p --permission-mode bypassPermissions --session-id "$session_id")
      [ -n "$model" ] && claude_args+=(--model "$model")
      [ -n "$reasoning" ] && claude_args+=(--effort "$reasoning")
      [ -n "$mcp_config" ] && claude_args+=(--mcp-config "$mcp_config")
      claude "${claude_args[@]}" < "$runner" | tee "$logpath"
      ;;
  esac
  rc=$?
  set -e
  finalize_role_status "$tid" "$rc" "$expected_output_file"
  if [ "$executor" = "codex" ]; then
    local codex_sid
    codex_sid="$(grep -m1 '^session id: ' "$logpath" 2>/dev/null | sed 's/^session id: //')"
    [ -n "$codex_sid" ] && task_update "$tid" "session_id=$codex_sid"
  fi
  return "$rc"
}

# spawn_role_background <tid> <issue> <logdir> <runner> <logpath>
# <session_id> <executor> <model> <reasoning> <mcp_config>
# <expected_output_file> - detached counterpart to spawn_role_foreground.
# Mirrors cmd_execute's background scaffolding (disown, own process group
# via `set -m`, signal-trap forensic logging, exit-sentinel + pid files that
# reap_task/maybe_resume_stalled_plan rely on) but without execute's --all
# chain loop, since a plan/review/replan is never chained. Returns
# immediately; the ledger row is left `status=running` with a live `pid`.
spawn_role_background() {
  local tid="$1" issue="$2" logdir="$3" runner="$4" logpath="$5" session_id="$6"
  local executor="$7" model="$8" reasoning="$9" mcp_config="${10}" expected_output_file="${11}"
  task_update "$tid" "status=running"
  local exitfile="$RUNTIME/tmp/issue-$issue/$tid.exit"
  local pidfile="$RUNTIME/tmp/issue-$issue/$tid.pid"
  local driverlog="$logdir/background-driver-$tid.log"
  set -m
  (
    trap 'echo "$(date "+%Y-%m-%dT%H:%M:%S%z") DRIVER_SIGNAL HUP"; exit 129' HUP
    trap 'echo "$(date "+%Y-%m-%dT%H:%M:%S%z") DRIVER_SIGNAL TERM"; exit 143' TERM
    trap 'echo "$(date "+%Y-%m-%dT%H:%M:%S%z") DRIVER_SIGNAL INT"; exit 130' INT
    trap 'echo "$(date "+%Y-%m-%dT%H:%M:%S%z") DRIVER_EXIT rc=$?"' EXIT
    local rc
    case "$executor" in
      codex)
        local -a codex_args=(exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox)
        [ -n "$model" ] && codex_args+=(-m "$model")
        [ -n "$reasoning" ] && codex_args+=(-c "model_reasoning_effort=$reasoning")
        codex "${codex_args[@]}" - < "$runner" > "$logpath" 2>&1
        ;;
      claude)
        local -a claude_args=(-p --permission-mode bypassPermissions --session-id "$session_id")
        [ -n "$model" ] && claude_args+=(--model "$model")
        [ -n "$reasoning" ] && claude_args+=(--effort "$reasoning")
        [ -n "$mcp_config" ] && claude_args+=(--mcp-config "$mcp_config")
        claude "${claude_args[@]}" < "$runner" > "$logpath" 2>&1
        ;;
    esac
    rc=$?
    finalize_role_status "$tid" "$rc" "$expected_output_file"
    if [ "$executor" = "codex" ]; then
      local codex_sid
      codex_sid="$(grep -m1 '^session id: ' "$logpath" 2>/dev/null | sed 's/^session id: //')"
      [ -n "$codex_sid" ] && task_update "$tid" "session_id=$codex_sid"
    fi
    echo "$rc" > "$exitfile"
  ) > "$driverlog" 2>&1 &
  local pid=$!
  set +m
  echo "$pid" > "$pidfile"
  disown "$pid" 2>/dev/null || true
  task_update "$tid" "pid=$pid"
  log "Task $tid started in background (pid $pid)."
  log "Driver log: $driverlog"
  log "Check with: ogre status --task $tid"
}
```

- [ ] **Step 2: Add `--main`/`--background` flag parsing to `cmd_feature`**

Modify the local-var line and flag-parsing `case` block (lines 1646, 1656-1680):

```bash
  local current="" plan_name="" planner="" model="" reasoning="" statement="" name="" browser_check="false" iso="new"
```

Add one case arm alongside the existing ones:

```bash
      --main) iso="main"; shift ;;
      --background) iso="background"; shift ;;
```

- [ ] **Step 3: Generate the task id before the runner heredoc, and add a completion-instruction rule**

`cmd_feature` currently writes the runner heredoc (lines 1772-1805) before doing anything else task-related. A non-`--main` run needs the task id embedded in the heredoc text itself (so the spawned subprocess knows which id to call `task-complete` on), so the id must exist before the heredoc is written.

Right before the `runner="$RUNTIME/tmp/issue-$issue/plan-runner.md"` line (1772), add:

```bash
  local tid=""
  local completion_rule=""
  if [ "$iso" != "main" ]; then
    tid="$(new_task_id)"
    completion_rule="* Mandatory last step: once \`$plan\` is fully written, run \`$SCRIPT_DIR/ogre task-complete $tid --status passed\` if the plan is complete and usable, or \`--status failed\` if you could not produce one. Use that exact path - \`ogre\` alone is not guaranteed to be on PATH.
"
  fi
```

Then in the heredoc's `## Rules` section, change:

```bash
* Do not keep placeholder issue numbers from the template.
* Use real issue numbers and issue paths from this runner prompt.
${browser_check_rule}
EOF2
```

to:

```bash
* Do not keep placeholder issue numbers/paths from the planning template - use the real issue path given above under "Current Issue" instead.
* This may be a freeform \`--statement\` with no numeric issue number (just a slug and a local file) - that is normal, not a sign the issue is missing or needs escalation. Treat its full text as the complete problem statement.
${browser_check_rule}${completion_rule}
EOF2
```

(This also carries forward the freeform-statement wording fix already merged to `main` - keep it, don't revert it.)

- [ ] **Step 4: Branch on `iso` after the runner/state-write block, replacing the final log lines**

The function currently ends with (after `write_state ...` around line 1820):

```bash
  log ""
  print_job_summary "$issue"
  log ""
  log "Planning runner created: $runner"
  log "Planner: $planner ${model:+($model)}${reasoning:+ [reasoning: $reasoning]}"
  log "Next inside Claude Code: read $runner and create the plan."
}
```

Replace it with:

```bash
  log ""
  print_job_summary "$issue"
  log ""
  log "Planning runner created: $runner"
  log "Planner: $planner ${model:+($model)}${reasoning:+ [reasoning: $reasoning]}"

  if [ "$iso" = "main" ]; then
    log "Next inside Claude Code: read $runner and create the plan."
    return
  fi

  case "$planner" in
    codex) command -v codex >/dev/null 2>&1 || { err "codex CLI not found"; exit 1; } ;;
    claude) command -v claude >/dev/null 2>&1 || { err "claude CLI not found"; exit 1; } ;;
    *) err "Unsupported planner: $planner"; exit 1 ;;
  esac

  local plan_logpath session_id=""
  plan_logpath="$logdir/plan-$(date '+%Y%m%d-%H%M%S')-${tid:5:8}.log"
  [ "$planner" = "claude" ] && session_id="$(gen_uuid)"
  task_create "$tid" "$issue" "plan" "$planner" "$model" "$iso" "fresh" "$runner" "$plan_logpath" "pending" "$reasoning" ""
  [ -n "$session_id" ] && task_update "$tid" "session_id=$session_id"

  if [ "$iso" = "background" ]; then
    spawn_role_background "$tid" "$issue" "$logdir" "$runner" "$plan_logpath" "$session_id" "$planner" "$model" "$reasoning" "" "$plan"
    return
  fi

  task_update "$tid" "status=running"
  spawn_role_foreground "$tid" "$runner" "$plan_logpath" "$session_id" "$planner" "$model" "$reasoning" "" "$plan" || true
  local final_status
  final_status="$(task_field "$tid" status)"
  log ""
  log "Task $tid finished: $final_status"
  log ""
  print_job_summary "$issue"
}
```

(`|| true` on the foreground call: a non-zero exit from a failed plan shouldn't itself kill the outer script via `set -e` before the summary prints - matches the same pattern `cmd_execute` uses around its own foreground call.)

- [ ] **Step 5: Write the failing tests first**

Add to `tests/cmd_feature.bats` (after the existing `"feature --statement writes issue file, state and planning runner"` test):

```bash
@test "feature default (no flag) spawns an isolated claude session and marks the plan task passed" {
  run "${OGRE_BIN}" feature --statement "base feature" --name 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Task"*"finished: passed"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'plan')
print(t['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
  [ "$(task_json_field "${tid}" type)" = "plan" ] || return 1
  [ -f ".ai/.ogre/plans/issue-42.md" ] || return 1
}

@test "feature --main preserves today's inline behavior and creates no ledger task" {
  run "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Next inside Claude Code: read"* ]] || return 1
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/tasks.json'))))")" = "0" ] || return 1
}

@test "feature --background starts detached and the plan task eventually passes" {
  run "${OGRE_BIN}" feature --statement "base feature" --name 42 --background
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"started in background"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'plan')
print(t['id'])
")"
  for _ in $(seq 1 50); do
    [ "$(task_json_field "${tid}" status)" != "running" ] && break
    sleep 0.1
  done
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
}

@test "feature foreground fails closed when the planner exits 0 but never calls task-complete" {
  # The claude/codex mocks (tests/mocks/) exit 0 unconditionally unless told
  # to call task-complete themselves - a plain run with no mock instruction
  # to do so must not be silently treated as passed.
  MOCK_CLAUDE_SKIP_TASK_COMPLETE="true" run "${OGRE_BIN}" feature --statement "base feature" --name 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Task"*"finished: failed"* ]] || return 1
}
```

- [ ] **Step 6: Run the new tests to see them fail**

Run: `bats tests/cmd_feature.bats`
Expected: the four new tests FAIL (functions/flags don't exist yet), everything else in the file still passes.

Check `tests/mocks/` for how the existing `claude`/`codex` mocks decide whether to call `task-complete` - if there's no existing `MOCK_CLAUDE_SKIP_TASK_COMPLETE`-style hook, add one to `tests/mocks/claude` (and `tests/mocks/codex` if present) that skips the `task-complete` call when that env var is set, matching whatever mechanism the existing `cmd_execute.bats` fail-closed test already uses (see `"execute foreground fails closed when codex exits 0 but never calls task-complete"`) - reuse the same mechanism/name if one already exists instead of inventing a second one.

- [ ] **Step 7: Implement the code from Steps 1-4**

Apply exactly the edits described above to `scripts/ogre`.

- [ ] **Step 8: Run the tests again to confirm they pass**

Run: `bats tests/cmd_feature.bats`
Expected: all tests PASS, including every pre-existing test (default-mode change must not break anything that didn't explicitly rely on today's inline default - re-check any pre-existing test that asserted on the old default behavior without `--main`, and add `--main` to it if it was relying on inline execution).

- [ ] **Step 9: Commit**

```bash
git add scripts/ogre tests/cmd_feature.bats
git commit -m "feat: spawn ogre feature's planner as an isolated subprocess by default, add --main/--background"
```

---

### Task 2: `ogre review-plan` isolation (reuses Task 1's shared functions)

**Files:**
- Modify: `scripts/ogre` - `cmd_review_plan()` (lines 2008-2060).
- Test: `tests/cmd_review_plan.bats`

**Interfaces:**
- Consumes: `finalize_role_status`, `spawn_role_foreground`, `spawn_role_background` (Task 1).
- Produces: ledger task `type="review"`, `expected_output_file` = the review's own `$review_path`.

- [ ] **Step 1: Add `--main`/`--background` flags and `iso` local**

Change:

```bash
  local target="${1:-}" reviewer="" model="" reasoning=""
```

to:

```bash
  local target="${1:-}" reviewer="" model="" reasoning="" iso="new"
```

Add to the flag `case`:

```bash
      --main) iso="main"; shift ;;
      --background) iso="background"; shift ;;
```

- [ ] **Step 2: Generate tid + completion rule before the heredoc**

Before `runner="$RUNTIME/tmp/issue-$issue/plan-review-runner.md"`:

```bash
  local tid="" completion_rule=""
  if [ "$iso" != "main" ]; then
    tid="$(new_task_id)"
    completion_rule="* Mandatory last step: once \`$review_path\` is fully written, run \`$SCRIPT_DIR/ogre task-complete $tid --status passed\` if the review is complete, or \`--status failed\` if you could not produce one. Use that exact path - \`ogre\` alone is not guaranteed to be on PATH.
"
  fi
```

Add `${completion_rule}` at the end of the heredoc's `Rules:` section (after the existing `* If there are no blocking issues, say so clearly.` line, before `EOF2`).

- [ ] **Step 3: Replace the final log lines**

Current ending:

```bash
  log "Plan review runner created: $runner"
  log "Reviewer: $reviewer ${model:+($model)}${reasoning:+ [reasoning: $reasoning]}"
  log "Review output: $review_path"
}
```

Replace with:

```bash
  log "Plan review runner created: $runner"
  log "Reviewer: $reviewer ${model:+($model)}${reasoning:+ [reasoning: $reasoning]}"
  log "Review output: $review_path"

  if [ "$iso" = "main" ]; then
    return
  fi

  case "$reviewer" in
    codex) command -v codex >/dev/null 2>&1 || { err "codex CLI not found"; exit 1; } ;;
    claude) command -v claude >/dev/null 2>&1 || { err "claude CLI not found"; exit 1; } ;;
    *) err "Unsupported reviewer: $reviewer"; exit 1 ;;
  esac

  local review_logpath session_id="" review_logdir="$RUNTIME/logs/issue-$issue"
  mkdir -p "$review_logdir"
  review_logpath="$review_logdir/review-$(date '+%Y%m%d-%H%M%S')-${tid:5:8}.log"
  [ "$reviewer" = "claude" ] && session_id="$(gen_uuid)"
  task_create "$tid" "$issue" "review" "$reviewer" "$model" "$iso" "fresh" "$runner" "$review_logpath" "pending" "$reasoning" ""
  [ -n "$session_id" ] && task_update "$tid" "session_id=$session_id"

  if [ "$iso" = "background" ]; then
    spawn_role_background "$tid" "$issue" "$review_logdir" "$runner" "$review_logpath" "$session_id" "$reviewer" "$model" "$reasoning" "" "$review_path"
    return
  fi

  task_update "$tid" "status=running"
  spawn_role_foreground "$tid" "$runner" "$review_logpath" "$session_id" "$reviewer" "$model" "$reasoning" "" "$review_path" || true
  local final_status
  final_status="$(task_field "$tid" status)"
  log ""
  log "Task $tid finished: $final_status"
}
```

- [ ] **Step 4: Write the failing tests**

Add to `tests/cmd_review_plan.bats` (first check the file's existing setup helper for how a plan gets created before review-plan runs, and match it):

```bash
@test "review-plan default spawns an isolated session and marks the review task passed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" review-plan 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Task"*"finished: passed"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'review')
print(t['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
}

@test "review-plan --main preserves inline behavior and creates no ledger task" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" review-plan 42 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Review output:"* ]] || return 1
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/tasks.json'))))")" = "0" ] || return 1
}

@test "review-plan --background starts detached and the review task eventually passes" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" review-plan 42 --background
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"started in background"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'review')
print(t['id'])
")"
  for _ in $(seq 1 50); do
    [ "$(task_json_field "${tid}" status)" != "running" ] && break
    sleep 0.1
  done
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
}
```

- [ ] **Step 5: Run to see them fail, then implement Steps 1-3, then run again to confirm pass**

Run: `bats tests/cmd_review_plan.bats` (expect new tests failing, then all passing after implementation) - same cycle as Task 1.

- [ ] **Step 6: Commit**

```bash
git add scripts/ogre tests/cmd_review_plan.bats
git commit -m "feat: spawn ogre review-plan's reviewer as an isolated subprocess by default, add --main/--background"
```

---

### Task 3: `ogre add-blocker` isolation (also adds missing `--planner`/`--model`/`--reasoning` flags)

**Files:**
- Modify: `scripts/ogre` - `cmd_add_blocker()` (lines 1830-2007).
- Test: `tests/cmd_add_blocker.bats`

**Interfaces:**
- Consumes: `finalize_role_status`, `spawn_role_foreground`, `spawn_role_background` (Task 1).
- Produces: ledger task `type="replan"`.

**Context:** `add-blocker` today has no `--planner`/`--model`/`--reasoning` flags at all - re-planning just relies on whichever session/model happens to run it. Spawning a subprocess requires knowing which CLI/model to invoke, so this task also adds those three flags, defaulting to the issue's already-seeded planner (`state.json`'s `planner`/`model` fields, written by `ogre feature`) when not passed.

- [ ] **Step 1: Add flags and `iso` local**

Change:

```bash
  local blocker="" statement="" name="" force="false" remarks=""
```

to:

```bash
  local blocker="" statement="" name="" force="false" remarks="" planner="" model="" reasoning="" iso="new"
```

Add to the flag `case`:

```bash
      --planner) planner="${2:-}"; shift 2 ;;
      --model) model="${2:-}"; shift 2 ;;
      --reasoning) reasoning="${2:-}"; shift 2 ;;
      --main) iso="main"; shift ;;
      --background) iso="background"; shift ;;
```

After the flag-parsing loop, before the blocker/statement validation, resolve planner/model from state if not passed:

```bash
  [ -n "$planner" ] || planner="$(json_field "$spath" planner)"
  [ -n "$planner" ] || planner="claude"
  [ -n "$model" ] || model="$(json_field "$spath" model)"
  [ -n "$model" ] || model="claude-sonnet-5"
```

- [ ] **Step 2: Generate tid + completion rule before the heredoc**

Before `runner="$RUNTIME/tmp/issue-$issue/plan-runner.md"` (line 1964):

```bash
  local tid="" completion_rule=""
  if [ "$iso" != "main" ]; then
    tid="$(new_task_id)"
    completion_rule="* Mandatory last step: once \`$plan\` is fully revised, run \`$SCRIPT_DIR/ogre task-complete $tid --status passed\` if the revision is complete, or \`--status failed\` if you could not finish it. Use that exact path - \`ogre\` alone is not guaranteed to be on PATH.
"
  fi
```

Change the heredoc's `## Rules` section from:

```bash
* Do not implement code.
* Do not modify application files.
* Use the real issue/blocker paths given above under "Current Issue"/"Blocking Issues" - a freeform \`--statement\` issue has no numeric number and that is normal, not a sign anything is missing.
EOF2
```

to:

```bash
* Do not implement code.
* Do not modify application files.
* Use the real issue/blocker paths given above under "Current Issue"/"Blocking Issues" - a freeform \`--statement\` issue has no numeric number and that is normal, not a sign anything is missing.
${completion_rule}EOF2
```

- [ ] **Step 3: Replace the final log lines**

Current ending of the function (lines 2000-2006):

```bash
  log ""
  log "Blocker added: $bpath"
  log "State status reset to 'planning' for issue $issue."
  log "Re-planning runner created: $runner"
  log "Next inside Claude Code: read $runner and revise the plan at $plan."
}
```

Replace with:

```bash
  log ""
  log "Blocker added: $bpath"
  log "State status reset to 'planning' for issue $issue."
  log "Re-planning runner created: $runner"

  if [ "$iso" = "main" ]; then
    log "Next inside Claude Code: read $runner and revise the plan at $plan."
    return
  fi

  case "$planner" in
    codex) command -v codex >/dev/null 2>&1 || { err "codex CLI not found"; exit 1; } ;;
    claude) command -v claude >/dev/null 2>&1 || { err "claude CLI not found"; exit 1; } ;;
    *) err "Unsupported planner: $planner"; exit 1 ;;
  esac

  local replan_logpath session_id=""
  replan_logpath="$logdir/replan-$(date '+%Y%m%d-%H%M%S')-${tid:5:8}.log"
  [ "$planner" = "claude" ] && session_id="$(gen_uuid)"
  task_create "$tid" "$issue" "replan" "$planner" "$model" "$iso" "fresh" "$runner" "$replan_logpath" "pending" "$reasoning" ""
  [ -n "$session_id" ] && task_update "$tid" "session_id=$session_id"

  if [ "$iso" = "background" ]; then
    spawn_role_background "$tid" "$issue" "$logdir" "$runner" "$replan_logpath" "$session_id" "$planner" "$model" "$reasoning" "" "$plan"
    return
  fi

  task_update "$tid" "status=running"
  spawn_role_foreground "$tid" "$runner" "$replan_logpath" "$session_id" "$planner" "$model" "$reasoning" "" "$plan" || true
  local final_status
  final_status="$(task_field "$tid" status)"
  log ""
  log "Task $tid finished: $final_status"
}
```

- [ ] **Step 4: Write the failing tests**

Add to `tests/cmd_add_blocker.bats`:

```bash
@test "add-blocker default spawns an isolated session and marks the replan task passed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" add-blocker 42 --statement "new blocker"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Task"*"finished: passed"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'replan')
print(t['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
}

@test "add-blocker --main preserves inline behavior and creates no ledger task" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" add-blocker 42 --statement "new blocker" --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Re-planning runner created:"* ]] || return 1
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/tasks.json'))))")" = "0" ] || return 1
}

@test "add-blocker --background starts detached and the replan task eventually passes" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" add-blocker 42 --statement "new blocker" --background
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"started in background"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'replan')
print(t['id'])
")"
  for _ in $(seq 1 50); do
    [ "$(task_json_field "${tid}" status)" != "running" ] && break
    sleep 0.1
  done
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
}
```

- [ ] **Step 5: Run to see them fail, implement Steps 1-3, run again to confirm pass**

Run: `bats tests/cmd_add_blocker.bats`

- [ ] **Step 6: Commit**

```bash
git add scripts/ogre tests/cmd_add_blocker.bats
git commit -m "feat: spawn ogre add-blocker's re-planner as an isolated subprocess by default, add --planner/--model/--reasoning/--main/--background"
```

---

### Task 4: Self-heal for a dead background plan/review/replan driver

**Files:**
- Modify: `scripts/ogre` - add `maybe_resume_stalled_plan()` near `maybe_resume_stalled_chain` (currently lines 451+); wire it into `_status_render` (both branches, near lines 3106 and 3145).
- Test: `tests/cmd_status.bats`

**Interfaces:**
- Consumes: `task_field`, `tasks_path`, `new_task_id`, `gen_uuid`, `get_plan_path`, `task_create`, `task_update`, `spawn_role_background` (Task 1), `log`.
- Produces: `maybe_resume_stalled_plan <issue>` - no return value; relaunches a dead background plan/review/replan task in place if one is found stalled.

- [ ] **Step 1: Add `maybe_resume_stalled_plan`**

Insert as a sibling function, right after `maybe_resume_stalled_chain` ends:

```bash
# maybe_resume_stalled_plan <issue> - self-heal counterpart to
# maybe_resume_stalled_chain, for a one-shot plan/review/replan --background
# task instead of an --all execute chain. Looks at the most recent
# plan/review/replan task for this issue launched with mode=background; if
# reap_task already flipped it to "failed" via its dead-pid branch (no exit
# sentinel - the process vanished without reporting) and the expected output
# file still doesn't exist, relaunch the identical call. Idempotent the same
# way maybe_resume_stalled_chain is: the relaunch's own new task shows up
# "running" with a live pid immediately, so a status call moments later sees
# that and does nothing.
maybe_resume_stalled_plan() {
  local issue="$1"
  local tid ttype executor model reasoning mcp_config runner logpath session_id pid_status
  { read -r tid; read -r ttype; read -r executor; read -r model; read -r reasoning; read -r mcp_config; read -r runner; read -r logpath; read -r session_id; read -r pid_status; } < <(python3 -c '
import json
try:
    tasks = json.load(open("'"$(tasks_path)"'"))
except Exception:
    tasks = []
cand = [t for t in tasks if t.get("issue") == "'"$issue"'" and t.get("type") in ("plan", "review", "replan") and t.get("mode") == "background"]
cand.sort(key=lambda t: t.get("created_at") or "")
if cand:
    t = cand[-1]
    for f in ("id", "type", "executor", "model", "reasoning", "mcp_config", "runner", "log_path", "session_id", "status"):
        print(t.get(f) or "")
else:
    print("\n" * 9)
')
  [ -n "$tid" ] || return 0
  [ "$pid_status" = "failed" ] || return 0

  local expected_output
  case "$ttype" in
    plan|replan) expected_output="$(get_plan_path "$issue" 2>/dev/null || true)" ;;
    review) expected_output="$RUNTIME/reviews/issue-$issue/plan-review.md" ;;
    *) return 0 ;;
  esac
  [ -n "$expected_output" ] || return 0
  [ -s "$expected_output" ] && return 0

  log "Task $tid ($ttype) was running in background but its process died without finishing - relaunching."
  local new_tid new_logpath new_session=""
  new_tid="$(new_task_id)"
  mkdir -p "$RUNTIME/logs/issue-$issue"
  new_logpath="$RUNTIME/logs/issue-$issue/${ttype}-$(date '+%Y%m%d-%H%M%S')-${new_tid:5:8}.log"
  [ "$executor" = "claude" ] && new_session="$(gen_uuid)"
  task_create "$new_tid" "$issue" "$ttype" "$executor" "$model" "background" "fresh" "$runner" "$new_logpath" "pending" "$reasoning" "$mcp_config"
  [ -n "$new_session" ] && task_update "$new_tid" "session_id=$new_session"
  spawn_role_background "$new_tid" "$issue" "$RUNTIME/logs/issue-$issue" "$runner" "$new_logpath" "$new_session" "$executor" "$model" "$reasoning" "$mcp_config" "$expected_output"
}
```

- [ ] **Step 2: Wire it into `_status_render`**

In the single-target branch (around line 3106):

```bash
      reap_all_tasks
      sync_state_from_plan "$issue"
      maybe_resume_stalled_chain "$issue"
      maybe_resume_stalled_plan "$issue"
      seed_knowledge "$issue"
```

In the all-issues loop branch (around line 3145):

```bash
      case "$fstatus" in
        completed|stopped) ;;
        *) sync_state_from_plan "$fissue"; maybe_resume_stalled_chain "$fissue"; maybe_resume_stalled_plan "$fissue" ;;
      esac
```

- [ ] **Step 3: Write the failing test**

Add to `tests/cmd_status.bats` (check the file's existing helpers for how a background task's pid gets killed to simulate a dead driver - reuse whatever `cmd_execute.bats`'s self-heal test already uses, e.g. a helper that kills the recorded pid without leaving an exit sentinel):

```bash
@test "status self-heals a dead background plan driver (no exit sentinel) by relaunching it" {
  run "${OGRE_BIN}" feature --statement "base feature" --name 42 --background
  [ "${status}" -eq 0 ] || return 1
  local tid pid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'plan')
print(t['id'])
")"
  for _ in $(seq 1 50); do
    pid="$(task_json_field "${tid}" pid)"
    [ -n "${pid}" ] && [ "${pid}" != "None" ] && break
    sleep 0.1
  done
  kill -9 "${pid}" 2>/dev/null || true
  rm -f ".ai/.ogre/tmp/issue-42/${tid}.exit"
  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"was running in background but its process died"* ]] || return 1
  local new_tid
  new_tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
plan_tasks = [t for t in tasks if t.get('type') == 'plan']
plan_tasks.sort(key=lambda t: t.get('created_at') or '')
print(plan_tasks[-1]['id'])
")"
  [ "${new_tid}" != "${tid}" ] || return 1
  for _ in $(seq 1 50); do
    [ "$(task_json_field "${new_tid}" status)" != "running" ] && break
    sleep 0.1
  done
  [ "$(task_json_field "${new_tid}" status)" = "passed" ] || return 1
  [ -f ".ai/.ogre/plans/issue-42.md" ] || return 1
}
```

- [ ] **Step 4: Run to see it fail, implement Steps 1-2, run again to confirm pass**

Run: `bats tests/cmd_status.bats`

- [ ] **Step 5: Commit**

```bash
git add scripts/ogre tests/cmd_status.bats
git commit -m "feat: ogre status self-heals a dead background plan/review/replan driver"
```

---

### Task 5: Update `SKILL.md`s, usage text, and README

**Files:**
- Modify: `skills/feature/SKILL.md`, `skills/review-plan/SKILL.md`, `skills/add-blocker/SKILL.md`, `scripts/ogre` (usage text near lines 16-22), `README.md`.

- [ ] **Step 1: `skills/feature/SKILL.md`**

Replace step 3-5 of the `## Behavior` section (currently: "Read the generated planning runner" / "Create the plan exactly as requested by that runner" / "Write the final plan to...") with:

```markdown
3. By default the helper spawns an isolated planner subprocess itself and blocks until it finishes (same isolation model as `ogre execute`) - you do not read the runner or write the plan yourself. Wait for the command to return, then read its "Task ... finished: passed|failed" line.
   - Pass `--background` to return immediately instead of waiting - report the task id to the user and tell them to check `ogre status <issue>` later; do not poll in a loop yourself.
   - Pass `--main` only if the user explicitly wants the planning done inline in this session (spends this session's own context, loses isolation) - in that case, and only then, read `.ai/.ogre/tmp/issue-<number>/plan-runner.md` yourself and create the plan exactly as it requests, same as before this flag existed.
4. If the run failed (or `--background` is still running), do not treat the plan as ready - check `.ai/.ogre/logs/issue-<number>/` for the planner's own log before deciding what to do next.
```

Also add to the "Optional flags" list:

```markdown
- `--main` — run planning inline in this session instead of spawning an isolated subprocess (loses context isolation; only pass when the user explicitly wants that).
- `--background` — spawn the isolated subprocess detached; returns immediately instead of waiting for the plan to finish.
```

- [ ] **Step 2: `skills/review-plan/SKILL.md` and `skills/add-blocker/SKILL.md`**

Read each file's current `## Behavior` section and apply the same shape of change as Step 1: replace "read the runner and do the review/re-plan yourself" language with "the helper spawns an isolated subprocess by default and blocks; `--background` returns immediately; `--main` preserves doing it yourself inline," and add `--main`/`--background` to each file's flags list.

- [ ] **Step 3: `scripts/ogre` usage text**

Update the three usage lines (near lines 16-22) to append `[--main|--background]` to `ogre feature`, `ogre review-plan`, and `ogre add-blocker`'s usage strings, matching how `ogre execute`'s usage line already shows `[--main|--background]`.

- [ ] **Step 4: README**

Add a short paragraph near the existing `[BROWSER-CHECK]`/isolation documentation (the section touched earlier for the `--all`/`--background` browser-check split) explaining that `feature`/`review-plan`/`add-blocker` now default to the same isolated-spawn model as `execute`, with `--main` as the explicit opt-out and `--background` for detached runs, and that `ogre status` self-heals a dead background driver for these the same way it does for `--all` execute chains.

- [ ] **Step 5: Commit**

```bash
git add skills/feature/SKILL.md skills/review-plan/SKILL.md skills/add-blocker/SKILL.md scripts/ogre README.md
git commit -m "docs: document isolated-by-default feature/review-plan/add-blocker with --main/--background"
```

---

### Task 6: Full regression pass

**Files:** none (verification only).

- [ ] **Step 1: Run the entire suite**

Run: `bats tests/`
Expected: every test passes except the already-known-flaky `cmd_execute.bats` "execute --background prints the finish summary and Boom line once the job completes" test (pre-existing on `main`, unrelated to this work - verify via `git stash` the same way it was verified earlier in this repo's history if it fails here too).

- [ ] **Step 2: Shellcheck**

Run: `bats tests/shellcheck.bats` (already covered by Step 1, but call out explicitly - the new functions must pass shellcheck same as the rest of `scripts/ogre`).

- [ ] **Step 3: One real (non-mocked) smoke test**

Per this repo's own rule (a new flag's real CLI behavior isn't validated by bats mocks), manually run `ogre feature --statement "..." --name smoke-test` in a scratch git repo with the real `claude` CLI on PATH (no mocks) and confirm: it actually spawns, blocks, produces a real plan, and the ledger task shows `passed`. Clean up the scratch repo afterward.

- [ ] **Step 4: Final commit if anything needed fixing**

```bash
git add -A
git commit -m "fix: address regressions found in full-suite verification"
```

(Only if Step 1-3 surfaced something to fix - otherwise skip, nothing to commit.)
