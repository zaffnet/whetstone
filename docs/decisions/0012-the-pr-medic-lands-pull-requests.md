# 0012: the pr-medic lands pull requests

## Context

ADR 0011 put every change through a pull request and left the merge click to zaffnet.
`allow_auto_merge` is on, but that only makes the button exist: GitHub has no repo-level
"always auto-merge", so each PR must be armed. PRs that nobody armed sat until a human
merged them. Copilot reviews, CI, and unresolved threads were the usual blockers.

GitHub's docs say Copilot never leaves an Approve review. The API on this repo has shown
`copilot-pull-request-reviewer[bot]:APPROVED`. Raising `required_approving_review_count` to
1 would deadlock zaffnet's own PRs if that approval does not count: GitHub forbids
self-approval, and there is no second human. 0011 already rejected that count.

## Decision

`.github/workflows/pr-medic.yml` is the merge bot. The same bytes live in
`template/project/.github/workflows/pr-medic.yml`. It is one file, `git`/`gh`/`jq` only,
configurable from the top `env:` block.

The approval gate lives in the workflow, not in a ruleset. `APPROVALS_REQUIRED` defaults to
`0`, matching the ruleset count. Raise it when a second human can approve. The platform
count stays 0.

Claude implements review threads and failing checks. A bash step after Claude rebases,
re-requests reviewers, evaluates the gate, and runs `gh pr merge --auto` (or a direct merge
when the host repo has auto-merge off). Claude is denied `gh pr merge`, `gh pr review`, and
`git push --force` without `--force-with-lease`. The medic never approves.

Local agents still never merge. Merging belongs to this workflow and to zaffnet in the web
UI.

A missing Claude credential, a missing GitHub App, or an API hiccup writes a notice and a
summary. The workflow exits 0. It must not become a required check, and the `pr-medic`
commit status it writes must not be added to a ruleset.

## Consequences

- A PR can land unattended once checks pass and the workflow gate is satisfied, the way
  #33 and #34 did when auto-merge was armed by hand.
- Paste the file into a repo with no secrets and the run stays green with a "not
  configured" summary.
- `GITHUB_TOKEN` pushes do not retrigger CI. A GitHub App (`APP_CLIENT_ID` /
  `APP_PRIVATE_KEY`) closes that loop. Commits must use the App bot noreply address, or
  `require_extra_approval_for_unattributed_changes` blocks the PR.
- Hourly cron is the fallback if `workflow_run` with `workflows: ["*"]` matches nothing on
  a host.

## Alternatives considered

- Raising `required_approving_review_count` to 1: deadlocks a solo maintainer if Copilot
  does not count, and the docs and the API disagree on whether it does.
- A ruleset bypass actor of type `User`: sources conflict on whether a personal repo
  accepts it. The workflow gate needs no bypass actor.
- Leaving merge to Claude: prompt injection could merge; the deny-list and the bash gate
  keep that off the model.
- A second settings file for the Claude deny-list: breaks the one-file drop-in.
