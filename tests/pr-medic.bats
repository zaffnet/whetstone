#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# The gate and pick filters, and the gate script against stub git and gh. These cases never
# skip: macos.yml pins the home.bats skip set, and a new skip here would fail it.

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  MEDIC="$REPO/.github/pr-medic"
}

# gh pr view --json statusCheckRollup returns two shapes. Getting this wrong is what made
# every commit status count as pending forever, and what let TIMED_OUT read as passing.
@test "check_counts buckets both CheckRun and StatusContext" {
  local got
  got=$(
    jq -c -L "$MEDIC" 'include "lib"; check_counts' <<'JSON'
{"statusCheckRollup": [
  {"__typename": "CheckRun", "name": "lint", "status": "COMPLETED", "conclusion": "SUCCESS"},
  {"__typename": "CheckRun", "name": "slow", "status": "IN_PROGRESS"},
  {"__typename": "CheckRun", "name": "gone", "status": "COMPLETED", "conclusion": "TIMED_OUT"},
  {"__typename": "CheckRun", "name": "skip", "status": "COMPLETED", "conclusion": "SKIPPED"},
  {"__typename": "StatusContext", "context": "legacy", "state": "SUCCESS"},
  {"__typename": "StatusContext", "context": "waiting", "state": "PENDING"},
  {"__typename": "StatusContext", "context": "broke", "state": "ERROR"},
  {"__typename": "CheckRun", "name": "medic", "status": "IN_PROGRESS", "workflowName": "pr-medic"}
]}
JSON
  )
  [ "$got" = '{"total":7,"failing":2,"pending":2}' ] || {
    echo "check_counts: got $got" >&2
    return 1
  }
}

@test "an empty rollup counts zero, so the gate can refuse it" {
  local got
  got=$(printf '%s' '{"statusCheckRollup": []}' | jq -c -L "$MEDIC" 'include "lib"; check_counts')
  [ "$got" = '{"total":0,"failing":0,"pending":0}' ]
}

# The reason as well as the action: decide has four separate wait branches, so asserting only
# the action lets a case pass for the wrong reason.
@test "gate fixtures" {
  local fixtures n i name expect expect_reason decision got got_reason
  fixtures="$REPO/tests/fixtures/pr-medic/gate.json"
  n=$(jq 'length' "$fixtures")
  [ "$n" -gt 0 ]
  i=0
  while [ "$i" -lt "$n" ]; do
    name=$(jq -r --argjson i "$i" '.[$i].name' "$fixtures")
    expect=$(jq -r --argjson i "$i" '.[$i].expect' "$fixtures")
    expect_reason=$(jq -r --argjson i "$i" '.[$i].expect_reason' "$fixtures")
    decision=$(jq -c --argjson i "$i" '.[$i].input' "$fixtures" \
      | jq -c -L "$MEDIC" -f "$MEDIC/gate.jq")
    got=$(jq -r .action <<<"$decision")
    got_reason=$(jq -r .reason <<<"$decision")
    [ "$got" = "$expect" ] && [ "$got_reason" = "$expect_reason" ] || {
      echo "gate '$name': expected $expect ($expect_reason), got $got ($got_reason)" >&2
      return 1
    }
    i=$((i + 1))
  done
}

@test "pick fixtures" {
  local fixtures n i name expect got
  fixtures="$REPO/tests/fixtures/pr-medic/pick.json"
  n=$(jq 'length' "$fixtures")
  [ "$n" -gt 0 ]
  i=0
  while [ "$i" -lt "$n" ]; do
    name=$(jq -r --argjson i "$i" '.[$i].name' "$fixtures")
    expect=$(jq -c --argjson i "$i" '.[$i].expect' "$fixtures")
    got=$(jq -c --argjson i "$i" '.[$i].input' "$fixtures" \
      | jq -c -L "$MEDIC" -f "$MEDIC/pick.jq") || {
      echo "pick '$name': jq aborted" >&2
      return 1
    }
    [ "$got" = "$expect" ] || {
      echo "pick '$name': expected $expect, got $got" >&2
      return 1
    }
    i=$((i + 1))
  done
}

# The Claude step is not continue-on-error, so a failure between resolving a thread and
# pushing the fix fails the job and after.sh never runs. That replaces the outcome
# bookkeeping the gate script used to carry.
@test "a Claude failure stops the run before the gate" {
  run ! grep -q continue-on-error "$REPO/.github/workflows/pr-medic.yml"
}

# after.sh against stub git and gh. Remote state alone cannot tell a finished run from one
# that resolved a thread and never pushed the fix, so the gate checks the runner as well.
setup_after() {
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
  git -C "$WORK" init -q -b main
  git -C "$WORK" config user.email bot@example.com
  git -C "$WORK" config user.name bot
  echo one >"$WORK/file"
  git -C "$WORK" add file
  git -C "$WORK" commit -q -m one
  LOCAL_HEAD=$(git -C "$WORK" rev-parse HEAD)

  export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  : >"$GH_LOG"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$*" in
  *"api graphql"*) printf '0\n' ;;
  *"api repos/o/r"*) printf '{"default_branch":"main","allow_auto_merge":false}\n' ;;
  *"--json mergeStateStatus"*) printf 'CLEAN\n' ;;
  *"--json headRefOid"*) printf '%s\n' "$STUB_REMOTE_HEAD" ;;
  *"--json state"*)
    printf '{"state":"OPEN","isDraft":false,"isCrossRepository":false,"mergeStateStatus":"CLEAN","latestReviews":[],"autoMergeRequest":null,"statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]}\n'
    ;;
esac
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export PATH

  # This state reaches `merge`: open, clean, no unresolved threads, one green check,
  # auto-merge unavailable. So a run that does nothing must show `pr merge` in the log, which
  # is what makes its absence in the cases below meaningful.
  export PR=7 REPO=o/r APPROVALS_REQUIRED=0 ARM_AUTO_MERGE=true MERGE_METHOD=squash
  export REREQUEST_REVIEWERS=""
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  export STUB_REMOTE_HEAD="$LOCAL_HEAD"
}

run_after() { (cd "$WORK" && bash "$MEDIC/after.sh"); }

@test "the gate merges when the checkout is clean and matches the PR head" {
  setup_after
  run_after
  grep -q 'pr merge' "$GH_LOG"
}

@test "the gate refuses to merge when an edit was never committed" {
  setup_after
  echo two >"$WORK/uncommitted"
  run run_after
  [ "$status" -ne 0 ]
  run ! grep -q 'pr merge' "$GH_LOG"
}

@test "the gate refuses to merge when a commit was never pushed" {
  setup_after
  echo two >>"$WORK/file"
  git -C "$WORK" commit -q -am two
  run run_after
  [ "$status" -ne 0 ]
  run ! grep -q 'pr merge' "$GH_LOG"
}
