load test_helper

@test "feature with no issue and no --statement errors" {
  run "${OGRE_BIN}" feature
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Provide an issue number/url/path, or --statement"* ]]
}

@test "feature rejects unknown option" {
  run "${OGRE_BIN}" feature 42 --bogus
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Unknown option: --bogus"* ]]
}

@test "feature --statement writes issue file, state and planning runner" {
  run "${OGRE_BIN}" feature --statement "add dark mode toggle" --name darkmode
  [ "${status}" -eq 0 ]
  [ -f ".ai/.ogre/issues/issue-darkmode.md" ]
  [[ "$(cat .ai/.ogre/issues/issue-darkmode.md)" == *"add dark mode toggle"* ]]
  [ ! -f ".ai/.ogre/plans/issue-darkmode.md" ] # plan not written yet, only referenced
  [ -f ".ai/.ogre/state/issue-darkmode.json" ]
  [ "$(state_field darkmode status)" = "planning" ]
  [ "$(state_field darkmode plan_path)" = ".ai/.ogre/plans/issue-darkmode.md" ]
  [ -f ".ai/.ogre/tmp/issue-darkmode/plan-runner.md" ]
  [[ "$(cat .ai/.ogre/tmp/issue-darkmode/plan-runner.md)" == *"issue-darkmode.md"* ]]
}

@test "feature seeds a per-issue knowledge base from the template" {
  run "${OGRE_BIN}" feature --statement "add dark mode toggle" --name darkmode
  [ "${status}" -eq 0 ]
  [ -f ".ai/.ogre/state/issue-darkmode-knowledge.md" ]
  # Heading carries the real issue slug, and the fixed sections are present.
  grep -q "^# Knowledge — darkmode" .ai/.ogre/state/issue-darkmode-knowledge.md
  grep -q "^## Verified Contracts" .ai/.ogre/state/issue-darkmode-knowledge.md
  grep -q "^## Step Log" .ai/.ogre/state/issue-darkmode-knowledge.md
}

@test "feature --statement without --name derives a slug" {
  run "${OGRE_BIN}" feature --statement "Fix login bug on retry"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"State written:"* ]]
  local f
  f="$(ls .ai/.ogre/issues/ | head -n1)"
  [[ "${f}" == issue-fix-login-bug-on-* ]]
}

@test "feature with numeric issue fetches via mocked gh" {
  run "${OGRE_BIN}" feature 42
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Fetching GitHub issue #42"* ]]
  [[ "$(cat .ai/.ogre/issues/issue-42.md)" == *"Mock GitHub Issue"* ]]
  [ "$(state_field 42 issue)" = "42" ]
}

@test "feature with numeric issue falls back to placeholder when gh fails" {
  export MOCK_GH_EXIT=1
  run "${OGRE_BIN}" feature 43
  [ "${status}" -eq 0 ]
  [[ "$(cat .ai/.ogre/issues/issue-43.md)" == *"Could not fetch automatically"* ]]
}

@test "feature with github issue URL fetches via mocked gh" {
  run "${OGRE_BIN}" feature "https://github.com/acme/widgets/issues/99"
  [ "${status}" -eq 0 ]
  [ "$(state_field 99 issue)" = "99" ]
  [[ "$(cat .ai/.ogre/issues/issue-99.md)" == *"Mock GitHub Issue"* ]]
}

@test "feature with non-github URL falls back to generic page fetch via mocked curl" {
  # slug_from_issue derives the slug from the URL itself (--name is only
  # honored on the --statement path), so the trailing path segment must be
  # non-numeric to get a readable slug instead of a bare issue number.
  run "${OGRE_BIN}" feature "https://gitlab.example.com/acme/widgets/-/issues/feature-request"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Fetching page content:"* ]]
  [[ "$(cat .ai/.ogre/issues/issue-feature-request.md)" == *"Mock Page"* ]]
}

@test "feature --blocks fetches each blocker and lists them in the runner" {
  run "${OGRE_BIN}" feature 42 --blocks 10,11
  [ "${status}" -eq 0 ]
  [ -f ".ai/.ogre/issues/issue-10.md" ]
  [ -f ".ai/.ogre/issues/issue-11.md" ]
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-runner.md)" == *"issue-10.md"* ]]
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-runner.md)" == *"issue-11.md"* ]]
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/issue-42.json'))['blocker_paths']))")" = "2" ]
}

