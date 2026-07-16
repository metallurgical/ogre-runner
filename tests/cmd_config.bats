load test_helper

@test "config rejects unknown option" {
  run "${OGRE_BIN}" config --bogus
  [ "${status}" -eq 1 ] || return 1
  [[ "${output}" == *"Unknown option: --bogus"* ]] || return 1
}

@test "config with no config.json creates it with explicit defaults (config.json-sourced, not fallback)" {
  run "${OGRE_BIN}" config
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *'"planner": { "provider": "claude", "model": "claude-sonnet-5" },        # config.json'* ]] || return 1
  [[ "${output}" == *'"executor": { "provider": "claude", "model": "claude-sonnet-5" },       # config.json'* ]] || return 1
  [[ "${output}" == *'"rescuer": { "provider": "claude", "model": "claude-sonnet-5" },        # config.json'* ]] || return 1
}

@test "config's rescuer role is independent of executor - setting one leaves the other at its own default" {
  "${OGRE_BIN}" init
  python3 -c "
import json
d = json.load(open('.ai/.ogre/config.json'))
d['defaults']['rescuer'] = {'provider': 'codex', 'model': 'gpt-5.5'}
json.dump(d, open('.ai/.ogre/config.json', 'w'))
"
  run "${OGRE_BIN}" config
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *'"rescuer": { "provider": "codex", "model": "gpt-5.5" }'*"config.json"* ]] || return 1
  [[ "${output}" == *'"executor": { "provider": "claude", "model": "claude-sonnet-5" }'*"config.json"* ]] || return 1
}

@test "config shows the hardcoded fallback for a role missing from an existing config.json's defaults" {
  mkdir -p .ai/.ogre
  printf '{}' > .ai/.ogre/config.json
  run "${OGRE_BIN}" config
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *'"planner": { "provider": "claude", "model": "claude-sonnet-5" },        # fallback'* ]] || return 1
  [[ "${output}" == *'"executor": { "provider": "claude", "model": "claude-sonnet-5" },       # fallback'* ]] || return 1
}

@test "config reflects a value set in config.json, distinct from the fallback" {
  "${OGRE_BIN}" init
  python3 -c "
import json
d = json.load(open('.ai/.ogre/config.json'))
d['defaults']['executor'] = {'provider': 'codex', 'model': 'gpt-5.5'}
json.dump(d, open('.ai/.ogre/config.json', 'w'))
"
  run "${OGRE_BIN}" config
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *'"executor": { "provider": "codex", "model": "gpt-5.5" }'*"config.json"* ]] || return 1
}

@test "config shows the config.json path" {
  run "${OGRE_BIN}" config
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Config file: .ai/.ogre/config.json"* ]] || return 1
}

@test "config --reset backs up the messed-up file and restores fresh-install defaults" {
  "${OGRE_BIN}" init
  python3 -c "
import json
d = json.load(open('.ai/.ogre/config.json'))
d['defaults']['executor'] = {'provider': 'codex', 'model': 'gpt-5.5'}
json.dump(d, open('.ai/.ogre/config.json', 'w'))
"
  run "${OGRE_BIN}" config --reset
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Backed up previous config to .ai/.ogre/config.json.bak"* ]] || return 1
  [[ "${output}" == *"Reset .ai/.ogre/config.json to fresh-install defaults"* ]] || return 1
  [ -f ".ai/.ogre/config.json.bak" ] || return 1
  [[ "$(python3 -c "import json;print(json.load(open('.ai/.ogre/config.json.bak'))['defaults']['executor']['provider'])")" == "codex" ]] || return 1
  [[ "$(python3 -c "import json;print(json.load(open('.ai/.ogre/config.json'))['defaults']['executor']['provider'])")" == "claude" ]] || return 1
  [[ "${output}" == *'"executor": { "provider": "claude", "model": "claude-sonnet-5" }'*"config.json"* ]] || return 1
}

@test "config --reset with no prior config.json still succeeds" {
  run "${OGRE_BIN}" config --reset
  [ "${status}" -eq 0 ] || return 1
  [[ "${output}" == *"Reset .ai/.ogre/config.json to fresh-install defaults"* ]] || return 1
  [[ "${output}" == *'"executor": { "provider": "claude", "model": "claude-sonnet-5" }'*"config.json"* ]] || return 1
}
