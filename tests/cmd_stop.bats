load test_helper

@test "stop with no target and no --all errors" {
  run "${OGRE_BIN}" stop
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Missing issue for stop, or use --all"* ]]
}

@test "stop on an unknown issue errors" {
  run "${OGRE_BIN}" stop 999
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No state found for issue 999"* ]]
}

@test "stop rejects unknown option" {
  run "${OGRE_BIN}" stop 42 --bogus
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Unknown option: --bogus"* ]]
}

@test "stop marks the issue stopped and leaves files in place" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run "${OGRE_BIN}" stop 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Issue (job) 42 marked as stopped."* ]]
  [ "$(state_field 42 status)" = "stopped" ]
  [ -f ".ai/.ogre/issues/issue-42.md" ]
}

@test "stop --job resolves by job id" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  local job_id
  job_id="$(state_field 42 job_id)"
  run "${OGRE_BIN}" stop --job "${job_id}"
  [ "${status}" -eq 0 ]
  [ "$(state_field 42 status)" = "stopped" ]
}

@test "stop --list shows runtime files without deleting anything" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run "${OGRE_BIN}" stop 42 --list
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"issue-42.md"* ]]
  [ -f ".ai/.ogre/issues/issue-42.md" ]
}

@test "stop --list without a target errors" {
  run "${OGRE_BIN}" stop --list
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Missing issue for --list"* ]]
}

@test "stop --archive moves issue files under archive/" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run "${OGRE_BIN}" stop 42 --archive
  [ "${status}" -eq 0 ]
  [ ! -f ".ai/.ogre/issues/issue-42.md" ]
  [ -n "$(find .ai/.ogre/archive -name 'issue-42.md' 2>/dev/null)" ]
}

@test "stop --delete cancels without typing yes" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run bash -c "printf 'no\n' | '${OGRE_BIN}' stop 42 --delete"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Cancelled."* ]]
  [ -f ".ai/.ogre/issues/issue-42.md" ]
}

@test "stop --delete removes all data for the issue when confirmed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run bash -c "printf 'yes\n' | '${OGRE_BIN}' stop 42 --delete"
  [ "${status}" -eq 0 ]
  [ ! -f ".ai/.ogre/issues/issue-42.md" ]
  [ ! -f ".ai/.ogre/state/issue-42.json" ]
}

@test "stop --all marks every issue stopped" {
  "${OGRE_BIN}" feature --statement "feature one" --name 42
  "${OGRE_BIN}" feature --statement "feature two" --name 43
  run "${OGRE_BIN}" stop --all
  [ "${status}" -eq 0 ]
  [ "$(state_field 42 status)" = "stopped" ]
  [ "$(state_field 43 status)" = "stopped" ]
}

@test "stop --task stops one task without touching its siblings or the job" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local t1 t2
  t1="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  t2="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[1]['id'])")"

  run "${OGRE_BIN}" stop --task "${t1}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Task ${t1} marked stopped."* ]]
  [ "$(task_json_field "${t1}" status)" = "stopped" ]
  [ "$(task_json_field "${t2}" status)" = "pending" ]
  [ "$(state_field 42 status)" = "planning" ]
}

@test "stop --task with unknown task id errors" {
  run "${OGRE_BIN}" stop --task task-does-not-exist
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No task found with id task-does-not-exist"* ]]
}

@test "stop --task on an already-finished task is a no-op" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  "${OGRE_BIN}" task-complete "${tid}" --status passed >/dev/null

  run "${OGRE_BIN}" stop --task "${tid}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"already passed. Nothing to stop."* ]]
}
