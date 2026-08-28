# Which of these pull requests can the medic help? Input:
#   {prs: [{view, unresolved, approvals}], skip_label, approvals_required, may_merge}
# where `view` is `gh pr view --json` output. Result: an array of PR numbers.
include "lib";

def keep($skip; $required; $may_merge):
  .view as $p
  | ($p | check_counts) as $c
  | (.approvals >= $required) as $approved
  | if ($p.state | ascii_upcase) != "OPEN" then false
    elif $p.isDraft then false
    # Every trigger runs in the base-repo context, so the App key, the Claude credential and
    # a write token are all present whatever repo the head came from. Fork support needs a
    # separate job that runs the untrusted code with no secrets.
    elif $p.isCrossRepository then false
    elif ($skip | length) > 0 and (([$p.labels[]?.name] | index($skip)) != null) then false
    else
      # Work Claude can do. total_checks is deliberately absent: a head whose checks have not
      # registered yet may still be mergeable by the time the gate runs, and gate.jq has the
      # last word.
      .unresolved > 0
      or $c.failing > 0
      or $p.mergeStateStatus == "BEHIND"
      or $p.mergeStateStatus == "DIRTY"
      # Or the gate might merge it. One somebody armed by hand is left alone: the gate would
      # only say noop, and GitHub owns that merge.
      or ($may_merge and $approved and $p.autoMergeRequest == null)
    end;

.skip_label as $skip
| .approvals_required as $required
| (.may_merge == true) as $may_merge
| [.prs[] | select(keep($skip; $required; $may_merge)) | .view.number]
