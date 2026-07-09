load test_helper

@test "execute with no target and no --job errors" {
  run "${OGRE_BIN}" execute
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Missing issue, plan path, or --job"* ]]
}

@test "execute rejects unknown option" {
  run "${OGRE_BIN}" execute 42 --bogus
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Unknown option: --bogus"* ]]
}

@test "execute errors when the plan does not exist" {
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Plan not found:"* ]]
}

@test "execute backfills state when a plan exists but state.json doesn't (ad-hoc plan, not created via ogre feature)" {
  write_plan_with_steps 42 "First step"
  [ ! -f ".ai/.ogre/state/issue-42.json" ]

  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"backfilling state"* ]]
  [[ "${output}" == *"Task"*"finished: passed"* ]]
  [ -f ".ai/.ogre/state/issue-42.json" ]
  # single-step plan: the one step passes, so the job rolls straight to completed
  [ "$(state_field 42 status)" = "completed" ]
}

@test "execute --job with unknown job id errors" {
  run "${OGRE_BIN}" execute --job job-does-not-exist
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No issue found with job id job-does-not-exist"* ]]
}

@test "execute rejects an unsupported executor" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --executor bogus
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Unsupported executor: bogus"* ]]
}

@test "execute errors when the claude CLI is missing (default executor)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  # Real PATH minus the mocks dir - codex/claude mocks are the only ones on PATH we control.
  run env PATH="/usr/bin:/bin" "${OGRE_BIN}" execute 42
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"claude CLI not found"* ]]
}

@test "execute errors when the codex CLI is missing" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  # Real PATH minus the mocks dir - codex/claude mocks are the only ones on PATH we control.
  run env PATH="/usr/bin:/bin" "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"codex CLI not found"* ]]
}

@test "execute --main prints instructions and does not spawn a subprocess" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Mode: --main."* ]]
  [[ "${output}" == *"recorded as pending"* ]]
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  [ "$(task_json_field "${tid}" status)" = "pending" ]
}

@test "execute foreground default (claude) runs the lowest pending step and marks it passed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Executor: claude"* ]]
  [[ "${output}" == *"Task"*"finished: passed"* ]]
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('step_index') == 1)
print(t['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "passed" ]
  [ -n "$(task_json_field "${tid}" session_id)" ]
  [ "$(state_field 42 status)" = "executing" ]
}

@test "execute foreground prints the job summary automatically after finishing a step" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Task"*"finished: passed"* ]]
  [[ "${output}" == *"Steps Completed"* ]]
  [[ "${output}" == *"Steps Remaining"* ]]
  [[ "${output}" == *"Second step"* ]]
  [[ "${output}" != *"Boom!"* ]]
}

@test "execute prints a Boom line only once the whole job is completed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Boom! Issue 42 has been resolved."* ]]
}

@test "execute --background prints the finish summary and Boom line once the job completes" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  run "${OGRE_BIN}" execute 42 --background
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"started in background"* ]]
  [[ "${output}" == *"Task"*"finished: passed"* ]]
  [[ "${output}" == *"Boom! Issue 42 has been resolved."* ]]
  [[ "${output}" == *"Steps Completed"* ]]
}

@test "execute foreground with --executor claude passes --permission-mode bypassPermissions (headless -p has no TTY to prompt)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ]
  [ -f "${args_file}" ]
  [[ "$(cat "${args_file}")" == *"--permission-mode bypassPermissions"* ]]
}

@test "execute --background with --executor claude passes --permission-mode bypassPermissions" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --background
  [ "${status}" -eq 0 ]
  [ -f "${args_file}" ]
  [[ "$(cat "${args_file}")" == *"--permission-mode bypassPermissions"* ]]
}

@test "execute foreground with --executor codex runs the lowest pending step and marks it passed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Executor: codex"* ]]
  [[ "${output}" == *"Task"*"finished: passed"* ]]
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('step_index') == 1)
print(t['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "passed" ]
  [ "$(task_json_field "${tid}" session_id)" = "mock-codex-session-1234" ]
  [ "$(state_field 42 status)" = "executing" ]
}

@test "execute foreground with --executor codex passes --sandbox workspace-write (default sandbox is read-only, silently no-ops writes)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  local args_file="${TEST_TMP}/codex-args.log"
  MOCK_CODEX_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 0 ]
  [ -f "${args_file}" ]
  [[ "$(cat "${args_file}")" == *"--sandbox workspace-write"* ]]
}

