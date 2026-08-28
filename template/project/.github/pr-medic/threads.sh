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
# What this run resolved, so after.sh can put it back if the head moves after apply has
# returned -- while the gate reads state, or while the merge is refused. Same directory as the
# snapshot, and for the same reason: the model must not be able to edit it.
: "${RESOLVED_FILE:=${RUNNER_TEMP:?}/pr-medic-state/resolved.json}"
# Whether the block on the pull request is this run's. Beside the other state, for the same
# reason: only the gate step reads it, and the model must not be able to write it.
: "${BLOCK_OWNED_FILE:=${RUNNER_TEMP:?}/pr-medic-state/block-owned}"

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

current_head() { gh pr view "$PR" --repo "$REPO" --json headRefOid --jq .headRefOid; }

# Reopen one thread, and confirm it. The mutation's own answer is the confirmation, so a call
# that reports success while leaving isResolved true is caught. Retried, because this is the
# only path that undoes a resolution and there is no later opportunity.
unresolve() {
  local id=$1 attempt state
  for attempt in 1 2 3; do
    # shellcheck disable=SC2016  # $threadId is a GraphQL variable.
    state=$(gh api graphql -f threadId="$id" -f query='
      mutation($threadId: ID!) {
        unresolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } }
      }' --jq '.data.unresolveReviewThread.thread.isResolved' 2>/dev/null) || state=unknown
    if [ "$state" = false ]; then return 0; fi
    [ "$attempt" = 3 ] || sleep "$attempt"
  done
  return 1
}

# Whether the pull request carries a label right now.
has_label() {
  gh pr view "$PR" --repo "$REPO" --json labels --jq '.labels[].name' | grep -qxF "$1"
}

# The block that outlives this run, taken before the first resolve rather than after a failed
# undo. A marker applied only on the way out can fail on the way out too, and then there is no
# block at all -- the job goes red, but pr-medic is deliberately not a required check, so the
# next wake reads the thread as satisfied and merges. This way nothing is resolved until the
# block that might be needed is in place and has been read back. pick.jq drops a labelled pull
# request and gate.jq refuses one; release_block lifts it once this run has accounted for what
# it resolved.
acquire_block() {
  [ -n "${BLOCK_LABEL:-}" ] || {
    echo "::error::no BLOCK_LABEL is set, so a resolution that went wrong could not be blocked"
    return 1
  }
  # Already this run's, from an earlier resolve in the same run.
  if [ -f "$BLOCK_OWNED_FILE" ]; then return 0; fi
  # There, but not this run's. `pick` runs before the per-PR concurrency lock, so a run can be
  # queued behind one that left its block; taking that over would end with this run releasing
  # somebody else's only safety marker. Refuse, and resolve nothing.
  if has_label "$BLOCK_LABEL"; then
    echo "::error::PR #$PR already carries $BLOCK_LABEL from another run; resolving nothing"
    return 1
  fi
  # A repository that has never used it does not have the label, and --add-label cannot create
  # one, so without this the block would be reported and not applied.
  gh label create "$BLOCK_LABEL" --repo "$REPO" --color B60205 \
    --description "pr-medic: a thread resolution needs checking by hand" >/dev/null 2>&1 || true
  gh pr edit "$PR" --repo "$REPO" --add-label "$BLOCK_LABEL" >/dev/null 2>&1 || true
  has_label "$BLOCK_LABEL" || return 1
  mkdir -p "$(dirname "$BLOCK_OWNED_FILE")"
  : >"$BLOCK_OWNED_FILE"
}

# Only a label this run put on. Anything else belongs to a run that could not account for what
# it resolved, and it is the only thing stopping a later merge on that.
release_block() {
  [ -n "${BLOCK_LABEL:-}" ] || return 0
  [ -f "$BLOCK_OWNED_FILE" ] || return 0
  # Not `|| true`. pick.jq skips a pull request carrying this label, so a block left on turns
  # the medic off for that pull request until a person notices -- and swallowing the failure
  # would report that as a green run. The ownership record stays put as well, so the next
  # attempt still knows the label is this run's to remove.
  gh pr edit "$PR" --repo "$REPO" --remove-label "$BLOCK_LABEL" >/dev/null || {
    echo "::error::PR #$PR still carries $BLOCK_LABEL; the medic skips it until that is removed"
    return 1
  }
  rm -f "$BLOCK_OWNED_FILE"
}

# Put back what this run resolved. Leaving a thread resolved against a head the gate never
# judged is the failure that matters: the reply stays either way, but a resolved thread is
# what the next run reads as satisfied, and it would merge on that.
undo_resolutions() {
  local id failed=0
  for id in ${resolved_ids[@]+"${resolved_ids[@]}"}; do
    unresolve "$id" || {
      echo "::error::thread $id is still resolved and could not be reopened"
      failed=1
    }
  done
  if [ "$failed" = 0 ]; then
    resolved_ids=() # nothing outstanding, so nothing for after.sh to undo a second time
    record_resolved
    release_block
  else
    echo "::error::PR #$PR keeps ${BLOCK_LABEL:-}: a resolution could not be undone and needs a person"
  fi
}

# Rewritten in full after each resolve, so a crash between the mutation and the next step still
# leaves after.sh the list it needs.
record_resolved() {
  mkdir -p "$(dirname "$RESOLVED_FILE")"
  printf '%s\n' ${resolved_ids[@]+"${resolved_ids[@]}"} \
    | jq -R -s -c 'split("\n") | map(select(. != ""))' >"$RESOLVED_FILE"
}

