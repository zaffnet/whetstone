#!/usr/bin/env bash
# Stop hook. It reports what the type checkers found and lets the turn end; the
# checkers also run in pre-commit and CI, so nothing here blocks.
# Suppressions are code_prose_honesty.sh's business, not this hook's.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

cwd="$(hook_field '.cwd // empty')"
[[ -n $cwd ]] || cwd="$PWD"

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# No Python in the repository means no opinion.
[[ -f pyproject.toml ]] || exit 0

# Nothing changed, nothing to check.
[[ -n "$(hook_changed_files '*.py' '*.pyi')" ]] || exit 0

# A repository's own script overrides the one shipped here, which is how it chooses
# different tools or flags. Tested for readable rather than executable, and run through
# bash below, because copier writes the template's copy without the executable bit and a
# generated project has no other checker.
checker="./run-typecheck.sh"
if [[ ! -r $checker ]]; then
  # The plugin sets CLAUDE_PLUGIN_ROOT; a Stop hook configured in settings.json does
  # not, so fall back to this script's own directory. `pwd -P` resolves the
  # ~/.agents/hooks symlink to the checkout, which is what puts bin/ one level up.
  # Guarded with :+ because unset, "$var/bin/run-typecheck.sh" is the absolute path
  # /bin/run-typecheck.sh.
  checker="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/run-typecheck.sh}"
  if [[ ! -r $checker ]]; then
    here="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)" || exit 0
    checker="$here/../bin/run-typecheck.sh"
  fi
  # The shipped script runs mypy and basedpyright from the target project's
  # environment, so a repository without them would fail on the missing
  # executables rather than on its code.
  [[ -r $checker ]] \
    && uv run --no-sync python -c 'import mypy, basedpyright' >/dev/null 2>&1 \
    || exit 0
fi

# Interleaved into one stream: a checker's complaint is on stdout or stderr
# depending on the tool, and the report needs both.
output=""
status=0
output="$(bash "$checker" 2>&1)" || status=$?
((status != 0)) || exit 0

printf '%s\n' "The type checkers failed. The work is not done until they pass.
Fix the root cause of every finding; do not silence a checker.

$output" | hook_emit_system_message
exit 0
