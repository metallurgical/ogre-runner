load test_helper

@test "feature with no issue and no --statement errors" {
  run "${OGRE_BIN}" feature
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Provide an issue number/url/path, or --statement"* ]] || return 1
}

@test "feature rejects unknown option" {
  run "${OGRE_BIN}" feature 42 --bogus
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Unknown option: --bogus"* ]] || return 1
}

@test "feature --statement writes issue file, state and planning runner" {
  run "${OGRE_BIN}" feature --statement "add dark mode toggle" --name darkmode --main
  [ "${status}" -eq 0 ] || return 1
  [ -f ".ai/.ogre/issues/issue-darkmode.md" ] || return 1
  [[ "$(cat .ai/.ogre/issues/issue-darkmode.md)" == *"add dark mode toggle"* ]] || return 1
  [ ! -f ".ai/.ogre/plans/issue-darkmode.md" ] # plan not written yet, only referenced
  [ -f ".ai/.ogre/state/issue-darkmode.json" ] || return 1
  [ "$(state_field darkmode status)" = "planning" ] || return 1
  [ "$(state_field darkmode plan_path)" = ".ai/.ogre/plans/issue-darkmode.md" ] || return 1
  [ -f ".ai/.ogre/tmp/issue-darkmode/plan-runner.md" ] || return 1
  [[ "$(cat .ai/.ogre/tmp/issue-darkmode/plan-runner.md)" == *"issue-darkmode.md"* ]] || return 1
}

@test "feature default (no flag) spawns an isolated claude session and marks the plan task passed" {
  export MOCK_CLAUDE_WRITE_FILE="$(pwd)/.ai/.ogre/plans/issue-42.md"
  run "${OGRE_BIN}" feature --statement "base feature" --name 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Task"*"finished: passed"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'plan')
print(t['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
  [ "$(task_json_field "${tid}" type)" = "plan" ] || return 1
  [ -f ".ai/.ogre/plans/issue-42.md" ] || return 1
}

@test "feature --main preserves today's inline behavior and creates no ledger task" {
  run "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Next inside Claude Code: read"* ]] || return 1
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/tasks.json'))))")" = "0" ] || return 1
}

@test "feature --background starts detached and the plan task eventually passes" {
  export MOCK_CLAUDE_WRITE_FILE="$(pwd)/.ai/.ogre/plans/issue-42.md"
  run "${OGRE_BIN}" feature --statement "base feature" --name 42 --background
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"started in background"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'plan')
print(t['id'])
")"
  wait_for_task_status "${tid}" passed 10 || return 1
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
}

@test "feature foreground fails closed when the planner exits 0 but never calls task-complete" {
  export MOCK_CLAUDE_SKIP_COMPLETE=1
  run "${OGRE_BIN}" feature --statement "base feature" --name 42
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Task"*"finished: failed"* ]] || return 1
}

@test "feature foreground marks the plan task failed (and exits 1) when the planner reports passed but never wrote the plan file" {
  run "${OGRE_BIN}" feature --statement "base feature" --name 42
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Task"*"finished: failed"* ]] || return 1
  [ ! -f ".ai/.ogre/plans/issue-42.md" ] || return 1
}

@test "feature seeds reviewer/executor from config.json defaults instead of a hardcoded claude" {
  "${OGRE_BIN}" init
  python3 -c "
import json
d = json.load(open('.ai/.ogre/config.json'))
d['defaults']['plan_reviewer'] = {'provider': 'codex', 'model': 'gpt-5.6-sol'}
d['defaults']['executor'] = {'provider': 'codex', 'model': 'gpt-5.6-sol'}
json.dump(d, open('.ai/.ogre/config.json', 'w'))
"
  run "${OGRE_BIN}" feature --statement "add dark mode toggle" --name darkmode --main
  [ "${status}" -eq 0 ] || return 1
  [[ "$(state_field darkmode reviewer)" == *"codex"* ]] || return 1
  [[ "$(state_field darkmode executor)" == *"codex"* ]] || return 1
}

@test "feature without --browser-check tells the planner to skip [BROWSER-CHECK] tags entirely" {
  run "${OGRE_BIN}" feature --statement "add dark mode toggle" --name darkmode --main
  [ "${status}" -eq 0 ] || return 1
  [[ "$(cat .ai/.ogre/tmp/issue-darkmode/plan-runner.md)" == *'Do NOT tag any step `[BROWSER-CHECK]`'* ]] || return 1
}

@test "feature --browser-check lets the planner tag [BROWSER-CHECK] normally (no override rule)" {
  run "${OGRE_BIN}" feature --statement "add dark mode toggle" --name darkmode --browser-check --main
  [ "${status}" -eq 0 ] || return 1
  [[ "$(cat .ai/.ogre/tmp/issue-darkmode/plan-runner.md)" != *"Do NOT tag any step"* ]] || return 1
}

