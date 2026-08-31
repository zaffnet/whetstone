#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# The two Stop hooks: hooks/typecheck.sh and hooks/audit_comments.sh. Both block a
# turn by printing {"decision": "block"} and are silent otherwise, so every case
# asserts one or the other.
#
# audit_comments.sh asks a headless Claude for the judgment. These cases stub
# `claude` on PATH: the hook's job is to build the diff, hand it over, and turn
# whatever comes back into a decision, and that is what is asserted here. Whether
# the model judges a given comment well is not something a test can pin down, and
# a suite that called the API would be slow, costly, and differently wrong each
# run.
#
# Each case builds a throwaway git repository, because both hooks read the working
# tree and would otherwise report on whetstone's own files.

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  WORK="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$WORK"
  git -C "$WORK" init -q
  : >"$WORK/pyproject.toml"
  git -C "$WORK" add -A
  git -C "$WORK" -c user.email=t@example.com -c user.name=t commit -qm init
  # CLAUDE_PLUGIN_ROOT is not exported here. A generated project's hook runs
  # without it, and a suite that set it for every case could not tell a hook that
  # works there from one that only works as a plugin.
  export REPO WORK
}

# Run a hook with a payload naming a directory, the throwaway repo by default.
# Only stdout is returned: the block decision is JSON on stdout, while stderr
# carries notes that are not part of the contract, such as a missing virtualenv
# on the machine running this.
run_hook() {
  local hook=$1 active=${2:-false} dir=${3:-$WORK}
  printf '{"cwd": "%s", "stop_hook_active": %s}' "$dir" "$active" \
    | bash "$REPO/hooks/$hook" 2>/dev/null
}

# Same, keeping stderr and dropping stdout, for the cases about reporting.
run_hook_stderr() {
  local hook=$1 dir=${2:-$WORK}
  printf '{"cwd": "%s", "stop_hook_active": false}' "$dir" \
    | { bash "$REPO/hooks/$hook" >/dev/null; } 2>&1
}

# "none" for a silent hook, so a case can assert the absence of a block without
# depending on jq's behaviour on empty input.
decision() {
  [[ -n $1 ]] || {
    printf 'none\n'
    return
  }
  jq -r '.decision // "none"' <<<"$1"
}

# A stub `claude` earlier on PATH than the real one. $1 is the envelope it prints;
# $2 is its exit status. Writing the invocation to $WORK/claude-argv lets a case
# assert how the hook called it.
stub_claude() {
  local envelope=$1 code=${2:-0}
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  {
    printf '#!/bin/sh\n'
    printf 'cat >"%s/claude-stdin"\n' "$WORK"
    printf 'printf "%%s\\n" "$*" >"%s/claude-argv"\n' "$WORK"
    printf 'cat <<'"'"'ENVELOPE'"'"'\n%s\nENVELOPE\n' "$envelope"
    printf 'exit %s\n' "$code"
  } >"$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  printf '%s' "$BATS_TEST_TMPDIR/bin"
}

# An envelope carrying $1 as the model's reply.
envelope() {
  jq -nc --arg result "$1" '{is_error: false, subtype: "success", result: $result}'
}

# Run audit_comments.sh with `claude` stubbed to reply $1, in $2 or the throwaway
# repo. The stub writes what it was given to $WORK regardless, so a case naming
# another directory still reads the diff from there.
run_audit() {
  local bin dir=${2:-$WORK}
  bin="$(stub_claude "$(envelope "$1")")"
  printf '{"cwd": "%s", "stop_hook_active": false}' "$dir" \
    | PATH="$bin:$PATH" bash "$REPO/hooks/audit_comments.sh" 2>/dev/null
}

@test "audit: findings become a block, one line each" {
  printf '# ==== BANNER ====\nx = 1\n' >"$WORK/a.py"
  run -0 run_audit '{"findings": [{"file": "a.py", "line": 1, "why": "Remove the banner."}]}'
  [ "$(decision "$output")" = block ]
  [[ $output == *"a.py:1"* ]]
  [[ $output == *"Remove the banner."* ]]
}

@test "audit: an empty findings list ends the turn" {
  printf '# Two, because the vendor rejects a third attempt.\nx = 1\n' >"$WORK/a.py"
  run -0 run_audit '{"findings": []}'
  [ "$(decision "$output")" = none ]
}

