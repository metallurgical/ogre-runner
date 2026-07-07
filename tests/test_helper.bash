OGRE_REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
OGRE_BIN="${OGRE_REPO_ROOT}/scripts/ogre"
MOCK_BIN="${BATS_TEST_DIRNAME}/mocks"

setup() {
  TEST_TMP="$(mktemp -d)"
  cd "${TEST_TMP}"
  export PATH="${MOCK_BIN}:${PATH}"
  # Reset per-test mock behavior overrides.
  unset MOCK_GH_EXIT MOCK_CURL_EXIT MOCK_CODEX_EXIT MOCK_CLAUDE_EXIT || true
}

teardown() {
  cd "${OGRE_REPO_ROOT}"
  rm -rf "${TEST_TMP}"
}

# state_field <issue> <field> - read one top-level field from an issue's state.json
state_field() {
  python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]))" \
    ".ai/.ogre/state/issue-$1.json" "$2"
}

# task_json_field <task-id> <field> - read one field from a task in the shared ledger
task_json_field() {
  python3 -c "
import json, sys
tid, field = sys.argv[1], sys.argv[2]
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next((x for x in tasks if x.get('id') == tid), None)
print(t.get(field) if t else '')
" "$1" "$2"
}

# write_plan_with_steps <issue> <step-text...> - fixture plan with a checklist
# `sync_state_from_plan` (called by execute/status/task-list) can seed tasks from.
write_plan_with_steps() {
  local issue="$1"; shift
  mkdir -p .ai/.ogre/plans
  {
    echo "# Plan for issue $issue"
    echo
    echo "## 6. Execution Order"
    echo
    for step in "$@"; do
      echo "- [ ] ${step}"
    done
  } > ".ai/.ogre/plans/issue-${issue}.md"
}

# wait_for_task_status <task-id> <status> <timeout-seconds> - poll the shared
# ledger for a background task (spawned detached, no PID we can `wait` on).
wait_for_task_status() {
  local tid="$1" want="$2" timeout="${3:-5}" waited=0
  while [ "${waited}" -lt "${timeout}" ]; do
    [ "$(task_json_field "${tid}" status)" = "${want}" ] && return 0
    sleep 0.2
    waited=$((waited + 1))
  done
  return 1
}
