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

The two APIs disagree on the login, which matters for any rule written in terms of "is a
bot": `gh pr view --json latestReviews` returns `copilot-pull-request-reviewer`, and
`gh api .../pulls/N/reviews` returns `copilot-pull-request-reviewer[bot]`. So the gate does
not test for the suffix. An approval means an `authorAssociation` of `OWNER`, `MEMBER` or
`COLLABORATOR`, which excludes Copilot and also excludes the drive-by approval any
authenticated account can leave on a public repository.

## Decision

`.github/workflows/pr-medic.yml` is the merge bot, and it is orchestration only: the bash
and jq live in `.github/pr-medic/` as ordinary files, `git`/`gh`/`jq` only, configurable
from the workflow's `env:` block.

A first attempt put everything in one file, so that pr-medic could be pasted into a
repository on its own. That cost 1334 lines of YAML with ~700 lines of bash and jq in `run:`
heredocs, a second 1334-line copy under `template/project/`, and a 219-line tool
(`tools/extract_pr_medic.py`) whose whole job was to slice the heredocs back out so
shellcheck and bats could see them. It also forced two copies each of the shared jq, because
a heredoc cannot be shared between jobs, and 56 `: "${VAR:=default}"` lines so that an
extracted script would run standalone. Nobody would read that, so nobody would adopt it. The
one-file rule is withdrawn; the workflow is 183 lines and the scripts total 245.

`template/project/.github/pr-medic/*` are byte-identical copies, and `single-source` diffs
them. The two workflows differ on exactly one line, because `workflow_run` names workflows
literally and a generated project's are not this repo's; `on:` takes no expressions, so that
one cannot be a variable. `ARM_AUTO_MERGE` reads the `PR_MEDIC_ARM_AUTO_MERGE` repository
variable and defaults to `false`, so a generated repository -- which has no ruleset on its
first day -- does not get an unattended merger just because its owner added a Claude
credential for `@claude` replies.

The approval gate lives in the workflow, not in a ruleset. `APPROVALS_REQUIRED` defaults to
`0`, matching the ruleset count. Raise it when a second human can approve. The platform
count stays 0.

Claude implements review threads and failing checks. `after.sh` then rebases, re-requests
reviewers, evaluates `gate.jq`, and runs `gh pr merge --auto` (or a direct merge when the
host repo has auto-merge off). The medic never approves.

The gate arms or merges only when this run finished cleanly: the worktree is clean and the
checkout is at the PR head the API reports. A Claude failure between resolving a thread and
pushing the fix would leave the remote with no unresolved threads and green checks on a head
the fix is missing from, which remote state alone cannot tell apart from a finished run. The
Claude step is therefore *not* `continue-on-error`: a failure fails the job and `after.sh`
never runs. That replaces the outcome bookkeeping an earlier draft carried in bash.

Claude runs behind an explicit `--allowedTools` allowlist, not only the deny block:
`claude-code-action` agent mode sets neither `--permission-mode` nor `--allowedTools`, so
without them the model has Read, Grep and Glob and cannot do the work at all. `gh pr merge`
and `gh pr review` are off the list, and `git push` is allowed only bare or with
`--force-with-lease`. The list is not a security boundary: resolving a review thread needs
`gh api graphql`, and the same command can approve or merge. What actually stops an
injected instruction from landing a change is the ruleset — required status checks and
`required_review_thread_resolution` — not the tool list.

The `@claude` mention path is `.github/workflows/claude.yml`, with `contents: read`. It
answers; it does not push, and it has nothing to do with landing pull requests. `allowed_bots`
does not list `github-actions[bot]`, because the medic posts under that login and would
otherwise wake itself.

There is no attempt budget and no `DRY_RUN`. The budget was a `pr-medic` commit status, an
`attempts=N` counter, a per-commit status loop and a `newer_review_than_medic` waiver --
about 70 lines to stop the hourly cron re-attempting an unchanged head. The escape hatch is
now the `no-medic` label. `DRY_RUN` threaded a third state through every write, and the
disarm it provided is `ARM_AUTO_MERGE` instead.

Local agents still never merge. Merging belongs to this workflow and to zaffnet in the web
UI.

A missing Claude credential or a missing GitHub App is configuration, and the run does the
reduced thing quietly: without Claude it still gates, and without an App it pushes with
`GITHUB_TOKEN`. An API error is not configuration, and the scripts run under
`set -euo pipefail`, so it fails the run. A red `pr-medic` is information. It must not become
a required check.

## Consequences

- A PR can land unattended once checks pass and the workflow gate is satisfied, the way
  #33 and #34 did when auto-merge was armed by hand.
- Adoption is `.github/pr-medic/` plus two workflow files, which is what the copier
  template ships anyway. It is no longer one paste-able file, and a misconfigured repository
  now goes red rather than green with a "not configured" summary.
- `GITHUB_TOKEN` pushes do not retrigger CI. A GitHub App (`APP_CLIENT_ID` /
  `APP_PRIVATE_KEY`) closes that loop. Commits must use the App bot noreply address, or
  `require_extra_approval_for_unattributed_changes` blocks the PR.
- `workflow_run` names workflows literally; there is no documented wildcard. The list is
  this repo's aggregate workflows, and the template's is a generated project's. A host whose
  names differ gets the hourly cron instead, which is slower but not broken.
- One run per head SHA, from a workflow-level `concurrency` group with
  `cancel-in-progress: true`. Without it every completing workflow wakes a run for the same
  push. Only `workflow_run` collapses: every other event keys on `github.run_id`, because the
  checks UI reports a cancelled run as a failed one.
- A pull request with a failing check Claude cannot fix re-runs Claude on every cron tick,
  unchanged. Label it `no-medic`.
- Every other event keys on `run_id`, so a burst of review comments produces a run each and
  they queue on the per-PR `pr-medic-<n>` mutex rather than cancelling. Queued runs are
  harmless now that nothing is spent per attempt: each re-reads state, and a PR the run ahead
  already handled reaches `noop` or `wait`.
- `check_counts` drops this workflow's own jobs by `workflowName`. On a `pull_request_review`
  wake `github.sha` is the PR head, so `medic` itself appears in `statusCheckRollup` as
  in-progress; counting it would make every review wake read as pending and never arm.
- `pick` is deliberately looser than the gate: it has no "checks exist, none pending" test,
  because a head whose checks have not registered yet may still be armable by the time
  `after.sh` runs. The gate has the last word.
- A green PR can land before Copilot has posted. `APPROVALS_REQUIRED` is `0`, and the
  ruleset holds a PR only for threads that already exist. This is a consequence of the solo
  maintainer, not an oversight.

## Alternatives considered

- Raising `required_approving_review_count` to 1: deadlocks a solo maintainer if Copilot
  does not count, and the docs and the API disagree on whether it does.
- A ruleset bypass actor of type `User`: sources conflict on whether a personal repo
  accepts it. The workflow gate needs no bypass actor.
- Leaving merge to Claude: prompt injection could merge. `after.sh` runs outside the
  model's reach, which is the control that holds; the tool allowlist only raises the cost.
- Keeping the one-file rule and cutting features to fit 200 lines: what would have to go is
  the gate's corrections, which are the part worth keeping.
