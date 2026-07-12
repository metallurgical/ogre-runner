load test_helper

@test "status with no issues yet says so" {
  run "${OGRE_BIN}" status
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"No issues yet."* ]] || return 1
  [[ "${output}" == *"Running/pending tasks:"* ]] || return 1
}

@test "status for an unknown issue errors" {
  run "${OGRE_BIN}" status 999
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No state found for issue 999"* ]] || return 1
}

@test "status for a known issue prints job summary and raw state" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Job Id"* ]] || return 1
  [[ "${output}" == *"42"* ]] || return 1
  [[ "${output}" == *"Raw state:"* ]] || return 1
  [[ "${output}" == *'"status": "planning"'* ]] || return 1
}

@test "status on a completed issue re-prints the Boom line (not just visible live during --background execute)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Only step"
  "${OGRE_BIN}" execute 42 >/dev/null
  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Boom! Issue 42 has been resolved."* ]] || return 1
}

@test "status on a not-yet-completed issue has no Boom line" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step" "Second step"
  "${OGRE_BIN}" execute 42 >/dev/null
  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" != *"Boom!"* ]] || return 1
}

@test "status --job resolves by job id" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  local job_id
  job_id="$(state_field 42 job_id)"
  run "${OGRE_BIN}" status --job "${job_id}"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Job Id"* ]] || return 1
}

@test "status --job with unknown job id errors" {
  run "${OGRE_BIN}" status --job "job-does-not-exist"
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No issue found with job id job-does-not-exist"* ]] || return 1
}

@test "status --tasks lists tasks, optionally filtered by issue" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Step one" "Step two"
  "${OGRE_BIN}" status 42 >/dev/null # triggers sync_state_from_plan, seeding tasks

  run "${OGRE_BIN}" status --tasks
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Tasks:"* ]] || return 1

  run "${OGRE_BIN}" status --tasks 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Tasks for issue 42:"* ]] || return 1
  [[ "${output}" == *"issue=42"* ]] || return 1
}

@test "status --task with unknown task id errors" {
  run "${OGRE_BIN}" status --task task-does-not-exist
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No task found with id task-does-not-exist"* ]] || return 1
}

@test "status --task shows the task summary and raw record" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Step one"
  "${OGRE_BIN}" status 42 >/dev/null

  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  run "${OGRE_BIN}" status --task "${tid}"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Task Id"* ]] || return 1
  [[ "${output}" == *"Raw task record:"* ]] || return 1
  [[ "${output}" == *"\"id\": \"${tid}\""* ]] || return 1
}

@test "status backfills state when a plan exists but state.json doesn't (ad-hoc plan, not created via ogre feature)" {
  write_plan_with_steps 42 "First step" "Second step"
  [ ! -f ".ai/.ogre/state/issue-42.json" ] || return 1

  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"backfilling state"* ]] || return 1
  [[ "${output}" == *"Job Id"* ]] || return 1
  [ -f ".ai/.ogre/state/issue-42.json" ] || return 1
  [ "$(state_field 42 status)" = "planning" ] || return 1
  [ "$(state_field 42 current_step)" = "First step" ] || return 1
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
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"marked failed"* ]] || return 1
  [ "$(task_json_field "${tid}" status)" = "failed" ] || return 1
}

@test "status auto-resumes a stalled --all chain: dead driver pid, terminal task, steps still pending" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Step one" "Step two"
  # Get the issue into "executing" (not "planning") the normal way, and tick
  # step one, so step two is the sole real pending item - mirrors a chain
  # that made some progress before its driver vanished.
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ] || return 1
  local job_id
  job_id="$(state_field 42 job_id)"

  # Simulate the driver-death signature directly: a mode=all chain task,
  # terminal status, a pid that can never be alive, no live process behind
  # it, with a real pending step left - exactly what's left behind when a
  # --all --background driver subshell dies between links instead of
  # spawning the next one.
  python3 - <<'PY'
