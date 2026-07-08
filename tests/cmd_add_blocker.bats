load test_helper

@test "add-blocker with no issue errors" {
  run "${OGRE_BIN}" add-blocker
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Missing issue for add-blocker"* ]]
}

@test "add-blocker without prior feature state errors" {
  run "${OGRE_BIN}" add-blocker 42 --statement "needs auth first"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"No Ogre state found for issue 42"* ]]
}

@test "add-blocker without blocker or --statement errors" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run "${OGRE_BIN}" add-blocker 42
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Provide a blocker issue number/url/path, or --statement"* ]]
}

@test "add-blocker --statement records the blocker and resets status to planning" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run "${OGRE_BIN}" add-blocker 42 --statement "needs auth first" --name authblock
  [ "${status}" -eq 0 ]
  [ -f ".ai/.ogre/issues/issue-authblock.md" ]
  [ "$(state_field 42 status)" = "planning" ]
  [[ "$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/issue-42.json'))['blocker_paths'])")" == *"issue-authblock.md"* ]]
  [ -f ".ai/.ogre/tmp/issue-42/plan-runner.md" ]
}

@test "add-blocker with numeric blocker fetches via mocked gh" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run "${OGRE_BIN}" add-blocker 42 7
  [ "${status}" -eq 0 ]
  [[ "$(cat .ai/.ogre/issues/issue-7.md)" == *"Mock GitHub Issue"* ]]
}

@test "add-blocker --remarks ties the remark to that blocker" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run "${OGRE_BIN}" add-blocker 42 7 --remarks "Have PR and Merged"
  [ "${status}" -eq 0 ]
  # remark stored in state, keyed by the blocker's path
  local remark
  remark="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/issue-42.json')).get('blocker_remarks', {}).get('.ai/.ogre/issues/issue-7.md', ''))")"
  [ "${remark}" = "Have PR and Merged" ]
  # remark prepended to the blocker file and shown in the runner
  [[ "$(head -n1 .ai/.ogre/issues/issue-7.md)" == *"Blocker remark (user-provided): Have PR and Merged"* ]]
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-runner.md)" == *'issue-7.md` — remark: "Have PR and Merged"'* ]]
}

@test "add-blocker without --remarks leaves the blocker unremarked" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  run "${OGRE_BIN}" add-blocker 42 7
  [ "${status}" -eq 0 ]
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/issue-42.json')).get('blocker_remarks', {})))")" = "0" ]
  [[ "$(head -n1 .ai/.ogre/issues/issue-7.md)" != *"Blocker remark"* ]]
}

@test "add-blocker refuses once execution has started, unless --force" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42
  mkdir -p .ai/.ogre/logs/issue-42
  touch .ai/.ogre/logs/issue-42/execute-20260101-000000-abcdef12.log

  run "${OGRE_BIN}" add-blocker 42 --statement "too late"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Execution has already started for issue 42"* ]]

  run "${OGRE_BIN}" add-blocker 42 --statement "forced anyway" --force
  [ "${status}" -eq 0 ]
  [ "$(state_field 42 status)" = "planning" ]
}
