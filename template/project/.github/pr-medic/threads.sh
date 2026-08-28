#!/usr/bin/env bash
# Hand Claude the review threads without handing it a command that can approve or merge.
#
# Resolving a review thread needs `gh api graphql`, and the same command can approve or
# merge, so an allowlist cannot separate them and `Bash(gh api graphql:*)` must not be on it.
# Instead: `dump` writes the unresolved threads to a file, Claude writes what it wants to say
# to another, and `apply` performs the replies here, in bash, outside the model's reach.
#
set -euo pipefail

: "${PR:?}" "${REPO:?}"
# Under RUNNER_TEMP, not the worktree: a file written inside it would trip the clean-worktree
# check in after.sh. Claude is told the same path, and reaches it via --add-dir.
: "${THREADS_FILE:=${RUNNER_TEMP:?}/pr-medic/threads.json}"
: "${REPLIES_FILE:=${RUNNER_TEMP:?}/pr-medic/replies.json}"

graphql() { gh api graphql "$@"; }

dump() {
  mkdir -p "$(dirname "$THREADS_FILE")"
  # shellcheck disable=SC2016  # $owner, $name and $pr are GraphQL variables.
  graphql -F owner="${REPO%/*}" -F name="${REPO#*/}" -F pr="$PR" -f query='
    query($owner: String!, $name: String!, $pr: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100) {
            nodes {
              id isResolved isOutdated path line
              comments(last: 100) { totalCount nodes { author { login } body } }
            }
          }
        }
      }
    }' --jq '[.data.repository.pullRequest.reviewThreads.nodes[]
              | select(.isResolved == false)
              | {thread_id: .id, path, line, outdated: .isOutdated,
                 truncated: (.comments.totalCount > 100),
                 comments: [.comments.nodes[] | {author: .author.login, body}]}]' >"$THREADS_FILE"
  printf '[]\n' >"$REPLIES_FILE"
  printf 'Wrote %s unresolved thread(s) to %s\n' "$(jq length "$THREADS_FILE")" "$THREADS_FILE"
}

apply() {
  # Claude wrote this file, so nothing in it is trusted. A malformed file is a failure rather
  # than a silent no-op: the gate is about to read "no unresolved threads" as ready to merge.
  jq -e 'type == "array"' "$REPLIES_FILE" >/dev/null || {
    echo "::error::$REPLIES_FILE is not a JSON array"
    exit 1
  }
  local known entry id reply body_file resolved=0 replied=0
  known=$(jq -c '[.[].thread_id]' "$THREADS_FILE")
  body_file=$(mktemp)
  while read -r entry; do
    id=$(jq -r '.thread_id // empty' <<<"$entry")
    # Only threads dump captured. An invented ID, or one belonging to another pull request,
    # is refused rather than acted on.
    if [ -z "$id" ] || [ "$(jq --argjson k "$known" --arg i "$id" -n '$k | index($i) != null')" != true ]; then
      echo "::error::reply names a thread that is not open on PR #$PR: ${id:-<none>}"
      exit 1
    fi
    # Not `jq -r ... >file` and a -s test: jq writes a newline, so an empty reply would
    # leave a one-byte file and pass.
    reply=$(jq -r '.reply // ""' <<<"$entry")
    [ -n "$reply" ] || {
      echo "::error::thread $id: every entry needs a reply"
      exit 1
    }
    printf '%s' "$reply" >"$body_file"
    # shellcheck disable=SC2016  # $threadId and $body are GraphQL variables.
    graphql -f threadId="$id" -F body=@"$body_file" -f query='
      mutation($threadId: ID!, $body: String!) {
        addPullRequestReviewThreadReply(
          input: {pullRequestReviewThreadId: $threadId, body: $body}
        ) { comment { id } }
      }' >/dev/null
    replied=$((replied + 1))
    # Resolving is the record that the code now satisfies the comment, so it is a separate
    # decision from replying and Claude has to ask for it.
    if [ "$(jq -r '.resolve // false' <<<"$entry")" = true ]; then
      # `last: 100` shows the most recent comments, so a truncated thread is one whose
      # beginning is missing. Replying to it is fine; recording it as satisfied is not.
      if [ "$(jq -r --arg i "$id" '[.[] | select(.thread_id == $i) | .truncated] | first' "$THREADS_FILE")" = true ]; then
        echo "::error::thread $id has more than 100 comments; it cannot be resolved from a partial read"
        exit 1
      fi
      # shellcheck disable=SC2016  # $threadId is a GraphQL variable.
      graphql -f threadId="$id" -f query='
        mutation($threadId: ID!) {
          resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } }
        }' >/dev/null
      resolved=$((resolved + 1))
    fi
  done < <(jq -c '.[]' "$REPLIES_FILE")
  rm -f "$body_file"
  printf -- '- PR #%s: replied to %s thread(s), resolved %s\n' \
    "$PR" "$replied" "$resolved" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

case "${1:-}" in
  dump) dump ;;
  apply) apply ;;
  *)
    echo "usage: threads.sh dump|apply" >&2
    exit 2
    ;;
esac
