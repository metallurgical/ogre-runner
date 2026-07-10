load test_helper

@test "review-plan with no target errors" {
  run "${OGRE_BIN}" review-plan
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Missing issue or plan path"* ]]
}

@test "review-plan rejects unknown option" {
  run "${OGRE_BIN}" review-plan 42 --bogus
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Unknown option: --bogus"* ]]
}

@test "review-plan errors when the plan file does not exist" {
  run "${OGRE_BIN}" review-plan 42
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Plan not found:"* ]]
}

@test "review-plan by issue number creates a review runner" {
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan 42
  [ "${status}" -eq 0 ]
  [ -f ".ai/.ogre/tmp/issue-42/plan-review-runner.md" ]
  [[ "$(cat .ai/.ogre/tmp/issue-42/plan-review-runner.md)" == *".ai/.ogre/plans/issue-42.md"* ]]
  [ -d ".ai/.ogre/reviews/issue-42" ]
  [[ "${output}" == *"Review output: .ai/.ogre/reviews/issue-42/plan-review.md"* ]]
}

@test "review-plan by direct plan path works and reports reviewer/model" {
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan .ai/.ogre/plans/issue-42.md --reviewer codex --model gpt-5.5
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Reviewer: codex (gpt-5.5)"* ]]
}

@test "review-plan accepts --reasoning and shows it in the reviewer log line" {
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan 42 --reviewer codex --model gpt-5.6-sol --reasoning medium
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Reviewer: codex (gpt-5.6-sol) [reasoning: medium]"* ]]
}

@test "review-plan omits the reasoning tag from the reviewer log line when --reasoning isn't passed" {
  write_plan_with_steps 42 "Do the thing"
  run "${OGRE_BIN}" review-plan 42
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"[reasoning:"* ]]
}
