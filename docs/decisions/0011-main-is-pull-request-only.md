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
- the seven required checks pass: `pre-commit`, `plugin-manifests`, `single-source`,
  `gitleaks`, both `bootstrap` roles, and `template-ok`. That last one aggregates every
  `render-and-check` and `longest-name` job, because those carry their matrix values in the
  job name: adding the `line_length` axis renamed all of them and left the ruleset waiting
  on four contexts no job produced. Require the aggregate, never a matrix job name.

No approving review is required: Copilot cannot approve, and the owner cannot approve their
own PR. Bot reviews are advisory: the ruleset does not require threads to be resolved or the
branch to be up to date with `main`, because with one contributor and several review bots
either requirement turns two open PRs into a queue. Merging is the owner's action. Agents
open PRs, request reviews, and address comments; they do not merge.

Superseded in part by [0012](0012-the-pr-medic-lands-pull-requests.md): merging is
`pr-medic.yml` and zaffnet in the web UI. Local agents still do not merge. The required
approval count stays 0.

## Consequences

- A fix takes one more step (branch, PR, wait for checks and review) and lands when either
  `pr-medic.yml` or zaffnet merges it (see 0012). Local agents merge nothing.
- `just release` still releases from a pushed `main`; the tag now arrives with a GitHub Release.
- Changing this policy means editing the ruleset in the repository settings, which leaves a
  trace in the audit log.

## Alternatives considered

- Classic branch protection: rulesets replace it, apply to admins without a separate toggle,
  and show up in the API as one object.
- Requiring one approving review: with a single human contributor nobody can give it, so
  every PR would need an admin bypass, which defeats the rule.
