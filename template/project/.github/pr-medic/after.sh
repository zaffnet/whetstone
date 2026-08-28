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
# Two checks, because trust-config.sh reverted TRUSTED_PATHS to the default branch's copies:
# a pull request that legitimately edits CLAUDE.md shows a difference it did not make, so
# those paths are excluded here -- and then compared separately against the state the restore
# left, so an edit Claude made to one of them after the restore is still caught.
excluded=()
for p in "${TRUSTED_PATHS[@]}"; do excluded+=(":(exclude)$p"); done
[ -z "$(git status --porcelain -- . "${excluded[@]}")" ] || {
  echo "::error::PR #$PR: the worktree is not clean, so a change here was never committed"
  exit 1
}
[ "$(trusted_state)" = "$(cat "$TRUSTED_STATE_FILE")" ] || {
  echo "::error::PR #$PR: $(printf '%s ' "${TRUSTED_PATHS[@]}")changed after the restore and was never committed"
  exit 1
}

# The Claude action rewrote origin to embed the token it was given, and since 59b895d that is
# the read-only one -- so a push from here would 403. Point origin back at the plain URL and
# let gh's credential helper supply this step's token, which is the one that can write.
# The gate has read the state it needed, so the restored config is only in the way from here.
restore_pr_config

git remote set-url origin "${GITHUB_SERVER_URL:-https://github.com}/$REPO.git"
gh auth setup-git

# The pull request's own base, not the repository default: mergeStateStatus BEHIND is relative
# to the base, so rebasing a release-targeting PR onto the default branch would force-push
# unrelated history onto it and then merge that.
base_ref=$(gh pr view "$PR" --repo "$REPO" --json baseRefName --jq .baseRefName)

# Claude commits; this pushes. The model's step holds no credential that can write, so there
# is nothing there for an injected instruction to misuse -- which is the boundary the tool
# allowlist could only approximate.
if [ -n "$(git log --oneline "@{upstream}..HEAD" 2>/dev/null)" ]; then
  "$here/push.sh"
fi
# From the checkout step, not from here: this script runs after Claude, so its own
# `git rev-parse HEAD` would already include Claude's commits and the re-request below would
# never fire on the one run that needed it.
head_before=${HEAD_BEFORE:-$(git rev-parse HEAD)}

# Claude may have rebased already, in which case this is a no-op. A push dismisses approvals
# and re-triggers review bots, so it happens after the fixes, never before.
case "$(gh pr view "$PR" --repo "$REPO" --json mergeStateStatus --jq .mergeStateStatus)" in
  BEHIND | DIRTY)
    git fetch origin "$base_ref"
    git rebase "origin/$base_ref" || {
      git rebase --abort
      echo "::error::PR #$PR: cannot rebase onto $base_ref"
      exit 1
    }
    "$here/push.sh" --force-with-lease
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
  --json state,isDraft,isCrossRepository,mergeStateStatus,labels,latestReviews,statusCheckRollup,autoMergeRequest)
decision=$(jq -n \
  --argjson pr "$view" \
  --argjson unresolved "$(unresolved_threads "$PR")" \
  --argjson approvals "$(approval_count <<<"$view")" \
  --argjson required "$APPROVALS_REQUIRED" \
  --argjson may "${MAY_MERGE:-false}" \
  --arg skip "${SKIP_LABEL:-}" \
  '{pr: $pr, unresolved: $unresolved, approvals: $approvals, approvals_required: $required,
    may_merge: $may, skip_label: $skip}' \
  | jq -c -L "$here" -f "$here/gate.jq")
action=$(jq -r .action <<<"$decision")
reason=$(jq -r .reason <<<"$decision")
echo "::notice::PR #$PR gate: $action ($reason)"
echo "- PR #$PR gate: \`$action\` ($reason)" >>"$GITHUB_STEP_SUMMARY"

# --match-head-commit pins the merge to the head the gate just judged, so a push landing
# between that read and this call cannot slip in unevaluated. No --auto: see gate.jq.
case "$action" in
  merge) gh pr merge "$PR" --repo "$REPO" "--$MERGE_METHOD" --match-head-commit "$remote_head" ;;
esac
