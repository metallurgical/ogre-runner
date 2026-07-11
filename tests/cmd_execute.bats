load test_helper

@test "execute with no target and no --job errors" {
  run "${OGRE_BIN}" execute
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Missing issue, plan path, or --job"* ]] || return 1
}

@test "execute rejects unknown option" {
  run "${OGRE_BIN}" execute 42 --bogus
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Unknown option: --bogus"* ]] || return 1
}

@test "execute errors when the plan does not exist" {
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Plan not found:"* ]] || return 1
}

@test "execute backfills state when a plan exists but state.json doesn't (ad-hoc plan, not created via ogre feature)" {
  write_plan_with_steps 42 "First step"
  [ ! -f ".ai/.ogre/state/issue-42.json" ] || return 1

  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"backfilling state"* ]] || return 1
  [[ "${output}" == *"Task"*"finished: passed"* ]] || return 1
  [ -f ".ai/.ogre/state/issue-42.json" ] || return 1
  # single-step plan: the one step passes, so the job rolls straight to completed
  [ "$(state_field 42 status)" = "completed" ] || return 1
}

@test "execute --job with unknown job id errors" {
  run "${OGRE_BIN}" execute --job job-does-not-exist
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No issue found with job id job-does-not-exist"* ]] || return 1
}

@test "execute rejects an unsupported executor" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --executor bogus
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Unsupported executor: bogus"* ]] || return 1
}

@test "execute errors when the claude CLI is missing (default executor)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  # Real PATH minus the mocks dir - codex/claude mocks are the only ones on PATH we control.
  run env PATH="/usr/bin:/bin" "${OGRE_BIN}" execute 42
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"claude CLI not found"* ]] || return 1
}

@test "execute errors when the codex CLI is missing" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  # Real PATH minus the mocks dir - codex/claude mocks are the only ones on PATH we control.
  run env PATH="/usr/bin:/bin" "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"codex CLI not found"* ]] || return 1
}

@test "execute --main prints instructions and does not spawn a subprocess" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Mode: --main."* ]] || return 1
  [[ "${output}" == *"recorded as pending"* ]] || return 1
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  [ "$(task_json_field "${tid}" status)" = "pending" ] || return 1
}

@test "execute foreground default (claude) runs the lowest pending step and marks it passed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Executor: claude"* ]] || return 1
  [[ "${output}" == *"Task"*"finished: passed"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('step_index') == 1)
print(t['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
  [ -n "$(task_json_field "${tid}" session_id)" ] || return 1
  [ "$(state_field 42 status)" = "executing" ] || return 1
}

@test "execute foreground prints the job summary automatically after finishing a step" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Task"*"finished: passed"* ]] || return 1
  [[ "${output}" == *"Steps Completed"* ]] || return 1
  [[ "${output}" == *"Steps Remaining"* ]] || return 1
  [[ "${output}" == *"Second step"* ]] || return 1
  [[ "${output}" != *"Boom!"* ]] || return 1
}

@test "execute prints a Boom line only once the whole job is completed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Boom! Issue 42 has been resolved."* ]] || return 1
}

@test "execute --background prints the finish summary and Boom line once the job completes" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  run "${OGRE_BIN}" execute 42 --background
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"started in background"* ]] || return 1
  [[ "${output}" == *"Task"*"finished: passed"* ]] || return 1
  [[ "${output}" == *"Boom! Issue 42 has been resolved."* ]] || return 1
  [[ "${output}" == *"Steps Completed"* ]] || return 1
}

@test "execute foreground with --executor claude passes --permission-mode bypassPermissions (headless -p has no TTY to prompt)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ] || return 1
  [ -f "${args_file}" ] || return 1
  [[ "$(cat "${args_file}")" == *"--permission-mode bypassPermissions"* ]] || return 1
}

@test "execute --background with --executor claude passes --permission-mode bypassPermissions" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --background
  [ "${status}" -eq 0 ] || return 1
  [ -f "${args_file}" ] || return 1
  [[ "$(cat "${args_file}")" == *"--permission-mode bypassPermissions"* ]] || return 1
}

