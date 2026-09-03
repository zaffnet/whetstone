#!/usr/bin/env bash
# Stop hook. It reports what the type checkers found and lets the turn end; the
# checkers also run in pre-commit and CI, so nothing here blocks.
# Suppressions are code_prose_honesty.sh's business, not this hook's.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

# How recently a file must have changed to count as this turn's work. Paired with
# the working-tree diff below, which alone cannot tell an edit from a `git checkout`
# or `git reset`: those move HEAD, and every file differing across the two commits
# reads as changed. A checkout also restamps the mtime of what it rewrites, so this
# window must have closed by the time the turn ends.
#
# The cost is that a Stop hook has no bounded delay from the write, so an edit
# followed by a long test run goes unreported. That is the safe direction: pre-commit
# and CI are the gates.
STALE_AFTER_SECONDS=30

# Lines of checker output to report. A systemMessage past the harness's inline limit
# is spilled to a file and reaches Claude truncated, so an unbounded report loses the
# findings it exists to deliver.
MAX_REPORT_LINES=200

# And a byte ceiling, because the limit that truncates is on bytes, not lines, and a
# single line can pass it on its own.
MAX_REPORT_BYTES=16384

cwd="$(hook_field '.cwd // empty')"
[[ -n $cwd ]] || cwd="$PWD"

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# The inherited value belongs to whichever project the session started in, and every
# `uv run` below warns about the mismatch when the checked repository is another one.
unset VIRTUAL_ENV

# No Python in the repository means no opinion.
[[ -f pyproject.toml ]] || exit 0

# The files to check, kept as a list rather than spent as a yes/no gate: it is what
# the checkers below are pointed at. Nothing written recently means nothing to check.
#
# Read in a loop because `mapfile -d` needs bash 4 and macOS ships bash 3.2.
candidates=()
while IFS= read -r -d '' file; do
  candidates+=("$file")
done < <(hook_changed_files '*.py' '*.pyi' | hook_recently_modified "$STALE_AFTER_SECONDS")
((${#candidates[@]})) || exit 0

# A module and its stub are one module to mypy: given both it reports a duplicate and
# stops without checking anything, so only one may be a target. The stub wins, the
# precedence a repository-wide run already gives it.
#
# Tested against the other candidates rather than against the filesystem. A stub that
# exists but was not written this turn is not a target, and dropping the
# implementation for it would leave nothing to check.
changed=()
for file in "${candidates[@]}"; do
  if [[ $file == *.py ]]; then
    stub="${file%.py}.pyi"
    for other in "${candidates[@]}"; do
      [[ $other == "$stub" ]] && continue 2
    done
  fi
  changed+=("$file")
done

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
#
# The changed files are passed as arguments, or the checkers default to the repository
# root and report on code this turn never touched.
#
# Output goes to a file so the status is captured before the trimming: piping into
# head would report head's status, which is 0 even when a checker failed.
output=""
status=0
report="$(mktemp)" || exit 0
trap 'rm -f "$report"' EXIT
bash "$checker" "${changed[@]}" >"$report" 2>&1 || status=$?
((status != 0)) || exit 0
output="$(head -n "$MAX_REPORT_LINES" "$report" | head -c "$MAX_REPORT_BYTES")"

# Reported, not enforced: this hook exits 0 either way, and pre-commit and CI are the
# gates.
printf '%s\n' "The type checkers reported findings on the files this turn changed.
Fix the root cause of each; do not silence a checker.

$output" | hook_emit_system_message
exit 0
