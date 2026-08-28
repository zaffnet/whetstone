#!/usr/bin/env bash
# Push the checked-out pull request branch, and nothing else.
#
# `git push` is not on the model's allowlist. Bare `git push` sends the current branch to its
# upstream, so combined with a branch switch it could target the default branch. This resolves
# the destination from the API and names it explicitly in the refspec, so neither the current
# branch nor the remote's configuration decides where the push lands.
set -euo pipefail

# Arguments before environment, so a usage error is a usage error whatever else is unset.
force=()
case "${1:-}" in
  "") ;;
  --force-with-lease) force=(--force-with-lease) ;;
  *)
    echo "usage: push.sh [--force-with-lease]" >&2
    exit 2
    ;;
esac
[ "$#" -le 1 ] || {
  echo "usage: push.sh [--force-with-lease]" >&2
  exit 2
}

: "${PR:?}" "${REPO:?}"

head_ref=$(gh pr view "$PR" --repo "$REPO" --json headRefName --jq .headRefName)
current=$(git rev-parse --abbrev-ref HEAD)
[ "$current" = "$head_ref" ] || {
  echo "::error::refusing to push: HEAD is '$current' but PR #$PR is '$head_ref'"
  exit 1
}
# ${force[@]+...}: bash 3.2 -- macOS's /bin/bash -- reads "${force[@]}" on an empty array as
# an unbound variable under set -u, so a plain push would die here rather than push.
git push ${force[@]+"${force[@]}"} origin "HEAD:refs/heads/$head_ref"
