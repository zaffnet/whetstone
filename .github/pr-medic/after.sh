#!/usr/bin/env bash
# After Claude: update a stale branch, re-request reviewers, then let gate.jq decide whether to
# merge the head it judged. It merges directly, pinned with --match-head-commit; there is no
# arming, see gate.jq. This step runs outside the model's reach, which is the control that
# holds -- an injected instruction cannot reach it.
set -euo pipefail

here=$(dirname "$0")
# shellcheck source=.github/pr-medic/lib.sh
. "$here/lib.sh"

# The Claude step ran with this directory read-only, so a redirection could not rewrite the
# snapshot or trusted-state. threads.sh writes resolved.json into it from here.
chmod -R u+w "$(dirname "$TRUSTED_STATE_FILE")" 2>/dev/null || true

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

# An extraheader beats the credential helper, so a leftover one decides the push instead of
# this step's token. The checkout's is read-only and the Claude action normally replaces it, but
# agent mode continues when that replacement fails -- so clear it rather than depend on it.
git config --unset-all "http.${GITHUB_SERVER_URL:-https://github.com}/.extraheader" 2>/dev/null || true
git remote set-url origin "${GITHUB_SERVER_URL:-https://github.com}/$REPO.git"
gh auth setup-git

# The pull request's own base, not the repository default: mergeStateStatus BEHIND is relative
# to the base, so rebasing a release-targeting PR onto the default branch would force-push
# unrelated history onto it and then merge that.
base_ref=$(gh pr view "$PR" --repo "$REPO" --json baseRefName --jq .baseRefName)

# Claude commits; this pushes. The model's step holds no credential that can write, so there
# is nothing there for an injected instruction to misuse -- which is the boundary the tool
# allowlist could only approximate.
#
# Two shapes, because the prompt tells the model to rebase a conflicting branch itself and that
# a later step pushes the result: new commits on top of the remote branch fast-forward, but a
# rebase rewrites history and HEAD no longer descends from it, where a plain push is rejected
# and the resolved conflict would never reach the gate. --force-with-lease for that case, so a
# remote that moved since the fetch still refuses.
if [ -n "$(git log --oneline "@{upstream}..HEAD" 2>/dev/null)" ]; then
  if git merge-base --is-ancestor "@{upstream}" HEAD; then
    "$here/push.sh"
  else
    "$here/push.sh" --force-with-lease
  fi
fi
# From the checkout step, not from here: this script runs after Claude, so its own
# `git rev-parse HEAD` would already include Claude's commits and the re-request below would
# never fire on the one run that needed it.
head_before=${HEAD_BEFORE:-$(git rev-parse HEAD)}

# Claude may have rebased already, in which case this is a no-op. A push dismisses approvals
# and re-triggers review bots, so it happens after the fixes, never before.
case "$(gh pr view "$PR" --repo "$REPO" --json mergeStateStatus --jq .mergeStateStatus)" in
  BEHIND | DIRTY)
    # --no-recurse-submodules for the same reason trust-config.sh and rebase.sh pass it, and it
    # matters more here: restore_pr_config has put the PR's .gitmodules back, and under the
    # default fetch.recurseSubmodules=on-demand a crafted one can make this step -- the one
    # holding the write token -- contact or block on a remote of the author's choosing.
    git fetch --no-recurse-submodules origin "$base_ref"
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
# reversible, so it happens after every check that could still stop this run. The head goes in
# with it: the check above cannot cover the time apply spends posting, so apply re-reads the
# head at each resolve and undoes its own work if the pull request moved under it.
# The re-runs the model asked for, performed here rather than by it. Its own step holds a
# credential the action copies into the subprocess, and every allowed command takes arguments,
# so `commit.sh "$GH_TOKEN"` was a way to publish it -- the model has no rerun command and no
# actions: write any more. Before the gate reads check state, so a re-run it starts is seen as
# pending and this run does not merge on the old answer. rerun.sh checks each id.
: "${RERUNS_FILE:=${RUNNER_TEMP:?}/pr-medic/reruns.json}"
if [ -s "$RERUNS_FILE" ]; then
  # The model wrote this file, so a malformed one is a failure rather than a silent skip.
  jq -e 'type == "array" and all(.[]; type == "number")' "$RERUNS_FILE" >/dev/null || {
    echo "::error::$RERUNS_FILE is not an array of run ids"
    exit 1
  }
  while read -r run_id; do
    if [ -n "$run_id" ]; then "$here/rerun.sh" "$run_id"; fi
  done < <(jq -r '.[]' "$RERUNS_FILE")
