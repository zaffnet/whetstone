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
one cannot be a variable. `MAY_MERGE` reads the `PR_MEDIC_MAY_MERGE` repository
variable and defaults to `false`, so a generated repository -- which has no ruleset on its
first day -- does not get an unattended merger just because its owner added a Claude
credential for `@claude` replies.

The approval gate lives in the workflow, not in a ruleset. `APPROVALS_REQUIRED` defaults to
`0`, matching the ruleset count. Raise it when a second human can approve. The platform
count stays 0.

Claude implements review threads and failing checks. `after.sh` then rebases, re-requests
reviewers, evaluates `gate.jq`, and merges the head the gate just judged with
`--match-head-commit`. The medic never approves.

The rebase target is the pull request's own `baseRefName`, not the repository default branch.
`mergeStateStatus == BEHIND` is relative to the base, so a pull request aimed at a release
branch would otherwise be force-pushed with unrelated default-branch history and then merged
into the wrong place. The medic's own scripts and `trust-config.sh` still come from the
default branch, deliberately: that is the trust anchor, and it is the most-reviewed ref.

It does not arm GitHub's auto-merge, and an earlier draft on this branch was wrong to.
Arming hands the decision to GitHub, whose only condition is *required* checks, so every
condition in `decide` that the platform does not enforce (the approval count, the skip
label, unresolved threads) stops being enforced the moment the arming lands, and a push or
a label arriving before the next wake merges anyway. The triggers cover neither head pushes
nor label changes, so that race is real and adding events does not close it. `pending
checks` is therefore a reason to come back rather than to delegate: the `workflow_run` wake
that fires when CI finishes is what brings the medic back to merge. A pull request somebody
armed by hand is left alone, `noop`, because that is GitHub's merge and not the medic's to
take away.

The gate arms or merges only when this run finished cleanly: the worktree is clean and the
checkout is at the PR head the API reports. A Claude failure between resolving a thread and
pushing the fix would leave the remote with no unresolved threads and green checks on a head
the fix is missing from, which remote state alone cannot tell apart from a finished run. The
Claude step is therefore *not* `continue-on-error`: a failure fails the job and `after.sh`
never runs. That replaces the outcome bookkeeping an earlier draft carried in bash.

Once it has read the state it needs, `restore_pr_config` puts the pull request's own copies
of `TRUSTED_PATHS` back. `git rebase` refuses to run with unstaged changes even though the
clean-worktree check excludes those paths, so leaving the restore in place made every stale
pull request that touches `CLAUDE.md` fail at the rebase.

The Claude CLI reads `.claude/`, `.mcp.json`, `CLAUDE.md` and `.husky` from the working
directory at startup -- SessionStart hooks, MCP servers, `NODE_OPTIONS` -- before any
tool-permission gating, and `gh pr checkout` puts the pull request's copies there.
`claude-code-action` restores them from the base branch itself, but only for entity pull
request events: `src/entrypoints/run.ts` guards `restoreConfigFromBase` on
`isEntityContext(context) && context.isPR`. The medic also wakes on `schedule`,
`workflow_dispatch` and `workflow_run`, so `.github/pr-medic/trust-config.sh` does the restore
for every event, between the checkout and the Claude step. Its path list mirrors upstream's
`SENSITIVE_PATHS` and a test pins it, because a path added upstream would silently go
unrestored here.

For the same reason the Claude deny-list is inline in the workflow rather than a file in the
checkout: a settings path is read after the restore and is not one of the restored paths, so a
pull request could edit it.

`allowed_bots` carries the medic's own login, built at runtime in the `bot` step. On a
`workflow_run` wake after a medic push, `github.actor` is whoever pushed -- this bot -- and
the action's agent mode calls `checkHumanActor`, which throws on any non-`User` actor that is
not allowed. Since the Claude step is not `continue-on-error`, omitting it would stop the gate
on the push-then-CI-completes wake, which is the main way a fix reaches it. This list does not
decide what the medic works on; `pick` does.

