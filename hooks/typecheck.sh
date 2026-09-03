#!/usr/bin/env bash
# Stop hook. It reports what the type checkers found and lets the turn end; the
# checkers also run in pre-commit and CI, so nothing here blocks.
# Suppressions are code_prose_honesty.sh's business, not this hook's.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

# How recently a file must have changed to count as this turn's work. The
# working-tree diff alone cannot tell an edit from a branch switch: `git checkout`
# or `git reset` moves HEAD, and every file that differs across the two commits
# then reads as changed, which pointed the checkers at a whole repository nobody
# had touched. A checkout restamps the mtime of every file it rewrites, so the
# window has to be short enough to have closed by the time the turn ends.
#
# The tradeoff this cannot escape: a Stop hook, unlike ruff_format.sh's
# PostToolUse, has no bounded delay from the write, so an edit followed by a long
# test run falls outside the window and goes unreported. Under-reporting is the
# safe direction. The checkers still run in pre-commit and CI, which are the
# gates; over-reporting sent five tools across a whole repository and produced a
# message too large for Claude to receive at all.
STALE_AFTER_SECONDS=30

# Lines of checker output to report. The full run of a large diff reached six
# figures of bytes, past the point where the harness inlines a systemMessage: it
# spilled to a file and Claude saw a truncated head, so the findings it was meant
# to act on never arrived. A bounded report is one that survives intact.
MAX_REPORT_LINES=200

cwd="$(hook_field '.cwd // empty')"
[[ -n $cwd ]] || cwd="$PWD"

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# Cleared as ruff_format.sh clears it: the inherited value belongs to whichever
# project the session started in, and every `uv run` below warns about the mismatch
# when the checked repository is a different one.
unset VIRTUAL_ENV

# No Python in the repository means no opinion.
[[ -f pyproject.toml ]] || exit 0

# The files to check: this turn's writes, not everything that differs from HEAD.
# Restricted to recent writes for the reason STALE_AFTER_SECONDS gives, and kept as
# a list rather than spent as a yes/no gate, because the list is what the checkers
# below are pointed at. Nothing written recently means nothing to check.
#
# Read in a loop rather than with `mapfile -d`, which needs bash 4: macOS ships
# bash 3.2, and this hook runs there.
changed=()
while IFS= read -r -d '' file; do
  changed+=("$file")
done < <(hook_changed_files '*.py' '*.pyi' | hook_recently_modified "$STALE_AFTER_SECONDS")
((${#changed[@]})) || exit 0

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
# The changed files are passed as arguments. Without them the checkers default to the
# repository root, so one edited file put every file in the tree through five tools
# and reported on code this turn never touched -- including, through
# `ruff format --check`, files that are not Python at all.
#
# The checker's status is captured before the output is trimmed, not after. Piping
# straight into head would report head's status, which is 0 even when a checker
# failed, and a pipeline substitution cannot reach the outer PIPESTATUS to recover
# it. So the full output goes to a file, and the trimming reads back from there.
output=""
status=0
report="$(mktemp)" || exit 0
trap 'rm -f "$report"' EXIT
bash "$checker" "${changed[@]}" >"$report" 2>&1 || status=$?
((status != 0)) || exit 0
output="$(head -n "$MAX_REPORT_LINES" "$report")"

# Reported, not enforced: this hook exits 0 either way, and pre-commit and CI are the
# gates. Wording that claimed otherwise described a block that does not happen here.
printf '%s\n' "The type checkers reported findings on the files this turn changed.
Fix the root cause of each; do not silence a checker.

$output" | hook_emit_system_message
exit 0
