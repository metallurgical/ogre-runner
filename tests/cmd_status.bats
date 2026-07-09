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

@test "status backfills state when a plan exists but state.json doesn't (ad-hoc plan, not created via ogre feature)" {
  write_plan_with_steps 42 "First step" "Second step"
  [ ! -f ".ai/.ogre/state/issue-42.json" ]

  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"backfilling state"* ]]
  [[ "${output}" == *"Job Id"* ]]
  [ -f ".ai/.ogre/state/issue-42.json" ]
  [ "$(state_field 42 status)" = "planning" ]
  [ "$(state_field 42 current_step)" = "First step" ]
}

@test "status auto-fails a running task whose recorded pid is dead (no exit sentinel)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" status 42 >/dev/null # seed ledger tasks
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  # Simulate a background wrapper that died without writing its exit sentinel:
  # ledger says running, recorded pid can never be alive, no <tid>.exit file.
  python3 - "${tid}" <<'PY'
import json, sys
p = ".ai/.ogre/state/tasks.json"
tasks = json.load(open(p))
for t in tasks:
    if t["id"] == sys.argv[1]:
        t["status"] = "running"
        t["pid"] = 99999999
json.dump(tasks, open(p, "w"), indent=2)
PY

  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"marked failed"* ]]
  [ "$(task_json_field "${tid}" status)" = "failed" ]
}

@test "status leaves a running task with a live pid untouched" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" status 42 >/dev/null
  local tid live_pid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  sleep 30 &
  live_pid=$!
  python3 - "${tid}" "${live_pid}" <<'PY'
import json, sys
p = ".ai/.ogre/state/tasks.json"
tasks = json.load(open(p))
for t in tasks:
    if t["id"] == sys.argv[1]:
        t["status"] = "running"
        t["pid"] = int(sys.argv[2])
json.dump(tasks, open(p, "w"), indent=2)
PY

  run "${OGRE_BIN}" status 42
  kill "${live_pid}" 2>/dev/null || true
  [ "${status}" -eq 0 ]
  [ "$(task_json_field "${tid}" status)" = "running" ]
}

@test "status shows a knowledge-base line and warns when it is bloated" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"

  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Knowledge:"* ]]
  [[ "${output}" == *"issue-42-knowledge.md"* ]]
  # A fresh skeleton is under the soft cap: no warning.
  [[ "${output}" != *"over the ~200 soft cap"* ]]

  # Bloat it past the soft cap and confirm the warning fires.
  python3 -c "open('.ai/.ogre/state/issue-42-knowledge.md','a').write('\n'.join('- x %d' % i for i in range(250)))"
  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"over the ~200 soft cap"* ]]
}

@test "status rejects unknown option" {
  run "${OGRE_BIN}" status --bogus
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Unknown option: --bogus"* ]]
}