Claude runs behind an explicit `--allowedTools` allowlist, not only the deny block:
`claude-code-action` agent mode sets neither `--permission-mode` nor `--allowedTools`, so
without them the model has Read, Grep and Glob and cannot do the work at all. `gh pr merge`
and `gh pr review` are off the list, and `git push` is allowed only bare or with
`--force-with-lease`.

`gh api` is off the list too, and denied outright. It used to be on it, because resolving a
review thread needs `gh api graphql` and there is no narrower form of that command — and the
same command approves and merges. So the model no longer touches the threads directly:
`.github/pr-medic/threads.sh dump` writes the unresolved threads to a file, the model writes
`[{thread_id, reply, resolve}]` to another, and `apply` performs the replies in bash. It
accepts only thread IDs that `dump` captured, requires a reply on every entry, refuses to
resolve a thread whose comments `dump` could only read in part, and treats a malformed file as
a failure rather than as nothing to do. Both files live under `RUNNER_TEMP`
and the model reaches them through `--add-dir`, because a file written inside the worktree
would trip the clean-worktree check in `after.sh`.

Every git primitive that can launch a command or choose a destination is off the allowlist and
on the deny list, replaced by a helper in `.github/pr-medic/` that validates its own
arguments: `rebase.sh` (no arguments; `git rebase --exec` runs shell commands), `commit.sh`
(one message; `git commit -F` reads a file into the message, which the next push publishes)
and `push.sh` (resolves the head ref from the API and names it in the refspec; bare
`git push` follows the upstream, and `git checkout` can change what that is). `just` and
`uv run` are gone for the same reason. `git diff` keeps only its argument-free forms, because
`--no-index` prints any file on disk, and `git log` and `git show` lose their wildcards
because `--output=FILE` writes wherever it is pointed -- including over the helper copies the
gate then runs. That directory is also made read-only once populated, so the two controls do
not depend on each other.
`gh api` buys nothing while something on the list can launch it: `uv run gh api ...` matches
`Bash(uv run:*)`, and `just` reads a justfile out of the pull request's own checkout. More
generally, any command that runs the pull request's code — its tests, its justfile, its hooks
— with a write token in the environment is equivalent to handing that pull request the token,
and there is no narrow form of it. Verification is CI's job; the medic reads the result.
`git push --force-with-lease` takes no argument either, because a refspec can name the default
branch. `.git` is denied to `Read`, `Grep` and `Glob` as well as to `Write` and `Edit`. Writes,
because a hand-written git config turns a read-only command into a launcher; reads, because
`claude-code-action` backs git with the token in the origin URL when commit signing is off
(`replaceCheckoutCredentials` in `src/github/operations/git-config.ts`), so `.git/config`
holds a live write credential for the length of the run.

None of that is a boundary, though; it is a set of guardrails inside the model's own process.
Allow-list patterns match on a prefix, and four consecutive rounds of review each found another
primitive whose flags reached past the deny list -- `uv run` and `just`, then `git rebase
--exec` and `git fetch --upload-pack`, then `git diff --no-index` and `git commit -F` and bare
`git push`, then `gh pr comment --body-file`. Enumerating flags loses to the next flag nobody
thought of.

So the boundary is drawn outside the process instead: **the Claude step holds no credential
that can write.** `token-ro` mints a second App token without `contents: write`, and that is
what the action receives -- which matters because the action puts whatever token it is given
into the origin URL, where `.git/config` made it readable. Claude commits through `commit.sh`
and does not push at all; `after.sh` pushes what it finds, in a step with no model in it. An
injected instruction now has nothing in reach to misuse, rather than nothing on a list.

`after.sh` has to undo one side effect of that: the action embeds whatever token it is given
in the origin URL, so after the Claude step the remote carries a read-only credential and a
push from the gate would fail. It repoints `origin` at the plain URL and re-runs
`gh auth setup-git`, which supplies the gate step's own token. Every push goes through
`push.sh`, including the one after a rebase, so there is a single path and a single
destination check.

Without a GitHub App there is no second token to mint and the Claude step falls back to
`GITHUB_TOKEN`, so a drop-in repository keeps the older, weaker property. That is the same
trade as the rest of the App path: configure one and the guarantees get stronger.

