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
    elif ([$p.labels[]?.name] | any(IN($skip[]))) then false
    # Somebody armed this by hand, and this gate never disarms. Any work on it is what lets
    # that arming fire -- resolving the last thread, or pushing a fix that turns the checks
    # green, hands the merge to GitHub on conditions gate.jq would not accept: no approval
    # count, no skip label, no all-checks. So an armed pull request is left alone entirely,
    # not merely excluded from the merge branch below.
    elif $p.autoMergeRequest != null then false
    else
      # Work Claude can do. total_checks is deliberately absent: a head whose checks have not
      # registered yet may still be mergeable by the time the gate runs, and gate.jq has the
      # last word.
      .unresolved > 0
      or $c.failing > 0
      or $p.mergeStateStatus == "BEHIND"
      or $p.mergeStateStatus == "DIRTY"
      # Or the gate might merge it.
      or ($may_merge and $approved)
    end;

# A list, not one name: the human skip label and the medic's own resolution block both refuse,
# and an empty entry must not match a pull request with no labels.
((.skip_label // "") | split(",") | map(select(length > 0))) as $skip
| .approvals_required as $required
| (.may_merge == true) as $may_merge
| [.prs[] | select(keep($skip; $required; $may_merge)) | .view.number]
