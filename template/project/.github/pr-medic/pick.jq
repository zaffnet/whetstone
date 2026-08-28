# Which of these pull requests can the medic help? Input:
#   {prs: [{view, unresolved, approvals}], skip_label, approvals_required, arm_auto_merge}
# where `view` is `gh pr view --json` output. Result: an array of PR numbers.
include "lib";

def keep($skip; $required; $arm):
  .view as $p
  | ($p | check_counts) as $c
  | (.approvals >= $required) as $approved
  | if ($p.state | ascii_upcase) != "OPEN" then false
    elif $p.isDraft then false
    # Every trigger runs in the base-repo context, so the App key, the Claude credential and
    # a write token are all present whatever repo the head came from. Fork support needs a
    # separate job that runs the untrusted code with no secrets.
    elif $p.isCrossRepository then false
    # Not a flat `false`: the label has to be able to stop a pull request the medic already
    # armed, and only the gate can take an arming back. So a labelled PR is still selected
    # when it is armed, and the gate refuses it, which disarms.
    elif ($skip | length) > 0 and (([$p.labels[]?.name] | index($skip)) != null) then
      $p.autoMergeRequest != null
    else
      # Work Claude can do. total_checks is absent from the unarmed case below for the same
      # reason it is absent here: a head whose checks have not registered yet may still be
      # armable by the time the gate runs, and gate.jq has the last word. On the armed side it
      # is present, because a head that lost its checks is one the gate has to disarm.
      .unresolved > 0
      or $c.failing > 0
      or $p.mergeStateStatus == "BEHIND"
      or $p.mergeStateStatus == "DIRTY"
      # Or a state the gate will act on. It arms an unarmed PR that passes, and takes the
      # arming back from an armed one that stopped passing -- and it can only do either if
      # this picks the PR. An armed PR that still passes is left alone, because the gate
      # would only say noop.
      or (
        if $p.autoMergeRequest == null then ($arm and $approved)
        else (($arm | not) or ($approved | not) or $c.total == 0)
        end
      )
    end;

.skip_label as $skip
| .approvals_required as $required
| (.arm_auto_merge == true) as $arm
| [.prs[] | select(keep($skip; $required; $arm)) | .view.number]
