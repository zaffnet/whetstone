#!/usr/bin/env bash
# Which open pull requests is this event about, and can the medic help any of them? Writes a
# JSON array of PR numbers to $GITHUB_OUTPUT as `prs`, and its length as `count`.
set -euo pipefail

here=$(dirname "$0")
# shellcheck source=.github/pr-medic/lib.sh
. "$here/lib.sh"

event() { jq -r "$1" "$GITHUB_EVENT_PATH"; }

# "This event names no pull request" and "sweep every open one" are different answers. Only
# schedule and a blank dispatch mean sweep; without that distinction, a comment on a plain
# issue rebases and force-pushes every open PR. --limit paginates internally, so 100 is a
# ceiling rather than a page size.
sweep() { gh pr list --repo "$REPO" --state open --limit 100 --json number --jq '.[].number'; }

candidates=""
case "$GITHUB_EVENT_NAME" in
  schedule) candidates=$(sweep) ;;
  workflow_dispatch) candidates=${PR_INPUT:-$(sweep)} ;;
  workflow_run) candidates=$(gh api "repos/$REPO/commits/$HEAD_SHA/pulls" --jq '.[].number') ;;
  pull_request_review | pull_request_review_comment) candidates=$(event '.pull_request.number') ;;
  issue_comment) candidates=$(event '.issue | select(.pull_request) | .number') ;;
esac

# An @claude mention is the mention job's work. The only PR this event names is the one
# being mentioned on, so drop the lot.
if [ -f "${GITHUB_EVENT_PATH:-}" ]; then
  case "$(event '[.comment.body, .review.body, .issue.body, .issue.title] | map(select(.)) | join(" ")')" in
    *@claude*) candidates="" ;;
  esac
fi

state=$(mktemp)
view=$(mktemp)
while read -r pr; do
  [ -n "$pr" ] || continue
  gh pr view "$pr" --repo "$REPO" \
    --json number,state,isDraft,isCrossRepository,labels,mergeStateStatus,autoMergeRequest,latestReviews,statusCheckRollup \
    >"$view"
  jq -c --argjson unresolved "$(unresolved_threads "$pr")" \
    --argjson approvals "$(approval_count <"$view")" \
    '{view: ., unresolved: $unresolved, approvals: $approvals}' <"$view" >>"$state"
done <<<"$candidates"

selected=$(jq -s -c \
  --arg skip "${SKIP_LABEL:-}" \
  --argjson required "${APPROVALS_REQUIRED:-0}" \
  --argjson arm "${ARM_AUTO_MERGE:-false}" \
  '{prs: ., skip_label: $skip, approvals_required: $required, arm_auto_merge: $arm}' "$state" \
  | jq -c -L "$here" -f "$here/pick.jq")

echo "prs=$selected" >>"$GITHUB_OUTPUT"
echo "count=$(jq length <<<"$selected")" >>"$GITHUB_OUTPUT"
echo "Picked $(jq length <<<"$selected") of $(wc -l <"$state" | tr -d ' '): $selected" >>"$GITHUB_STEP_SUMMARY"
