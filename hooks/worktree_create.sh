#!/usr/bin/env bash
# WorktreeCreate hook. Replaces Claude Code's default worktree logic entirely.
# Instead of `git worktree add` into .claude/worktrees/<name>/, worktrees are
# placed as siblings of the repository (or under WORKTREE_ROOT) and set up in full.
#
# WorktreeCreate does not support matchers; it fires on every worktree creation
# (--worktree, EnterWorktree, agent isolation: "worktree", background sessions).
#
# Contract with Claude Code:
#   stdin  JSON payload with .base_path (repo root) and .worktree_name.
#   stdout the resulting worktree path, as the ONLY line. Everything else goes
#          to stderr so the path parse stays clean.
#   exit   0 on success; any non-zero aborts creation and shows stderr.
#
# Setup itself is delegated to setup-working-tree.sh next to this file, which
# creates the branch from HEAD, copies the .worktreeinclude paths (Claude Code no
# longer does this once a hook is present), and rebuilds the virtualenv.
#
# Environment:
#   WORKTREE_ROOT  Parent directory for new worktrees (default: the repo's parent).
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

base_path="$(hook_field '.base_path // empty')"
worktree_name="$(hook_field '.worktree_name // empty')"

if [[ -z "$base_path" || -z "$worktree_name" ]]; then
  echo "worktree_create: missing base_path or worktree_name in hook payload" >&2
  exit 1
fi

safe_name="${worktree_name//\//-}"
target="${WORKTREE_ROOT:-$(dirname "$base_path")}/$safe_name"

mkdir -p "$(dirname "$target")"

bash "${BASH_SOURCE[0]%/*}/setup-working-tree.sh" \
  --source "$base_path" --new "$worktree_name" "$target" 1>&2

(cd "$target" && pwd)