fi

# From here a resolution can exist that only this run can account for, and most of the ways
# this script can stop are set -e exits that run no code path at all -- the reviewer POST
# below, a gate API call, a jq failure. Any of them leaves the thread resolved against a head
# nothing judged, and the next wake reads that as satisfied. So the undo is a trap, cleared
# only once the resolutions are accounted for. `|| true` because threads.sh answers its own
# failure by labelling the pull request, and the original exit status is the useful one.
undo_resolutions_on_exit=1
trap '[ "$undo_resolutions_on_exit" = 0 ] || "$here/threads.sh" undo || true' EXIT

EXPECTED_HEAD=$remote_head "$here/threads.sh" apply

# Only when this run pushed. Re-requesting on every wake leaves a review newer than the last
# medic run by construction, which is a self-sustaining loop.
if [ "$head_before" != "$head_now" ]; then
  IFS=, read -r -a reviewers <<<"${REREQUEST_REVIEWERS:-}"
  # ${reviewers[@]+...} for the empty case this ${REREQUEST_REVIEWERS:-} anticipates: on bash
  # 3.2 the plain expansion is an unbound variable under set -u, and it would fail the gate on
  # exactly the runs that pushed.
  for reviewer in ${reviewers[@]+"${reviewers[@]}"}; do
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
  --arg skip "${SKIP_LABEL:-},${BLOCK_LABEL:-}" \
  '{pr: $pr, unresolved: $unresolved, approvals: $approvals, approvals_required: $required,
    may_merge: $may, skip_label: $skip}' \
  | jq -c -L "$here" -f "$here/gate.jq")
action=$(jq -r .action <<<"$decision")
reason=$(jq -r .reason <<<"$decision")
echo "::notice::PR #$PR gate: $action ($reason)"
echo "- PR #$PR gate: \`$action\` ($reason)" >>"$GITHUB_STEP_SUMMARY"

# --match-head-commit pins the merge to the head the gate just judged, so a push landing
# between that read and this call cannot slip in unevaluated. No --auto: see gate.jq.
#
# Either way the resolutions have to be accounted for. apply checks the head at each resolve,
# but it cannot cover the time spent here: the gate read above and this call both take a while,
# and a push landing in that window leaves this run's resolutions attached to a head nothing
# judged. The refused merge is not the fix -- a later run would read those threads as satisfied
# and merge the new head -- so they are reopened instead.
case "$action" in
  merge)
    gh pr merge "$PR" --repo "$REPO" "--$MERGE_METHOD" --match-head-commit "$remote_head" || {
      echo "::error::PR #$PR: the merge was refused on ${remote_head:0:7}; undoing this run's resolutions"
      exit 1
    }
    ;;
  *)
    # No merge this run, so the resolutions have to hold until another one judges the head.
    now=$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq .headRefOid)
    [ "$now" = "$remote_head" ] || {
      echo "::error::PR #$PR moved to ${now:0:7} after the gate read ${remote_head:0:7}; undoing"
      exit 1
    }
    ;;
esac
# Merged on the head the gate judged, or still on it. Either way the resolutions stand, so the
# block threads.sh took before it resolved anything can come off.
undo_resolutions_on_exit=0
"$here/threads.sh" release
