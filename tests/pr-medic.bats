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

# On a workflow_run wake after a medic push, github.actor is this bot, and the Claude action's
# agent mode calls checkHumanActor, which throws on a non-User actor absent from allowed_bots.
# The Claude step is not continue-on-error, so that failure would stop the gate -- and the
# push-then-CI-completes wake is the main way a fix reaches it.
@test "the medic's own login is in allowed_bots" {
  local wf="$REPO/.github/workflows/pr-medic.yml"
  # shellcheck disable=SC2016  # grepping for these literals is the point.
  grep -qF 'allowed_bots: ${{ steps.bot.outputs.bots }}' "$wf"
  # shellcheck disable=SC2016
  grep -qF '"$login,$TRIGGER_BOTS" >>"$GITHUB_OUTPUT"' "$wf"
}

# after.sh against stub git and gh. Remote state alone cannot tell a finished run from one
# that resolved a thread and never pushed the fix, so the gate checks the runner as well.

# The state the gate reaches `merge` on: open, clean, no unresolved threads, one green check,
# auto-merge unavailable. A run that does nothing therefore shows `pr merge` in the log, which
# is what makes its absence in the cases below meaningful.
default_view() {
  printf '%s' '{"state":"OPEN","isDraft":false,"isCrossRepository":false,'
  printf '%s' '"mergeStateStatus":"CLEAN","latestReviews":[],"autoMergeRequest":null,'
  printf '%s' '"statusCheckRollup":[{"__typename":"CheckRun","name":"ci","workflowName":"lint",'
  printf '%s' '"status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-01-01T00:00:00Z"}]}'
}

# setup_after [view-json]
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

  GH_LOG="$BATS_TEST_TMPDIR/gh.log"
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
  *"--json state"*) printf '%s\n' "$STUB_VIEW" ;;
esac
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  STUB_VIEW=${1:-$(default_view)}
  STUB_REMOTE_HEAD=$LOCAL_HEAD
  HEAD_BEFORE=$LOCAL_HEAD
  PR=7
  REPO=o/r
  APPROVALS_REQUIRED=0
  ARM_AUTO_MERGE=true
  MERGE_METHOD=squash
  REREQUEST_REVIEWERS=
  GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  export GH_LOG PATH STUB_VIEW STUB_REMOTE_HEAD HEAD_BEFORE PR REPO
  export APPROVALS_REQUIRED ARM_AUTO_MERGE MERGE_METHOD REREQUEST_REVIEWERS GITHUB_STEP_SUMMARY
}

run_after() { (cd "$WORK" && bash "$MEDIC/after.sh"); }

# Commit locally and tell the stub the remote moved with us, as a real push would.
commit_and_push() {
  echo two >>"$WORK/file"
  git -C "$WORK" commit -q -am two
  STUB_REMOTE_HEAD=$(git -C "$WORK" rev-parse HEAD)
  export STUB_REMOTE_HEAD
}

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

# The gate arms auto-merge, so it has to be able to take that back: GitHub merges an armed PR
# on required checks alone, and APPROVALS_REQUIRED lives in this workflow, not in the ruleset.
@test "the gate disarms an armed PR that no longer passes" {
  setup_after "$(default_view | jq -c '.autoMergeRequest = {"enabledAt": "2026-01-01T00:00:00Z"}
    | .statusCheckRollup[0].conclusion = "FAILURE"')"
  run_after
  grep -q 'disable-auto' "$GH_LOG"
}

@test "the gate leaves an armed PR that still passes alone" {
  setup_after "$(default_view | jq -c '.autoMergeRequest = {"enabledAt": "2026-01-01T00:00:00Z"}')"
  run_after
  run ! grep -q 'disable-auto' "$GH_LOG"
}

# after.sh runs after Claude, so its own HEAD already carries Claude's commits. Without the
# baseline from the checkout step, the one run that pushed never re-requests a reviewer.
@test "reviewers are re-requested against the pre-Claude HEAD" {
  setup_after
  REREQUEST_REVIEWERS='copilot-pull-request-reviewer[bot]'
  export REREQUEST_REVIEWERS
  commit_and_push
  run_after
  grep -q 'requested_reviewers' "$GH_LOG"
}

@test "reviewers are not re-requested when this run pushed nothing" {
  setup_after
  REREQUEST_REVIEWERS='copilot-pull-request-reviewer[bot]'
  export REREQUEST_REVIEWERS
  run_after
  run ! grep -q 'requested_reviewers' "$GH_LOG"
}
