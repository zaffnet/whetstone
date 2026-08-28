#!/usr/bin/env bash
# After Claude: update a stale branch, re-request reviewers, then let gate.jq decide whether
# to arm auto-merge. This step runs outside the model's reach, which is the control that
# holds -- an injected instruction cannot reach it.
set -euo pipefail

here=$(dirname "$0")
# shellcheck source=.github/pr-medic/lib.sh
. "$here/lib.sh"

# Before anything irreversible: a fix that was never committed is not on the remote, and
# resolving a thread for it would leave the next run reading "no unresolved threads" as ready
# to merge. This is also why the rebase below is not attempted on a dirty tree.
# Excluding TRUSTED_PATHS: trust-config.sh reverted those to the default branch's copies, so
# a pull request that legitimately edits CLAUDE.md or .claude/ shows up here as a difference
# it did not make. Reading that as an uncommitted fix would reject exactly those PRs.
untracked=()
for p in "${TRUSTED_PATHS[@]}"; do untracked+=(":(exclude)$p"); done
[ -z "$(git status --porcelain -- . "${untracked[@]}")" ] || {
  echo "::error::PR #$PR: the worktree is not clean, so a change here was never committed"
  exit 1
}

repo=$(gh api "repos/$REPO" --jq '{default_branch, allow_auto_merge}')
default_branch=$(jq -r .default_branch <<<"$repo")
# From the checkout step, not from here: this script runs after Claude, so its own
# `git rev-parse HEAD` would already include Claude's commits and the re-request below would
# never fire on the one run that needed it.
head_before=${HEAD_BEFORE:-$(git rev-parse HEAD)}

# Claude may have rebased already, in which case this is a no-op. A push dismisses approvals
# and re-triggers review bots, so it happens after the fixes, never before.
case "$(gh pr view "$PR" --repo "$REPO" --json mergeStateStatus --jq .mergeStateStatus)" in
  BEHIND | DIRTY)
    git fetch origin "$default_branch"
    git rebase "origin/$default_branch" || {
      git rebase --abort
      echo "::error::PR #$PR: cannot rebase onto $default_branch"
      exit 1
    }
    git push --force-with-lease
    ;;
esac

# The gate judges the remote head, and remote state alone cannot tell a finished run apart
# from one that committed a fix and never pushed it.
head_now=$(git rev-parse HEAD)
remote_head=$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq .headRefOid)
[ "$head_now" = "$remote_head" ] || {
  echo "::error::PR #$PR: the checkout is at ${head_now:0:7} but the PR head is ${remote_head:0:7}"
  exit 1
}

# Only now: the checkout is clean and matches the remote, so the fix the model is about to
# claim in a reply is demonstrably on the head the gate will judge. Resolving a thread is not
# reversible, so it happens after every check that could still stop this run.
"$here/threads.sh" apply

# Only when this run pushed. Re-requesting on every wake leaves a review newer than the last
# medic run by construction, which is a self-sustaining loop.
if [ "$head_before" != "$head_now" ]; then
  IFS=, read -r -a reviewers <<<"${REREQUEST_REVIEWERS:-}"
  for reviewer in "${reviewers[@]}"; do
    gh api -X POST "repos/$REPO/pulls/$PR/requested_reviewers" -f "reviewers[]=$reviewer" >/dev/null
  done
fi

view=$(gh pr view "$PR" --repo "$REPO" \
  --json state,isDraft,isCrossRepository,mergeStateStatus,latestReviews,statusCheckRollup,autoMergeRequest)
decision=$(jq -n \
  --argjson pr "$view" \
  --argjson unresolved "$(unresolved_threads "$PR")" \
  --argjson approvals "$(approval_count <<<"$view")" \
  --argjson required "$APPROVALS_REQUIRED" \
  --argjson arm "$ARM_AUTO_MERGE" \
  --argjson auto "$(jq .allow_auto_merge <<<"$repo")" \
  '{pr: $pr, unresolved: $unresolved, approvals: $approvals, approvals_required: $required,
    arm_auto_merge: $arm, allow_auto_merge: $auto}' \
  | jq -c -L "$here" -f "$here/gate.jq")
action=$(jq -r .action <<<"$decision")
reason=$(jq -r .reason <<<"$decision")
echo "::notice::PR #$PR gate: $action ($reason)"
echo "- PR #$PR gate: \`$action\` ($reason)" >>"$GITHUB_STEP_SUMMARY"

# --match-head-commit pins the merge to the head the gate just judged, so a push landing
# between that read and this call cannot slip in unevaluated.
case "$action" in
  arm) gh pr merge "$PR" --repo "$REPO" "--$MERGE_METHOD" --auto --match-head-commit "$remote_head" ;;
  merge) gh pr merge "$PR" --repo "$REPO" "--$MERGE_METHOD" --match-head-commit "$remote_head" ;;
  # The gate is only authoritative if it can take an arming back. GitHub merges an armed PR on
  # required checks alone, and APPROVALS_REQUIRED lives here rather than in the ruleset, so a
  # push that dismissed the approval would otherwise land anyway. `noop` is the armed PR that
  # still passes, and is deliberately not in this list.
  refuse | wait)
    if [ "$(jq -r '.autoMergeRequest != null' <<<"$view")" = true ]; then
      gh pr merge "$PR" --repo "$REPO" --disable-auto
      echo "- PR #$PR: auto-merge disarmed" >>"$GITHUB_STEP_SUMMARY"
    fi
    ;;
esac
