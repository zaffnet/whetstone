#!/usr/bin/env bash
# Re-run the failed jobs of one workflow run, if that run belongs to this pull request's head.
#
# This exists so `gh run rerun` need not be on the model's tool allowlist. `Bash(gh run rerun:*)`
# plus the actions: write token is the run id of anything in the repository -- an old release or
# deployment run -- and the model reads PR-controlled check logs, so an injected instruction had
# a privileged side effect within reach. The run id is checked here instead, outside the model.
set -euo pipefail

: "${PR:?}" "${REPO:?}"

run_id=${1:-}
[ "$#" -eq 1 ] && [ -n "$run_id" ] || {
  echo "usage: rerun.sh <run-id>" >&2
  exit 2
}
case $run_id in
  *[!0-9]*)
    echo "usage: rerun.sh <run-id>" >&2
    exit 2
    ;;
esac

head=$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq .headRefOid)
run=$(gh api "repos/$REPO/actions/runs/$run_id" --jq '{sha: .head_sha, path: .path, repo: .repository.full_name}')

# Naming another repository's run reaches it through this repository's token.
[ "$(jq -r .repo <<<"$run")" = "$REPO" ] || {
  echo "::error::run $run_id does not belong to $REPO"
  exit 1
}
# The head, not the pull request: a run on an earlier head tells nothing about the code the
# gate is about to judge, and re-running it only produces a stale answer.
run_sha=$(jq -r .sha <<<"$run")
[ "$run_sha" = "$head" ] || {
  echo "::error::run $run_id is on ${run_sha:0:7}, not PR #$PR's head ${head:0:7}"
  exit 1
}
# Never this workflow. A medic re-running itself is a loop no gate result can end.
case "$(jq -r .path <<<"$run")" in
  */pr-medic.yml)
    echo "::error::run $run_id is pr-medic's own; re-running it would loop"
    exit 1
    ;;
esac

gh run rerun "$run_id" --failed
