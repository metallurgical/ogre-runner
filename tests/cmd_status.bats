load test_helper

@test "status with no issues yet says so" {
  run "${OGRE_BIN}" status
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"No issues yet."* ]]
  [[ "${output}" == *"Running/pending tasks:"* ]]
}

@test "status for an unknown issue errors" {
  run "${OGRE_BIN}" status 999
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No state found for issue 999"* ]]
}

@test "status for a known issue prints job summary and raw state" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Job Id"* ]]
  [[ "${output}" == *"42"* ]]
  [[ "${output}" == *"Raw state:"* ]]
  [[ "${output}" == *'"status": "planning"'* ]]
}

@test "status --job resolves by job id" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  local job_id
  job_id="$(state_field 42 job_id)"
  run "${OGRE_BIN}" status --job "${job_id}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Job Id"* ]]
}

@test "status --job with unknown job id errors" {
  run "${OGRE_BIN}" status --job "job-does-not-exist"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No issue found with job id job-does-not-exist"* ]]
}

@test "status --tasks lists tasks, optionally filtered by issue" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Step one" "Step two"
  "${OGRE_BIN}" status 42 >/dev/null # triggers sync_state_from_plan, seeding tasks

  run "${OGRE_BIN}" status --tasks
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Tasks:"* ]]

  run "${OGRE_BIN}" status --tasks 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Tasks for issue 42:"* ]]
  [[ "${output}" == *"issue=42"* ]]
}

@test "status --task with unknown task id errors" {
  run "${OGRE_BIN}" status --task task-does-not-exist
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No task found with id task-does-not-exist"* ]]
}

@test "status --task shows the task summary and raw record" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Step one"
  "${OGRE_BIN}" status 42 >/dev/null

  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  run "${OGRE_BIN}" status --task "${tid}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Task Id"* ]]
  [[ "${output}" == *"Raw task record:"* ]]
  [[ "${output}" == *"\"id\": \"${tid}\""* ]]
}

@test "status rejects unknown option" {
  run "${OGRE_BIN}" status --bogus
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Unknown option: --bogus"* ]]
}
