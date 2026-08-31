#!/usr/bin/env bash
# Check formatting with ruff, then types with mypy --strict, basedpyright, and Pyrefly.
# Read-only: nothing here rewrites a file.
# Every tool runs even after one fails, so a single pass reports every complaint;
# the exit status is 1 if any tool failed.
#
# Usage: run-typecheck.sh [path ...]
# Paths default to the repo root and are passed to every tool.
#
# Run it from anywhere inside a repository: the repo root is the git top level,
# which is also where the tools resolve their configuration from. A project that
# wants different tools or flags ships its own ./run-typecheck.sh at that root,
# and the typecheck Stop hook prefers that copy over this one.
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

if ! command -v uvx >/dev/null 2>&1; then
  printf '%s\n' "$name: uvx not found. Install uv: https://docs.astral.sh/uv/" >&2
  exit 127
fi

targets=("${@:-.}")
workers=$("$python" -c "import os; print(min(4, os.cpu_count() or 1))")

status=0
run() {
  printf '\n==> %s\n' "$*"
  "$@" || status=1
}

# --check, so this reports rather than rewrites: it runs as a Stop hook, after
# the work has been reported done, and a gate that edited the tree there would
# change code nobody reviewed. Stable mode, not --preview, so a pass here is a
# pass at pre-commit; skip-magic-trailing-comma lives in pyproject.toml, so both
# collapse the same way.
run uv run --no-sync ruff format --check --color always "${targets[@]}"

run uv run --no-sync mypy --strict --num-workers "$workers" "${targets[@]}"

# --threads takes an optional count. A bare `--threads <path>` treats the path as
# the count and crashes. Pass the same cap mypy uses.
run uv run --no-sync basedpyright --threads "$workers" "${targets[@]}"

# Pyrefly is not a project dependency; uvx fetches an ephemeral copy.
# --preset all is the strictest named preset; the extra flags turn on checks
# that `all` does not set by itself. search-path is only passed when stubs/ exists,
# because Pyrefly errors on a missing search path.
pyrefly=(
  uvx pyrefly check
  --preset all
  --check-unannotated-defs=true
  --strict-callable-subtyping=true
  --strict-partial-subtyping=true
  --python-interpreter-path "$python"
)
[[ -d stubs ]] && pyrefly+=(--search-path stubs)
run "${pyrefly[@]}" "${targets[@]}"

exit "$status"
