# 0012: agents merge their own pull requests

Supersedes [0011](0011-main-is-pull-request-only.md), which kept the merge for the owner.

## Context

0011 put every change behind a pull request and left merging to zaffnet. The protection it
describes has held: no direct pushes, required checks, a Copilot review on every PR. What it
also produced is a queue. An agent finishes the work, addresses the review, resolves the
threads, and then stops on a green PR that needs one human click. With unattended agents
(ADR 0009) doing most of the work, that click is the slowest step in the loop, and it is not
a review -- by the time it happens the diff has already been read by Copilot and the checks
have already passed.

## Decision

Agents merge. The gate that used to be a person is now three conditions, checked by
`bin/merge-pr.sh` before it enables auto-merge:

- the pull request is open and not conflicting;
- at least one approving review stands, from anyone -- Copilot's counts;
- every review thread is resolved.

Checks are left to GitHub: the script enables auto-merge rather than merging, so the
required checks in the `main-is-pull-request-only` ruleset still decide when the merge
happens, and a PR whose CI is still running is queued rather than refused.

Approvals are read from `latestReviews`, the current review per author, so a stale one does
not count. `dismiss_stale_reviews` is on, so pushing to a branch drops the approval that was
given to the code before the push, and the PR waits for a fresh one.

This applies wherever an agent runs: Claude Code and Codex locally, and Claude Code on CI
through `.github/workflows/claude.yml`, which carries `contents: write` and
`pull-requests: write` for exactly this. That workflow stores no model credential: it
federates, exchanging the job's OIDC token for an AWS session that reads the key from
Secrets Manager (`docs/ci-claude-auth.md`). `Allow GitHub Actions to create and approve pull
requests` is enabled on the repository so a review from CI counts as the approval the gate
requires.

The ruleset is unchanged. In particular `required_approving_review_count` stays 0: raising
it to 1 would enforce the same rule at the platform level, but it would also bind zaffnet,
who cannot approve their own pull request and would need a bypass to land anything Copilot
had not approved. The gate belongs in the tool the agents call, not in a rule that locks out
the one person who can override it.

## Consequences

- A green, approved, fully resolved PR lands without waiting for a human.
- The owner keeps every override: the merge button, `gh pr merge`, and admin rights on the
  ruleset are all untouched. The change is what agents may do, not what anyone may not.
- An agent that wants to land work must get an approval, which in practice means Copilot has
  read the diff and had its comments addressed.
- `bin/merge-pr.sh` is now on the path to `main`, so it is tested directly
  (`tests/merge-pr.bats`) rather than trusted.

## Alternatives considered

- Requiring the approval in the ruleset (`required_approving_review_count: 1`): binds the
  owner too, for the reason above, and Copilot's approval does not satisfy it.
- Letting agents merge with no approval at all, on green checks: the checks here are lint,
  secrets, and rendering. Nothing in them reads a diff for sense, which is the one thing a
  review adds.
- A separate machine account to approve: another credential to hold and rotate
  (ADR 0008 keeps those to a minimum) for an approval the CI job can already give.
