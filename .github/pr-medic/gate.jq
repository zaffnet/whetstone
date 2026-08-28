# May the medic land this pull request? Input:
#   {pr, unresolved, approvals, approvals_required, arm_auto_merge, allow_auto_merge,
#    skip_label}
# `approvals` is counted by approval_count in lib.sh, which asks for push access rather than
# trusting authorAssociation.
# where `pr` is `gh pr view --json` output. Result: {action, reason}, one of
# refuse (do not touch it), wait (come back later), noop, arm (hand the merge to GitHub) or
# merge (for a repo with auto-merge switched off). The branch order is the design.
include "lib";

.pr as $p
| ($p | check_counts) as $c
| (.skip_label // "") as $skip
| if ($p.state | ascii_upcase) != "OPEN" then {action: "refuse", reason: "closed"}
  elif $p.isDraft then {action: "refuse", reason: "draft"}
  elif $p.isCrossRepository then {action: "refuse", reason: "fork"}
  # Re-read here, not just in pick: the label is the escape hatch, so it has to work when it
  # is applied to a pull request the medic has already armed. `refuse` disarms.
  # $skip, not .skip_label: inside the pipe below `.` is the label array, not the root.
  elif ($skip | length) > 0 and (([$p.labels[]?.name] | index($skip)) != null) then
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
  elif .arm_auto_merge != true then {action: "wait", reason: "ARM_AUTO_MERGE false"}
  # After the switch, not before it: an armed PR that ignored ARM_AUTO_MERGE would keep a
  # kill switch from doing anything, because GitHub merges on required checks alone.
  # Pending is below, and deliberately: waiting for checks is what an arming is for.
  elif $p.autoMergeRequest != null then {action: "noop", reason: "already armed"}
  # Before arm, not only before merge: gh pr merge --auto waits for *required* checks, and a
  # repo with no ruleset has none, so arming there merges at once while optional CI runs.
  elif $c.pending > 0 then {action: "wait", reason: "pending checks"}
  elif .allow_auto_merge then {action: "arm", reason: "gate passed"}
  else {action: "merge", reason: "gate passed, auto-merge off"}
  end
