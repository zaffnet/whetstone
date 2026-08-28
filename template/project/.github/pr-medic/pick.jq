# Which of these pull requests can the medic help? Input:
#   {prs: [{view, unresolved}], skip_label, approvals_required}
# where `view` is `gh pr view --json` output. Result: an array of PR numbers.
include "lib";

def keep($skip; $required):
  .view as $p
  | ($p | check_counts) as $c
  | if ($p.state | ascii_upcase) != "OPEN" then false
    elif $p.isDraft then false
    # Every trigger runs in the base-repo context, so the App key, the Claude credential and
    # a write token are all present whatever repo the head came from. Fork support needs a
    # separate job that runs the untrusted code with no secrets.
    elif $p.isCrossRepository then false
    elif ($skip | length) > 0 and (([$p.labels[]?.name] | index($skip)) != null) then false
    else
      # Something to fix, or ready to arm. "Worth a look", not "safe to merge": total_checks
      # is deliberately absent here, because a head whose checks have not registered yet may
      # still become armable by the time the gate runs. gate.jq has the last word.
      .unresolved > 0
      or $c.failing > 0
      or $p.mergeStateStatus == "BEHIND"
      or $p.mergeStateStatus == "DIRTY"
      or ($p.autoMergeRequest == null and (($p.latestReviews | approvals) >= $required))
    end;

.skip_label as $skip
| .approvals_required as $required
| [.prs[] | select(keep($skip; $required)) | .view.number]
