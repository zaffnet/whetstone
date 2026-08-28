#!/usr/bin/env bash
# Hand Claude the review threads without handing it a command that can approve or merge.
#
# Resolving a review thread needs `gh api graphql`, and the same command can approve or
# merge, so an allowlist cannot separate them and `Bash(gh api graphql:*)` must not be on it.
# Instead: `dump` writes the unresolved threads to a file, Claude writes what it wants to say
# to another, and `apply` performs the replies here, in bash, outside the model's reach.
#
set -euo pipefail

here=$(dirname "$0")
# shellcheck source=.github/pr-medic/lib.sh
. "$here/lib.sh"

: "${PR:?}" "${REPO:?}"
# Under RUNNER_TEMP, not the worktree: a file written inside it would trip the clean-worktree
# check in after.sh. Claude is told the same path, and reaches it via --add-dir.
: "${THREADS_FILE:=${RUNNER_TEMP:?}/pr-medic/threads.json}"
: "${REPLIES_FILE:=${RUNNER_TEMP:?}/pr-medic/replies.json}"
# Outside pr-medic/, so outside --add-dir: what the threads looked like when the model was
# given them, which is the only thing its `resolve: true` can honestly refer to.
: "${THREAD_SNAPSHOT:=${RUNNER_TEMP:?}/pr-medic-state/threads.json}"

# Of these logins, the ones whose text may be put in front of the model: push access, or one
# of the bots the workflow names. A bot holds no collaborator permission, so it cannot be
# established that way -- this is the same list the action gets as `allowed_bots`, and for the
# same reason. Input: one login per line. Output: a JSON array.
trusted_logins() {
  local login trusted=()
  while read -r login; do
    [ -n "$login" ] || continue
    case ",${TRUSTED_BOTS:-}," in
      *",$login,"*)
        trusted+=("$login")
        continue
        ;;
    esac
    ! has_push_access "$login" || trusted+=("$login")
  done
  printf '%s\n' ${trusted[@]+"${trusted[@]}"} | jq -R -s -c 'split("\n") | map(select(. != ""))'
}

# The unresolved threads, as they are right now, less the ones the model must not be steered
# by. Anyone who can read a public repository can open a review thread, and the hourly sweep
# reaches a pull request whether or not an event for it was accepted -- so without this the
# thread body of any passer-by becomes prompt text that after.sh then pushes.
#
# Every author of a thread, not only the one who opened it: an untrusted reply on a Copilot
# thread is still text in the prompt. A skipped thread stays unresolved, which the merge gate
# counts, so the pull request waits for someone with push access rather than merging. No cost
# to a contributor: pick.jq refuses a fork, so the PR's own author can push by construction.
fetch_threads() {
  local raw trusted kept dropped
  # shellcheck disable=SC2016  # $owner, $name and $pr are GraphQL variables.
  raw=$(gh api graphql -F owner="${REPO%/*}" -F name="${REPO#*/}" -F pr="$PR" -f query='
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
                 comments: [.comments.nodes[] | {author: .author.login, body}]}]')
  trusted=$(jq -r '[.[].comments[].author] | unique | .[]' <<<"$raw" | trusted_logins)
  # IN, not index or inside: those match substrings, so `ali` would pass as `alice`. A null
  # author -- a deleted account -- matches nothing and the thread is skipped.
  kept=$(jq -c --argjson trusted "$trusted" \
    '[.[] | select(all(.comments[].author; IN($trusted[])))]' <<<"$raw")
  dropped=$(($(jq length <<<"$raw") - $(jq length <<<"$kept")))
  [ "$dropped" -eq 0 ] \
    || echo "::warning::PR #$PR: $dropped unresolved thread(s) withheld; an author cannot push" >&2
  printf '%s\n' "$kept"
}

dump() {
  mkdir -p "$(dirname "$THREADS_FILE")" "$(dirname "$REPLIES_FILE")" "$(dirname "$THREAD_SNAPSHOT")"
  fetch_threads >"$THREAD_SNAPSHOT"
  cp "$THREAD_SNAPSHOT" "$THREADS_FILE"
  printf '[]\n' >"$REPLIES_FILE"
  printf 'Wrote %s unresolved thread(s) to %s\n' "$(jq length "$THREADS_FILE")" "$THREADS_FILE"
}

comments_of() { jq -c --arg i "$1" '[.[] | select(.thread_id == $i) | .comments] | first'; }

apply() {
  # Claude wrote this file, so nothing in it is trusted. A malformed file is a failure rather
  # than a silent no-op: the gate is about to read "no unresolved threads" as ready to merge.
  jq -e 'type == "array"' "$REPLIES_FILE" >/dev/null || {
    echo "::error::$REPLIES_FILE is not a JSON array"
    exit 1
  }
  # Re-queried, not read back from THREADS_FILE: the model can write in that directory, so
  # the file it was handed is not evidence of anything once it has finished. This is the list
  # of threads that are open now, which is also the list that matters.
  local threads known entry id reply body_file resolved=0 replied=0
  threads=$(fetch_threads)
  # Open now *and* in the snapshot the model was given. Current alone would accept a thread
  # opened after dump, which the model never saw and cannot have an answer to.
  known=$(jq -c --slurpfile snap "$THREAD_SNAPSHOT" \
    '[$snap[0][].thread_id] as $shown | [.[].thread_id | select(IN($shown[]))]' <<<"$threads")
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
    gh api graphql -f threadId="$id" -F body=@"$body_file" -f query='
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
      if [ "$(jq -r --arg i "$id" '[.[] | select(.thread_id == $i) | .truncated] | first' <<<"$threads")" = true ]; then
        echo "::error::thread $id has more than 100 comments; it cannot be resolved from a partial read"
        exit 1
      fi
      # A reviewer can add a comment while the model works. Resolving then would mark that new
      # comment satisfied as well, and the gate would go on to see no unresolved threads.
      if [ "$(comments_of "$id" <<<"$threads")" != "$(comments_of "$id" <"$THREAD_SNAPSHOT")" ]; then
        echo "::error::thread $id changed while this run was in progress; not resolving it"
        exit 1
      fi
      # shellcheck disable=SC2016  # $threadId is a GraphQL variable.
      gh api graphql -f threadId="$id" -f query='
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
