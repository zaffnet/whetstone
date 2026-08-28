# shellcheck shell=bash
# Sourced by pick.sh and after.sh. Expects REPO and GH_TOKEN in the environment.

# How many review threads on a pull request are unresolved. Asks for totalCount as well as
# the page: past 100 threads the page reports *fewer* unresolved than there are, so report
# one unresolved and let the caller refuse rather than read an over-long list as clean.
unresolved_threads() {
  # shellcheck disable=SC2016  # $owner, $name and $pr are GraphQL variables.
  gh api graphql -F owner="${REPO%/*}" -F name="${REPO#*/}" -F pr="$1" -f query='
    query($owner: String!, $name: String!, $pr: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100) { totalCount nodes { isResolved } }
        }
      }
    }' --jq '.data.repository.pullRequest.reviewThreads
             | if .totalCount > 100 then 1
               else [.nodes[] | select(.isResolved == false)] | length
               end'
}
