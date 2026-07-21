load test_helper

@test "review-plan with no target errors" {
  run "${OGRE_BIN}" review-plan
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Missing issue or plan path"* ]] || return 1
}

@test "review-plan rejects unknown option" {
  run "${OGRE_BIN}" review-plan 42 --bogus --main
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Unknown option: --bogus"* ]] || return 1
}

@test "review-plan errors when the plan file does not exist" {
  run "${OGRE_BIN}" review-plan 42 --main
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Plan not found:"* ]] || return 1
}

@test "review-plan by issue number creates a review runner" {
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan 42 --main
  [ "${status}" -eq 0 ] || return 1
  [ -f ".ai/.ogre/tmp/issue-42/plan-review-runner.md" ] || return 1
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-review-runner.md)" == *".ai/.ogre/plans/issue-42.md"* ]] || return 1
  [ -d ".ai/.ogre/reviews/issue-42" ] || return 1
  [[ "${output}" == *"Review output: .ai/.ogre/reviews/issue-42/plan-review.md"* ]] || return 1
}

@test "review-plan short flags (-R -m -r -M) behave like their long forms, -R != -r" {
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan 42 -R codex -m gpt-5.6-sol -r low -M
  [ "${status}" -eq 0 ] || return 1
  [ -f ".ai/.ogre/tmp/issue-42/plan-review-runner.md" ] || return 1
  [[ "$(state_field 42 reviewer)" == *"codex"* ]] || return 1
}

@test "review-plan default spawns an isolated session and marks the review task passed" {
  write_plan_with_steps 42 "Do the thing"
  export MOCK_CLAUDE_WRITE_FILE="$(pwd)/.ai/.ogre/reviews/issue-42/plan-review.md"
  run "${OGRE_BIN}" review-plan 42
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Task"*"finished: passed"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'review')
print(t['id'])
")"
  [ "$(task_json_field "${tid}" status)" = "passed" ] || return 1
}

@test "review-plan --live passes --output-format stream-json to a claude reviewer" {
  write_plan_with_steps 42 "Do the thing"
  export MOCK_CLAUDE_WRITE_FILE="$(pwd)/.ai/.ogre/reviews/issue-42/plan-review.md"
  local args_file="${TEST_TMP}/claude-args.log"
  MOCK_CLAUDE_ARGS_FILE="${args_file}" run "${OGRE_BIN}" review-plan 42 --live
  [ "${status}" -eq 0 ] || return 1
  [ -f "${args_file}" ] || return 1
  [[ "$(cat "${args_file}")" == *"--output-format stream-json --verbose"* ]] || return 1
}

@test "review-plan --main preserves inline behavior and creates no ledger task" {
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan 42 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Review output:"* ]] || return 1
  [ "$(python3 -c "import json; print(len(json.load(open('.ai/.ogre/state/tasks.json'))))")" = "0" ] || return 1
}

@test "review-plan --background starts detached and the review task eventually passes" {
  write_plan_with_steps 42 "Do the thing"
  export MOCK_CLAUDE_WRITE_FILE="$(pwd)/.ai/.ogre/reviews/issue-42/plan-review.md"
  run "${OGRE_BIN}" review-plan 42 --background
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"started in background"* ]] || return 1
  local tid
  tid="$(python3 -c "
import json
tasks = json.load(open('.ai/.ogre/state/tasks.json'))
t = next(t for t in tasks if t.get('type') == 'review')
print(t['id'])
")"
  wait_for_task_status "${tid}" passed 10 || return 1
}

@test "review-plan by direct plan path works and reports reviewer/model" {
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan .ai/.ogre/plans/issue-42.md --reviewer codex --model gpt-5.5 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Reviewer: codex (gpt-5.5)"* ]] || return 1
}

@test "review-plan accepts --reasoning and shows it in the reviewer log line" {
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan 42 --reviewer codex --model gpt-5.6-sol --reasoning medium --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Reviewer: codex (gpt-5.6-sol) [reasoning: medium]"* ]] || return 1
}

@test "review-plan omits the reasoning tag from the reviewer log line when --reasoning isn't passed" {
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan 42 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" != *"[reasoning:"* ]] || return 1
}

@test "review-plan persists the resolved reviewer into state.json" {
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan 42 --reviewer codex --model gpt-5.5 --main
  [ "${status}" -eq 0 ] || return 1
  [ -f ".ai/.ogre/state/issue-42.json" ] || return 1
  [[ "$(state_field 42 reviewer)" == *"codex"* ]] || return 1
  [[ "$(state_field 42 reviewer)" == *"gpt-5.5"* ]] || return 1
}

@test "review-plan --reviewer flag wins over config.json default when persisting state.json" {
  "${OGRE_BIN}" init
  python3 -c "
import json
d = json.load(open('.ai/.ogre/config.json'))
d['defaults']['plan_reviewer'] = {'provider': 'codex', 'model': 'gpt-5.6-sol'}
json.dump(d, open('.ai/.ogre/config.json', 'w'))
"
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan 42 --reviewer claude --model claude-sonnet-5 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "$(state_field 42 reviewer)" == *"claude"* ]] || return 1
  [[ "$(state_field 42 reviewer)" != *"codex"* ]] || return 1
}

@test "review-plan falls back to config.json default reviewer when --reviewer is omitted, and persists it" {
  "${OGRE_BIN}" init
  python3 -c "
import json
d = json.load(open('.ai/.ogre/config.json'))
d['defaults']['plan_reviewer'] = {'provider': 'codex', 'model': 'gpt-5.6-sol'}
json.dump(d, open('.ai/.ogre/config.json', 'w'))
"
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan 42 --main
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Reviewer: codex (gpt-5.6-sol)"* ]] || return 1
  [[ "$(state_field 42 reviewer)" == *"codex"* ]] || return 1
}

@test "review-plan updates state.json's reviewer field, overwriting the value seeded at feature-creation" {
  "${OGRE_BIN}" feature --statement "base feature" --name 42 --main
  write_plan_with_steps 42 "Do the thing"
  [[ "$(state_field 42 reviewer)" == *"claude"* ]] || return 1
  run "${OGRE_BIN}" review-plan 42 --reviewer codex --model gpt-5.6-sol --main
  [ "${status}" -eq 0 ] || return 1
  [[ "$(state_field 42 reviewer)" == *"codex"* ]] || return 1
  [[ "$(state_field 42 reviewer)" == *"gpt-5.6-sol"* ]] || return 1
}
