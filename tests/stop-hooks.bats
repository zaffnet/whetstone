#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# The two Stop hooks: hooks/typecheck.sh and hooks/audit_comments.sh. Both block a
# turn by printing {"decision": "block"} and are silent otherwise, so every case
# asserts one or the other.
#
# Each case builds a throwaway git repository, because both hooks read the working
# tree diff and would otherwise report on whetstone's own files.

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  WORK="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$WORK"
  git -C "$WORK" init -q
  : >"$WORK/pyproject.toml"
  git -C "$WORK" add -A
  git -C "$WORK" -c user.email=t@example.com -c user.name=t commit -qm init
  export REPO WORK CLAUDE_PLUGIN_ROOT="$REPO"
}

# Run a hook with a payload naming the throwaway repo. Only stdout is returned:
# the block decision is JSON on stdout, while stderr carries notes that are not
# part of the contract, such as a missing virtualenv on the machine running this.
run_hook() {
  local hook=$1 active=${2:-false} dir=${3:-$WORK}
  printf '{"cwd": "%s", "stop_hook_active": %s}' "$dir" "$active" \
    | bash "$REPO/hooks/$hook" 2>/dev/null
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

@test "typecheck: a new type: ignore blocks the turn" {
  printf 'x = 1  # type: ignore\n' >"$WORK/a.py"
  run -0 run_hook typecheck.sh
  [ "$(decision "$output")" = block ]
  [[ $output == *"type: ignore"* ]]
}

@test "typecheck: a documented noqa blocks too" {
  # The rule is every new suppression, not only the bare ones: a reason explains
  # the silence without removing it.
  printf 'import os  # noqa: F401  -- re-exported\n' >"$WORK/a.py"
  run -0 run_hook typecheck.sh
  [ "$(decision "$output")" = block ]
}

@test "typecheck: a suppression already committed is not reported" {
  printf 'x = 1  # type: ignore\n' >"$WORK/a.py"
  git -C "$WORK" add -A
  git -C "$WORK" -c user.email=t@example.com -c user.name=t commit -qm add
  run -0 run_hook typecheck.sh
  [ "$(decision "$output")" = none ]
}

@test "typecheck: reports the file and line of each suppression" {
  printf 'a = 1\nb = 2  # noqa\n' >"$WORK/a.py"
  run -0 run_hook typecheck.sh
  [[ $output == *"a.py:2"* ]]
}

@test "typecheck: stands down while already continuing from a Stop hook" {
  printf 'x = 1  # type: ignore\n' >"$WORK/a.py"
  run -0 run_hook typecheck.sh true
  [ -z "$output" ]
}

@test "typecheck: silent outside a git repository" {
  plain="$BATS_TEST_TMPDIR/plain"
  mkdir -p "$plain"
  run -0 run_hook typecheck.sh false "$plain"
  [ -z "$output" ]
}

@test "typecheck: silent in a repository with no pyproject.toml" {
  rm "$WORK/pyproject.toml"
  printf 'x = 1  # type: ignore\n' >"$WORK/a.py"
  run -0 run_hook typecheck.sh
  [ -z "$output" ]
}

@test "audit: a narrated file blocks the turn" {
  cat >"$WORK/a.py" <<'PY'
# ==================== HELPERS ====================
def get_user(uid: int) -> str:
    """Get the user."""
    # Changed: we now return a string
    value = 0
    value += 1  # increment value
    return str(uid)
PY
  run -0 run_hook audit_comments.sh
  [ "$(decision "$output")" = block ]
  [[ $output == *banner* ]]
  [[ $output == *session-narration* ]]
}

@test "audit: a comment that states a reason is left alone" {
  cat >"$WORK/a.py" <<'PY'
# The upstream gateway drops idle connections at 35s, so stay under that.
TIMEOUT = 30
# Two, because the vendor rejects a third attempt in the same minute.
RETRIES = 2
# Capped: the vendor bans a client that backs off past 60s.
BACKOFF = 60
# Required by the spec, which orders the header before the body.
ORDERED = True
PY
  run -0 run_hook audit_comments.sh
  [ "$(decision "$output")" = none ]
}

@test "audit: a few findings in a long file stay under the density gate" {
  {
    printf '# ==== BANNER ====\n'
    for i in $(seq 1 200); do printf 'x%s = %s\n' "$i" "$i"; done
  } >"$WORK/a.py"
  run -0 run_hook audit_comments.sh
  [ "$(decision "$output")" = none ]
}

@test "audit: stands down while already continuing from a Stop hook" {
  printf '# ==== BANNER ====\n# ==== OTHER ====\n# ==== MORE ====\n# ==== AGAIN ====\n' >"$WORK/a.py"
  run -0 run_hook audit_comments.sh true
  [ -z "$output" ]
}

@test "audit: a path containing a space is still audited" {
  cat >"$WORK/has space.py" <<'PY'
# ==================== HELPERS ====================
# Fixed: the loop now breaks early
# Note that this is important
# End of function
PY
  run -0 run_hook audit_comments.sh
  [ "$(decision "$output")" = block ]
  [[ $output == *"has space.py"* ]]
}

@test "audit: a licence header is not a finding" {
  cat >"$WORK/a.py" <<'PY'
# Copyright 2026 Example
# SPDX-License-Identifier: MIT
PY
  run -0 run_hook audit_comments.sh
  [ "$(decision "$output")" = none ]
}

@test "typecheck: a file-level directive is a suppression" {
  # `# mypy: ignore-errors` silences the whole module, so missing it would let
  # every error in the file through.
  printf '# mypy: ignore-errors\nimport os\n' >"$WORK/a.py"
  run -0 run_hook typecheck.sh
  [ "$(decision "$output")" = block ]
  [[ $output == *"ignore-errors"* ]]
}

@test "typecheck: a pyright rule directive is a suppression" {
  printf '# pyright: reportAssignmentType=false\nx = 1\n' >"$WORK/a.py"
  run -0 run_hook typecheck.sh
  [ "$(decision "$output")" = block ]
}

@test "typecheck: the same words inside a string are not a suppression" {
  # Suppressions are read as comment tokens, not as raw line text.
  printf 'MSG = "# type: ignore is a suppression"\n' >"$WORK/a.py"
  run -0 run_hook typecheck.sh
  [ "$(decision "$output")" = none ]
}

@test "audit: a committed comment is not reported when another line changes" {
  # The scope is the lines the diff adds, so editing one line does not put the
  # rest of the file on this session's account.
  cat >"$WORK/a.py" <<'PY'
# ==================== HELPERS ====================
# Fixed: an old committed comment
# Note that this is old
value = 1
PY
  git -C "$WORK" add -A
  git -C "$WORK" -c user.email=t@example.com -c user.name=t commit -qm add
  printf 'other = 2\n' >>"$WORK/a.py"
  run -0 run_hook audit_comments.sh
  [ "$(decision "$output")" = none ]
}

@test "audit: an edited docstring is in scope for all of its lines" {
  # A docstring spans lines, so rewriting the middle of one puts the whole in
  # scope rather than only the line that changed.
  cat >"$WORK/a.py" <<'PY'
def add(a: int, b: int) -> int:
    """Add two numbers.

    Args:
        a: The first number.
        b: The second.

    Returns:
        The sum.
    """
    return a + b
PY
  git -C "$WORK" add -A
  git -C "$WORK" -c user.email=t@example.com -c user.name=t commit -qm add
  sed -i '' 's/a: The first number./a: The first addend./' "$WORK/a.py"
  run -0 run_hook audit_comments.sh
  [ "$(decision "$output")" = block ]
  [[ $output == *oversized-docstring* ]]
}

# A stub `python3` earlier on PATH than the real one, exiting with $1.
fake_python3() {
  local code=$1
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  {
    printf '#!/bin/sh\n'
    printf 'echo "SyntaxError: invalid syntax" >&2\n'
    printf 'exit %s\n' "$code"
  } >"$BATS_TEST_TMPDIR/bin/python3"
  chmod +x "$BATS_TEST_TMPDIR/bin/python3"
  printf '%s' "$BATS_TEST_TMPDIR/bin"
}

@test "audit: an auditor that cannot run is reported, not treated as clean" {
  # Exit 0 is clean and 1 is findings, so anything else has to be told apart from
  # both: silently passing would retire the check the first time the interpreter
  # on PATH could not run the tool.
  printf '# ==== BANNER ====\n' >"$WORK/a.py"
  local bin
  bin="$(fake_python3 2)"
  # stdout only: the warning goes to stderr, and what matters here is that no
  # block decision is printed.
  run -0 env "PATH=$bin:$PATH" bash -c \
    "bash '$REPO/hooks/audit_comments.sh' 2>/dev/null <<<'{\"cwd\": \"$WORK\", \"stop_hook_active\": false}'"
  [ -z "$output" ]
}

@test "audit: the auditor's own error reaches stderr" {
  printf '# ==== BANNER ====\n' >"$WORK/a.py"
  local bin
  bin="$(fake_python3 2)"
  run -0 env "PATH=$bin:$PATH" bash -c \
    "bash '$REPO/hooks/audit_comments.sh' >/dev/null 2>&1 <<<'{\"cwd\": \"$WORK\", \"stop_hook_active\": false}'; \
     bash '$REPO/hooks/audit_comments.sh' 2>&1 >/dev/null <<<'{\"cwd\": \"$WORK\", \"stop_hook_active\": false}'"
  [[ $output == *"auditor failed"* ]]
  [[ $output == *SyntaxError* ]]
}

@test "typecheck: a finder that cannot run is reported, not treated as clean" {
  printf 'x = 1  # noqa\n' >"$WORK/a.py"
  local bin
  bin="$(fake_python3 2)"
  run -0 env "PATH=$bin:$PATH" bash -c \
    "bash '$REPO/hooks/typecheck.sh' 2>&1 >/dev/null <<<'{\"cwd\": \"$WORK\", \"stop_hook_active\": false}'"
  [[ $output == *"finder failed"* ]]
}
