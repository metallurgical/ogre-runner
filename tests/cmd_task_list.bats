load test_helper

@test "task-list with no job-id errors" {
  run "${OGRE_BIN}" task-list
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Usage: ogre task-list <job-id>"* ]] || return 1
}

@test "task-list with unknown job-id errors" {
  run "${OGRE_BIN}" task-list job-does-not-exist
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No issue found with job id job-does-not-exist"* ]] || return 1
}

@test "task-list shows every seeded step for the job" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  local job_id
  job_id="$(state_field 42 job_id)"

  run "${OGRE_BIN}" task-list "${job_id}"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Job Id: ${job_id}   Issue: 42"* ]] || return 1
  [[ "${output}" == *"First step"* ]] || return 1
  [[ "${output}" == *"Second step"* ]] || return 1
  [[ "${output}" == *"View one:  ogre status --task <task-id>"* ]] || return 1
}

@test "task-list with no tasks yet says so" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  local job_id
  job_id="$(state_field 42 job_id)"

  run "${OGRE_BIN}" task-list "${job_id}"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"No tasks yet for this job."* ]] || return 1
}
