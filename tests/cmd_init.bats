load test_helper

@test "init creates runtime dirs, config.json and tasks.json" {
  run "${OGRE_BIN}" init
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Ogre runtime initialized at .ai/.ogre"* ]] || return 1
  for d in issues plans reviews logs state tmp archive prompts; do
    [ -d ".ai/.ogre/${d}" ] || return 1
  done
  [ -f ".ai/.ogre/config.json" ] || return 1
  [ "$(cat .ai/.ogre/state/tasks.json)" = "[]" ] || return 1
  [ "$(python3 -c "import json; print(json.load(open('.ai/.ogre/config.json'))['defaults']['executor']['provider'])")" = "claude" ] || return 1
}

@test "init copies prompt templates into runtime" {
  run "${OGRE_BIN}" init
  [ "${status}" -eq 0 ] || return 1
  [ -f ".ai/.ogre/prompts/execution-handoff.md" ] || return 1
}

@test "init is idempotent and preserves existing tasks.json" {
  "${OGRE_BIN}" init
  printf '[{"id":"task-keep"}]' > .ai/.ogre/state/tasks.json
  run "${OGRE_BIN}" init
  [ "${status}" -eq 0 ] || return 1
  [[ "$(cat .ai/.ogre/state/tasks.json)" == *"task-keep"* ]] || return 1
}
