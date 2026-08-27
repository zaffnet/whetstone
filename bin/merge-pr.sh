#!/usr/bin/env bash
# Enables auto-merge on a pull request once it is fit to land, or says why it is not.
# Agents call this instead of `gh pr merge` (ADR 0012): the gate is here, in one place,
# rather than in each agent's judgement.
#
# The gate: the PR is open, mergeable, has at least one approving review from anyone
# (Copilot counts -- see ADR 0012), and every review thread is resolved. Checks are left to
# GitHub: --auto holds the merge until the required ones pass, so a PR whose CI is still
# running is queued rather than refused.
#
# Usage: merge-pr.sh PR_NUMBER [--squash|--rebase]
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ! $1 =~ ^[1-9][0-9]*$ ]]; then
  printf 'Usage: %s PR_NUMBER [--squash|--rebase]\n' "${0##*/}" >&2
  exit 2
fi
pr=$1
method=${2---squash}
if [[ $method != --squash && $method != --rebase ]]; then
  printf '%s: merge method must be --squash or --rebase, got %s\n' "${0##*/}" "$method" >&2
  exit 2
fi

# One round trip for everything the gate needs. latestReviews is the current review per
# author, so a stale approval does not count: `dismiss_stale_reviews` is on, and pushing to
# a branch drops the approvals that were given to the code before it. Copilot's approval
# counts while it stands, which is what "an approval from anyone" means here (ADR 0012).
read -r state mergeable approvals unresolved < <(
  # shellcheck disable=SC2016  # the $-names are GraphQL variables, bound below by -F.
  gh api graphql -F owner='{owner}' -F name='{repo}' -F pr="$pr" \
    -f query='query($owner: String!, $name: String!, $pr: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $pr) {
          state
          mergeable
          latestReviews(first: 50) { nodes { state } }
          reviewThreads(first: 100) { nodes { isResolved } }
        }
      }
    }' \
    --jq '.data.repository.pullRequest
      | [ .state,
          .mergeable,
          ([.latestReviews.nodes[] | select(.state == "APPROVED")] | length),
          ([.reviewThreads.nodes[] | select(.isResolved == false)] | length)
        ] | @tsv'
)

problems=()
[[ $state == OPEN ]] || problems+=("it is $state")
# CONFLICTING is a hard no. UNKNOWN means GitHub has not finished computing the merge
# commit, which --auto will wait out, so it is not a refusal.
[[ $mergeable != CONFLICTING ]] || problems+=("it has conflicts with the base branch")
[[ $approvals -gt 0 ]] || problems+=("no approving review yet")
[[ $unresolved -eq 0 ]] || problems+=("$unresolved review thread(s) unresolved")

if [[ ${#problems[@]} -gt 0 ]]; then
  printf 'not merging #%s:\n' "$pr" >&2
  printf '  %s\n' "${problems[@]}" >&2
  exit 1
fi

gh pr merge "$pr" --auto "$method"
printf 'auto-merge enabled on #%s (%s); GitHub merges it when the required checks pass\n' \
  "$pr" "${method#--}"
