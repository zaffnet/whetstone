#!/usr/bin/env bash
# Rebase the checked-out pull request onto its own base branch. Takes no arguments: the
# destination comes from the API, not from the caller.
#
# This exists so `git rebase` need not be on the model's tool allowlist. `git rebase --exec
# <cmd>` (and `-x`) runs shell commands, which makes an unrestricted rebase a way to reach
# `gh api` and merge or approve despite the deny list. Same for `git fetch --upload-pack`.
# The model gets this, plus `git rebase --continue` and `--abort` by exact match -- neither of
# which takes a command.
set -euo pipefail

# shellcheck source=.github/pr-medic/lib.sh
. "$(dirname "$0")/lib.sh"
: "${PR:?}" "${REPO:?}"

# The pull request's own base, not the repository default branch. A PR targeting a release
# branch must not be rebased onto main.
base_ref=$(gh pr view "$PR" --repo "$REPO" --json baseRefName --jq .baseRefName)
git fetch --no-recurse-submodules origin "$base_ref"
git rebase "origin/$base_ref"
