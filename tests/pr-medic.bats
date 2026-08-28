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
  # Anchored on the commands, not on prose: matching the first occurrence of the bare name
  # picked up the comment above the step, so moving the command itself left this green.
  at() { grep -nE "$1" "$wf" | head -1 | cut -d: -f1; }
  [ "$(at '^ +gh pr checkout ')" -lt "$(at '^ +\.github/pr-medic/trust-config\.sh$')" ]
  [ "$(at '^ +\.github/pr-medic/trust-config\.sh$')" -lt "$(at '^ +- name: Run Claude Code$')" ]
  # And the medic's own scripts are taken from the default branch before any of them runs.
  [ "$(at '^ +git checkout .origin/.base. -- \.github/pr-medic')" -lt \
    "$(at '^ +\.github/pr-medic/trust-config\.sh$')" ]
  # And no settings file is read out of the checkout.
  run ! grep -q 'settings: \.github' "$wf"
  run ! grep -q 'settings: \.github' "$REPO/.github/workflows/claude.yml"
}

@test "trust-config covers every path the action treats as sensitive" {
  # Mirrors SENSITIVE_PATHS in claude-code-action's restore-config.ts. If upstream adds one,
  # this restores fewer than it should; re-check when bumping the pinned SHA.
  local got
  got=$(sed -n 's/^TRUSTED_PATHS=(\(.*\))$/\1/p' "$MEDIC/lib.sh")
  [ "$got" = ".claude .mcp.json .claude.json .gitmodules .ripgreprc CLAUDE.md CLAUDE.local.md .husky" ] || {
    echo "TRUSTED_PATHS drifted: $got" >&2
    return 1
  }
  # One list, two readers: trust-config.sh reverts these, so after.sh must not read the
  # difference as an uncommitted fix and reject the PR that legitimately edited one.
  grep -q 'TRUSTED_PATHS\[@\]' "$MEDIC/trust-config.sh"
  grep -q 'TRUSTED_PATHS\[@\]' "$MEDIC/after.sh"
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

# Denying `gh api` is worth nothing if something on the allowlist can launch it. `uv run gh
# api ...` matches `Bash(uv run:*)`, and `just` reads a justfile out of the PR checkout, so
# either one hands a prompt-injected instruction the write token.
@test "no launcher can run PR-controlled code" {
  local tools
  tools=$(grep -o 'allowedTools "[^"]*"' "$REPO/.github/workflows/pr-medic.yml")
  # `uv run <anything>`; `just` reads a justfile out of the PR checkout; `git rebase --exec`
  # and `git fetch --upload-pack` both take a command. None may be reachable with arguments.
  run ! grep -qE 'uv run|Bash\(just|Bash\(git rebase:|Bash\(git fetch' <<<"$tools"
  # Only the two rebase subcommands that take no command, plus the no-argument helper.
  grep -qF 'Bash(git rebase --continue)' <<<"$tools"
  grep -qF 'Bash(git rebase --abort)' <<<"$tools"
  grep -qF 'Bash(.github/pr-medic/rebase.sh)' <<<"$tools"
  # And the force push takes no refspec, or it could name the default branch.
  run ! grep -q 'force-with-lease:\*' <<<"$tools"
  grep -qF 'Bash(git push --force-with-lease)' <<<"$tools"
  # Denied outright as well, since deny beats allow.
  local deny
  deny=$(grep -o '"deny":\[[^]]*\]' "$REPO/.github/workflows/pr-medic.yml")
  for entry in 'Bash(just:*)' 'Bash(uv run:*)' 'Bash(git fetch:*)' \
    'Bash(git rebase --exec:*)' 'Bash(git rebase -x:*)' 'Write(.git/**)'; do
    grep -qF "$entry" <<<"$deny" || {
      echo "missing deny entry: $entry" >&2
      return 1
    }
  done
}

# rebase.sh takes no arguments at all: the destination comes from the API, not the caller, so
# there is nothing for an injected instruction to redirect.
@test "rebase.sh accepts no destination from its caller" {
  # shellcheck disable=SC2016  # a grep pattern for positional parameters, not an expansion.
  run ! grep -qE '\$1|\$\{1|\$@|\$\*' "$MEDIC/rebase.sh"
}

# Resolving a thread is not reversible. If it happened before the runner checks, a run that
# exits on an unpushed fix would leave the next one reading "no unresolved threads" as ready to
# merge -- the exact partial-run state the gate exists to catch.
@test "threads are resolved only after the checks that can still stop the run" {
  at() { grep -nE "$1" "$MEDIC/after.sh" | head -1 | cut -d: -f1; }
  [ "$(at 'git status --porcelain')" -lt "$(at 'threads\.sh" apply')" ]
  [ "$(at 'remote_head=')" -lt "$(at 'threads\.sh" apply')" ]
  # The invocation, not the bare name: the bare name matched the header comment on line 2.
  [ "$(at 'threads\.sh" apply')" -lt "$(at 'jq .* -f .*gate\.jq')" ]
}

# authorAssociation is not a permission check: MEMBER only means org membership, whose base
# role may be Read, and a collaborator can hold Read or Triage. So the count asks for the
# permission. It excluded Copilot before, but only by accident.
# approval_count LOGIN:STATE ... -> the count, against a stub permission API.
# Arguments rather than hand-built JSON: quoting a nested object inside a bats assertion is
# its own source of bugs, and jq -n cannot get it wrong.
approvals_for() {
  local reviews
  reviews=$(printf '%s\n' "$@" | jq -R -s -c '
    split("\n") | map(select(length > 0) | split(":"))
    | {latestReviews: map({author: {login: .[0]}, state: (.[1] // "APPROVED")})}')
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *collaborators/writer/permission*) printf 'write\n' ;;
  *collaborators/owner/permission*) printf 'admin\n' ;;
  *collaborators/reader/permission*) printf 'read\n' ;;
  *collaborators/triager/permission*) printf 'read\n' ;;
  *) exit 1 ;; # not a collaborator at all: the API 404s
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" REPO=o/r bash -c \
    ". '$MEDIC/lib.sh'; approval_count" <<<"$reviews"
}

@test "approval_count counts push access, not association" {
  [ "$(approvals_for writer)" = 1 ]
  [ "$(approvals_for owner)" = 1 ]
  # Read and Triage roles cannot push, so their approval must not satisfy the gate.
  [ "$(approvals_for reader)" = 0 ]
  [ "$(approvals_for triager)" = 0 ]
  # Copilot reviews as a non-collaborator, so the permission lookup 404s. The old
  # authorAssociation test excluded it too, but only by accident.
  [ "$(approvals_for copilot-pull-request-reviewer)" = 0 ]
}

@test "approval_count ignores non-approvals and counts a login once" {
  [ "$(approvals_for writer:CHANGES_REQUESTED)" = 0 ]
  [ "$(approvals_for writer:COMMENTED)" = 0 ]
  [ "$(approvals_for writer writer)" = 1 ]
  [ "$(approvals_for writer owner)" = 2 ]
  [ "$(approvals_for writer:APPROVED reader:APPROVED)" = 1 ]
  [ "$(printf '' | approvals_for)" = 0 ]
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

# `last: 100` shows the newest comments, so a truncated thread is one whose beginning is
# missing. Replying is fine; recording it as satisfied is not.
@test "threads.sh will not resolve a thread it could only read in part" {
  setup_threads
  printf '%s\n' '[{"thread_id":"T_long","path":"a.py","line":1,"truncated":true,"comments":[]}]' >"$THREADS_FILE"
  printf '%s\n' '[{"thread_id":"T_long","reply":"x","resolve":true}]' >"$REPLIES_FILE"
  run "$MEDIC/threads.sh" apply
  [ "$status" -ne 0 ]
  run ! grep -q 'resolveReviewThread' "$GH_LOG"
}

@test "threads.sh still replies to a thread it could only read in part" {
  setup_threads
  printf '%s\n' '[{"thread_id":"T_long","path":"a.py","line":1,"truncated":true,"comments":[]}]' >"$THREADS_FILE"
  printf '%s\n' '[{"thread_id":"T_long","reply":"partial read, leaving open"}]' >"$REPLIES_FILE"
  "$MEDIC/threads.sh" apply
  grep -q 'addPullRequestReviewThreadReply' "$GH_LOG"
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
  printf '%s' '{"state":"OPEN","isDraft":false,"isCrossRepository":false,"labels":[],'
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
  *"api repos/o/r"*) printf 'main\n' ;;
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
  MAY_MERGE=true
  MERGE_METHOD=squash
  SKIP_LABEL=no-medic
  REREQUEST_REVIEWERS=
  GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  export GH_LOG PATH STUB_VIEW STUB_REMOTE_HEAD HEAD_BEFORE PR REPO
  export RUNNER_TEMP THREADS_FILE REPLIES_FILE
  export APPROVALS_REQUIRED MAY_MERGE MERGE_METHOD REREQUEST_REVIEWERS GITHUB_STEP_SUMMARY
  export SKIP_LABEL
  # trust-config.sh records this after restoring TRUSTED_PATHS; after.sh compares against it,
  # so an edit Claude makes to a restored path is caught even though those paths are excluded
  # from the plain clean-worktree check.
  TRUSTED_STATE_FILE="$BATS_TEST_TMPDIR/trusted-state"
  export TRUSTED_STATE_FILE
  # shellcheck source=/dev/null
  (cd "$WORK" && . "$MEDIC/lib.sh" && trusted_state) >"$TRUSTED_STATE_FILE"
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

# trust-config.sh reverts CLAUDE.md and friends to the default branch's copies, so a PR that
# legitimately edits one leaves the worktree differing from its head. Rejecting that would
# reject exactly those pull requests -- so the difference the restore itself made is recorded
# and allowed. The order matters: revert, then record.
@test "the gate ignores the difference the restore itself made" {
  setup_after
  echo "reverted to the default branch's copy" >"$WORK/CLAUDE.md"
  mkdir -p "$WORK/.claude"
  echo '{}' >"$WORK/.claude/settings.json"
  # shellcheck source=/dev/null
  (cd "$WORK" && . "$MEDIC/lib.sh" && trusted_state) >"$TRUSTED_STATE_FILE"
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

# The medic never arms, so it never disarms either: it merges the head the gate just judged, or
# it does nothing. A pull request somebody armed by hand belongs to GitHub.
@test "the gate never delegates to auto-merge" {
  setup_after
  run_after
  run ! grep -qE -- '--auto|disable-auto' "$GH_LOG"
  grep -q -- '--match-head-commit' "$GH_LOG"
}

@test "a hand-armed PR is left to GitHub" {
  setup_after "$(default_view | jq -c '.autoMergeRequest = {"enabledAt": "2026-01-01T00:00:00Z"}')"
  run_after
  run ! grep -q 'pr merge' "$GH_LOG"
}

# Excluding TRUSTED_PATHS from the clean check must not hide an edit Claude made to one of
# them after trust-config.sh restored it -- the thread asking for that edit would then be
# resolved against a head the fix is missing from.
@test "the gate catches an uncommitted edit to a restored path" {
  setup_after
  echo "edited after the restore" >>"$WORK/CLAUDE.md"
  run run_after
  [ "$status" -ne 0 ]
  run ! grep -q 'pr merge' "$GH_LOG"
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