That leaves the model with no command that can approve or merge, rather than an allowlist that
could not separate the two. The ruleset — required status checks and
`required_review_thread_resolution` — is still the control that holds; this removes the
standing hole above it. Two review rounds asked for this and were told a second file would
break the one-file drop-in; withdrawing that rule is what made it available.

`.github/pr-medic/` is taken from the default branch into `RUNNER_TEMP` after
`gh pr checkout`, and the gate runs that copy. Restoring it into the checkout instead was not
durable: the model has `Edit` and `Write` there, so it could rewrite `after.sh` between the
restore and the gate step that executes it. Copying it out of reach also avoids a second
problem -- a pull request that legitimately edits these scripts, as the one introducing them
does, would look dirty to `after.sh`'s own clean-worktree check.

The helpers on the tool allowlist are the copies under `RUNNER_TEMP`, not the ones in the
checkout, and `prompt.md` is read from there too. Otherwise a pull request could rewrite
`commit.sh` and have the model invoke the allowlisted path -- arbitrary shell, past every deny
rule -- or rewrite the instructions the model is given.

If `.github/pr-medic` is missing from the default branch the job fails. It used to fall back
to the checkout's copy, which would have run PR-controlled scripts with the write token in the
next step -- the exact thing taking them from the default branch is for. A missing helper
directory is a configuration error, so it is reported as one.

Nothing the model writes is treated as evidence. `threads.sh apply` re-queries the open
threads instead of reading back the file it handed over, because `--add-dir` makes that file
writable; and `trusted-state` lives outside that directory, because only `after.sh` reads it
and a state file the model could rewrite would certify whatever it liked. The digest covers
the contents of the trusted paths, not only git's view of them: a path the pull request
deletes is restored untracked, where `git status` prints the same `??` line whatever the file
holds and `git diff HEAD` sees nothing -- so an edit there passed the check, and
`restore_pr_config`'s `git clean` then deleted a fix a reply had already claimed.

The threads `apply` will act on are the intersection of what is open now and what the
snapshot holds. Open-now alone would accept a thread created after `dump`, which the model was
never shown and can have no answer to.

A thread only reaches the model if every one of its comment authors can push to the
repository, or is one of the bots the workflow names -- the same list the action gets as
`allowed_bots`, judged by `repos/{repo}/collaborators/{login}/permission` rather than by
`authorAssociation`, for the reasons under `approval_count`. This is a public repository:
anyone who can read it can open a review thread, and the hourly sweep reaches a pull request
whether or not an event for it was accepted. Without the filter, any passer-by's thread body
became prompt text that `after.sh` then pushed. Every author, not only the one who opened the
thread, because an untrusted reply on a Copilot thread is still text in the prompt. A withheld
thread stays unresolved, which the merge gate counts, so the pull request waits for someone
with push access instead of merging -- fail-closed, and no change to what a stranger could
already do by leaving a comment. It costs a contributor nothing: `pick.jq` refuses a
cross-repository pull request, so every branch the medic works on is one in this repository
and its author can push by construction.

`apply` also refuses to resolve a thread whose comments have changed since `dump` took its
snapshot. A reviewer can add a comment while the model is working, and a `resolve: true`
written before that arrived would mark the new comment satisfied too -- after which the gate
sees no unresolved threads and merges. Replying to such a thread is still allowed; only the
claim that the code now satisfies it is refused.

That comparison reads the thread again immediately before each resolve, not once at the top of
`apply`: posting replies takes seconds, and a comment landing in that window was invisible in
the older list. Since the reply just posted is this run's own, the test is that the thread is
the snapshot with exactly one comment appended, which also catches a comment that arrived
before the reply -- ours would no longer be the only addition.

Resolving is a claim about a particular head, so `after.sh` passes the head it verified and
`apply` re-reads the live head before each resolve. Nothing can make the read atomic with the
mutation, so the window is one call wide, and a move seen afterwards is compensated rather
than left: `apply` unresolves every thread it resolved in that run and fails. A thread left
resolved against a head the gate never judged is the state that matters, because the next run
reads a resolved thread as satisfied and would merge on it.