import json, uuid, datetime
p = ".ai/.ogre/state/tasks.json"
tasks = json.load(open(p))
now = datetime.datetime.now().astimezone().isoformat()
tasks.append({
    "id": "task-{}".format(uuid.uuid4()), "issue": "42", "type": "execute",
    "executor": "claude", "model": "claude-sonnet-5", "mode": "all", "freshness": "fresh",
    "runner": None, "log_path": None, "status": "failed",
    "pid": 99999999, "exit_code": 0, "session_id": None, "notes": None,
    "created_at": now, "started_at": now, "ended_at": now, "updated_at": now,
})
json.dump(tasks, open(p, "w"), indent=2)
PY

  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"looks stalled"* ]] || return 1
  [[ "${output}" == *"Auto-resuming"* ]] || return 1

  # The resume itself runs detached (--background) - poll briefly for the
  # spawned mock claude to actually have been invoked instead of asserting
  # immediately and racing it.
  local waited=0
  while [ ! -s "${args_file}" ] && [ "${waited}" -lt 20 ]; do
    sleep 0.2
    waited=$((waited + 1))
  done
  [ -s "${args_file}" ] || return 1
}

@test "status auto-resume preserves reasoning from the dead task's own ledger record, and codex resumes unsandboxed regardless" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Step one" "[BROWSER-CHECK] Step two"
  run "${OGRE_BIN}" execute 42 --executor codex
  [ "${status}" -eq 0 ] || return 1
  local job_id
  job_id="$(state_field 42 job_id)"

  # A dead-driver mode=all task that *did* have --reasoning set on the
  # original invocation (task_create persists this; before the fix it was
  # dropped entirely, so a self-healed resume always came back at
  # default-effort no matter what was passed).
  python3 - <<'PY'
import json, uuid, datetime
p = ".ai/.ogre/state/tasks.json"
tasks = json.load(open(p))
now = datetime.datetime.now().astimezone().isoformat()
tasks.append({
    "id": "task-{}".format(uuid.uuid4()), "issue": "42", "type": "execute",
    "executor": "codex", "model": None, "mode": "all", "freshness": "fresh",
    "runner": None, "log_path": None, "status": "failed",
    "pid": 99999999, "exit_code": 0, "session_id": None, "notes": None,
    "reasoning": "low", "mcp_config": None,
    "created_at": now, "started_at": now, "ended_at": now, "updated_at": now,
})
json.dump(tasks, open(p, "w"), indent=2)
PY

  local args_file="${TEST_TMP}/codex-args.log"
  MOCK_CODEX_ARGS_FILE="${args_file}" run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"looks stalled"* ]] || return 1
  [[ "${output}" == *"Auto-resuming"* ]] || return 1

  local waited=0
  while [ ! -s "${args_file}" ] && [ "${waited}" -lt 20 ]; do
    sleep 0.2
    waited=$((waited + 1))
  done
  [ -s "${args_file}" ] || return 1
  [[ "$(cat "${args_file}")" == *"-c model_reasoning_effort=low"* ]] || return 1
  [[ "$(cat "${args_file}")" == *"--dangerously-bypass-approvals-and-sandbox"* ]] || return 1
}

@test "status does not touch a stopped issue even with a dead-pid mode=all task and steps pending" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Step one" "Step two"
  run "${OGRE_BIN}" execute 42
  [ "${status}" -eq 0 ] || return 1
  "${OGRE_BIN}" stop 42 >/dev/null

  python3 - <<'PY'
import json, uuid, datetime
p = ".ai/.ogre/state/tasks.json"
tasks = json.load(open(p))
now = datetime.datetime.now().astimezone().isoformat()
tasks.append({
    "id": "task-{}".format(uuid.uuid4()), "issue": "42", "type": "execute",
    "executor": "claude", "model": "claude-sonnet-5", "mode": "all", "freshness": "fresh",
    "runner": None, "log_path": None, "status": "failed",
    "pid": 99999999, "exit_code": 0, "session_id": None, "notes": None,
    "created_at": now, "started_at": now, "ended_at": now, "updated_at": now,
})
json.dump(tasks, open(p, "w"), indent=2)
PY

  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" != *"looks stalled"* ]] || return 1
  [[ "${output}" != *"Auto-resuming"* ]] || return 1
  [ ! -f "${args_file}" ] || return 1
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
  [ "${status}" -eq 0 ] || return 1
  [ "$(task_json_field "${tid}" status)" = "running" ] || return 1
}

