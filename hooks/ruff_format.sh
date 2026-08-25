#!/usr/bin/env bash
# PostToolUse hook. After Claude edits a Python file, apply ruff lint fixes and
# formatting so problems surface at edit time instead of at pre-commit time.
# Claude Code passes the tool-call payload as JSON on stdin.
# This hook never blocks: it always exits 0 and lets pre-commit be the gate.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

file_path="$(hook_field '.tool_input.file_path // empty')"

case "$file_path" in
  *.py | *.pyi)
    # Send any remaining (unfixable) lint output to stderr so Claude sees it.
    uv run ruff check --fix "$file_path" 1>&2 || true
    uv run ruff format "$file_path" >/dev/null 2>&1 || true
    ;;
esac

exit 0
