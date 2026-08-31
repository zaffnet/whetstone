#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Cases for tools/find-suppressions.py. Suppressions are read as comment tokens,
# so the two cases that matter are the file-level directives, which silence a
# whole module, and the string literal, which is not a suppression at all.

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  FINDER="$REPO/tools/find-suppressions.py"
  SAMPLE="$BATS_TEST_TMPDIR/sample.py"
  export REPO FINDER SAMPLE
}

find_in() {
  cat >"$SAMPLE"
  python3 "$FINDER" "$SAMPLE"
}

@test "a bare noqa is a suppression" {
  run -1 find_in <<<'import os  # noqa'
  [[ $output == *noqa* ]]
}

@test "a documented noqa is still a suppression" {
  run -1 find_in <<<'import os  # noqa: F401  -- re-exported'
  [[ $output == *noqa* ]]
}

@test "a type: ignore is a suppression" {
  run -1 find_in <<<'x: int = "s"  # type: ignore[assignment]'
  [ -n "$output" ]
}

@test "mypy: ignore-errors silences the module and is a suppression" {
  run -1 find_in <<<'# mypy: ignore-errors'
  [[ $output == *ignore-errors* ]]
}

@test "a pyright rule directive is a suppression" {
  run -1 find_in <<<'# pyright: reportAssignmentType=false'
  [ -n "$output" ]
}

@test "a pyright mode directive is a suppression" {
  run -1 find_in <<<'# pyright: basic'
  [ -n "$output" ]
}

@test "a pyrefly ignore is a suppression" {
  run -1 find_in <<<'x = 1  # pyrefly: ignore'
  [ -n "$output" ]
}

@test "the same words inside a string are not a suppression" {
  run -0 find_in <<<'MSG = "# type: ignore is a suppression"'
  [ -z "$output" ]
}

@test "the words in a docstring are not a suppression" {
  run -0 find_in <<'PY'
"""Explains that # noqa is not allowed here."""
PY
  [ -z "$output" ]
}

@test "an ordinary comment is not a suppression" {
  run -0 find_in <<<'# Two, because the vendor rejects a third attempt.'
  [ -z "$output" ]
}

@test "a line list limits the report to those lines" {
  run -1 find_in <<'PY'
a = 1  # noqa
b = 2  # type: ignore
PY
  # Both without a filter, then only the second with one.
  [ "$(grep -c ':' <<<"$output")" -eq 2 ]
  run -1 python3 "$FINDER" "$SAMPLE:2"
  [[ $output == *":2"* ]]
  [[ $output != *":1"* ]]
}

@test "an unparseable file is left to the checkers" {
  run -0 find_in <<<'def broken( ->'
  [ -z "$output" ]
}
