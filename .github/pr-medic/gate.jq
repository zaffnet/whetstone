# May the medic land this pull request? Input:
#   {pr, unresolved, approvals, approvals_required, may_merge, skip_label}
# where `pr` is `gh pr view --json` output and `approvals` is counted by approval_count in
# lib.sh, which asks for push access rather than trusting authorAssociation. Result:
# {action, reason} -- refuse (do not touch it), wait (come back later), noop, or merge.
# The branch order is the design.
#
# There is no "arm auto-merge" action. Arming hands the decision to GitHub, whose only
# condition is *required* checks, so every condition here that the platform does not enforce
# -- the approval count, the skip label, unresolved threads -- stops being enforced the moment
# the arming lands. A push or a label arriving before the next wake would merge anyway. So the
# medic merges the head it has just judged, with --match-head-commit, or it does nothing.
include "lib";

.pr as $p
| ($p | check_counts) as $c
# A list, not one name: the human skip label and the medic's own resolution block both refuse.
| ((.skip_label // "") | split(",") | map(select(length > 0))) as $skip
| if ($p.state | ascii_upcase) != "OPEN" then {action: "refuse", reason: "closed"}
  elif $p.isDraft then {action: "refuse", reason: "draft"}
  elif $p.isCrossRepository then {action: "refuse", reason: "fork"}
  # Re-read here, not just in pick: a label applied after pick has to stop the merge.
  # $skip, not .skip_label: inside the pipe below `.` is the label array, not the root.
  elif ([$p.labels[]?.name] | any(IN($skip[]))) then
    {action: "refuse", reason: "skip label"}
  # DIRTY is the conflicted value of mergeStateStatus. CONFLICTING belongs to the separate
  # mergeable field, which this workflow never asks for.
  elif $p.mergeStateStatus == "DIRTY" then {action: "refuse", reason: "conflicts"}
  elif .unresolved > 0 then {action: "refuse", reason: "unresolved threads"}
  # An empty rollup is the state right after a force-push, and the permanent state when that
  # push used GITHUB_TOKEN. Reading it as green merges a commit nothing has tested.
  elif $c.total == 0 then {action: "refuse", reason: "no checks on this head"}
  elif $c.failing > 0 then {action: "refuse", reason: "failing checks"}
  elif .approvals < .approvals_required then {action: "wait", reason: "approvals"}
  elif .may_merge != true then {action: "wait", reason: "MAY_MERGE false"}
  # Somebody switched auto-merge on by hand. Not ours to merge, and not ours to take away.
  elif $p.autoMergeRequest != null then {action: "noop", reason: "auto-merge enabled by hand"}
  # A pending check is a reason to come back, not to merge. The workflow_run wake that fires
  # when it finishes is what brings us here again.
  elif $c.pending > 0 then {action: "wait", reason: "pending checks"}
  else {action: "merge", reason: "gate passed"}
  end
