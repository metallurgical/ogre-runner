load test_helper

@test "init creates runtime dirs, config.json and tasks.json" {
  run "${OGRE_BIN}" init
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Ogre runtime initialized at .ai/.ogre"* ]]
  for d in issues plans reviews logs state tmp archive prompts; do
    [ -d ".ai/.ogre/${d}" ]
  done
  [ -f ".ai/.ogre/config.json" ]
  [ "$(cat .ai/.ogre/state/tasks.json)" = "[]" ]
  [ "$(python3 -c "import json; print(json.load(open('.ai/.ogre/config.json'))['defaults']['executor']['provider'])")" = "claude" ]
}

@test "init copies prompt templates into runtime" {
  run "${OGRE_BIN}" init
  [ "${status}" -eq 0 ]
  [ -f ".ai/.ogre/prompts/execution-handoff.md" ]
}

@test "init is idempotent and preserves existing tasks.json" {
  "${OGRE_BIN}" init
  printf '[{"id":"task-keep"}]' > .ai/.ogre/state/tasks.json
  run "${OGRE_BIN}" init
  [ "${status}" -eq 0 ]
  [[ "$(cat .ai/.ogre/state/tasks.json)" == *"task-keep"* ]]
}
