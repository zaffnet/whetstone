#!/usr/bin/env bash
# After Claude: update a stale branch, re-request reviewers, then let gate.jq decide whether
# to arm auto-merge. This step runs outside the model's reach, which is the control that
# holds -- an injected instruction cannot reach it.
set -euo pipefail

here=$(dirname "$0")
# shellcheck source=.github/pr-medic/lib.sh
. "$here/lib.sh"

repo=$(gh api "repos/$REPO" --jq '{default_branch, allow_auto_merge}')
default_branch=$(jq -r .default_branch <<<"$repo")
head_before=$(git rev-parse HEAD)

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

# The gate judges the remote head. A fix that was never committed, or never pushed, is not
# in it -- and remote state alone cannot tell that apart from a run that finished cleanly.
[ -z "$(git status --porcelain)" ] || {
  echo "::error::PR #$PR: the worktree is not clean, so a change here was never committed"
  exit 1
}
head_now=$(git rev-parse HEAD)
remote_head=$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq .headRefOid)
[ "$head_now" = "$remote_head" ] || {
  echo "::error::PR #$PR: the checkout is at ${head_now:0:7} but the PR head is ${remote_head:0:7}"
  exit 1
}

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
  --argjson required "$APPROVALS_REQUIRED" \
  --argjson arm "$ARM_AUTO_MERGE" \
  --argjson auto "$(jq .allow_auto_merge <<<"$repo")" \
  '{pr: $pr, unresolved: $unresolved, approvals_required: $required,
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
esac