@test "audit: a fenced reply is still read" {
  # The one deviation from "JSON and nothing else" worth expecting.
  printf '# ==== BANNER ====\nx = 1\n' >"$WORK/a.py"
  run -0 run_audit '```json
{"findings": [{"file": "a.py", "line": 1, "why": "Remove the banner."}]}
```'
  [ "$(decision "$output")" = block ]
}

@test "audit: a reply that is not JSON is reported, not treated as clean" {
  # Silently passing would retire the check the first time the model answered in
  # prose, which is exactly when it needs saying.
  printf '# ==== BANNER ====\nx = 1\n' >"$WORK/a.py"
  local bin
  bin="$(stub_claude "$(envelope 'I could not audit this diff.')")"
  run -0 env "PATH=$bin:$PATH" bash -c \
    "bash '$REPO/hooks/audit_comments.sh' 2>&1 >/dev/null <<<'{\"cwd\": \"$WORK\", \"stop_hook_active\": false}'"
  [[ $output == *"did not answer with a findings array"* ]]
}

@test "audit: findings that are not an array are reported, not treated as clean" {
  # `length` is defined on an object and a string as well as an array, so a reply
  # carrying some other shape under .findings would otherwise read as a clean
  # audit, or reach `.[]` and fail there.
  printf '# ==== BANNER ====\nx = 1\n' >"$WORK/a.py"
  local bin
  bin="$(stub_claude "$(envelope '{"findings": {}}')")"
  run -0 env "PATH=$bin:$PATH" bash -c \
    "bash '$REPO/hooks/audit_comments.sh' 2>&1 >/dev/null <<<'{\"cwd\": \"$WORK\", \"stop_hook_active\": false}'"
  [[ $output == *"did not answer with a findings array"* ]]
}

@test "audit: an envelope reporting an error does not block" {
  printf '# ==== BANNER ====\nx = 1\n' >"$WORK/a.py"
  local bin
  bin="$(stub_claude '{"is_error": true, "subtype": "error_max_turns", "result": "turn limit"}')"
  run -0 env "PATH=$bin:$PATH" bash -c \
    "bash '$REPO/hooks/audit_comments.sh' 2>/dev/null <<<'{\"cwd\": \"$WORK\", \"stop_hook_active\": false}'"
  [ -z "$output" ]
}

@test "audit: a claude that exits non-zero is reported on stderr" {
  printf '# ==== BANNER ====\nx = 1\n' >"$WORK/a.py"
  local bin
  bin="$(stub_claude '' 1)"
  run -0 env "PATH=$bin:$PATH" bash -c \
    "bash '$REPO/hooks/audit_comments.sh' 2>&1 >/dev/null <<<'{\"cwd\": \"$WORK\", \"stop_hook_active\": false}'"
  [[ $output == *"did not run"* ]]
}

@test "audit: a missing claude is reported on stderr" {
  # A PATH holding what the hook reaches for and nothing named claude. bash is on
  # it because `env` resolves the interpreter through PATH too, and without it the
  # case fails on a missing shell rather than on the hook.
  local no_claude="$BATS_TEST_TMPDIR/no-claude" t
  mkdir -p "$no_claude"
  for t in bash cat jq; do
    ln -sf "$(command -v "$t")" "$no_claude/$t"
  done
  run -0 env "PATH=$no_claude" bash -c \
    "bash '$REPO/hooks/audit_comments.sh' 2>&1 >/dev/null <<<'{\"cwd\": \"$WORK\", \"stop_hook_active\": false}'"
  [[ $output == *"claude was not found"* ]]
}

@test "audit: the diff reaches the model, and committed lines do not" {
  printf '# ==== COMMITTED BANNER ====\ncommitted = 1\n' >"$WORK/a.py"
  git -C "$WORK" add -A
  git -C "$WORK" -c user.email=t@example.com -c user.name=t commit -qm add
  printf '# ==== ADDED BANNER ====\nadded = 2\n' >>"$WORK/a.py"
  run -0 run_audit '{"findings": []}'
  [[ "$(cat "$WORK/claude-stdin")" == *"ADDED BANNER"* ]]
  # The committed line is context in a -U3 diff, but it is not an added line.
  [[ "$(grep '^+' "$WORK/claude-stdin")" != *"COMMITTED BANNER"* ]]
}

@test "audit: an untracked file is audited" {
  printf '# ==== BANNER ====\nx = 1\n' >"$WORK/fresh.py"
  run -0 run_audit '{"findings": []}'
  [[ "$(cat "$WORK/claude-stdin")" == *"fresh.py"* ]]
}

@test "audit: this machine's settings and MCP servers stay out of the call" {
  # None of them bear on the question, and loading them tripled the cost.
  printf '# ==== BANNER ====\nx = 1\n' >"$WORK/a.py"
  run -0 run_audit '{"findings": []}'
  local argv
  argv="$(cat "$WORK/claude-argv")"
  [[ $argv == *"--strict-mcp-config"* ]]
  [[ $argv == *"--setting-sources"* ]]
  [[ $argv == *"--max-turns 1"* ]]
}

@test "audit: no diff means no call" {
  run -0 run_audit '{"findings": []}'
  [ ! -f "$WORK/claude-argv" ]
}

@test "audit: blocks again on a re-entered stop" {
  # stop_hook_active is not consulted: the findings hold for as long as the
  # comments do, and standing down on the second pass would make the block a
  # formality that waiting out is cheaper than answering.
  printf '# ==== BANNER ====\nx = 1\n' >"$WORK/a.py"
  local bin
  bin="$(stub_claude "$(envelope '{"findings": [{"file": "a.py", "line": 1, "why": "Delete the banner."}]}')")"
  run -0 env "PATH=$bin:$PATH" bash -c \
    "bash '$REPO/hooks/audit_comments.sh' 2>/dev/null <<<'{\"cwd\": \"$WORK\", \"stop_hook_active\": true}'"
  [ "$(decision "$output")" = block ]
}

@test "audit: staged Python before the first commit is audited" {
  # There is no HEAD to diff against yet, and a staged file is not untracked, so
  # an unguarded hook builds an empty diff and never makes the call.
  local fresh="$BATS_TEST_TMPDIR/fresh"
  mkdir -p "$fresh"
  git -C "$fresh" init -q
  printf '# ==== BANNER ====\nx = 1\n' >"$fresh/a.py"
  git -C "$fresh" add a.py
  run -0 run_audit '{"findings": []}' "$fresh"
  [[ "$(cat "$WORK/claude-stdin")" == *"BANNER"* ]]
}

@test "audit: silent outside a git repository" {
  local plain="$BATS_TEST_TMPDIR/plain"
  mkdir -p "$plain"
  run -0 run_hook audit_comments.sh false "$plain"
  [ -z "$output" ]
}

@test "typecheck: blocks again on a re-entered stop" {
  # The checkers failing is not a matter of opinion, so it is reported for as
  # long as it is true.
  printf 'x = 1\n' >"$WORK/a.py"
  {
    printf '#!/bin/sh\n'
    printf 'echo "a.py:1: error: still broken"\n'
    printf 'exit 1\n'
  } >"$WORK/run-typecheck.sh"
  chmod +x "$WORK/run-typecheck.sh"
  run -0 run_hook typecheck.sh true
  [ "$(decision "$output")" = block ]
}

@test "typecheck: silent outside a git repository" {
  local plain="$BATS_TEST_TMPDIR/plain"
  mkdir -p "$plain"
  run -0 run_hook typecheck.sh false "$plain"
  [ -z "$output" ]
}

@test "typecheck: silent in a repository with no pyproject.toml" {
  rm "$WORK/pyproject.toml"
  printf 'x: str = 1\n' >"$WORK/a.py"
  run -0 run_hook typecheck.sh
  [ -z "$output" ]
}

@test "typecheck: silent when no Python changed" {
  printf 'notes\n' >"$WORK/README.md"
  run -0 run_hook typecheck.sh
  [ -z "$output" ]
}

@test "typecheck: the fallback stands down when its checkers are absent" {
  # bin/run-typecheck.sh runs mypy and basedpyright from the target project's
  # environment. A repository without them must fail on its code, not on the
  # missing executables.
  export CLAUDE_PLUGIN_ROOT="$REPO"
  printf 'x: str = 1\n' >"$WORK/a.py"
  run -0 run_hook typecheck.sh
  [ "$(decision "$output")" = none ]
}

@test "typecheck: the shared checker runs without CLAUDE_PLUGIN_ROOT" {
  # A Stop hook configured in settings.json runs without CLAUDE_PLUGIN_ROOT. Before
  # the script resolved the shared checker from its own directory, that left `checker`
  # empty and the hook exited 0, so every repository outside the template ended a turn
  # unchecked and said nothing.
  #
  # $WORK gets the two things bin/run-typecheck.sh requires of a project -- a python in
  # .venv/bin and the import guard satisfied -- through a stubbed `uv` that reports a
  # type error. The block text is the assertion: it comes from the shared checker, so
  # it cannot appear unless the fallback resolved and ran.
  mkdir -p "$WORK/.venv/bin" "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho 4\n' >"$WORK/.venv/bin/python"
  chmod +x "$WORK/.venv/bin/python"
  {
    printf '#!/bin/sh\n'
    printf 'case "$*" in\n'
    printf '  *"import mypy"*) exit 0 ;;\n'
    printf '  *mypy*) echo "a.py:1: error: found by the shared checker"; exit 1 ;;\n'
    printf '  *) exit 0 ;;\n'
    printf 'esac\n'
  } >"$BATS_TEST_TMPDIR/bin/uv"
  printf '#!/bin/sh\nexit 0\n' >"$BATS_TEST_TMPDIR/bin/uvx"
  chmod +x "$BATS_TEST_TMPDIR/bin/uv" "$BATS_TEST_TMPDIR/bin/uvx"
  printf 'x: str = 1\n' >"$WORK/a.py"

  run -0 env -u CLAUDE_PLUGIN_ROOT "PATH=$BATS_TEST_TMPDIR/bin:$PATH" bash -c \
    "bash '$REPO/hooks/typecheck.sh' 2>/dev/null <<<'{\"cwd\": \"$WORK\", \"stop_hook_active\": false}'"
  [ "$(decision "$output")" = block ]
  [[ $output == *"found by the shared checker"* ]]
}

@test "typecheck: the repository's own script is preferred and its output blocks" {
  # Also the shape a generated project has, since CLAUDE_PLUGIN_ROOT is unset
  # here: ./run-typecheck.sh is the only checker such a project has.
  printf 'x = 1\n' >"$WORK/a.py"
  {
    printf '#!/bin/sh\n'
    printf 'echo "a.py:1: error: something is wrong"\n'
    printf 'exit 1\n'
  } >"$WORK/run-typecheck.sh"
  chmod +x "$WORK/run-typecheck.sh"
  run -0 run_hook typecheck.sh
  [ "$(decision "$output")" = block ]
  [[ $output == *"something is wrong"* ]]
}

@test "typecheck: a script without the executable bit still runs" {
  # copier writes the template's run-typecheck.sh without it, and that copy is the
  # only checker a generated project has.
  printf 'x = 1\n' >"$WORK/a.py"
  {
    printf '#!/bin/sh\n'
    printf 'echo "a.py:1: error: ran unexecutable"\n'
    printf 'exit 1\n'
  } >"$WORK/run-typecheck.sh"
  chmod -x "$WORK/run-typecheck.sh"
  run -0 run_hook typecheck.sh
  [ "$(decision "$output")" = block ]
  [[ $output == *"ran unexecutable"* ]]
}

@test "typecheck: a passing script ends the turn" {
  printf 'x = 1\n' >"$WORK/a.py"
  printf '#!/bin/sh\nexit 0\n' >"$WORK/run-typecheck.sh"
  chmod +x "$WORK/run-typecheck.sh"
  run -0 run_hook typecheck.sh
  [ "$(decision "$output")" = none ]
}

@test "typecheck: a missing virtualenv is reported without blocking" {
  # The machine's problem, not the code's: blocking would burn the turn on
  # something Claude cannot fix.
  printf 'x = 1\n' >"$WORK/a.py"
  {
    printf '#!/bin/sh\n'
    printf 'echo "run-typecheck.sh: missing .venv/bin/python. Run: uv sync --all-groups" >&2\n'
    printf 'exit 127\n'
  } >"$WORK/run-typecheck.sh"
  chmod +x "$WORK/run-typecheck.sh"
  run -0 run_hook typecheck.sh
  [ -z "$output" ]
  run -0 run_hook_stderr typecheck.sh
  [[ $output == *"uv sync"* ]]
}
