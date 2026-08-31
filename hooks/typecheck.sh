#!/usr/bin/env bash
# Stop hook. The turn does not end while the type checkers fail.
#
# Suppressions are not this hook's business: the code-honesty auditor reads the
# diff and reports every `# noqa` and `# type: ignore` it adds, which is the same
# question it already answers about comments.
#
# Blocking is `{"decision": "block", "reason": ...}` on stdout. The checkers
# failing is not a matter of opinion, so this reports it again on every stop for
# as long as it is true: there is no way out but to fix the code. Claude Code
# ends the turn itself after 8 consecutive blocks, which is the only ceiling
# here, and it is the harness's, not this hook's.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

cwd="$(hook_field '.cwd // empty')"
[[ -n $cwd ]] || cwd="$PWD"

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# No Python in the repository means no opinion.
[[ -f pyproject.toml ]] || exit 0

# Before the first commit there is no HEAD to diff against. The empty tree stands
# in for the absent commit, so the check below reports whether anything changed
# instead of that the command failed.
base=HEAD
git rev-parse --verify -q HEAD >/dev/null \
  || base="$(git hash-object -t tree /dev/null)"

# Nothing changed, nothing to check.
git diff --quiet "$base" -- '*.py' '*.pyi' 2>/dev/null \
  && [[ -z "$(git ls-files --others --exclude-standard -- '*.py' '*.pyi' 2>/dev/null)" ]] \
  && exit 0

# A repository's own script overrides the one shipped here, which is how it
# chooses different tools or flags. Readable rather than executable, and run
# through bash below: copier writes the template's copy without the executable
# bit, and a generated project has no other checker.
checker="./run-typecheck.sh"
if [[ ! -r $checker ]]; then
  # The plugin sets CLAUDE_PLUGIN_ROOT; a Stop hook configured in settings.json does
  # not, so fall back to this script's own directory. `pwd -P` resolves the
  # ~/.agents/hooks symlink to the checkout, which is what puts bin/ one level up.
  # Guarded with :+ because unset, "$var/bin/run-typecheck.sh" is the absolute path
  # /bin/run-typecheck.sh, which is not this repository's script.
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

# A missing virtualenv or uvx is the machine's problem, not the code's, so it is
# reported without blocking.
if [[ $output == *"Run: uv sync"* || $output == *"uvx not found"* ]]; then
  printf '%s\n' "$output" >&2
  exit 0
fi

reason="The type checkers failed. The work is not done until they pass.
Fix the root cause of every finding; do not silence a checker.

$output"

jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
exit 0