@test "status reaps a codex task via its exit sentinel and captures the session id from the log" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" status 42 >/dev/null # seed ledger tasks
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"

  # A background codex task that finished but only left its exit sentinel (its
  # own task-complete never landed). reap_task must read executor + session_id
  # + log_path in one batched pass, mark it failed with the sentinel's exit
  # code, and lift the codex session id out of the log tail.
  mkdir -p ".ai/.ogre/tmp/issue-42"
  local logpath=".ai/.ogre/logs/issue-42/reaped.log"
  mkdir -p ".ai/.ogre/logs/issue-42"
  printf 'session id: reaped-sid-42\nwork...\n' > "${logpath}"
  python3 - "${tid}" "${logpath}" <<'PY'
import json, sys
p = ".ai/.ogre/state/tasks.json"
tasks = json.load(open(p))
for t in tasks:
    if t["id"] == sys.argv[1]:
        t["status"] = "running"
        t["executor"] = "codex"
        t["session_id"] = None
        t["log_path"] = sys.argv[2]
json.dump(tasks, open(p, "w"), indent=2)
PY
  printf '7' > ".ai/.ogre/tmp/issue-42/${tid}.exit"

  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [ "$(task_json_field "${tid}" status)" = "failed" ] || return 1
  [ "$(task_json_field "${tid}" exit_code)" = "7" ] || return 1
  [ "$(task_json_field "${tid}" session_id)" = "reaped-sid-42" ] || return 1
}

@test "status shows a knowledge-base line and warns when it is bloated" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "First step"

  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Knowledge:"* ]] || return 1
  [[ "${output}" == *"issue-42-knowledge.md"* ]] || return 1
  # A fresh skeleton is under the soft cap: no warning.
  [[ "${output}" != *"over the ~200 soft cap"* ]] || return 1

  # Bloat it past the soft cap and confirm the warning fires.
  python3 -c "open('.ai/.ogre/state/issue-42-knowledge.md','a').write('\n'.join('- x %d' % i for i in range(250)))"
  run "${OGRE_BIN}" status 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"over the ~200 soft cap"* ]] || return 1
}

@test "status rejects unknown option" {
  run "${OGRE_BIN}" status --bogus
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Unknown option: --bogus"* ]] || return 1
}

# count_tasks_for_issue <issue> - rows in the shared ledger for one issue.
count_tasks_for_issue() {
  python3 -c "import json,sys; print(len([t for t in json.load(open('.ai/.ogre/state/tasks.json')) if str(t.get('issue'))==sys.argv[1]]))" "$1"
}

@test "status (no args) compacts orphaned tasks whose state file is gone" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  write_plan_with_steps 42 "Step one" "Step two"
  "${OGRE_BIN}" status 42 >/dev/null # seeds step tasks for issue 42
  [ "$(count_tasks_for_issue 42)" -ge 2 ] || return 1

  # Simulate a lost/orphaned issue: state file gone, ledger rows left behind.
  rm -f .ai/.ogre/state/issue-42.json

  run "${OGRE_BIN}" status
  [ "${status}" -eq 0 ] || return 1
  [ "$(count_tasks_for_issue 42)" -eq 0 ] || return 1
}

@test "status (no args) keeps a live issue's tasks while dropping orphans" {
  "${OGRE_BIN}" feature --statement "live one" --name 99
  write_plan_with_steps 99 "Step one"
  "${OGRE_BIN}" status 99 >/dev/null

  "${OGRE_BIN}" feature --statement "will orphan" --name 42
  write_plan_with_steps 42 "Step one"
  "${OGRE_BIN}" status 42 >/dev/null
  rm -f .ai/.ogre/state/issue-42.json   # orphan 42, keep 99 live

  run "${OGRE_BIN}" status
  [ "${status}" -eq 0 ] || return 1
  [ "$(count_tasks_for_issue 99)" -ge 1 ]   # live issue untouched
  [ "$(count_tasks_for_issue 42)" -eq 0 ]   # orphan compacted away
}

@test "status (no args) still lists a stopped issue (terminal re-sync skipped)" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  "${OGRE_BIN}" stop 42 >/dev/null
  run "${OGRE_BIN}" status
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"42"* ]] || return 1
  [[ "${output}" == *"stopped"* ]] || return 1
}