@test "feature --blocker with --remarks ties the remark to that blocker" {
  run "${OGRE_BIN}" feature 42 --blocker 10 --remarks "PR under review"
  [ "${status}" -eq 0 ]
  # remark stored in state, keyed by the blocker's path
  local remark
  remark="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/issue-42.json')).get('blocker_remarks', {}).get('.ai/.ogre/issues/issue-10.md', ''))")"
  [ "${remark}" = "PR under review" ]
  # remark prepended to the blocker's own file
  [[ "$(head -n1 .ai/.ogre/issues/issue-10.md)" == *"Blocker remark (user-provided): PR under review"* ]]
  # remark shown inline next to the blocker in the planning runner
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-runner.md)" == *'issue-10.md` — remark: "PR under review"'* ]]
}

@test "feature blockers without --remarks carry no remark" {
  run "${OGRE_BIN}" feature 42 --blocks 10,11
  [ "${status}" -eq 0 ]
  # no blocker_remarks keys at all
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/issue-42.json')).get('blocker_remarks', {})))")" = "0" ]
  # blocker file is not prefixed with a remark header
  [[ "$(head -n1 .ai/.ogre/issues/issue-10.md)" != *"Blocker remark"* ]]
  # runner lists the blocker plainly, no "remark:" suffix
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-runner.md)" != *"issue-10.md\` — remark"* ]]
}

@test "feature mixes remark-less --blocks with a remarked --blocker" {
  run "${OGRE_BIN}" feature 42 --blocks 10 --blocker 11 --remarks "PR merged"
  [ "${status}" -eq 0 ]
  [ "$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/issue-42.json'))['blocker_remarks'])")" = "{'.ai/.ogre/issues/issue-11.md': 'PR merged'}" ]
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/issue-42.json'))['blocker_paths']))")" = "2" ]
}

@test "feature --remarks with no preceding --blocker errors" {
  run "${OGRE_BIN}" feature 42 --remarks "orphan remark"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"--remarks must follow a --blocker"* ]]
}

@test "feature on existing plan defaults to preserving it (no stdin = choice 1)" {
  "${OGRE_BIN}" feature --statement "first pass" --name dup
  mkdir -p .ai/.ogre/plans
  echo "# existing plan" > .ai/.ogre/plans/issue-dup.md
  run "${OGRE_BIN}" feature --statement "second pass" --name dup </dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Continuing existing work."* ]]
  [[ "${output}" == *"Existing plan preserved."* ]]
  [ "$(cat .ai/.ogre/plans/issue-dup.md)" = "# existing plan" ]
}

@test "feature on existing plan choice 2 replaces the plan file only" {
  mkdir -p .ai/.ogre/plans
  echo "# existing plan" > .ai/.ogre/plans/issue-dup2.md
  run bash -c "printf '2\n' | '${OGRE_BIN}' feature --statement 'redo' --name dup2"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Removed existing plan only."* ]]
  [ ! -f ".ai/.ogre/plans/issue-dup2.md" ]
}

@test "feature on existing plan choice 4 deletes all data for the issue and starts fresh" {
  "${OGRE_BIN}" feature --statement "first pass" --name dup4
  mkdir -p .ai/.ogre/plans
  echo "# existing plan" > .ai/.ogre/plans/issue-dup4.md
  run bash -c "printf '4\n' | '${OGRE_BIN}' feature --statement 'fresh start' --name dup4"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Deleted Ogre data for issue dup4."* ]]
  [[ "$(cat .ai/.ogre/issues/issue-dup4.md)" == *"fresh start"* ]]
}

@test "feature on existing plan choice 5 cancels without changes" {
  mkdir -p .ai/.ogre/plans
  echo "# existing plan" > .ai/.ogre/plans/issue-dup5.md
  run bash -c "printf '5\n' | '${OGRE_BIN}' feature --statement 'nope' --name dup5"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Cancelled."* ]]
  [ "$(cat .ai/.ogre/plans/issue-dup5.md)" = "# existing plan" ]
}
