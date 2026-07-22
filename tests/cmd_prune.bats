load test_helper

# backdate_task_ended <task-id> <days-ago> - rewrites one ledger task's
# ended_at/updated_at into the past, so age-gating (--older-than) can be
# tested deterministically instead of waiting real days.
backdate_task_ended() {
  local tid="$1" days_ago="$2"
  python3 -c "
import json, datetime
path = '.ai/.ogre/state/tasks.json'
tasks = json.load(open(path))
ts = (datetime.datetime.now().astimezone() - datetime.timedelta(days=int('${days_ago}'))).isoformat()
for t in tasks:
    if t.get('id') == '${tid}':
        t['ended_at'] = ts
        t['updated_at'] = ts
json.dump(tasks, open(path, 'w'))
"
}

# backdate_state_updated <issue> <days-ago> - same, for a state.json's own
# updated_at (what --all scope's feature/execute eligibility keys off).
backdate_state_updated() {
  local issue="$1" days_ago="$2"
  python3 -c "
import json, datetime
path = '.ai/.ogre/state/issue-${issue}.json'
d = json.load(open(path))
d['updated_at'] = (datetime.datetime.now().astimezone() - datetime.timedelta(days=int('${days_ago}'))).isoformat()
json.dump(d, open(path, 'w'))
"
}

@test "prune with no data says nothing to prune" {
  run "${OGRE_BIN}" prune
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Nothing to prune"* ]] || return 1
}

@test "prune rejects unknown option" {
  run "${OGRE_BIN}" prune --bogus
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Unknown option: --bogus"* ]] || return 1
}

@test "prune rejects a non-numeric --older-than" {
  run "${OGRE_BIN}" prune --older-than abc
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"--older-than must be a non-negative integer"* ]] || return 1
}

@test "purge is an alias for prune" {
  run "${OGRE_BIN}" purge
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Nothing to prune"* ]] || return 1
}

@test "prune default scope ignores a freshly-finished rescue (younger than --older-than default)" {
  "${OGRE_BIN}" rescue "fix login bug" --name login-fix
  run "${OGRE_BIN}" prune
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Nothing to prune"* ]] || return 1
  [ -d ".ai/.ogre/logs/issue-rescue-login-fix" ] || return 1
}

@test "prune default scope lists a backdated finished rescue but does not delete it without --yes" {
  "${OGRE_BIN}" rescue "fix login bug" --name login-fix
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
print(next(t for t in tasks if t.get('type') == 'rescue')['id'])
")"
  backdate_task_ended "${tid}" 5
  run "${OGRE_BIN}" prune
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"rescue-login-fix"* ]] || return 1
  [[ "${output}" == *"Dry run - nothing deleted"* ]] || return 1
  [ -d ".ai/.ogre/logs/issue-rescue-login-fix" ] || return 1
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
}

@test "prune --yes deletes an eligible rescue's files and ledger row" {
  "${OGRE_BIN}" rescue "fix login bug" --name login-fix
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
print(next(t for t in tasks if t.get('type') == 'rescue')['id'])
")"
  backdate_task_ended "${tid}" 5
  run "${OGRE_BIN}" prune --yes
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Pruned 1 issue(s)"* ]] || return 1
  [ ! -d ".ai/.ogre/logs/issue-rescue-login-fix" ] || return 1
  [ ! -d ".ai/.ogre/tmp/issue-rescue-login-fix" ] || return 1
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/tasks.json'))))")" = "0" ] || return 1
}

@test "prune never touches a still-running rescue task even if very old" {
  "${OGRE_BIN}" rescue "fix login bug" --name login-fix --background
  wait_for_task_status "$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
print(next(t for t in tasks if t.get('type') == 'rescue')['id'])
")" passed 5

  # Add a second, still-"running" task under a fresh issue to simulate an
  # in-flight rescue, backdated so age alone would otherwise make it eligible.
  python3 -c "
import json, datetime
path = '.ai/.ogre/state/tasks.json'
tasks = json.load(open(path))
old = (datetime.datetime.now().astimezone() - datetime.timedelta(days=5)).isoformat()
tasks.append({'id': 'task-fake-running', 'issue': 'rescue-still-going', 'type': 'rescue',
              'status': 'running', 'ended_at': None, 'updated_at': old})
json.dump(tasks, open(path, 'w'))
"
  mkdir -p ".ai/.ogre/logs/issue-rescue-still-going"
  run "${OGRE_BIN}" prune --yes
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" != *"rescue-still-going"* ]] || return 1
  [ -d ".ai/.ogre/logs/issue-rescue-still-going" ] || return 1
}

@test "prune without --all ignores a finished feature issue" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  python3 -c "
import json
path = '.ai/.ogre/state/issue-42.json'
d = json.load(open(path))
d['status'] = 'completed'
json.dump(d, open(path, 'w'))
"
  backdate_state_updated 42 5
  run "${OGRE_BIN}" prune
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Nothing to prune"* ]] || return 1
  [[ "${output}" == *"Pass --all"* ]] || return 1
  [ -f ".ai/.ogre/state/issue-42.json" ] || return 1
}

@test "prune --all lists and deletes a backdated completed feature issue" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  python3 -c "
import json
path = '.ai/.ogre/state/issue-42.json'
d = json.load(open(path))
d['status'] = 'completed'
json.dump(d, open(path, 'w'))
"
  backdate_state_updated 42 5

  run "${OGRE_BIN}" prune --all
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"feature"*"42"* ]] || return 1
  [ -f ".ai/.ogre/state/issue-42.json" ] || return 1

  run "${OGRE_BIN}" prune --all --yes
  [ "${status}" -eq 0 ] || return 1
  [ ! -f ".ai/.ogre/state/issue-42.json" ] || return 1
  [ ! -f ".ai/.ogre/issues/issue-42.md" ] || return 1
}

@test "prune --all does not sweep a feature issue that is still in progress" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  backdate_state_updated 42 5
  run "${OGRE_BIN}" prune --all
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Nothing to prune"* ]] || return 1
  [ -f ".ai/.ogre/state/issue-42.json" ] || return 1
}

@test "prune --older-than 0 includes a rescue finished moments ago" {
  "${OGRE_BIN}" rescue "fix login bug" --name login-fix
  run "${OGRE_BIN}" prune --older-than 0
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"rescue-login-fix"* ]] || return 1
}