@test "execute foreground with --executor codex runs the lowest pending step and marks it passed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Executor: codex"* ]] || return 1
  [[ "${output}" == *"Task"*"finished: passed"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('step_index') == 1)
print(t['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
  [ "$(task_json_field "${tid}" session_id)" = "mock-codex-session-1234" ] || return 1
  [ "$(state_field 42 status)" = "executing" ] || return 1
}

@test "execute foreground with --executor codex passes --sandbox workspace-write (default sandbox is read-only, silently no-ops writes)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  local args_file="${TEST_TMP}/codex-args.log"
  MOCK_CODEX_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 0 ] || return 1
  [ -f "${args_file}" ] || return 1
  [[ "$(cat "${args_file}")" == *"--sandbox workspace-write"* ]] || return 1
}

@test "execute --background with --executor codex passes --sandbox workspace-write" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  local args_file="${TEST_TMP}/codex-args.log"
  MOCK_CODEX_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --executor codex --background
  [ "${status}" -eq 0 ] || return 1
  [ -f "${args_file}" ] || return 1
  [[ "$(cat "${args_file}")" == *"--sandbox workspace-write"* ]] || return 1
}

@test "execute --reasoning passes --effort to claude" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --reasoning high
  [ "${status}" -eq 0 ] || return 1
  [[ "$(cat "${args_file}")" == *"--effort high"* ]] || return 1
}

@test "execute --reasoning passes -c model_reasoning_effort= to codex" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  local args_file="${TEST_TMP}/codex-args.log"
  MOCK_CODEX_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --executor codex --reasoning low
  [ "${status}" -eq 0 ] || return 1
  [[ "$(cat "${args_file}")" == *"-c model_reasoning_effort=low"* ]] || return 1
}

@test "execute without --reasoning omits the effort flag entirely (uses the CLI's own default, not forced by Ogre)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  local claude_args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${claude_args_file}" run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ] || return 1
  [[ "$(cat "${claude_args_file}")" != *"--effort"* ]] || return 1

  "${OGRE_BIN}" feature --statement "base feature" --name 43
  write_plan_with_steps 43 "Only step"
  local codex_args_file="${TEST_TMP}/codex-args.log"
  MOCK_CODEX_ARGS_FILE="${codex_args_file}" run "${OGRE_BIN}" execute 43 --executor codex
  [ "${status}" -eq 0 ] || return 1
  [[ "$(cat "${codex_args_file}")" != *"model_reasoning_effort"* ]] || return 1
}

@test "execute foreground fails closed when codex exits 0 but never calls task-complete" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  export MOCK_CODEX_SKIP_COMPLETE=1
  run "${OGRE_BIN}" execute 42 --executor codex
  # rc==0 alone never proves the domain task passed - if the subprocess
  # never wrote its own status, finalize_link_status must fail closed
  # instead of guessing "passed" from the bare exit code.
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Task"*"finished: failed"* ]] || return 1
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  [ "$(task_json_field "${tid}" status)" = "failed" ] || return 1
  [ "$(task_json_field "${tid}" exit_code)" = "0" ] || return 1
}

@test "execute leaves a ledger-passed step out of pending_steps even if its plan checkbox was never ticked" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ] || return 1
  # The mock codex marks the task passed via `ogre task-complete` but never
  # edits the plan file, so "First step"'s checkbox is still unticked. The
  # ledger-passed signal alone must still be enough to advance past it.
  [ "$(state_field 42 current_step)" = "Second step" ] || return 1
  local pending
  pending="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/issue-42.json'))['pending_steps'])")"
  [[ "${pending}" != *"First step"* ]] || return 1
}

