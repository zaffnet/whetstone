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

if ! command -v uvx >/dev/null 2>&1; then
  printf '%s\n' "$name: uvx not found. Install uv: https://docs.astral.sh/uv/" >&2
  exit 127
fi

targets=("$@")
workers=$("$python" -c "import os; print(min(4, os.cpu_count() or 1))")

status=0
run() {
  printf '\n==> %s\n' "$*"
  "$@" || status=1
}

run uv run --no-sync ruff format --check --force-exclude --color always "${targets[@]+"${targets[@]}"}"

ruff_check=(
  uv run --no-sync ruff check
  --target-version py312
  --config "line-length = 100"
  --select ALL
  --extend-select E266
  --ignore "D100,D101,D102,D103,D104,D105,D203,D213,COM812,FIX,TD,TRY003,CPY001"
  --extend-include bin/sync-mcp
  --extend-include bin/sync-iterm2-profile
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
run "${ruff_check[@]}" "${targets[@]+"${targets[@]}"}"

mypy_targets=()
for target in "${targets[@]+"${targets[@]}"}"; do
  if [[ $target == *.py ]]; then
    stub="${target%.py}.pyi"
    for other in "${targets[@]+"${targets[@]}"}"; do
      [[ $other == "$stub" ]] && continue 2
    done
  fi
  mypy_targets+=("$target")
done
mypy=(uv run --no-sync mypy --strict --scripts-are-modules --num-workers "$workers")
run "${mypy[@]}" "${mypy_targets[@]+"${mypy_targets[@]}"}"

run uv run --no-sync basedpyright --threads "$workers" "${targets[@]+"${targets[@]}"}"

pyrefly=(
  uvx pyrefly check
  --preset all
  --check-unannotated-defs=true
  --strict-callable-subtyping=true
  --strict-partial-subtyping=true
  --python-interpreter-path "$python"
)
[[ -d stubs ]] && pyrefly+=(--search-path stubs)
run "${pyrefly[@]}" "${targets[@]+"${targets[@]}"}"

exit "$status"