@test "feature seeds a per-issue knowledge base from the template" {
  run "${OGRE_BIN}" feature --statement "add dark mode toggle" --name darkmode --main
  [ "${status}" -eq 0 ] || return 1
  [ -f ".ai/.ogre/state/issue-darkmode-knowledge.md" ] || return 1
  # Heading carries the real issue slug, and the fixed sections are present.
  grep -q "^# Knowledge — darkmode" .ai/.ogre/state/issue-darkmode-knowledge.md
  grep -q "^## Verified Contracts" .ai/.ogre/state/issue-darkmode-knowledge.md
  grep -q "^## Step Log" .ai/.ogre/state/issue-darkmode-knowledge.md
}

@test "feature --statement without --name derives a slug" {
  run "${OGRE_BIN}" feature --statement "Fix login bug on retry" --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"State written:"* ]] || return 1
  local f
  f="$(ls .ai/.ogre/issues/ | head -n1)"
  [[ "${f}" == issue-fix-login-bug-on-* ]] || return 1
}

@test "feature with numeric issue fetches via mocked gh" {
  run "${OGRE_BIN}" feature 42 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Fetching GitHub issue #42"* ]] || return 1
  [[ "$(cat .ai/.ogre/issues/issue-42.md)" == *"Mock GitHub Issue"* ]] || return 1
  [ "$(state_field 42 issue)" = "42" ] || return 1
}

@test "feature with numeric issue falls back to placeholder when gh fails" {
  export MOCK_GH_EXIT=1
  run "${OGRE_BIN}" feature 43 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "$(cat .ai/.ogre/issues/issue-43.md)" == *"Could not fetch automatically"* ]] || return 1
}

@test "feature with github issue URL fetches via mocked gh" {
  run "${OGRE_BIN}" feature "https://github.com/acme/widgets/issues/99" --main
  [ "${status}" -eq 0 ] || return 1
  [ "$(state_field 99 issue)" = "99" ] || return 1
  [[ "$(cat .ai/.ogre/issues/issue-99.md)" == *"Mock GitHub Issue"* ]] || return 1
}

@test "feature with non-github URL falls back to generic page fetch via mocked curl" {
  # slug_from_issue derives the slug from the URL itself (--name is only
  # honored on the --statement path), so the trailing path segment must be
  # non-numeric to get a readable slug instead of a bare issue number.
  run "${OGRE_BIN}" feature "https://gitlab.example.com/acme/widgets/-/issues/feature-request" --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Fetching page content:"* ]] || return 1
  [[ "$(cat .ai/.ogre/issues/issue-feature-request.md)" == *"Mock Page"* ]] || return 1
}

@test "feature --blocks fetches each blocker and lists them in the runner" {
  run "${OGRE_BIN}" feature 42 --blocks 10,11 --main
  [ "${status}" -eq 0 ] || return 1
  [ -f ".ai/.ogre/issues/issue-10.md" ] || return 1
  [ -f ".ai/.ogre/issues/issue-11.md" ] || return 1
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-runner.md)" == *"issue-10.md"* ]] || return 1
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-runner.md)" == *"issue-11.md"* ]] || return 1
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/issue-42.json'))['blocker_paths']))")" = "2" ] || return 1
}

@test "feature --blocker with --remarks ties the remark to that blocker" {
  run "${OGRE_BIN}" feature 42 --blocker 10 --remarks "PR under review" --main
  [ "${status}" -eq 0 ] || return 1
  # remark stored in state, keyed by the blocker's path
  local remark
  remark="$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/issue-42.json')).get('blocker_remarks', {}).get('.ai/.ogre/issues/issue-10.md', ''))")"
  [ "${remark}" = "PR under review" ] || return 1
  # remark prepended to the blocker's own file
  [[ "$(head -n1 .ai/.ogre/issues/issue-10.md)" == *"Blocker remark (user-provided):** PR under review"* ]] || return 1
  # remark shown inline next to the blocker in the planning runner
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-runner.md)" == *'issue-10.md` — remark: "PR under review"'* ]] || return 1
}