@test "execute foreground with a failing codex run marks the task failed and exits non-zero" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  export MOCK_CODEX_EXIT=7
  run "${OGRE_BIN}" execute 42 --executor codex
  # `set -e` aborts cmd_execute the instant run_link_foreground returns
  # non-zero, so the script's own exit code is the mock's raw exit code
  # (not massaged to 1), and the "Task ... finished: ..." summary line
  # further down is never reached - only the ledger write happens.
  [ "${status}" -eq 7 ] || return 1
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  [ "$(task_json_field "${tid}" status)" = "failed" ] || return 1
  [ "$(task_json_field "${tid}" exit_code)" = "7" ] || return 1
}

@test "execute falls back a [BROWSER-CHECK] step to --main (out-of-order --step) when no browser MCP" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "[BROWSER-CHECK] Verify the page renders correctly"
  # Mock `claude mcp list` reports no browser MCP, so the browser-check step
  # can't run isolated -> auto-fall back to --main (still completes here).
  run "${OGRE_BIN}" execute 42 --step 2 --yes
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"[BROWSER-CHECK]"* ]] || return 1
  [[ "${output}" == *"no browser MCP was detected"* ]] || return 1
  [[ "${output}" == *"Falling back to --main"* ]] || return 1
  [[ "${output}" == *"Mode: --main."* ]] || return 1
  # Fell back before spawning anything - task recorded pending, not run.
  local tid2
  tid2="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('step_index') == 2)
print(t['id'])
")"
  [ "$(task_json_field "${tid2}" status)" = "pending" ] || return 1
}

@test "execute --main runs a [BROWSER-CHECK] step fine (no CLI subprocess involved)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the page renders correctly"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Mode: --main."* ]] || return 1
}

@test "execute --all stops when next step is [BROWSER-CHECK] and no browser MCP is detected" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the page renders correctly" "Second step"
  # No browser_mcp configured and the mock `claude mcp list` reports none, so
  # the chain can't verify a browser-check step in isolation -> it stops.
  run "${OGRE_BIN}" execute 42 --all --yes
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"[BROWSER-CHECK]"* ]] || return 1
  [[ "${output}" == *"no browser MCP was detected"* ]] || return 1
  [[ "${output}" == *"--main"* ]] || return 1
  # Refused before spawning anything - the seeded per-step tasks (from
  # sync_state_from_plan) exist but none was ever set running/passed/failed.
  local statuses
  statuses="$(python3 -c "import json; print([t.get('status') for t in json.load(open('.ai/.ogre/state/tasks.json'))])")"
  [[ "${statuses}" != *"running"* ]] || return 1
}

@test "execute --all does NOT stop on [BROWSER-CHECK] when a browser MCP is configured" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the page renders correctly" "Second step"
  # A configured browser MCP means the spawned session can verify it in
  # isolation, so the up-front guard must NOT fire. --main keeps the mock from
  # actually chaining (which never ticks plan checkboxes) while still exercising
  # the guard decision.
  run "${OGRE_BIN}" execute 42 --all --main --mcp-config /tmp/fake-mcp.json
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" != *"no browser MCP was detected"* ]] || return 1
}

@test "execute --all retries a failed [BROWSER-CHECK] with ad-hoc [AUTO-FIX] attempts, capped at 2, then marks it failed with a reason" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the modal renders"
  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" MOCK_CLAUDE_STATUS=failed \
    run "${OGRE_BIN}" execute 42 --all --mcp-config /tmp/fake-mcp.json
  [ "${status}" -eq 1 ] || return 1
  # Real retries happened: more than just the one initial spawn.
  local call_count
  call_count="$(wc -l < "${args_file}")"
  [ "${call_count}" -ge 3 ] || return 1
  local plan_content
  plan_content="$(cat .ai/.ogre/plans/issue-42.md)"
  [[ "${plan_content}" == *"[AUTO-FIX 1/2 fp:"* ]] || return 1
  [[ "${plan_content}" == *"[AUTO-FIX 2/2 fp:"* ]] || return 1
  [[ "${plan_content}" != *"[AUTO-FIX 3/2 fp:"* ]] || return 1
  [[ "${output}" == *"still failing after 2 ad-hoc"* ]] || return 1
  # The stop message and the ledger note both carry the actual last failure
  # (from the failed attempt's own log tail), not just a "go read the logs"
  # pointer - the mock claude's log always contains this line.
  [[ "${output}" == *"Last verification failure:"* ]] || return 1
  [[ "${output}" == *"Mock claude -p output"* ]] || return 1
  # The original [BROWSER-CHECK] item's own ledger task ends up explicitly
  # failed with a reason, not stuck at "pending" forever.
  local browser_check_status browser_check_notes
  browser_check_status="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = [x for x in tasks if x.get('issue')=='42' and (x.get('step') or '').startswith('[BROWSER-CHECK]')]
