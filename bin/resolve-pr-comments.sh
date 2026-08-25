#!/usr/bin/env bash
# Resolves every unresolved review thread on a pull request in the current repo.
#
# Usage: resolve-pr-comments.sh PR_NUMBER
set -euo pipefail

if [[ $# -ne 1 || ! $1 =~ ^[1-9][0-9]*$ ]]; then
  printf 'Usage: %s PR_NUMBER\n' "${0##*/}" >&2
  exit 2
fi
pr=$1

# The $-prefixed names in the query are GraphQL variables bound by gh from the -F
# flags ($endCursor comes from --paginate), so they must reach the server unexpanded.
# shellcheck disable=SC2016
gh api graphql --paginate \
  -F owner='{owner}' -F name='{repo}' -F pr="$pr" \
  -f query='query($owner: String!, $name: String!, $pr: Int!, $endCursor: String) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100, after: $endCursor) {
          nodes { id isResolved }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | .id' \
  | while IFS= read -r thread_id; do
    # shellcheck disable=SC2016  # $threadId is a GraphQL variable, bound below by -F.
    gh api graphql --silent \
      -F threadId="$thread_id" \
      -f query='mutation($threadId: ID!) {
      resolveReviewThread(input: {threadId: $threadId}) {
        thread { id isResolved }
      }
    }'
  done
