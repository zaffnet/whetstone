#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Gate and pick filters extracted from pr-medic.yml. These cases never skip:
# macos.yml pins the home.bats skip set, and a new skip here would fail it.

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  EXTRACT="$REPO/tools/extract_pr_medic.py"
  GATE_JQ="$BATS_TEST_TMPDIR/gate.jq"
  PICK_JQ="$BATS_TEST_TMPDIR/pick.jq"
  CHECKS_JQ="$BATS_TEST_TMPDIR/checks.jq"
  python3 "$EXTRACT" pr-medic-gate.jq >"$GATE_JQ"
  python3 "$EXTRACT" pr-medic-pick.jq >"$PICK_JQ"
  python3 "$EXTRACT" pr-medic-checks.jq >"$CHECKS_JQ"
}

# gh pr view --json statusCheckRollup returns two shapes. Getting this wrong is what made
# every commit status count as pending forever, and what let TIMED_OUT read as passing.
@test "check rollup buckets both CheckRun and StatusContext" {
  local got
  got=$(
    jq -c -f "$CHECKS_JQ" <<'JSON'
{"statusCheckRollup": [
  {"__typename": "CheckRun", "name": "lint", "status": "COMPLETED", "conclusion": "SUCCESS"},
  {"__typename": "CheckRun", "name": "slow", "status": "IN_PROGRESS"},
  {"__typename": "CheckRun", "name": "gone", "status": "COMPLETED", "conclusion": "TIMED_OUT"},
  {"__typename": "CheckRun", "name": "skip", "status": "COMPLETED", "conclusion": "SKIPPED"},
  {"__typename": "StatusContext", "context": "legacy", "state": "SUCCESS"},
  {"__typename": "StatusContext", "context": "waiting", "state": "PENDING"},
  {"__typename": "StatusContext", "context": "broke", "state": "ERROR"},
  {"__typename": "StatusContext", "context": "pr-medic", "state": "SUCCESS"}
]}
JSON
  )
  [ "$got" = '{"total":7,"failing":2,"pending":2}' ] || {
    echo "check rollup: got $got" >&2
    return 1
  }
}

@test "an empty rollup counts zero, so the gate can refuse it" {
  local got
  got=$(printf '%s' '{"statusCheckRollup": []}' | jq -c -f "$CHECKS_JQ")
  [ "$got" = '{"total":0,"failing":0,"pending":0}' ]
}

@test "pr-medic marker copies match, jq parses, and shellcheck passes" {
  python3 "$EXTRACT" --check
}

# The reason as well as the action: decide has four separate wait branches, so asserting
# only the action lets a case pass for the wrong reason.
@test "gate fixtures" {
  local n name expect expect_reason got got_reason decision
  n=$(jq 'length' "$REPO/tests/fixtures/pr-medic/gate.json")
  [ "$n" -gt 0 ]
  i=0
  while [ "$i" -lt "$n" ]; do
    name=$(jq -r --argjson i "$i" '.[$i].name' "$REPO/tests/fixtures/pr-medic/gate.json")
    expect=$(jq -r --argjson i "$i" '.[$i].expect' "$REPO/tests/fixtures/pr-medic/gate.json")
    expect_reason=$(jq -r --argjson i "$i" '.[$i].expect_reason' "$REPO/tests/fixtures/pr-medic/gate.json")
    [ "$expect_reason" != "null" ] || {
      echo "gate fixture '$name': no expect_reason" >&2
      return 1
    }
    decision=$(jq -c --argjson i "$i" '.[$i].input' "$REPO/tests/fixtures/pr-medic/gate.json" | jq -c -f "$GATE_JQ")
    got=$(printf '%s' "$decision" | jq -r .action)
    got_reason=$(printf '%s' "$decision" | jq -r .reason)
    [ "$got" = "$expect" ] && [ "$got_reason" = "$expect_reason" ] || {
      echo "gate fixture '$name': expected $expect ($expect_reason), got $got ($got_reason)" >&2
      return 1
    }
    i=$((i + 1))
  done
}

@test "pick fixtures" {
  local n name expect got
  n=$(jq 'length' "$REPO/tests/fixtures/pr-medic/pick.json")
  [ "$n" -gt 0 ]
  i=0
  while [ "$i" -lt "$n" ]; do
    name=$(jq -r --argjson i "$i" '.[$i].name' "$REPO/tests/fixtures/pr-medic/pick.json")
    expect=$(jq -c --argjson i "$i" '.[$i].expect' "$REPO/tests/fixtures/pr-medic/pick.json")
    got=$(jq -c --argjson i "$i" '.[$i].input' "$REPO/tests/fixtures/pr-medic/pick.json" | jq -c -f "$PICK_JQ") || {
      echo "pick fixture '$name': jq aborted" >&2
      return 1
    }
    [ "$got" = "$expect" ] || {
      echo "pick fixture '$name': expected $expect, got $got" >&2
      return 1
    }
    i=$((i + 1))
  done
}