print(t[0]['status'] if t else 'MISSING')
")"
  browser_check_notes="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = [x for x in tasks if x.get('issue')=='42' and (x.get('step') or '').startswith('[BROWSER-CHECK]')]
print(t[0].get('notes') or '' if t else '')
")"
  [ "${browser_check_status}" = "failed" ] || return 1
  [[ "${browser_check_notes}" == *"Last verification failure:"* ]] || return 1
  [[ "${browser_check_notes}" == *"Mock claude -p output"* ]] || return 1
}

@test "execute --all: ad-hoc [AUTO-FIX] steps don't inflate the step count status/task-list show the user" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the modal renders"
  MOCK_CLAUDE_STATUS=failed run "${OGRE_BIN}" execute 42 --all --mcp-config /tmp/fake-mcp.json
  [ "${status}" -eq 1 ] || return 1
  local plan_content
  plan_content="$(cat .ai/.ogre/plans/issue-42.md)"
  [[ "${plan_content}" == *"[AUTO-FIX 1/2 fp:"* ]] || return 1
  [[ "${plan_content}" == *"[AUTO-FIX 2/2 fp:"* ]] || return 1

  # "Steps Total"/"Steps (N):" must stay at the 1 originally-planned item -
  # the 2 ad-hoc auto-fix attempts are internal retries, not new plan steps
  # (this is the exact "plan started at 4 steps, suddenly shows 6" confusion
  # this behavior exists to avoid).
  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Steps Total"*"1"* ]] || return 1
  [[ "${output}" == *"Steps (1):"* ]] || return 1
  [[ "${output}" == *"Auto-fixes (2, internal):"* ]] || return 1

  local job_id
  job_id="$(state_field 42 job_id)"
  run "${OGRE_BIN}" task-list "${job_id}"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Steps: 1  (+2 internal auto-fix)"* ]] || return 1
  [[ "${output}" == *"auto-fix"* ]] || return 1
}

@test "execute --all does not auto-fix a failed step that is not [BROWSER-CHECK] - stops immediately, same as before" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Just a normal step"
  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" MOCK_CLAUDE_STATUS=failed \
    run "${OGRE_BIN}" execute 42 --all
  [ "${status}" -eq 1 ] || return 1
  local call_count
  call_count="$(wc -l < "${args_file}")"
  [ "${call_count}" -eq 1 ] || return 1
  local plan_content
  plan_content="$(cat .ai/.ogre/plans/issue-42.md)"
  [[ "${plan_content}" != *"AUTO-FIX"* ]] || return 1
}

@test "execute --all --executor codex retries a failed [BROWSER-CHECK] with ad-hoc [AUTO-FIX] attempts, keeping the unsandboxed bypass scoped to only the [BROWSER-CHECK] attempts, never the [AUTO-FIX] step itself" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the modal renders"
  local args_file="${TEST_TMP}/codex-args.log"
  MOCK_CODEX_ARGS_FILE="${args_file}" MOCK_CODEX_STATUS=failed \
    run "${OGRE_BIN}" execute 42 --all --executor codex --codex-unsandboxed-browser-check
  [ "${status}" -eq 1 ] || return 1
  # Real retries happened: more than just the one initial spawn.
  local call_count
  call_count="$(wc -l < "${args_file}")"
  [ "${call_count}" -ge 3 ] || return 1
  local plan_content
  plan_content="$(cat .ai/.ogre/plans/issue-42.md)"
  [[ "${plan_content}" == *"[AUTO-FIX 1/2 fp:"* ]] || return 1
  [[ "${plan_content}" == *"[AUTO-FIX 2/2 fp:"* ]] || return 1
  [[ "${plan_content}" != *"[AUTO-FIX 3/2 fp:"* ]] || return 1
  [[ "${output}" == *"still failing after 2 ad-hoc"* ]] || return 1
  [[ "${output}" == *"Last verification failure:"* ]] || return 1
  [[ "${output}" == *"Mock codex exec output"* ]] || return 1
  local browser_check_status browser_check_notes
  browser_check_status="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = [x for x in tasks if x.get('issue')=='42' and (x.get('step') or '').startswith('[BROWSER-CHECK]')]
