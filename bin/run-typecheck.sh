#!/usr/bin/env bash
set -euo pipefail

name=$(basename "$0")

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf '%s\n' "$name: not inside a git repository" >&2
  exit 127
}
cd "$root"

python=$root/.venv/bin/python
if [[ ! -x $python ]]; then
  printf '%s\n' "$name: missing $python. Run: uv sync --all-groups" >&2
  exit 127
fi

targets=("${@:-.}")
workers=$("$python" -c "import os; print(min(4, os.cpu_count() or 1))")

status=0
run() {
  printf '\n==> %s\n' "$*"
  "$@" || status=1
}

run uv run --no-sync ruff format --check --force-exclude --color always "${targets[@]}"
run uv run --no-sync ruff check --force-exclude --color always "${targets[@]}"
run uv run --no-sync mypy --num-workers "$workers" "${targets[@]}"
run uv run --no-sync basedpyright --threads "$workers" "${targets[@]}"
run uv run --no-sync pyrefly check "${targets[@]}"

exit "$status"