# The gate's blocked flag, run as a script against stub git and gh. The Claude step is
# continue-on-error, so a failure part-way through -- a thread resolved, the fix not pushed --
# reaches the gate as remote state that looks finished. These cases pin that it refuses.
setup_after() {
  AFTER="$BATS_TEST_TMPDIR/after.sh"
  python3 "$EXTRACT" pr-medic-after.sh >"$AFTER"
  export GATE_JQ CHECKS_JQ
  GATE_JQ=$(cat "$BATS_TEST_TMPDIR/gate.jq")
  CHECKS_JQ=$(cat "$BATS_TEST_TMPDIR/checks.jq")

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
  export STUB_VIEW="$BATS_TEST_TMPDIR/view.json"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$*" in
  *"--json headRefOid --jq"*) printf '%s\n' "$STUB_REMOTE_HEAD" ;;
  *"api graphql"*) printf '%s\n' '{"total":0,"unresolved":0}' ;;
  *"pr view"*"--json number"*) cat "$STUB_VIEW" ;;
esac
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export PATH

  export PR=7 REPO=o/r GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  export GITHUB_OUTPUT=/dev/null
  # The gate reaches `merge` on this state: open, clean, no unresolved threads, one green
  # check, auto-merge unavailable. So a run that does nothing must show `pr merge` in the log,
  # which is what makes its absence in the cases below meaningful.
  export UPDATE_STALE_BRANCH=false ALLOW_AUTO_MERGE=false ARM_AUTO_MERGE=true
  export APPROVALS_REQUIRED=0 DRY_RUN=false CLAUDE_OUTCOME=success
  export STUB_REMOTE_HEAD="$LOCAL_HEAD" HEAD_BEFORE="$LOCAL_HEAD"
}

write_view() {
  cat >"$STUB_VIEW" <<JSON
{"number": 7, "state": "OPEN", "isDraft": false, "isCrossRepository": false,
 "author": {"login": "human"}, "mergeStateStatus": "CLEAN", "latestReviews": [],
 "statusCheckRollup": [{"__typename": "CheckRun", "name": "ci", "status": "COMPLETED", "conclusion": "SUCCESS"}],
 "autoMergeRequest": null, "headRefOid": "$STUB_REMOTE_HEAD"}
JSON
}

run_after() {
  write_view
  (cd "$WORK" && bash "$AFTER")
}

@test "gate merges when the checkout is clean and matches the PR head" {
  setup_after
  run_after
  grep -q 'pr merge' "$GH_LOG"
}

@test "gate refuses to merge when the Claude step failed" {
  setup_after
  CLAUDE_OUTCOME=failure
  run_after
  run ! grep -q 'pr merge' "$GH_LOG"
  grep -q 'did not finish' "$GITHUB_STEP_SUMMARY"
}

@test "gate refuses to merge when an edit was never committed" {
  setup_after
  echo two >"$WORK/uncommitted"
  run_after
  run ! grep -q 'pr merge' "$GH_LOG"
  grep -q 'worktree is not clean' "$GITHUB_STEP_SUMMARY"
}

@test "gate refuses to merge when a commit was never pushed" {
  setup_after
  echo two >>"$WORK/file"
  git -C "$WORK" commit -q -am two
  run_after
  run ! grep -q 'pr merge' "$GH_LOG"
  grep -q 'never pushed' "$GITHUB_STEP_SUMMARY"
}

# The staleness re-check, run as a script against a stub gh. The per-PR mutex queues rather
# than cancels, so this step is the only thing between a selection pick made minutes ago and
# a second Claude run that spends the attempt budget on a head someone else already fixed.
setup_fresh() {
  FRESH="$BATS_TEST_TMPDIR/fresh.sh"
  python3 "$EXTRACT" pr-medic-fresh.sh >"$FRESH"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$STUB_NOW"
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export PATH

  export PR=7 REPO=o/r
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/fresh.out"
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/fresh.md"
  : >"$GITHUB_OUTPUT"
  : >"$GITHUB_STEP_SUMMARY"
  export PICKED_HEADS='{"7":"aaaaaaaa"}'
  export STUB_NOW='{"state":"OPEN","headRefOid":"aaaaaaaa"}'
}

fresh_ok() {
  bash "$FRESH"
  grep -q '^ok=true$' "$GITHUB_OUTPUT"
}

fresh_stands_down() {
  bash "$FRESH"
  grep -q '^ok=false$' "$GITHUB_OUTPUT"
}

@test "fresh proceeds when the PR is open at the head pick judged" {
  setup_fresh
  fresh_ok
}

@test "fresh stands down when the head moved while the job waited" {
  setup_fresh
  STUB_NOW='{"state":"OPEN","headRefOid":"bbbbbbbb"}'
  fresh_stands_down
  grep -q 'head moved' "$GITHUB_STEP_SUMMARY"
}

@test "fresh stands down when the PR closed while the job waited" {
  setup_fresh
  STUB_NOW='{"state":"MERGED","headRefOid":"aaaaaaaa"}'
  fresh_stands_down
  grep -q 'no longer open' "$GITHUB_STEP_SUMMARY"
}

@test "fresh stands down when the PR is unreadable" {
  setup_fresh
  STUB_NOW=''
  fresh_stands_down
  grep -q 'could not re-read' "$GITHUB_STEP_SUMMARY"
}

@test "fresh stands down when pick recorded no head for this PR" {
  setup_fresh
  PICKED_HEADS='{"9":"aaaaaaaa"}'
  fresh_stands_down
  grep -q 'recorded no head' "$GITHUB_STEP_SUMMARY"
}