print(t[0]['status'] if t else 'MISSING')
")"
  browser_check_notes="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = [x for x in tasks if x.get('issue')=='42' and (x.get('step') or '').startswith('[BROWSER-CHECK]')]
print(t[0].get('notes') or '' if t else '')
")"
  [ "${browser_check_status}" = "failed" ] || return 1
  [[ "${browser_check_notes}" == *"Last verification failure:"* ]] || return 1
  [[ "${browser_check_notes}" == *"Mock codex exec output"* ]] || return 1
  # Every spawn ever made must be one of exactly two kinds: an unsandboxed
  # [BROWSER-CHECK] attempt, or a sandboxed [AUTO-FIX] attempt. A synthesized
  # [AUTO-FIX ...] line's own reason text embeds the original failed item's
  # text (which itself contains "[BROWSER-CHECK]") - if next_step_is_browser_
  # check()'s substring match ever regresses to matching that embedded text,
  # an [AUTO-FIX] step would wrongly get spawned fully unsandboxed instead of
  # under --sandbox workspace-write. Assert the invariant directly: bypass and
  # workspace-write flags must never both be absent, or both be present, on
  # any single logged invocation line.
  while IFS= read -r line; do
    # Skip "mcp list" calls (the browser-MCP detector, not an exec spawn).
    case "$line" in mcp*) continue ;; esac
    case "$line" in
      *--dangerously-bypass-approvals-and-sandbox*"--sandbox workspace-write"*|*"--sandbox workspace-write"*--dangerously-bypass-approvals-and-sandbox*)
        echo "invocation had both bypass and workspace-write: $line"; return 1 ;;
      *--dangerously-bypass-approvals-and-sandbox*) : ;;
      *"--sandbox workspace-write"*) : ;;
      *) echo "invocation had neither bypass nor workspace-write: $line"; return 1 ;;
    esac
  done < "${args_file}"
  # 5 real "exec" spawns total (the 1st line is codex's own "mcp list"
  # browser-MCP probe, not a spawn): 3 unsandboxed [BROWSER-CHECK] attempts
  # (initial, then one retry after each of the 2 AUTO-FIX attempts), and 2
  # sandboxed [AUTO-FIX] steps themselves.
  local exec_count bypass_count
  exec_count="$(grep -c '^exec ' "${args_file}")"
  bypass_count="$(grep -c -- "--dangerously-bypass-approvals-and-sandbox" "${args_file}")"
  [ "${exec_count}" -eq 5 ] || return 1
  [ "${bypass_count}" -eq 3 ] || return 1
}

@test "execute a [BROWSER-CHECK] step with no browser MCP auto-falls back to --main with a notice" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the modal renders"
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"no browser MCP was detected"* ]] || return 1
  [[ "${output}" == *"Falling back to --main"* ]] || return 1
  [[ "${output}" == *"Mode: --main."* ]]   # ran inline, no subprocess spawned
}

@test "execute a [BROWSER-CHECK] step with --mcp-config runs isolated and passes --mcp-config to claude" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the modal renders"
  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --mcp-config /tmp/fake-mcp.json
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" != *"Falling back to --main"* ]] || return 1
  [[ "${output}" == *"running isolated"* ]] || return 1
  [ -f "${args_file}" ] || return 1
  [[ "$(cat "${args_file}")" == *"--mcp-config /tmp/fake-mcp.json"* ]] || return 1
}

