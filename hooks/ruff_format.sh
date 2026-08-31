#!/usr/bin/env bash
# PostToolUse hook. After Claude edits a Python file, apply ruff lint fixes and
# formatting so problems surface at edit time instead of at pre-commit time.
# Never blocks: every failure path exits 0 and lets pre-commit be the gate.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

file_path="$(hook_field '.tool_input.file_path // empty')" || exit 0

case "$file_path" in
  *.py | *.pyi) ;;
  *) exit 0 ;;
esac

# Run ruff from the project that owns the file, so a file in another repository
# (reachable through --add-dir) is formatted under its own pyproject.toml, not
# this one's. No pyproject.toml above the file means no opinion: do nothing.
project_root="$(dirname -- "$file_path")"
while [[ ! -f $project_root/pyproject.toml ]]; do
  [[ $project_root != / && $project_root != . ]] || exit 0
  project_root="$(dirname -- "$project_root")"
done
cd "$project_root" || exit 0

# Unfixable lint output goes to stderr so Claude sees it. --no-sync: formatting must
# not resolve, lock, or install that project's environment on every edit; if ruff is
# not there yet, pre-commit is the gate.
uv run --no-sync ruff check --fix "$file_path" 1>&2 || true
uv run --no-sync ruff format "$file_path" >/dev/null 2>&1 || true

exit 0