apply() {
  # The head after.sh verified the checkout against. Resolving a thread is a claim about a
  # specific head, so without it there is nothing to make the claim true.
  : "${EXPECTED_HEAD:?}"
  # Claude wrote this file, so nothing in it is trusted. A malformed file is a failure rather
  # than a silent no-op: the gate is about to read "no unresolved threads" as ready to merge.
  jq -e 'type == "array"' "$REPLIES_FILE" >/dev/null || {
    echo "::error::$REPLIES_FILE is not a JSON array"
    exit 1
  }
  # Re-queried, not read back from THREADS_FILE: the model can write in that directory, so
  # the file it was handed is not evidence of anything once it has finished. This is the list
  # of threads that are open now, which is also the list that matters.
  local threads known entry id reply body_file fresh now was head resolved=0 replied=0
  local resolved_ids=()
  record_resolved # empty, so a file left by an earlier run is never mistaken for this one's
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
      # Read again rather than reuse the list from the top of this function. Posting replies
      # takes seconds, and a reviewer comment landing in that window would be invisible in the
      # older list and marked satisfied along with everything else.
      fresh=$(fetch_threads)
      # `last: 100` shows the most recent comments, so a truncated thread is one whose
      # beginning is missing. Replying to it is fine; recording it as satisfied is not.
      if [ "$(jq -r --arg i "$id" '[.[] | select(.thread_id == $i) | .truncated] | first' <<<"$fresh")" = true ]; then
        echo "::error::thread $id has more than 100 comments; it cannot be resolved from a partial read"
        undo_resolutions
        exit 1
      fi
      # A reviewer can add a comment while the model works, or while this loop runs. Resolving
      # then would mark that comment satisfied too, and the gate would go on to see no
      # unresolved threads. The one comment that is expected is the reply just posted, so the
      # thread has to be the snapshot with exactly one appended -- which also catches a comment
      # that arrived before the reply, because ours would no longer be the only addition.
      now=$(comments_of "$id" <<<"$fresh")
      was=$(comments_of "$id" <"$THREAD_SNAPSHOT")
      if [ "$(jq -n --argjson now "$now" --argjson was "$was" \
        '$now | length == (($was | length) + 1) and .[0:($was | length)] == $was')" != true ]; then
        echo "::error::thread $id changed while this run was in progress; not resolving it"
        undo_resolutions
        exit 1
      fi
      # Before anything irreversible, and on every resolve, because it is a no-op once held.
      acquire_block || {
        echo "::error::PR #$PR: ${BLOCK_LABEL:-<unset>} cannot be held; nothing will be resolved"
        undo_resolutions
        exit 1
      }
      # The head the gate verified the checkout against. A push landing between that check and
      # here would leave this thread resolved against code the gate never judged, and the next
      # run reads a resolved thread as satisfied. Nothing makes the mutation atomic with this
      # read, so the window is one call wide and a move seen later is undone below.
      head=$(current_head)
      [ "$head" = "$EXPECTED_HEAD" ] || {
        echo "::error::PR #$PR moved to ${head:0:7} from ${EXPECTED_HEAD:0:7}; not resolving thread $id"
        undo_resolutions
        exit 1
      }
      # shellcheck disable=SC2016  # $threadId is a GraphQL variable.
      gh api graphql -f threadId="$id" -f query='
        mutation($threadId: ID!) {
          resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } }
        }' >/dev/null
      resolved_ids+=("$id")
      record_resolved
      resolved=$((resolved + 1))
    fi
  done < <(jq -c '.[]' "$REPLIES_FILE")
  rm -f "$body_file"
  # A push that lands after the last resolve is still a resolve against a head the gate did not
  # judge, and no per-thread check can see it. Undo rather than leave it.
  if [ "${#resolved_ids[@]}" -gt 0 ]; then
    head=$(current_head)
    [ "$head" = "$EXPECTED_HEAD" ] || {
      echo "::error::PR #$PR moved to ${head:0:7} while threads were being resolved; undoing"
      undo_resolutions
      exit 1
    }
  fi
  printf -- '- PR #%s: replied to %s thread(s), resolved %s\n' \
    "$PR" "$replied" "$resolved" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# Reopen whatever apply resolved. after.sh calls this when the head moved after apply returned:
# the gate read and the merge attempt both take time, and the merge being refused on the old sha
# is not enough on its own -- the threads would stay resolved for the next run to act on.
undo() {
  local id ids
  [ -s "${RESOLVED_FILE:-}" ] || return 0
  ids=$(jq -r '.[]' "$RESOLVED_FILE")
  local resolved_ids=()
  while read -r id; do
    if [ -n "$id" ]; then resolved_ids+=("$id"); fi
  done <<<"$ids"
  [ "${#resolved_ids[@]}" -gt 0 ] || return 0
  undo_resolutions
}

# after.sh, once the run has merged on the head the gate judged or confirmed it did not move.
release() { release_block; }

case "${1:-}" in
  dump) dump ;;
  apply) apply ;;
  undo) undo ;;
  release) release ;;
  *)
    echo "usage: threads.sh dump|apply|undo|release" >&2
    exit 2
    ;;
esac
