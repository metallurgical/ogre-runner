load test_helper

@test "add-blocker with no issue errors" {
  run "${OGRE_BIN}" add-blocker
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Missing issue for add-blocker"* ]] || return 1
}

@test "add-blocker without prior feature state errors" {
  run "${OGRE_BIN}" add-blocker 42 --statement "needs auth first" --main
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No Ogre state found for issue 42"* ]] || return 1
}

@test "add-blocker without blocker or --statement errors" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" add-blocker 42 --main
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Provide a blocker issue number/url/path, or --statement"* ]] || return 1
}

@test "add-blocker --statement records the blocker and resets status to planning" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" add-blocker 42 --statement "needs auth first" --name authblock --main
  [ "${status}" -eq 0 ] || return 1
  [ -f ".ai/.ogre/issues/issue-authblock.md" ] || return 1
  [ "$(state_field 42 status)" = "planning" ] || return 1
  [[ "$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/issue-42.json'))['blocker_paths'])")" == *"issue-authblock.md"* ]] || return 1
  [ -f ".ai/.ogre/tmp/issue-42/plan-runner.md" ] || return 1
}

@test "add-blocker default spawns an isolated session and marks the replan task passed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  export MOCK_CLAUDE_WRITE_FILE="$(pwd)/.ai/.ogre/plans/issue-42.md"
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
  export MOCK_CLAUDE_WRITE_FILE="$(pwd)/.ai/.ogre/plans/issue-42.md"
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
  wait_for_task_status "${tid}" passed 10 || return 1
}

@test "add-blocker with numeric blocker fetches via mocked gh" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" add-blocker 42 7 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "$(cat .ai/.ogre/issues/issue-7.md)" == *"Mock GitHub Issue"* ]] || return 1
}

@test "add-blocker --remarks ties the remark to that blocker" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" add-blocker 42 7 --remarks "Have PR and Merged" --main
  [ "${status}" -eq 0 ] || return 1
  # remark stored in state, keyed by the blocker's path
  local remark
  remark="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/issue-42.json')).get('blocker_remarks', {}).get('.ai/.ogre/issues/issue-7.md', ''))")"
  [ "${remark}" = "Have PR and Merged" ] || return 1
  # remark prepended to the blocker file and shown in the runner
  [[ "$(head -n1 .ai/.ogre/issues/issue-7.md)" == *"Blocker remark (user-provided):** Have PR and Merged"* ]] || return 1
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-runner.md)" == *'issue-7.md` — remark: "Have PR and Merged"'* ]] || return 1
}

@test "add-blocker without --remarks leaves the blocker unremarked" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" add-blocker 42 7 --main
  [ "${status}" -eq 0 ] || return 1
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/issue-42.json')).get('blocker_remarks', {})))")" = "0" ] || return 1
  [[ "$(head -n1 .ai/.ogre/issues/issue-7.md)" != *"Blocker remark"* ]] || return 1
}

@test "add-blocker refuses once execution has started, unless --force" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  mkdir -p .ai/.ogre/logs/issue-42
  touch .ai/.ogre/logs/issue-42/execute-20260101-000000-abcdef12.log

  run "${OGRE_BIN}" add-blocker 42 --statement "too late" --main
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Execution has already started for issue 42"* ]] || return 1

  run "${OGRE_BIN}" add-blocker 42 --statement "forced anyway" --force --main
  [ "${status}" -eq 0 ] || return 1
  [ "$(state_field 42 status)" = "planning" ] || return 1
}

@test "add-blocker --force after a step passed flags it to the user and the planner" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "Add reset column" "Wire up controller"
  # Run the first step to a passing state via the mock executor flow.
  "${OGRE_BIN}" execute 42 >/dev/null
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
print(next(t for t in tasks if t.get('step_index') == 1)['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1

  run "${OGRE_BIN}" add-blocker 42 --statement "must invalidate old tokens" --name invtok --force --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"NOT retroactively revised"* ]] || return 1
  [[ "${output}" == *"Add reset column"* ]] || return 1
  # And the same reaches the re-planning runner prompt.
  grep -q "Already-Completed Steps (not retroactively revised)" .ai/.ogre/tmp/issue-42/plan-runner.md
  grep -q "Add reset column" .ai/.ogre/tmp/issue-42/plan-runner.md
}

@test "add-blocker --force with no passed steps yet shows no stale-step warning" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "First step"
  # Execution "started" only via a stray log file - no task has passed.
  mkdir -p .ai/.ogre/logs/issue-42
  touch .ai/.ogre/logs/issue-42/execute-20260101-000000-abcdef12.log

  run "${OGRE_BIN}" add-blocker 42 --statement "late blocker" --name late --force --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" != *"NOT retroactively revised"* ]] || return 1
  ! grep -q "Already-Completed Steps" .ai/.ogre/tmp/issue-42/plan-runner.md
}

@test "add-blocker rejects a --name containing path traversal or shell metacharacters" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" add-blocker 42 --statement "blk" --name "../../evil" --main
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Invalid --name"* ]] || return 1
  [ ! -d ".ai/.ogre/issues/../../evil" ] || return 1
}
