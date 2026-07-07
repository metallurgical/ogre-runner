load test_helper

@test "no args prints usage and exits 0" {
  run "${OGRE_BIN}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage:"* ]]
  [[ "${output}" == *"ogre feature"* ]]
}

@test "-h prints usage and exits 0" {
  run "${OGRE_BIN}" -h
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage:"* ]]
}

@test "--help prints usage and exits 0" {
  run "${OGRE_BIN}" --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage:"* ]]
}

@test "help prints usage and exits 0" {
  run "${OGRE_BIN}" help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage:"* ]]
}

@test "unknown command errors and exits 1" {
  run "${OGRE_BIN}" bogus-command
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"ERROR: Unknown command: bogus-command"* ]]
  [[ "${output}" == *"Usage:"* ]]
}
