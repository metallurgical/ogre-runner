load test_helper

@test "stop with no target and no --all errors" {
  run "${OGRE_BIN}" stop
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Missing issue for stop, or use --all"* ]] || return 1
}

@test "stop on an unknown issue errors" {
  run "${OGRE_BIN}" stop 999
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No state found for issue 999"* ]] || return 1
}

@test "stop rejects unknown option" {
  run "${OGRE_BIN}" stop 42 --bogus
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Unknown option: --bogus"* ]] || return 1
}

@test "stop marks the issue stopped and leaves files in place" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" stop 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Issue (job) 42 marked as stopped."* ]] || return 1
  [ "$(state_field 42 status)" = "stopped" ] || return 1
  [ -f ".ai/.ogre/issues/issue-42.md" ] || return 1
}

@test "stop --job resolves by job id" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  local job_id
  job_id="$(state_field 42 job_id)"
  run "${OGRE_BIN}" stop --job "${job_id}"
  [ "${status}" -eq 0 ] || return 1
  [ "$(state_field 42 status)" = "stopped" ] || return 1
}

@test "stop --list shows runtime files without deleting anything" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" stop 42 --list
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"issue-42.md"* ]] || return 1
  [[ "${output}" == *"issue-42-knowledge.md"* ]] || return 1
  [ -f ".ai/.ogre/issues/issue-42.md" ] || return 1
  [ -f ".ai/.ogre/state/issue-42-knowledge.md" ] || return 1
}

@test "stop --list without a target errors" {
  run "${OGRE_BIN}" stop --list
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Missing issue for --list"* ]] || return 1
}

@test "stop --archive moves issue files under archive/" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run "${OGRE_BIN}" stop 42 --archive
  [ "${status}" -eq 0 ] || return 1
  [ ! -f ".ai/.ogre/issues/issue-42.md" ] || return 1
  [ -n "$(find .ai/.ogre/archive -name 'issue-42.md' 2>/dev/null)" ] || return 1
  # Knowledge base moves with it - nothing orphaned in state/.
  [ ! -f ".ai/.ogre/state/issue-42-knowledge.md" ] || return 1
  [ -n "$(find .ai/.ogre/archive -name 'issue-42-knowledge.md' 2>/dev/null)" ] || return 1
}

@test "stop --archive prunes the issue's tasks from the shared ledger" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "Step one" "Step two"
  "${OGRE_BIN}" status 42 >/dev/null   # seeds step tasks for issue 42
  run python3 -c "import json; print(len([t for t in json.load(open('.ai/.ogre/state/tasks.json')) if str(t.get('issue'))=='42']))"
  [ "${output}" -ge 2 ] || return 1

  run "${OGRE_BIN}" stop 42 --archive
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Pruned"* ]] || return 1
  # Ledger no longer counts the archived issue's tasks (state moved to archive/,
  # so sync could never reconcile them again - they'd leak otherwise).
  run python3 -c "import json; print(len([t for t in json.load(open('.ai/.ogre/state/tasks.json')) if str(t.get('issue'))=='42']))"
  [ "${output}" -eq 0 ] || return 1
}

@test "stop --delete cancels without typing yes" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run bash -c "printf 'no\n' | '${OGRE_BIN}' stop 42 --delete"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Cancelled."* ]] || return 1
  [ -f ".ai/.ogre/issues/issue-42.md" ] || return 1
}

@test "stop --delete removes all data for the issue when confirmed" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  run bash -c "printf 'yes\n' | '${OGRE_BIN}' stop 42 --delete"
  [ "${status}" -eq 0 ] || return 1
  [ ! -f ".ai/.ogre/issues/issue-42.md" ] || return 1
  [ ! -f ".ai/.ogre/state/issue-42.json" ] || return 1
  # Knowledge base is deleted too - nothing left to bloat state/.
  [ ! -f ".ai/.ogre/state/issue-42-knowledge.md" ] || return 1
}

