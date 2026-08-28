#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# The gate and pick filters, and the gate script against stub git and gh. These cases never
# skip: macos.yml pins the home.bats skip set, and a new skip here would fail it.

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  MEDIC="$REPO/.github/pr-medic"
  # check_counts keys its own-jobs filter on this. CI runs bats inside a workflow, so without
  # pinning it the fixtures would be filtered against whichever workflow ran them.
  export GITHUB_WORKFLOW=pr-medic
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

# The Claude CLI reads .claude/, .mcp.json, CLAUDE.md and .husky from cwd at startup --
# hooks, MCP servers, NODE_OPTIONS -- before any tool-permission gating. claude-code-action
# restores those from base only for entity PR events (run.ts guards restoreConfigFromBase on
# `isEntityContext(context) && context.isPR`), and the medic also wakes on schedule and
# workflow_run. So the checkout step restores them itself, and the deny list is inline rather
# than a path into the PR checkout.
@test "trusted config is restored before Claude runs" {
  local wf="$REPO/.github/workflows/pr-medic.yml"
  # The order matters: after the checkout, before the Claude step.
  at() { grep -n "$1" "$wf" | head -1 | cut -d: -f1; }
  [ "$(at 'gh pr checkout')" -lt "$(at 'trust-config.sh')" ]
  [ "$(at 'trust-config.sh')" -lt "$(at 'Run Claude Code')" ]
  # And no settings file is read out of the checkout.
  run ! grep -q 'settings: \.github' "$wf"
  run ! grep -q 'settings: \.github' "$REPO/.github/workflows/claude.yml"
}

@test "trust-config covers every path the action treats as sensitive" {
  # Mirrors SENSITIVE_PATHS in claude-code-action's restore-config.ts. If upstream adds one,
  # this restores fewer than it should; re-check when bumping the pinned SHA.
  local got
  got=$(sed -n 's/^paths=(\(.*\))$/\1/p' "$MEDIC/trust-config.sh")
  [ "$got" = ".claude .mcp.json .claude.json .gitmodules .ripgreprc CLAUDE.md CLAUDE.local.md .husky" ] || {
    echo "trust-config paths drifted: $got" >&2
    return 1
  }
}

# threads.sh replaces `gh api graphql` on the tool allowlist: that was the last command left
# that could approve or merge, and an allowlist cannot separate it from resolving a thread.
# Keyed on the workflow name, not a literal: renaming the workflow must not silently leave it
# counting its own jobs as pending forever.
@test "check_counts follows the workflow name" {
  local rollup counted
  rollup='{"statusCheckRollup":[{"__typename":"CheckRun","name":"medic","workflowName":"pr-medic","status":"IN_PROGRESS"}]}'
  counted=$(GITHUB_WORKFLOW=something-else jq -c -L "$MEDIC" 'include "lib"; check_counts' <<<"$rollup")
  [ "$counted" = '{"total":1,"failing":0,"pending":1}' ] || {
    echo "expected the row to count under another workflow name, got $counted" >&2
    return 1
  }
  counted=$(jq -c -L "$MEDIC" 'include "lib"; check_counts' <<<"$rollup")
  [ "$counted" = '{"total":0,"failing":0,"pending":0}' ]
}

@test "no gh api reaches the model" {
  local tools
  tools=$(grep -o 'allowedTools "[^"]*"' "$REPO/.github/workflows/pr-medic.yml")
  run ! grep -q 'gh api' <<<"$tools"
  # And denied outright in both workflows, since deny beats allow.
  grep -qF 'Bash(gh api:*)' "$REPO/.github/workflows/pr-medic.yml"
  grep -qF 'Bash(gh api:*)' "$REPO/.github/workflows/claude.yml"
}

setup_threads() {
  export PR=7 REPO=o/r RUNNER_TEMP="$BATS_TEST_TMPDIR"
  export THREADS_FILE="$BATS_TEST_TMPDIR/threads.json"
  export REPLIES_FILE="$BATS_TEST_TMPDIR/replies.json"
  export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  : >"$GH_LOG"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export PATH
  printf '%s\n' '[{"thread_id":"T_known","path":"a.py","line":1,"comments":[]}]' >"$THREADS_FILE"
}

@test "threads.sh replies and resolves only what it was asked to" {
  setup_threads
  printf '%s\n' '[{"thread_id":"T_known","reply":"fixed in abc1234","resolve":true}]' >"$REPLIES_FILE"
  "$MEDIC/threads.sh" apply
  grep -q 'addPullRequestReviewThreadReply' "$GH_LOG"
  grep -q 'resolveReviewThread' "$GH_LOG"
}

@test "threads.sh replies without resolving when not asked" {
  setup_threads
  printf '%s\n' '[{"thread_id":"T_known","reply":"left alone because ..."}]' >"$REPLIES_FILE"
  "$MEDIC/threads.sh" apply
  grep -q 'addPullRequestReviewThreadReply' "$GH_LOG"
  run ! grep -q 'resolveReviewThread' "$GH_LOG"
}

# The model wrote this file, so an id it invented -- or one belonging to another pull request
# -- must not be acted on.
@test "threads.sh refuses a thread id it did not capture" {
  setup_threads
  printf '%s\n' '[{"thread_id":"T_elsewhere","reply":"x","resolve":true}]' >"$REPLIES_FILE"
  run "$MEDIC/threads.sh" apply
  [ "$status" -ne 0 ]
  run ! grep -q 'resolveReviewThread' "$GH_LOG"
}

@test "threads.sh refuses an entry with no reply" {
  setup_threads
  printf '%s\n' '[{"thread_id":"T_known","resolve":true}]' >"$REPLIES_FILE"
  run "$MEDIC/threads.sh" apply
  [ "$status" -ne 0 ]
  run ! grep -q 'resolveReviewThread' "$GH_LOG"
}

# A malformed file is a failure, not a no-op: the gate is about to read "no unresolved
# threads" as ready to merge.
@test "threads.sh refuses a replies file that is not a JSON array" {
  setup_threads
  printf 'not json\n' >"$REPLIES_FILE"
  run "$MEDIC/threads.sh" apply
  [ "$status" -ne 0 ]
}

@test "threads.sh apply is a no-op when the model wrote nothing" {
  setup_threads
  printf '[]\n' >"$REPLIES_FILE"
  "$MEDIC/threads.sh" apply
  run ! grep -q 'addPullRequestReviewThreadReply' "$GH_LOG"
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
  # after.sh posts the model's replies before it gates. Nothing to post here.
  RUNNER_TEMP="$BATS_TEST_TMPDIR"
  THREADS_FILE="$BATS_TEST_TMPDIR/threads.json"
  REPLIES_FILE="$BATS_TEST_TMPDIR/replies.json"
  printf '[]\n' >"$THREADS_FILE"
  printf '[]\n' >"$REPLIES_FILE"
  HEAD_BEFORE=$LOCAL_HEAD
  PR=7
  REPO=o/r
  APPROVALS_REQUIRED=0
  ARM_AUTO_MERGE=true
  MERGE_METHOD=squash
  REREQUEST_REVIEWERS=
  GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  export GH_LOG PATH STUB_VIEW STUB_REMOTE_HEAD HEAD_BEFORE PR REPO
  export RUNNER_TEMP THREADS_FILE REPLIES_FILE
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