@test "execute a [BROWSER-CHECK] step with --executor codex falls back to --main by default, even with a Playwright MCP configured (config presence alone is not sufficient - codex's sandbox blocks the browser subprocess regardless)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the modal renders"
  # Mock `codex mcp list` reports a Playwright MCP, but without the explicit
  # --codex-unsandboxed-browser-check opt-in this must NOT be treated as
  # isolable - proven false positive (browser_navigate gets silently
  # cancelled under codex's default sandbox even when the MCP is listed).
  run "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"no browser MCP was detected"* ]] || return 1
  [[ "${output}" == *"Mode: --main."* ]] || return 1
}

@test "execute a [BROWSER-CHECK] step with --executor codex and no browser MCP falls back to --main" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the modal renders"
  MOCK_CODEX_NO_MCP=1 run "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"no browser MCP was detected"* ]] || return 1
  [[ "${output}" == *"Mode: --main."* ]] || return 1
}

@test "execute a [BROWSER-CHECK] step with --executor codex --codex-unsandboxed-browser-check runs isolated with --dangerously-bypass-approvals-and-sandbox, not --sandbox workspace-write" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the modal renders"
  local args_file="${TEST_TMP}/codex-args.log"
  MOCK_CODEX_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --executor codex --codex-unsandboxed-browser-check
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" != *"Falling back to --main"* ]] || return 1
  [[ "${output}" == *"running isolated"* ]] || return 1
  [[ "${output}" == *"UNSANDBOXED"* ]] || return 1
  [ -f "${args_file}" ] || return 1
  [[ "$(cat "${args_file}")" == *"--dangerously-bypass-approvals-and-sandbox"* ]] || return 1
  [[ "$(cat "${args_file}")" != *"--sandbox workspace-write"* ]] || return 1
  grep -qi "external .*playwright.* MCP" .ai/.ogre/tmp/issue-42/run-next.md
  grep -qi "in-app browser" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute a [BROWSER-CHECK] step with --codex-unsandboxed-browser-check but no browser MCP still falls back to --main (opt-in alone isn't enough, still needs a real playwright MCP)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the modal renders"
  MOCK_CODEX_NO_MCP=1 run "${OGRE_BIN}" execute 42 --executor codex --codex-unsandboxed-browser-check
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"no browser MCP was detected"* ]] || return 1
  [[ "${output}" == *"Mode: --main."* ]] || return 1
}

@test "execute a non-browser-check step with --executor codex --codex-unsandboxed-browser-check stays sandboxed (bypass only applies to the actual [BROWSER-CHECK] step)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Plain step, no browser check"
  local args_file="${TEST_TMP}/codex-args.log"
  MOCK_CODEX_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --executor codex --codex-unsandboxed-browser-check
  [ "${status}" -eq 0 ] || return 1
  [ -f "${args_file}" ] || return 1
  [[ "$(cat "${args_file}")" == *"--sandbox workspace-write"* ]] || return 1
  [[ "$(cat "${args_file}")" != *"--dangerously-bypass-approvals-and-sandbox"* ]] || return 1
}

@test "execute a [BROWSER-CHECK] step uses codex_unsandboxed_browser_check from config.json to run isolated with the bypass" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the modal renders"
  python3 - <<'PY'
import json
p = ".ai/.ogre/config.json"
d = json.load(open(p)); d["codex_unsandboxed_browser_check"] = True
json.dump(d, open(p, "w"), indent=2)
PY
  local args_file="${TEST_TMP}/codex-args.log"
  MOCK_CODEX_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"running isolated"* ]] || return 1
  [[ "$(cat "${args_file}")" == *"--dangerously-bypass-approvals-and-sandbox"* ]] || return 1
}

@test "execute a [BROWSER-CHECK] step uses browser_mcp from config.json to run isolated" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the modal renders"
  python3 - <<'PY'
