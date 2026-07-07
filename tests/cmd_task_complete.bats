load test_helper

@test "task-complete with no task id errors" {
  run "${OGRE_BIN}" task-complete
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Usage: ogre task-complete <task-id>"* ]]
}

@test "task-complete with unknown task id errors" {
  run "${OGRE_BIN}" task-complete task-does-not-exist
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No task found with id task-does-not-exist"* ]]
}

@test "task-complete rejects an invalid --status value" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"

  run "${OGRE_BIN}" task-complete "${tid}" --status bogus
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Invalid --status: bogus"* ]]
}

@test "task-complete defaults to passed and updates the ledger" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"

  run "${OGRE_BIN}" task-complete "${tid}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Task ${tid} marked passed."* ]]
  [ "$(task_json_field "${tid}" status)" = "passed" ]
}

@test "task-complete --status failed --exit-code records both fields" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"

  run "${OGRE_BIN}" task-complete "${tid}" --status failed --exit-code 3
  [ "${status}" -eq 0 ]
  [ "$(task_json_field "${tid}" status)" = "failed" ]
  [ "$(task_json_field "${tid}" exit_code)" = "3" ]
}
