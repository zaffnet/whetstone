#!/usr/bin/env bash
# Check formatting with ruff, then types with mypy --strict, basedpyright, and Pyrefly.
# Read-only: nothing here rewrites a file.
# Every tool runs even after one fails, so a single pass reports every complaint;
# the exit status is 1 if any tool failed.
#
# Usage: run-typecheck.sh [path ...]
# Paths default to the repo root and are passed to every tool.
#
# Run it from anywhere inside a repository: it cd's to the git top level, which is
# where the tools resolve their configuration from. A project that wants different
# tools or flags ships its own ./run-typecheck.sh at that root, and the typecheck
# Stop hook prefers that copy over this one.
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

# --check, so this reports rather than rewrites: it runs as a Stop hook, and a gate
# that edited the tree would change code nobody reviewed. Stable mode, not --preview,
# so a pass here is a pass at pre-commit.
#
# --force-exclude, because ruff checks a path named on the command line even when the
# project excludes it. Without it a caller passing explicit targets reports findings
# on generated code that a repository-wide run skips.
run uv run --no-sync ruff format --check --force-exclude --color always "${targets[@]}"

# explicit-preview-rules keeps --preview + ALL from enabling every preview rule;
# E266 is the one preview rule opted into.
ruff_check=(
  uv run --no-sync ruff check
  --target-version py312
  --config "line-length = 100"
  --select ALL
  --extend-select E266
  --ignore "D100,D101,D102,D103,D104,D105,D203,D213,COM812,FIX,TD,TRY003,CPY001"
  --per-file-ignores "*_test.py:S101"
  --per-file-ignores "*_test.py:S105"
  --per-file-ignores "*_test.py:S404"
  --per-file-ignores "*_test.py:S603"
  --per-file-ignores "*_test.py:PLR2004"
  --per-file-ignores "*.pyi:ANN401"
  --config "lint.explicit-preview-rules = true"
  --force-exclude
  --preview
  --color always
)
run "${ruff_check[@]}" "${targets[@]}"

# A module and its stub are one module to mypy: given both it reports a duplicate and
# stops having checked nothing, so only one may be a target. The stub wins, the
# precedence a repository-wide run already gives it. Scoped to this invocation because
# the other tools do not collide and do report findings the stub alone cannot carry.
#
# A stub absent from the target list is not substituted in: it was not asked for, and
# for a caller passing explicit paths that would check something it never named.
mypy_targets=()
for target in "${targets[@]}"; do
  if [[ $target == *.py ]]; then
    stub="${target%.py}.pyi"
    for other in "${targets[@]}"; do
      [[ $other == "$stub" ]] && continue 2
    done
  fi
  mypy_targets+=("$target")
done
run uv run --no-sync mypy --strict --num-workers "$workers" "${mypy_targets[@]}"

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