@test "execute --background with --executor codex passes --sandbox workspace-write" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  local args_file="${TEST_TMP}/codex-args.log"
  MOCK_CODEX_ARGS_FILE="${args_file}" run "${OGRE_BIN}" execute 42 --executor codex --background
  [ "${status}" -eq 0 ]
  [ -f "${args_file}" ]
  [[ "$(cat "${args_file}")" == *"--sandbox workspace-write"* ]]
}

@test "execute foreground fails closed when codex exits 0 but never calls task-complete" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  export MOCK_CODEX_SKIP_COMPLETE=1
  run "${OGRE_BIN}" execute 42 --executor codex
  # rc==0 alone never proves the domain task passed - if the subprocess
  # never wrote its own status, finalize_link_status must fail closed
  # instead of guessing "passed" from the bare exit code.
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Task"*"finished: failed"* ]]
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  [ "$(task_json_field "${tid}" status)" = "failed" ]
  [ "$(task_json_field "${tid}" exit_code)" = "0" ]
}

@test "execute leaves a ledger-passed step out of pending_steps even if its plan checkbox was never ticked" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ]
  # The mock codex marks the task passed via `ogre task-complete` but never
  # edits the plan file, so "First step"'s checkbox is still unticked. The
  # ledger-passed signal alone must still be enough to advance past it.
  [ "$(state_field 42 current_step)" = "Second step" ]
  local pending
  pending="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/issue-42.json'))['pending_steps'])")"
  [[ "${pending}" != *"First step"* ]]
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
  [ "${status}" -eq 7 ]
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  [ "$(task_json_field "${tid}" status)" = "failed" ]
  [ "$(task_json_field "${tid}" exit_code)" = "7" ]
}

@test "execute auto-switches a [BROWSER-CHECK] step to --main instead of spawning a CLI" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "[BROWSER-CHECK] Verify the page renders correctly"
  run "${OGRE_BIN}" execute 42 --step 2 --yes
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"[BROWSER-CHECK]"* ]]
  [[ "${output}" == *"Switching to --main"* ]]
  [[ "${output}" == *"Mode: --main."* ]]
  # Auto-switched before spawning anything - task recorded pending, not run.
  local tid2
  tid2="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('step_index') == 2)
print(t['id'])
")"
  [ "$(task_json_field "${tid2}" status)" = "pending" ]
}

@test "execute --main runs a [BROWSER-CHECK] step fine (no CLI subprocess involved)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the page renders correctly"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Mode: --main."* ]]
}

@test "execute --all refuses up front when the next pending step is [BROWSER-CHECK]" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the page renders correctly" "Second step"
  run "${OGRE_BIN}" execute 42 --all --yes
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"[BROWSER-CHECK]"* ]]
  [[ "${output}" == *"--main"* ]]
  # Refused before spawning anything - the seeded per-step tasks (from
  # sync_state_from_plan) exist but none was ever set running/passed/failed.
  local statuses
  statuses="$(python3 -c "import json; print([t.get('status') for t in json.load(open('.ai/.ogre/state/tasks.json'))])")"
  [[ "${statuses}" != *"running"* ]]
}

@test "execute --all --main is unaffected by [BROWSER-CHECK] (real browser tools available inline)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "[BROWSER-CHECK] Verify the page renders correctly"
  run "${OGRE_BIN}" execute 42 --all --main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Mode: --main."* ]]
}

@test "execute --executor claude assigns a session id up front" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --executor claude
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Executor: claude"* ]]
  [[ "${output}" == *"Session id:"* ]]
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
  [ "${status}" -eq 0 ]
  [ "$(task_json_field "${tid2}" status)" = "passed" ]
}

@test "execute --step targets a specific step number" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run "${OGRE_BIN}" execute 42 --step 2 --yes
  [ "${status}" -eq 0 ]
  local tid2
  tid2="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('step_index') == 2)