@test "stop --delete also removes attached blocker files and a custom-named plan" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --plan cp-42.md --main
  "${OGRE_BIN}" add-blocker 42 --statement "blk" --name myblocker
  # The custom plan is referenced in state (plan_path) but only written later; create it.
  echo "plan body" > .ai/.ogre/plans/cp-42.md
  [ -f ".ai/.ogre/issues/issue-myblocker.md" ] || return 1

  run bash -c "printf 'yes\n' | '${OGRE_BIN}' stop 42 --delete"
  [ "${status}" -eq 0 ] || return 1
  [ ! -f ".ai/.ogre/issues/issue-myblocker.md" ]   # blocker file gone
  [ ! -f ".ai/.ogre/plans/cp-42.md" ]              # custom-named plan gone
  # Absolutely nothing for issue 42 left behind anywhere under the runtime.
  [ -z "$(find .ai/.ogre -path '*archive*' -prune -o -name '*42*' -print 2>/dev/null)" ] || return 1
}

@test "stop --delete keeps a shared blocker still referenced by another issue" {
  "${OGRE_BIN}" feature --statement "first" --name 42 --main
  "${OGRE_BIN}" feature --statement "second" --name 99 --main
  "${OGRE_BIN}" add-blocker 42 7
  "${OGRE_BIN}" add-blocker 99 7   # same fetched blocker file, two issues
  [ -f ".ai/.ogre/issues/issue-7.md" ] || return 1

  run bash -c "printf 'yes\n' | '${OGRE_BIN}' stop 42 --delete"
  [ "${status}" -eq 0 ] || return 1
  # issue 99 still references it, so it must survive deleting issue 42.
  [ -f ".ai/.ogre/issues/issue-7.md" ] || return 1
}

@test "stop --delete leaves a user-external blocker source untouched" {
  mkdir -p notes && echo "external blocker" > notes/ext.md
  "${OGRE_BIN}" feature --statement "base" --name 42 --main
  "${OGRE_BIN}" add-blocker 42 ./notes/ext.md
  run bash -c "printf 'yes\n' | '${OGRE_BIN}' stop 42 --delete"
  [ "${status}" -eq 0 ] || return 1
  # The runtime copy is gone, but the user's original file outside .ai/ stays.
  [ -f "notes/ext.md" ] || return 1
}

@test "stop --all marks every issue stopped" {
  "${OGRE_BIN}" feature --statement "feature one" --name 42 --main
  "${OGRE_BIN}" feature --statement "feature two" --name 43 --main
  run "${OGRE_BIN}" stop --all
  [ "${status}" -eq 0 ] || return 1
  [ "$(state_field 42 status)" = "stopped" ] || return 1
  [ "$(state_field 43 status)" = "stopped" ] || return 1
}

@test "stop --task stops one task without touching its siblings or the job" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "First step" "Second step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local t1 t2
  t1="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  t2="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[1]['id'])")"

  run "${OGRE_BIN}" stop --task "${t1}"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Task ${t1} marked stopped."* ]] || return 1
  [ "$(task_json_field "${t1}" status)" = "stopped" ] || return 1
  [ "$(task_json_field "${t2}" status)" = "pending" ] || return 1
  [ "$(state_field 42 status)" = "planning" ] || return 1
}

@test "stop --task with unknown task id errors" {
  run "${OGRE_BIN}" stop --task task-does-not-exist
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"No task found with id task-does-not-exist"* ]] || return 1
}

@test "stop --task on an already-finished task is a no-op" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "First step"
  "${OGRE_BIN}" task-list "$(state_field 42 job_id)" >/dev/null
  local tid
  tid="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/tasks.json'))[0]['id'])")"
  "${OGRE_BIN}" task-complete "${tid}" --status passed >/dev/null

  run "${OGRE_BIN}" stop --task "${tid}"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"already passed. Nothing to stop."* ]] || return 1
}
