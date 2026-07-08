# Lints the project's shell scripts. Runs as part of `bats tests/`.
# .bats files themselves are excluded (bats DSL isn't valid bash).
# Severity is capped at `warning` so info/style suggestions don't fail CI.
#
# Self-contained (no `load test_helper`) so it doesn't inherit the per-test
# temp-dir setup/teardown, which this lint check has no use for.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
}

@test "shell scripts pass shellcheck (severity=warning)" {
  # shellcheck reads .shellcheckrc (shell=bash) from the repo root.
  cd "${REPO_ROOT}"
  run shellcheck --severity=warning \
    scripts/ogre \
    tests/test_helper.bash \
    tests/mocks/*
  [ "${status}" -eq 0 ] || {
    echo "${output}"
    false
  }
}