@test "feature blockers without --remarks carry no remark" {
  run "${OGRE_BIN}" feature 42 --blocks 10,11 --main
  [ "${status}" -eq 0 ] || return 1
  # no blocker_remarks keys at all
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/issue-42.json')).get('blocker_remarks', {})))")" = "0" ] || return 1
  # blocker file is not prefixed with a remark header
  [[ "$(head -n1 .ai/.ogre/issues/issue-10.md)" != *"Blocker remark"* ]] || return 1
  # runner lists the blocker plainly, no "remark:" suffix
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-runner.md)" != *"issue-10.md\` — remark"* ]] || return 1
}

@test "feature mixes remark-less --blocks with a remarked --blocker" {
  run "${OGRE_BIN}" feature 42 --blocks 10 --blocker 11 --remarks "PR merged" --main
  [ "${status}" -eq 0 ] || return 1
  [ "$(python3 -c "import json; print(json.load(open('.ai/.ogre/state/issue-42.json'))['blocker_remarks'])")" = "{'.ai/.ogre/issues/issue-11.md': 'PR merged'}" ] || return 1
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/issue-42.json'))['blocker_paths']))")" = "2" ] || return 1
}

@test "feature --remarks with no preceding --blocker errors" {
  run "${OGRE_BIN}" feature 42 --remarks "orphan remark"
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"--remarks must follow a --blocker"* ]] || return 1
}

@test "feature on existing plan defaults to preserving it (no stdin = choice 1)" {
  "${OGRE_BIN}" feature --statement "first pass" --name dup --main
  mkdir -p .ai/.ogre/plans
  echo "# existing plan" > .ai/.ogre/plans/issue-dup.md
  run "${OGRE_BIN}" feature --statement "second pass" --name dup --main </dev/null
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Continuing existing work."* ]] || return 1
  [[ "${output}" == *"Existing plan preserved."* ]] || return 1
  [ "$(cat .ai/.ogre/plans/issue-dup.md)" = "# existing plan" ] || return 1
}

@test "feature on existing plan choice 2 replaces the plan file only" {
  mkdir -p .ai/.ogre/plans
  echo "# existing plan" > .ai/.ogre/plans/issue-dup2.md
  run bash -c "printf '2\n' | '${OGRE_BIN}' feature --statement 'redo' --name dup2 --main"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Removed existing plan only."* ]] || return 1
  [ ! -f ".ai/.ogre/plans/issue-dup2.md" ] || return 1
}

@test "feature on existing plan choice 4 deletes all data for the issue and starts fresh" {
  "${OGRE_BIN}" feature --statement "first pass" --name dup4 --main
  mkdir -p .ai/.ogre/plans
  echo "# existing plan" > .ai/.ogre/plans/issue-dup4.md
  run bash -c "printf '4\n' | '${OGRE_BIN}' feature --statement 'fresh start' --name dup4 --main"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Deleted Ogre data for issue dup4."* ]] || return 1
  [[ "$(cat .ai/.ogre/issues/issue-dup4.md)" == *"fresh start"* ]] || return 1
}

@test "feature on existing plan choice 5 cancels without changes" {
  mkdir -p .ai/.ogre/plans
  echo "# existing plan" > .ai/.ogre/plans/issue-dup5.md
  run bash -c "printf '5\n' | '${OGRE_BIN}' feature --statement 'nope' --name dup5"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Cancelled."* ]] || return 1
  [ "$(cat .ai/.ogre/plans/issue-dup5.md)" = "# existing plan" ] || return 1
}

@test "feature rejects a --name containing path traversal or shell metacharacters" {
  run "${OGRE_BIN}" feature --statement "x" --name "../../../../tmp/evilslug"
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Invalid --name"* ]] || return 1
  [ ! -d "/tmp/evilslug" ] || return 1

  run "${OGRE_BIN}" feature --statement "x" --name 'x"; touch /tmp/PWNED_test; x="'
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Invalid --name"* ]] || return 1
  [ ! -f "/tmp/PWNED_test" ] || return 1
}

@test "feature accepts a plain alnum/dash/underscore --name" {
  run "${OGRE_BIN}" feature --statement "x" --name "valid_name-42" --main
  [ "${status}" -eq 0 ] || return 1
  [ -f ".ai/.ogre/state/issue-valid_name-42.json" ] || return 1
}

@test "feature rejects a --plan value with a directory component or .." {
  run "${OGRE_BIN}" feature --statement "x" --name 42 --plan "../../../../tmp/evil.md"
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Invalid --plan"* ]] || return 1
  [ ! -f "/tmp/evil.md" ] || return 1

  run "${OGRE_BIN}" feature --statement "x" --name 43 --plan "sub/dir/evil.md"
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Invalid --plan"* ]] || return 1
}

@test "feature accepts a plain custom --plan filename" {
  run "${OGRE_BIN}" feature --statement "x" --name 44 --plan "custom-plan.md" --main
  [ "${status}" -eq 0 ] || return 1
  [ "$(state_field 44 plan_path)" = ".ai/.ogre/plans/custom-plan.md" ] || return 1
}

@test "feature accepts --reasoning and shows it in the planner log line" {
  run "${OGRE_BIN}" feature --statement "x" --name 46 --planner codex --model gpt-5.6-sol --reasoning high --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Planner: codex (gpt-5.6-sol) [reasoning: high]"* ]] || return 1
}

@test "feature omits the reasoning tag from the planner log line when --reasoning isn't passed" {
  run "${OGRE_BIN}" feature --statement "x" --name 47 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" != *"[reasoning:"* ]] || return 1
}

@test "state.json stays valid JSON even when --model contains quotes" {
  run "${OGRE_BIN}" feature --statement "x" --name 45 --planner claude --model 'sonnet", "injected": "1' --main
  [ "${status}" -eq 0 ] || return 1
  # Must parse as JSON, the literal quote must be escaped data not broken syntax,
  # and no extra top-level key must have been injected.
  run python3 -c "
import json
d = json.load(open('.ai/.ogre/state/issue-45.json'))
assert 'injected' not in d, 'JSON injection succeeded'
assert d['planner']['model'] == 'sonnet\", \"injected\": \"1'
print('ok')
"
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == "ok" ]] || return 1
}
