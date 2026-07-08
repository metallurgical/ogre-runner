# Ogre CLI tests (bats-core)

Tests for `scripts/ogre`. One file per subcommand, plus `cli.bats` for
top-level dispatch (help/usage/unknown command).

## Install bats-core

```
brew install bats-core
```

## Install shellcheck (for the lint test)

`tests/shellcheck.bats` lints the shell scripts (`scripts/ogre`,
`tests/test_helper.bash`, `tests/mocks/*`) via ShellCheck. It `skip`s
cleanly if `shellcheck` isn't on `PATH`, so it never blocks the suite.

```
brew install shellcheck
```

If `brew` tries to build ShellCheck (and GHC) from source on your macOS,
grab the prebuilt binary instead:

```
# from https://github.com/koalaman/shellcheck/releases
curl -fsSL -o sc.tar.xz \
  https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.darwin.x86_64.tar.xz
tar xf sc.tar.xz && sudo cp shellcheck-v0.10.0/shellcheck /usr/local/bin/
```

Dialect (`shell=bash`) is pinned in `.shellcheckrc` at the repo root.
Lint policy caps severity at `warning` (info/style suggestions don't fail).

## Run

```
bats tests/                 # everything
bats tests/cmd_status.bats  # just one command
bats tests/shellcheck.bats  # just the shellcheck lint

# lint directly, without bats:
shellcheck --severity=warning scripts/ogre tests/test_helper.bash tests/mocks/*
```

## How it works

- `test_helper.bash` is loaded by every `.bats` file (`load test_helper`).
  `setup()` creates a fresh temp dir per test and `cd`s into it, so
  `.ai/.ogre` never touches this repo. `teardown()` removes it.
- `tests/mocks/{gh,curl,codex,claude}` are fake executables prepended to
  `PATH` in `setup()`. They print deterministic output instead of hitting
  the network or spawning a real AI CLI. Each supports a `MOCK_<NAME>_EXIT`
  env var to force a non-zero exit for failure-path tests, e.g.
  `MOCK_GH_EXIT=1`, `MOCK_CODEX_EXIT=7`. `python3` runs for real (only used
  for local JSON handling, no network).
- Helpers in `test_helper.bash`: `state_field <issue> <field>`,
  `task_json_field <task-id> <field>`, `write_plan_with_steps <issue>
  <step-text...>` (fixture plan with a `## 6. Execution Order` checklist),
  `wait_for_task_status <task-id> <status> <timeout>` (polls the shared
  ledger for background tasks spawned with `--background`, since they're
  disowned and can't be `wait`ed on directly).

## Adding tests for a new/changed command

Copy an existing `cmd_*.bats` file as a template and keep it self-contained
so it can run on its own via `bats tests/cmd_<name>.bats`. Cover: missing
required args, unknown flags, the happy path (files/state JSON written),
and whatever domain-specific edge cases the code branches on. If the new
command shells out to something other than `gh`/`curl`/`codex`/`claude`,
add a fake under `tests/mocks/` and prepend it the same way.
