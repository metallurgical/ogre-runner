load test_helper

@test "task-complete with no task id errors" {
  run "${OGRE_BIN}" task-complete
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Usage: ogre task-complete <task-id>"* ]] || return 1
}

@test "task-complete with unknown task id errors" {
  run "${OGRE_BIN}" task-complete task-does-not-exist
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No task found with id task-does-not-exist"* ]] || return 1
}

@test "task-complete rejects an invalid --status value" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"

  run "${OGRE_BIN}" task-complete "${tid}" --status bogus
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Invalid --status: bogus"* ]] || return 1
}

@test "task-complete defaults to passed and updates the ledger" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"

  run "${OGRE_BIN}" task-complete "${tid}"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Task ${tid} marked passed."* ]] || return 1
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
}

@test "task-complete --notes records findings on the task and shows them in the summary" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"

  run "${OGRE_BIN}" task-complete "${tid}" --notes "reset route is POST /password/email, not /forgot"
  [ "${status}" -eq 0 ] || return 1
  [ "$(task_json_field "${tid}" notes)" = "reset route is POST /password/email, not /forgot" ] || return 1
  [[ "${output}" == *"Notes"* ]] || return 1
  [[ "${output}" == *"reset route is POST /password/email"* ]] || return 1
}

@test "concurrent task-complete calls all land (ledger writes serialize, no lost updates)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "Step 1" "Step 2" "Step 3" "Step 4" "Step 5" "Step 6" "Step 7" "Step 8"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tids tid
  tids="$(python3 -c "import json; [print(t['id']) for t in json.load(open('.ai/.ogre/state/tasks.json'))]")"

  while IFS= read -r tid; do
    "${OGRE_BIN}" task-complete "${tid}" >/dev/null &
  done <<< "${tids}"
  wait

  # Every one of the 8 parallel read-modify-write cycles must have landed.
  while IFS= read -r tid; do
    [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
  done <<< "${tids}"
  # Atomic writes leave no temp file behind.
  [ ! -f ".ai/.ogre/state/tasks.json.tmp" ] || return 1
  python3 -c "import json; json.load(open('.ai/.ogre/state/tasks.json'))"
}

@test "task-complete --status failed --exit-code records both fields" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"

  run "${OGRE_BIN}" task-complete "${tid}" --status failed --exit-code 3
  [ "${status}" -eq 0 ] || return 1
  [ "$(task_json_field "${tid}" status)" = "failed" ] || return 1
  [ "$(task_json_field "${tid}" exit_code)" = "3" ] || return 1
}
