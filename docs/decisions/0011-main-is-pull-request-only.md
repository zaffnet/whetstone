# 0011: `main` takes pull requests only

## Context

Until now every change landed on `main` as a direct push, including rounds of agent-made
fixes. The CI workflows ran after the fact, and no reviewer, human or bot, saw a diff before
it was on the default branch. Agents that run unattended (ADR 0009) made this the normal
path, not the exception.

## Decision

A repository ruleset, `main-is-pull-request-only`, protects the default branch with an empty
bypass list, so it binds the owner as well as any agent:

- no direct pushes, deletions, or force-pushes;
- every change arrives as a pull request, and Copilot code review is requested
  automatically;
- every review thread is resolved before merge;
- the ten CI checks (`pre-commit`, `plugin-manifests`, `single-source`, `gitleaks`, both
  `bootstrap` roles, all four `render-and-check` variants) pass on a branch that is up to
  date with `main`.

No approving review is required: Copilot cannot approve, and the owner cannot approve their
own PR. Merging is the owner's action. Agents open PRs, request reviews, and address
comments; they do not merge.

## Consequences

- A fix takes one more step (branch, PR, wait for checks and review) and lands only when
  zaffnet merges it.
- `just release` still tags a pushed `main`; it now also publishes a GitHub Release.
- Changing this policy means editing the ruleset in the repository settings, which leaves a
  trace in the audit log.

## Alternatives considered

- Classic branch protection: rulesets replace it, apply to admins without a separate toggle,
  and show up in the API as one object.
- Requiring one approving review: with a single human contributor nobody can give it, so
  every PR would need an admin bypass, which defeats the rule.
