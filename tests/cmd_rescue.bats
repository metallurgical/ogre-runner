load test_helper

@test "rescue with no task description errors" {
  run "${OGRE_BIN}" rescue
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Missing task description"* ]] || return 1
}

@test "rescue rejects unknown option" {
  run "${OGRE_BIN}" rescue "fix login bug" --bogus
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Unknown option: --bogus"* ]] || return 1
}

@test "rescue rejects an unsupported rescuer" {
  run "${OGRE_BIN}" rescue "fix login bug" --rescuer bogus --main
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Unsupported rescuer: bogus"* ]] || return 1
}

@test "rescue accepts the task as a positional arg and creates a runner embedding it verbatim" {
  run "${OGRE_BIN}" rescue "fix error in login backend" --name login-fix --main
  [ "${status}" -eq 0 ] || return 1
  [ -f ".ai/.ogre/tmp/issue-rescue-login-fix/rescue-runner.md" ] || return 1
  [[ "$(cat .ai/.ogre/tmp/issue-rescue-login-fix/rescue-runner.md)" == *"fix error in login backend"* ]] || return 1
}

@test "rescue accepts the task via --statement instead of a positional arg" {
  run "${OGRE_BIN}" rescue --statement "implement forgot password page" --name forgot-pw --main
  [ "${status}" -eq 0 ] || return 1
  [[ "$(cat .ai/.ogre/tmp/issue-rescue-forgot-pw/rescue-runner.md)" == *"implement forgot password page"* ]] || return 1
}

@test "rescue creates no job/state file - it is not tied to any plan or issue" {
  run "${OGRE_BIN}" rescue "fix login bug" --name login-fix --main
  [ "${status}" -eq 0 ] || return 1
  [ ! -f ".ai/.ogre/state/issue-rescue-login-fix.json" ] || return 1
}

@test "rescue --main creates no ledger task and reports no subprocess was spawned" {
  run "${OGRE_BIN}" rescue "fix login bug" --name login-fix --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"no subprocess spawned"* ]] || return 1
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/tasks.json'))))")" = "0" ] || return 1
}

@test "rescue default spawns an isolated session and marks the rescue task passed" {
  run "${OGRE_BIN}" rescue "fix login bug" --name login-fix
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Task"*"finished: passed"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'rescue')
print(t['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
  [ "$(task_json_field "${tid}" issue)" = "rescue-login-fix" ] || return 1
}

@test "rescue --background starts detached and the rescue task eventually passes" {
  run "${OGRE_BIN}" rescue "fix login bug" --name login-fix --background
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"started in background"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'rescue')
print(t['id'])
")"
  wait_for_task_status "${tid}" passed 10 || return 1
}

@test "rescue reports a failed task when the rescuer self-reports failure" {
  export MOCK_CLAUDE_STATUS="failed"
  run "${OGRE_BIN}" rescue "fix login bug" --name login-fix
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Task"*"finished: failed"* ]] || return 1
}

@test "rescue with --rescuer codex --model gpt-5.5 --main reports rescuer/model" {
  run "${OGRE_BIN}" rescue "fix login bug" --rescuer codex --model gpt-5.5 --name login-fix --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Rescuer: codex (gpt-5.5)"* ]] || return 1
}

@test "rescue accepts --reasoning and shows it in the rescuer log line" {
  run "${OGRE_BIN}" rescue "fix login bug" --rescuer codex --model gpt-5.6-sol --reasoning medium --name login-fix --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Rescuer: codex (gpt-5.6-sol) [reasoning: medium]"* ]] || return 1
}

@test "rescue omits the reasoning tag from the rescuer log line when --reasoning isn't passed" {
  run "${OGRE_BIN}" rescue "fix login bug" --name login-fix --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" != *"[reasoning:"* ]] || return 1
}

@test "rescue falls back to config.json's defaults.rescuer role when --rescuer is omitted" {
  "${OGRE_BIN}" init
  python3 -c "
import json
d = json.load(open('.ai/.ogre/config.json'))
d['defaults']['rescuer'] = {'provider': 'codex', 'model': 'gpt-5.6-sol'}
json.dump(d, open('.ai/.ogre/config.json', 'w'))
"
  run "${OGRE_BIN}" rescue "fix login bug" --name login-fix --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Rescuer: codex (gpt-5.6-sol)"* ]] || return 1
}

@test "rescue --rescuer flag wins over config.json default" {
  "${OGRE_BIN}" init
  python3 -c "
import json
d = json.load(open('.ai/.ogre/config.json'))
d['defaults']['rescuer'] = {'provider': 'codex', 'model': 'gpt-5.6-sol'}
json.dump(d, open('.ai/.ogre/config.json', 'w'))
"
  run "${OGRE_BIN}" rescue "fix login bug" --rescuer claude --model claude-sonnet-5 --name login-fix --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Rescuer: claude (claude-sonnet-5)"* ]] || return 1
}

@test "rescue's defaults.rescuer is independent of defaults.executor" {
  "${OGRE_BIN}" init
  python3 -c "
import json
d = json.load(open('.ai/.ogre/config.json'))
d['defaults']['executor'] = {'provider': 'codex', 'model': 'gpt-5.6-sol'}
json.dump(d, open('.ai/.ogre/config.json', 'w'))
"
  run "${OGRE_BIN}" rescue "fix login bug" --name login-fix --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Rescuer: claude"* ]] || return 1
  [[ "${output}" != *"codex"* ]] || return 1
}

@test "rescue errors when the claude CLI is missing (default rescuer)" {
  # Real PATH minus the mocks dir - codex/claude mocks are the only ones on PATH we control.
  run env PATH="/usr/bin:/bin" "${OGRE_BIN}" rescue "fix login bug" --name login-fix
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"claude CLI not found"* ]] || return 1
}

@test "rescue errors when the codex CLI is missing" {
  run env PATH="/usr/bin:/bin" "${OGRE_BIN}" rescue "fix login bug" --rescuer codex --name login-fix
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"codex CLI not found"* ]] || return 1
}

@test "rescue auto-derives a slug from the task text when --name is omitted" {
  run "${OGRE_BIN}" rescue "fix error in login backend" --main
  [ "${status}" -eq 0 ] || return 1
  local runner_count
  runner_count="$(find .ai/.ogre/tmp -maxdepth 1 -type d -name 'issue-rescue-fix-error-in-login-*' | wc -l | tr -d ' ')"
  [ "${runner_count}" = "1" ] || return 1
}

@test "rescue --name is validated as a plain slug" {
  run "${OGRE_BIN}" rescue "fix login bug" --name "../evil" --main
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Invalid --name"* ]] || return 1
}