`after.sh` pushes in one of two shapes. New commits on top of the remote branch fast-forward;
a rebase rewrites history, HEAD stops descending from the remote branch, and a plain push is
rejected -- so a conflict the model was told to resolve would never reach the gate.
`git merge-base --is-ancestor` picks between them, and the rewritten case uses
`--force-with-lease`, which still refuses a remote that moved since the fetch. Both go through
`push.sh`, so the destination is always resolved from the API.

Every `git fetch` in the helpers passes `--no-recurse-submodules`. Under the default
`fetch.recurseSubmodules=on-demand` git reads `.gitmodules` during a fetch, and `after.sh`
fetches after `restore_pr_config` has put the pull request's copy back -- in the step that
holds the write token. A test asserts the flag on every fetch rather than trusting review.

`gh run rerun` is not on the model's allowlist either. With the `actions: write` token,
`Bash(gh run rerun:*)` is the run id of anything in the repository -- an old release or
deployment run -- and the model reads pull-request-controlled check logs, so an injected
instruction had a privileged side effect within reach. `rerun.sh` takes one run id and checks it
against this repository, this pull request's head, and not `pr-medic.yml` itself, which a medic
re-running would turn into a loop no gate result can end.

Undoing a resolution is verified and retried, and its failure is not a warning. The job going
red is not a control here: `pr-medic` is deliberately not a required check, so a later wake
would read the thread as satisfied and merge. If a thread cannot be reopened the pull request
gets the skip label, which `pick.jq` drops and `gate.jq` refuses, and which takes a person to
clear. `apply` also records the threads it resolved to a file outside `--add-dir`, because its
own per-resolve check cannot cover the time `after.sh` spends reading the gate and attempting
the merge -- a push landing there leaves the resolutions attached to a head nothing judged, and
the refused merge does not undo them. `after.sh` reopens them instead.

The tool allowlist cannot be the control against redirection. Every `Bash(... :*)` rule is a
prefix match, so it admits a redirection as readily as the command: `gh run view --log >
$GITHUB_ENV` is an allowed `gh run view`, and `BASH_ENV` or `PATH` set in that file is read by
the *next* step -- the gate, holding the write token -- which would undo the point of giving
the model a read-only one. A step cannot sanitise its own environment after the fact either,
because `BASH_ENV` is read before a run block's first line. So `GITHUB_ENV` and `GITHUB_PATH`
are pointed at throwaway files for the Claude step, and the runner reads back the paths it
assigned, which stay empty. `GITHUB_OUTPUT` and `GITHUB_STATE` are left alone: they reach no
other step, and the action needs them. The alternative -- the model in a separate job -- was
not taken, because the gate's checks are about runner state that no artifact can carry across a
job boundary without the model being able to forge it.

The same redirection reaches the gate's evidence: `git status > .../trusted-state` needs no tool
at all, so keeping the snapshot and `trusted-state` outside `--add-dir` only stops the Write
tool. `$RUNNER_TEMP/pr-medic-state` is made read-only, directory included, before the Claude
step, and `after.sh` takes the writes back.

Reopening a resolution is a trap, not a branch. Most of the ways `after.sh` can stop are `set
-e` exits that run no code path -- the reviewer POST, a gate API call, a jq failure -- and any
of them would leave a thread resolved against a head nothing judged. The trap is armed before
`apply` and cleared only once the run has merged on the judged head or confirmed the head has
not moved.

Re-runs are brokered rather than granted. The action copies the token it is given into the
model's subprocess, and every allowed command takes arguments, so `commit.sh "$GH_TOKEN"` was a
way to publish that credential in a commit message this script then pushes. Removing the
argument would not have helped -- a redirection reaches a file in the checkout just as well --
so the answer is that the token stops being worth stealing: the model's token is read-only
throughout, it has no re-run command, and it writes the run ids it wants into `reruns.json`.
`after.sh` performs them through `rerun.sh`, before the gate reads check state, so a re-run this
run starts is seen as pending rather than merged over.

The skip label is created before it is applied and the result is read back. A repository that
has never used the label does not have it, `--add-label` cannot create one, and this path was
reporting a block it had not applied -- which is worse than no block, because it is the only
thing between a stale resolution and the next wake merging on it.

