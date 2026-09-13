#!/usr/bin/env bash
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
