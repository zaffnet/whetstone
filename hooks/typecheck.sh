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

# Every candidate is a target. A module and its stub collide only for mypy, and the
# runner drops the implementation for that one invocation: ruff and basedpyright
# report real findings on the .py -- an unused import, a return type -- and report
# nothing when handed only the .pyi, so dropping it here would lose them.
#
# Prefixed with ./ because these paths go to the checkers as arguments, and git tracks
# a name like `--version.py`: bare, every one of the four reads it as an option and
# checks nothing. Verified on all four; `--` would fix the leading dash too, but
# basedpyright rejects the separator itself.
changed=()
for file in "${candidates[@]}"; do
  changed+=("./$file")
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
# Trimmed in two steps rather than one pipeline. Piping `head -n` into `head -c`
# makes the first receive SIGPIPE when the second closes early, and under the
# `set -o pipefail` and `set -e` of _common.sh the assignment then aborts the hook --
# silently dropping exactly the oversized report the byte cap exists to trim.
output="$(head -n "$MAX_REPORT_LINES" "$report")"

# Whether the line trim dropped anything. Tracked because that trim is otherwise
# silent: short lines stay under the byte ceiling below, so a long report of them
# ended mid-findings and read as the complete list.
#
# awk counts records, not the newline bytes `wc -l` counts. A checker whose last line
# carries no trailing newline is one record that `wc -l` does not see, so 201 such
# lines read as 200 and the report was trimmed with no marker.
truncated=no
(($(awk 'END {print NR}' "$report") > MAX_REPORT_LINES)) && truncated=yes

# Then the byte ceiling, in bash's own substring operator rather than `cut`, which
# counts per line and so bounds nothing on a multi-line report. ${var:0:n} counts
# characters, keeping the result valid UTF-8 where a byte count would split one, and
# the quarter allows for the four bytes a character can take.
#
# The marker and the lead are part of the budget, not additions to it. The cap is on
# the whole systemMessage, so trimming the report to the full ceiling and then
# prepending the lead put the emitted message over it again.
truncation_marker='[report truncated; run the checkers directly for the rest]'

# Reported, not enforced: this hook exits 0 either way, and pre-commit and CI are the
# gates.
lead="The type checkers reported findings on the files this turn changed.
Fix the root cause of each; do not silence a checker.
"

# The two newlines that join the lead to the report, counted with everything else.
overhead=$((${#lead} + ${#truncation_marker} + 2))
if (($(printf '%s' "$output" | wc -c) > MAX_REPORT_BYTES - overhead)); then
  output="${output:0:$(((MAX_REPORT_BYTES - overhead) / 4))}"
  truncated=yes
fi
[[ $truncated == yes ]] && output="$output
$truncation_marker"

printf '%s\n%s\n' "$lead" "$output" | hook_emit_system_message
exit 0
