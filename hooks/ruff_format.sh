#!/usr/bin/env bash
# PostToolUse hook. After a Python file changes, apply ruff lint fixes and formatting
# so problems surface at edit time instead of at pre-commit time.
#
# Matched against Edit, Write, NotebookEdit, Bash, and PowerShell. The first three
# name the file in the payload; a shell tool does not, so the working tree is what
# says which files changed. Both paths land here because a formatter that only sees
# Edit and Write misses everything a shell command writes.
#
# Never blocks: every failure path exits 0 and lets pre-commit be the gate.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

# Run ruff from the project that owns the file, so a file in another repository
# (reachable through --add-dir) is formatted under its own pyproject.toml, not
# this one's. No pyproject.toml above the file means no opinion: do nothing.
format_one() {
  local file_path=$1 project_root
  case "$file_path" in
    *.py | *.pyi) ;;
    *) return 0 ;;
  esac
  [[ -f $file_path ]] || return 0

  project_root="$(dirname -- "$file_path")"
  while [[ ! -f $project_root/pyproject.toml ]]; do
    [[ $project_root != / && $project_root != . ]] || return 0
    project_root="$(dirname -- "$project_root")"
  done

  # A subshell so the cd and VIRTUAL_ENV do not carry to the next file in the loop
  # below. VIRTUAL_ENV is cleared because the inherited one belongs to whichever
  # project the session started in, and uv warns about the mismatch on every call.
  (
    cd "$project_root" || exit 0
    unset VIRTUAL_ENV
    # The project's own ruff first, then one on PATH. Neither present means the
    # project has not installed it yet, and building an environment mid-turn costs
    # far more than the formatting is worth, so `uv run` is deliberately not used.
    local ruff=.venv/bin/ruff
    [[ -x $ruff ]] || ruff="$(command -v ruff 2>/dev/null)" || exit 0
    # Printed only when ruff exits non-zero, which is when something is left
    # unfixed. A clean pass still writes "All checks passed!", and that is not a
    # finding: reporting it would put noise in front of Claude on every edit.
    local lint
    lint="$("$ruff" check --fix "$file_path" 2>&1)" || printf '%s\n' "$lint"
    "$ruff" format "$file_path" >/dev/null 2>&1 || true
  )
}

file_path="$(hook_field '.tool_input.file_path // empty')" || exit 0

report=""
if [[ -n $file_path ]]; then
  report="$(format_one "$file_path")"
else
  # A shell tool wrote something, or the payload names no file. Ask the working tree
  # instead, from the repository that owns the cwd.
  cwd="$(hook_field '.cwd // empty')"
  [[ -n $cwd ]] || cwd="$PWD"
  root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
  cd "$root" || exit 0

  while IFS= read -r -d '' changed; do
    report+="$(format_one "$changed")"
  done < <(hook_changed_files '*.py' '*.pyi')
fi

# What ruff could not fix itself, which is the part worth Claude's attention.
[[ -n ${report//[[:space:]]/} ]] || exit 0
printf '%s\n' "$report" | hook_emit_system_message PostToolUse
exit 0