The App is required, not preferred, and the medic job's own permissions are all read. The
read-only App token passed as `github_token` is not a boundary by itself: `action.yml` sets
`DEFAULT_WORKFLOW_TOKEN: ${{ github.token }}` on the step that runs the action, and
`base-action/src/parse-sdk-options.ts` copies the whole process environment into the SDK, so
the job token reaches the model whatever this workflow passes. A write-capable job token is
therefore a write-capable token in the model's hands, and `commit.sh "$DEFAULT_WORKFLOW_TOKEN"`
publishes it. Every write uses the App token instead, with no `|| github.token` fallback to put
one back, and the job does not run at all without `APP_CLIENT_ID` -- the `pick` job warns when
it had work and no App, because a silently skipped job reads as nothing to do. The action's
`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` is also set, but as the second line: its own documentation
calls it best-effort, and a control that has to hold cannot be best-effort.

A re-run request has to name one of the pull request's own checks, not merely a run on its head
sha. A release or deployment workflow triggered by the same commit is on the same sha, and
`gh run list` is on the model's allowlist, so it could find one. `rerun.sh` intersects the id
with the run ids in the pull request's `statusCheckRollup`.

A bot's comment wakes the medic only if the bot is in `TRIGGER_BOTS`. `threads.sh` posts a reply
whether or not it resolves the thread, and that reply is a `pull_request_review_comment` like
any other -- so a thread the model decided not to resolve woke the medic, which replied again,
which woke it again. The medic's own login is not in `TRIGGER_BOTS` and Copilot's is, which is
the whole of the distinction.

The resolution block is a label of its own, `BLOCK_LABEL`, taken before the first resolve and
lifted only once the run has accounted for what it resolved. Separate from `SKIP_LABEL` so that
lifting it cannot clear a person's "leave this alone", and taken first because a marker applied
on the way out can fail on the way out: `apply` resolves nothing until the block is in place and
has been read back. Both names go to `pick.jq` and `gate.jq`, which refuse on either.

The token given to the model's step is read-only in every scope. Its `pull-requests` permission
was `write` until it did not need to be: an explicit prompt selects the action's agent mode,
which creates no tracking comment -- `src/modes/agent/index.ts` leaves `claudeCommentId`
undefined and the update at the end of `run.ts` is guarded on it -- and the medic's replies are
posted by `threads.sh` in the gate step.

On `schedule`, `workflow_dispatch` and `workflow_run` the workflow file itself is trusted, so
the copy in `RUNNER_TEMP` is what the gate runs and the chain holds. On an entity event the
workflow file is the pull request's as well, so nothing written in the file can help: that is a
property of `pull_request_review` running the head's workflow, and it means write access to
this repository is already full control.

The `@claude` mention path is `.github/workflows/claude.yml`, with `contents: read`. It
answers; it does not push, and it has nothing to do with landing pull requests. `allowed_bots`
does not list `github-actions[bot]`, because the medic posts under that login and would
otherwise wake itself.

There is no attempt budget and no `DRY_RUN`. The budget was a `pr-medic` commit status, an
`attempts=N` counter, a per-commit status loop and a `newer_review_than_medic` waiver --
about 70 lines to stop the hourly cron re-attempting an unchanged head. The escape hatch is
now the `no-medic` label. `DRY_RUN` threaded a third state through every write, and the
disarm it provided is `MAY_MERGE` instead.

Local agents still never merge. Merging belongs to this workflow and to zaffnet in the web
UI.

`SKIP_LABEL` is checked by the gate as well as by `pick`, because a label applied after
`pick` has run must still stop the merge.

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
- Runs queue and are never cancelled. A cancel between Claude resolving a thread and pushing
  the fix leaves the remote looking finished on a head the fix is missing from, and the next
  run checks out that head clean, so neither runner check catches it. Queueing costs duplicate
  wakes; each re-reads state and reaches `noop`. Only `workflow_run` collapses onto the head
  SHA; every other event keys on `github.run_id`.
- `pick` selects a pull request the gate might merge, and leaves alone one somebody armed by
  hand, because the gate would only say `noop` there. `MAY_MERGE` sits above that `noop` in
  `decide`, so the switch still reports something actionable on a hand-armed pull request.
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
