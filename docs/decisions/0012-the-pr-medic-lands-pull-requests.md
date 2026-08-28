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
not test for the suffix. `@humans` means an `authorAssociation` of `OWNER`, `MEMBER` or
`COLLABORATOR`, which excludes Copilot and also excludes the drive-by approval any
authenticated account can leave on a public repository.

## Decision

`.github/workflows/pr-medic.yml` is the merge bot. It is one file, `git`/`gh`/`jq` only,
configurable from the top `env:` block.

`template/project/.github/workflows/pr-medic.yml` is rendered from it by
`tools/extract_pr_medic.py --sync`, which pre-commit runs, and which `single-source` checks.
The copies are not byte-identical: the template ships `DRY_RUN: "true"` and
`ARM_AUTO_MERGE: "false"`, and `workflow_run` names a generated project's workflows. A
generated repository has no ruleset on its first day, so an owner who adds a Claude
credential to get `@claude` replies must not thereby get an unattended merger as well.
The substitution table in that tool is the whole of the difference between the two files.

The approval gate lives in the workflow, not in a ruleset. `APPROVALS_REQUIRED` defaults to
`0`, matching the ruleset count. Raise it when a second human can approve. The platform
count stays 0.

Claude implements review threads and failing checks. A bash step after Claude rebases,
re-requests reviewers, evaluates the gate, and runs `gh pr merge --auto` (or a direct merge
when the host repo has auto-merge off). The medic never approves.

Claude runs behind an explicit `--allowedTools` allowlist, not only the deny block:
`claude-code-action` agent mode sets neither `--permission-mode` nor `--allowedTools`, so
without them the model has Read, Grep and Glob and cannot do the work at all. `gh pr merge`
and `gh pr review` are off the list, and `git push` is allowed only bare or with
`--force-with-lease`. The list is not a security boundary: resolving a review thread needs
`gh api graphql`, and the same command can approve or merge. What actually stops an
injected instruction from landing a change is the ruleset — required status checks and
`required_review_thread_resolution` — not the tool list.

The `@claude` mention path is a separate job with `contents: read`. It answers; it does not
push. `TRIGGER_BOTS` does not list `github-actions[bot]`, because the medic posts under that
login and would otherwise wake itself.

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
- `workflow_run` names workflows literally; there is no documented wildcard. The list is
  this repo's aggregate workflows, and the template's is a generated project's. A host whose
  names differ gets the hourly cron instead, which is slower but not broken.
- One run per head SHA, from a workflow-level `concurrency` group with
  `cancel-in-progress: true`. Without it every completing workflow wakes a run, and each
  reads the attempts status before any writes it. A cancel during `git push` or
  `gh pr merge` is possible; both are idempotent on the next wake.
- A green PR can land before Copilot has posted. `APPROVALS_REQUIRED` is `0`, and the
  ruleset holds a PR only for threads that already exist. This is a consequence of the solo
  maintainer, not an oversight.

## Alternatives considered

- Raising `required_approving_review_count` to 1: deadlocks a solo maintainer if Copilot
  does not count, and the docs and the API disagree on whether it does.
- A ruleset bypass actor of type `User`: sources conflict on whether a personal repo
  accepts it. The workflow gate needs no bypass actor.
- Leaving merge to Claude: prompt injection could merge. The bash gate runs outside the
  model's reach, which is the control that holds; the tool allowlist only raises the cost.
- A second settings file for the Claude deny-list: breaks the one-file drop-in.