print(t['id'])
")"
  [ "$(task_json_field "${tid2}" status)" = "passed" ]
}

@test "execute --task/--step out of order without --yes refuses non-interactively" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  run bash -c "'${OGRE_BIN}' execute 42 --step 2 </dev/null"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Refusing to proceed non-interactively without confirmation"* ]]
}

@test "execute with no matching --task/--step errors" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --task task-does-not-exist
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No matching pending task for that --task/--step under issue 42"* ]]
}

@test "execute reports no pending steps left once everything has passed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  "${OGRE_BIN}" execute 42
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No pending steps left for issue 42. Nothing to execute."* ]]
}

@test "execute --background runs detached and the task eventually passes" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --background
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"started in background"* ]]
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  wait_for_task_status "${tid}" passed 30
  [ "$(task_json_field "${tid}" status)" = "passed" ]
}

@test "execute on a previously-stopped task warns and requires confirmation" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  "${OGRE_BIN}" stop --task "${tid}" >/dev/null

  run bash -c "'${OGRE_BIN}' execute 42 </dev/null"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"previously stopped"* ]]
  [[ "${output}" == *"Refusing to proceed non-interactively without confirmation"* ]]

  run "${OGRE_BIN}" execute 42 --yes
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Proceeding (--yes passed)."* ]]
  [ "$(task_json_field "${tid}" status)" = "passed" ]
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
  [ "$(task_json_field "${tid1}" notes)" = "users table lacks reset_token column" ]

  run "${OGRE_BIN}" execute 42 --main # targets step 2; --main only writes the runner
  [ "${status}" -eq 0 ]
  ! grep -q "Notes from earlier sessions" .ai/.ogre/tmp/issue-42/run-next.md
  ! grep -q "users table lacks reset_token column" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute --all runner embeds the default hard cap of 3 items per session" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --all --main
  [ "${status}" -eq 0 ]
  grep -q "at most 3 checklist items" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute --all --max-steps overrides the per-session cap" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --all --max-steps 5 --main
  [ "${status}" -eq 0 ]
  grep -q "at most 5 checklist items" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute rejects a non-positive or non-numeric --max-steps" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --all --max-steps 0
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Invalid --max-steps"* ]]
  run "${OGRE_BIN}" execute 42 --all --max-steps lots
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Invalid --max-steps"* ]]
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
  [ "${status}" -eq 0 ]
  grep -q "Repo drift since the plan was written" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "landed after plan" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "dirty.txt" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute runner has no drift section outside a git repo" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ]
  ! grep -q "Repo drift" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute on a backfilled job warns the runner that pending may already be implemented" {
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"backfilling state"* ]]
  grep -q "Backfilled ledger warning" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute on a normally-created job carries no backfill warning" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ]
  ! grep -q "Backfilled ledger warning" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute --retry with no failed step errors" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --retry
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No failed step to retry"* ]]
}

@test "execute --retry rejects --all" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --retry --all
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"can't be combined with --all"* ]]
}

@test "execute --retry re-targets the failed step and injects the failed attempt's log tail" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  export MOCK_CODEX_STATUS=failed
  run "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 1 ]
  unset MOCK_CODEX_STATUS
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
print(next(t for t in tasks if t.get('step_index') == 1)['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "failed" ]

  run "${OGRE_BIN}" execute 42 --retry --main # --main: only writes the runner
  [ "${status}" -eq 0 ]
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
  [ "${status}" -eq 0 ]
  [ -f ".ai/.ogre/state/issue-42-knowledge.md" ]
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
  [ "${status}" -eq 0 ]
  grep -q "Knowledge from earlier steps" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "uuid PK (app/Models/User.php)" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute does not inject an all-placeholder knowledge base" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ]
  ! grep -q "Knowledge from earlier steps" .ai/.ogre/tmp/issue-42/run-next.md
}

@test "execute runner instructs the executor to update the knowledge base" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  run "${OGRE_BIN}" execute 42 --main
  [ "${status}" -eq 0 ]
  grep -q "UPDATE the knowledge base" .ai/.ogre/tmp/issue-42/run-next.md
  grep -q "issue-42-knowledge.md" .ai/.ogre/tmp/issue-42/run-next.md
}
