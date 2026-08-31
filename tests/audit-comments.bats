#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Cases for tools/audit-comments.py. Every rule keys on the shape of a comment,
# so each case is a snippet whose shape is the point.
#
# The cases asserting silence are the ones that matter: a tool that reported a
# comment stating a reason would delete the comments worth keeping, and the first
# thing anyone would do about that is switch the hook off.

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  AUDITOR="$REPO/tools/audit-comments.py"
  SAMPLE="$BATS_TEST_TMPDIR/sample.py"
  export REPO AUDITOR SAMPLE
}

# Write the snippet on stdin to the sample file and audit it.
audit() {
  cat >"$SAMPLE"
  python3 "$AUDITOR" "$SAMPLE"
}

@test "a section banner is reported" {
  run -1 audit <<<'# ==================== HELPERS ===================='
  [[ $output == *banner* ]]
}

@test "a changelog comment is reported" {
  run -1 audit <<<'# Changed: we now use a set'
  [[ $output == *session-narration* ]]
}

@test "a comment citing the request is reported" {
  run -1 audit <<<'# As requested, the loop breaks early'
  [[ $output == *session-narration* ]]
}

@test "a comment on how the code used to be is reported" {
  run -1 audit <<<'# Previously this returned None'
  [[ $output == *session-narration* ]]
}

@test "an emoji is reported" {
  run -1 audit <<<'# Ship it 🚀'
  [[ $output == *emoji* ]]
}

@test "unverifiable praise is reported" {
  run -1 audit <<<'# A production-ready parser'
  [[ $output == *marketing* ]]
}

@test "a filler opener is reported" {
  run -1 audit <<<'# Note that the value is cached'
  [[ $output == *hedge* ]]
}

@test "an end-of-block marker is reported" {
  run -1 audit <<<'# End of function'
  [[ $output == *end-marker* ]]
}

@test "a label naming a category is reported" {
  run -1 audit <<<'# Error handling'
  [[ $output == *empty-label* ]]
}

@test "a TODO naming no work is reported" {
  run -1 audit <<<'# TODO: implement this'
  [[ $output == *vague-todo* ]]
}

@test "a comment restating its line is reported" {
  run -1 audit <<'PY'
count = 0
count += 1  # increment count
PY
  [[ $output == *restates-code* ]]
}

@test "a comment stating a reason is never reported" {
  # One case per marker family: cause, consequence, requirement, tracked work.
  run -0 audit <<'PY'
# Two, because the vendor rejects a third attempt in the same minute.
RETRIES = 2
# The gateway drops idle connections at 35s, so stay under that.
TIMEOUT = 30
# Required by the spec, which orders the header before the body.
ORDERED = True
# TODO(#412): drop once the vendor ships the fix.
WORKAROUND = True
PY
  [ -z "$output" ]
}

@test "a suppression pragma is left to the typecheck hook" {
  run -0 audit <<'PY'
import os  # noqa: F401
value: int = 1  # type: ignore[assignment]
PY
  [ -z "$output" ]
}

@test "a docstring restating the function name is reported" {
  run -1 audit <<'PY'
def get_user(uid: int) -> str:
    """Get the user."""
    return str(uid)
PY
  [[ $output == *restates-name* ]]
}

@test "a docstring adding a word the name lacks is left alone" {
  run -0 audit <<'PY'
def get_user(uid: int) -> str:
    """Get the user, or the anonymous placeholder when the id is unknown."""
    return str(uid)
PY
  [ -z "$output" ]
}

@test "Args and Returns over a one-line body are reported" {
  run -1 audit <<'PY'
def add(a: int, b: int) -> int:
    """Add two numbers.

    Args:
        a: The first number.
        b: The second number.

    Returns:
        The sum.
    """
    return a + b
PY
  [[ $output == *oversized-docstring* ]]
}

@test "a long docstring stating reasons is left alone" {
  run -0 audit <<'PY'
def normalise(rows: list[str]) -> list[str]:
    """Strip the vendor's byte-order mark.

    The feed is declared UTF-8 but ships a BOM on every line, because the
    vendor writes it with a Windows tool. Downstream parsing breaks on it, so
    it must be removed before anything else reads the rows. The vendor has
    refused to fix this twice, which is why it is handled here rather than
    upstream, and the workaround stays until they do.
    """
    return [row.lstrip("﻿") for row in rows]
PY
  [ -z "$output" ]
}

@test "a licence header is not a finding" {
  run -0 audit <<'PY'
# Copyright 2026 Example
# SPDX-License-Identifier: MIT
PY
  [ -z "$output" ]
}

@test "a module docstring has no name to restate" {
  run -0 audit <<<'"""Sample."""'
  [ -z "$output" ]
}

@test "one finding in a long file stays under the density gate" {
  {
    printf '# ==== BANNER ====\n'
    for n in $(seq 1 200); do printf 'x%s = %s\n' "$n" "$n"; done
  } >"$BATS_TEST_TMPDIR/long.py"
  run -0 python3 "$AUDITOR" "$BATS_TEST_TMPDIR/long.py"
  [ -z "$output" ]
}

@test "a narrated file clears the density gate" {
  run -1 audit <<'PY'
# ==== BANNER ====
# Changed: we now cache
# Note that this matters
# End of section
x = 1
PY
  [ -n "$output" ]
}

@test "whetstone's own tools report nothing" {
  # The auditor read by its own rules, and the two hand-written tools beside it.
  run -0 python3 "$AUDITOR" "$REPO/tools"
  [ -z "$output" ]
}

@test "a line list limits the report to those lines" {
  cat >"$SAMPLE" <<'PY'
# ==== OLD BANNER ====
x = 1
# ==== NEW BANNER ====
y = 2
PY
  run -1 python3 "$AUDITOR" "$SAMPLE:3"
  [[ $output == *":3"* ]]
  [[ $output != *":1"* ]]
}

@test "a path with no line list is read whole" {
  printf '# ==== A ====\n# ==== B ====\n# ==== C ====\n# ==== D ====\n' >"$SAMPLE"
  run -1 python3 "$AUDITOR" "$SAMPLE"
  [ "$(grep -c banner <<<"$output")" -eq 4 ]
}
