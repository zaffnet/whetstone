#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# bin/merge-pr.sh is the only thing between an agent and `main` (ADR 0012), so the gate is
# tested rather than trusted. Every case puts a fake `gh` first on PATH: it answers the one
# GraphQL query the script makes with a canned row, and records the `gh pr merge` it was
# asked for, so a case can assert the merge did not happen without any network at all.

setup_file() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  export REPO
}

# stub_gh STATE MERGEABLE APPROVALS UNRESOLVED
stub_gh() {
  BIN="$BATS_TEST_TMPDIR/bin"
  MERGE_LOG="$BATS_TEST_TMPDIR/merge.log"
  mkdir -p "$BIN"
  : >"$MERGE_LOG"
  cat >"$BIN/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = api ]; then
  printf '%s\t%s\t%s\t%s\n' '$1' '$2' '$3' '$4'
  exit 0
fi
printf '%s\n' "\$*" >>'$MERGE_LOG'
EOF
  chmod +x "$BIN/gh"
  export BIN MERGE_LOG
}

merge_pr() {
  run env PATH="$BIN:$PATH" "$REPO/bin/merge-pr.sh" "$@"
}

@test "an approved PR with every thread resolved gets auto-merge" {
  stub_gh OPEN MERGEABLE 1 0
  merge_pr 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-merge enabled on #7 (squash)"* ]]
  grep -qx 'pr merge 7 --auto --squash' "$MERGE_LOG"
}

@test "--rebase is passed through" {
  stub_gh OPEN MERGEABLE 1 0
  merge_pr 7 --rebase
  [ "$status" -eq 0 ]
  grep -qx 'pr merge 7 --auto --rebase' "$MERGE_LOG"
}

@test "no approving review means no merge" {
  stub_gh OPEN MERGEABLE 0 0
  merge_pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"no approving review yet"* ]]
  [ ! -s "$MERGE_LOG" ]
}

@test "an unresolved thread means no merge" {
  stub_gh OPEN MERGEABLE 2 3
  merge_pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"3 review thread(s) unresolved"* ]]
  [ ! -s "$MERGE_LOG" ]
}

@test "a conflicting or closed PR means no merge" {
  stub_gh OPEN CONFLICTING 1 0
  merge_pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"conflicts with the base branch"* ]]

  stub_gh CLOSED MERGEABLE 1 0
  merge_pr 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"it is CLOSED"* ]]
  [ ! -s "$MERGE_LOG" ]
}

# UNKNOWN is GitHub still computing the merge commit, not a conflict. Refusing on it would
# make the gate flaky on a PR opened seconds earlier.
@test "a mergeable state GitHub has not computed yet is not a refusal" {
  stub_gh OPEN UNKNOWN 1 0
  merge_pr 7
  [ "$status" -eq 0 ]
  grep -qx 'pr merge 7 --auto --squash' "$MERGE_LOG"
}

@test "a bad argument is rejected before anything is called" {
  stub_gh OPEN MERGEABLE 1 0
  merge_pr
  [ "$status" -eq 2 ]
  merge_pr not-a-number
  [ "$status" -eq 2 ]
  merge_pr 7 --force
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be --squash or --rebase"* ]]
  [ ! -s "$MERGE_LOG" ]
}
