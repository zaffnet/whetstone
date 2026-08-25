#!/usr/bin/env bash
# Force-removes git worktrees and prunes stale entries.
#
# Usage: remove-worktrees.sh PATH [PATH...]
#        remove-worktrees.sh --all      # every worktree except the main one, after confirming
set -euo pipefail

usage() {
  printf 'Usage: %s PATH [PATH...] | --all\n' "${0##*/}"
}

[[ $# -gt 0 ]] || {
  usage >&2
  exit 2
}

main_worktree="$(git worktree list --porcelain | awk 'NR==1 && $1=="worktree" {print $2}')"
worktrees=()

if [[ $1 == --all ]]; then
  while IFS= read -r path; do
    [[ $path == "$main_worktree" ]] || worktrees+=("$path")
  done < <(git worktree list --porcelain | awk '$1=="worktree" {print $2}')
  if [[ ${#worktrees[@]} -eq 0 ]]; then
    echo "No worktrees besides $main_worktree."
    exit 0
  fi
  printf 'About to remove %d worktree(s):\n' "${#worktrees[@]}"
  printf '  %s\n' "${worktrees[@]}"
  read -r -p 'Proceed? (y/N) ' answer
  [[ $answer == [Yy]* ]] || {
    echo Aborted.
    exit 0
  }
else
  for wt in "$@"; do
    [[ $wt == -* ]] && {
      usage >&2
      exit 2
    }
    worktrees+=("$wt")
  done
fi

for wt in "${worktrees[@]}"; do
  echo "Removing $wt"
  git worktree remove --force "$wt"
done

git worktree prune
git worktree list
