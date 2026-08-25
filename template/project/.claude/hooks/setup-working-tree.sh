#!/usr/bin/env bash
# Create a git worktree and make it ready to work in.
#
#   setup-working-tree.sh --new <branch> <target-dir>   new branch from HEAD
#   setup-working-tree.sh <branch> <target-dir>         existing branch
#
# After `git worktree add`, copies every path listed in .worktreeinclude (local
# files git does not track: .env, agent config, editor settings), then rebuilds
# the virtualenv and installs the pre-commit hooks.
set -euo pipefail

new_branch=false
if [[ ${1:-} == "--new" ]]; then
  new_branch=true
  shift
fi
branch=${1:?branch name required}
target=${2:?target directory required}

repo_root="$(git rev-parse --show-toplevel)"
mkdir -p "$(dirname "$target")"

if $new_branch; then
  git -C "$repo_root" worktree add -b "$branch" "$target" HEAD
else
  git -C "$repo_root" worktree add "$target" "$branch"
fi

if [[ -f "$repo_root/.worktreeinclude" ]]; then
  while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    src="$repo_root/$line"
    [[ -e $src ]] || continue
    mkdir -p "$(dirname "$target/$line")"
    cp -Rp "$src" "$target/$line"
  done <"$repo_root/.worktreeinclude"
fi

(
  cd "$target"
  uv sync -q --all-groups
  uv run pre-commit install >/dev/null
)
