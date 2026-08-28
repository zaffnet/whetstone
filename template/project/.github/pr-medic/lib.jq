# Shared definitions for pick.jq and gate.jq. Include with `jq -L <this directory>`.

# gh pr view --json statusCheckRollup mixes two shapes. A CheckRun carries status and
# conclusion; a StatusContext carries state and no conclusion field at all -- which is why
# reading a missing conclusion as pending counted every commit status as pending forever,
# and why a plain FAILURE test missed ERROR, TIMED_OUT, CANCELLED and STARTUP_FAILURE.
def check_counts:
  def bucket:
    if .__typename == "StatusContext" then
      ((.state // "") | ascii_upcase) as $s
      | if $s == "PENDING" or $s == "EXPECTED" then "pending"
        elif $s == "SUCCESS" then "ok"
        else "fail"
        end
    else
      ((.status // "") | ascii_upcase) as $st
      | ((.conclusion // "") | ascii_upcase) as $c
      | if $st != "COMPLETED" then "pending"
        elif $c == "SUCCESS" or $c == "NEUTRAL" or $c == "SKIPPED" then "ok"
        else "fail"
        end
    end;
  # Drop this workflow's own jobs. On a pull_request_review wake github.sha is the PR head,
  # so `medic` itself lands in the rollup, and counting it makes every such wake read as
  # pending and never arm. A commit status carries no workflowName, so it is kept. Keyed on
  # GITHUB_WORKFLOW rather than a literal, so renaming the workflow cannot silently stop it.
  [(.statusCheckRollup // [])[] | select(.workflowName != ($ENV.GITHUB_WORKFLOW // "pr-medic"))]
  # One head can carry several runs of the same workflow -- a `gh run rerun`, or a burst of
  # triggers. The rollup keeps every one: on this repo `medic (42)` appeared as both FAILURE
  # and CANCELLED at once. Keep the newest row per check, or a stale failed attempt holds
  # failing > 0 for good and the rerun the prompt asks for can never clear it.
  | group_by([(.name // .context), (.workflowName // "")])
  | map(
      # A pending member wins outright. `gh pr view` gives CheckRuns no createdAt, and
      # startedAt is null until a run starts, so a queued rerun sorts as "" and `last` would
      # pick the completed row it replaces -- merging while the rerun is still to come.
      (map(bucket) | index("pending")) as $queued
      | if $queued != null then "pending"
        # The latest timestamp either field carries, not startedAt alone: a run cancelled while
        # still queued is COMPLETED with conclusion CANCELLED and no startedAt, so it buckets
        # `fail` rather than `pending` and sorted as "" -- putting it first and letting `last`
        # pick the older success it replaced.
        else (sort_by([.completedAt, .startedAt] | map(select(. != null)) | max // "")
              | last | bucket)
        end
    )
  | {
      total: length,
      failing: (map(select(. == "fail")) | length),
      pending: (map(select(. == "pending")) | length)
    };