import json
p = ".ai/.ogre/config.json"
d = json.load(open(p)); d["browser_mcp"] = "/tmp/cfg-mcp.json"
json.dump(d, open(p, "w"), indent=2)
PY
  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"running isolated"* ]] || return 1
  [[ "$(cat "${args_file}")" == *"--mcp-config /tmp/cfg-mcp.json"* ]] || return 1
}

@test "execute --all --main is unaffected by [BROWSER-CHECK] (real browser tools available inline)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the page renders correctly"
  run "${OGRE_BIN}" execute 42 --all --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Mode: --main."* ]] || return 1
}

@test "execute --executor claude assigns a session id up front" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --executor claude
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Executor: claude"* ]] || return 1
  [[ "${output}" == *"Session id:"* ]] || return 1
}

@test "execute --task targets a specific step out of order" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid2
  tid2="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('step_index') == 2)
print(t['id'])
")"
  run "${OGRE_BIN}" execute 42 --task "${tid2}" --yes
  [ "${status}" -eq 0 ] || return 1
  [ "$(task_json_field "${tid2}" status)" = "passed" ] || return 1
}

@test "execute --step targets a specific step number" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run "${OGRE_BIN}" execute 42 --step 2 --yes
  [ "${status}" -eq 0 ] || return 1
  local tid2
  tid2="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('step_index') == 2)
print(t['id'])
")"
  [ "$(task_json_field "${tid2}" status)" = "passed" ] || return 1
}

@test "execute --task/--step out of order without --yes refuses non-interactively" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run bash -c "'${OGRE_BIN}' execute 42 --step 2 </dev/null"
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Refusing to proceed non-interactively without confirmation"* ]] || return 1
}

@test "execute with no matching --task/--step errors" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --task task-does-not-exist
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No matching pending task for that --task/--step under issue 42"* ]] || return 1
}

@test "execute reports no pending steps left once everything has passed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  "${OGRE_BIN}" execute 42
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No pending steps left for issue 42. Nothing to execute."* ]] || return 1
}

@test "execute --background runs detached and the task eventually passes" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --background
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"started in background"* ]] || return 1
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  wait_for_task_status "${tid}" passed 30
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
}

@test "execute --background puts the driver subshell in its own process group, not the launching shell's" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  local launcher_pgid
  launcher_pgid="$(ps -o pgid= -p $$ | tr -d ' ')"
  run "${OGRE_BIN}" execute 42 --background
  [ "${status}" -eq 0 ] || return 1
  local bg_pid bg_pgid
  bg_pid="$(cat .ai/.ogre/tmp/issue-42/*.pid)"
  # A merely-disowned child stays in the launching shell's process group -
  # anything that signals that whole group (not just closing its stdout,
  # which the driver-log redirect already survives) still kills it. `set -m`
  # around the launch must give it a separate group (pgid == its own pid).
  bg_pgid="$(ps -o pgid= -p "${bg_pid}" 2>/dev/null | tr -d ' ')"
  [ -n "${bg_pgid}" ] || return 1
  [ "${bg_pgid}" != "${launcher_pgid}" ] || return 1
  [ "${bg_pgid}" = "${bg_pid}" ] || return 1
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  wait_for_task_status "${tid}" passed 30
}

@test "execute on a previously-stopped task warns and requires confirmation" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  "${OGRE_BIN}" stop --task "${tid}" >/dev/null

  run bash -c "'${OGRE_BIN}' execute 42 </dev/null"
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"previously stopped"* ]] || return 1
  [[ "${output}" == *"Refusing to proceed non-interactively without confirmation"* ]] || return 1

  run "${OGRE_BIN}" execute 42 --yes
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Proceeding (--yes passed)."* ]] || return 1
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
}

@test "task-complete --notes records to the ledger but no longer injects into the runner" {
  # Cross-step knowledge now travels through the per-issue knowledge base, not
  # the ledger note. --notes stays a per-task ledger marker only.
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid1
  tid1="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
print(next(t for t in tasks if t.get('step_index') == 1)['id'])
")"
  "${OGRE_BIN}" task-complete "${tid1}" --notes "users table lacks reset_token column" >/dev/null
  [ "$(task_json_field "${tid1}" notes)" = "users table lacks reset_token column" ] || return 1

  run "${OGRE_BIN}" execute 42 --main # targets step 2; --main only writes the runner
  [ "${status}" -eq 0 ] || return 1
  ! grep -q "Notes from earlier sessions" .ai/.ogre/tmp/issue-42/run-next.md
  ! grep -q "users table lacks reset_token column" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute --all runner embeds the default hard cap of 3 items per session" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --all --main
  [ "${status}" -eq 0 ] || return 1
  grep -q "at most 3 checklist items" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute --all --max-steps overrides the per-session cap" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --all --max-steps 5 --main
  [ "${status}" -eq 0 ] || return 1
  grep -q "at most 5 checklist items" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute rejects a non-positive or non-numeric --max-steps" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --all --max-steps 0
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Invalid --max-steps"* ]] || return 1
  run "${OGRE_BIN}" execute 42 --all --max-steps lots
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Invalid --max-steps"* ]] || return 1
}

@test "execute injects repo drift (new commits + dirty tree) into the runner prompt" {
  git init -q .
  git -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m "baseline"
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  sleep 1 # drift window anchors on the plan's mtime; keep the commit clearly after it
  echo x > drifted.txt
  git add drifted.txt
  git -c user.email=t@t.t -c user.name=t commit -q -m "landed after plan"
  echo y > dirty.txt

  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ] || return 1
  grep -q "Repo drift since the plan was written" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "landed after plan" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "dirty.txt" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute runner has no drift section outside a git repo" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ] || return 1
  ! grep -q "Repo drift" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute on a backfilled job warns the runner that pending may already be implemented" {
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"backfilling state"* ]] || return 1
  grep -q "Backfilled ledger warning" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute on a normally-created job carries no backfill warning" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ] || return 1
  ! grep -q "Backfilled ledger warning" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute --retry with no failed step errors" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --retry
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No failed step to retry"* ]] || return 1
}

@test "execute --retry rejects --all" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --retry --all
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"can't be combined with --all"* ]] || return 1
}

@test "execute --retry re-targets the failed step and injects the failed attempt's log tail" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  export MOCK_CODEX_STATUS=failed
  run "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 1 ] || return 1
  unset MOCK_CODEX_STATUS
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
print(next(t for t in tasks if t.get('step_index') == 1)['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "failed" ] || return 1

  run "${OGRE_BIN}" execute 42 --retry --main # --main: only writes the runner
  [ "${status}" -eq 0 ] || return 1
  grep -q "step 1" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "First step" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "Previous attempt for this step FAILED" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "Log tail from the failed attempt" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "Mock codex exec output" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute lazily seeds a knowledge base for a job created before it existed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  rm -f .ai/.ogre/state/issue-42-knowledge.md # simulate a pre-knowledge job
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ] || return 1
  [ -f ".ai/.ogre/state/issue-42-knowledge.md" ] || return 1
}

@test "execute injects the knowledge base into the runner once it has real content" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  # Record a real verified contract in the knowledge base.
  python3 - <<'PY'
p = ".ai/.ogre/state/issue-42-knowledge.md"
s = open(p).read().replace(
    "## Verified Contracts\n",
    "## Verified Contracts\n- App\\Models\\User: uuid PK (app/Models/User.php)\n",
    1,
)
open(p, "w").write(s)
PY
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ] || return 1
  grep -q "Knowledge from earlier steps" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "uuid PK (app/Models/User.php)" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute does not inject an all-placeholder knowledge base" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ] || return 1
  ! grep -q "Knowledge from earlier steps" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute runner instructs the executor to update the knowledge base" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ] || return 1
  grep -q "UPDATE the knowledge base" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "issue-42-knowledge.md" .ai/.ogre/tmp/issue-42/run-next.md
}
