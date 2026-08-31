#!/usr/bin/env bash
# Stop hook. The turn does not end while the type checkers fail.
#
# Suppressions are not this hook's business: the code-honesty auditor reads the
# diff and reports every `# noqa` and `# type: ignore` it adds, which is the same
# question it already answers about comments.
#
# Blocking is `{"decision": "block", "reason": ...}` on stdout. Claude Code sets
# stop_hook_active once it is already continuing because of a Stop hook, and gives
# up after 8 consecutive blocks; this hook checks the flag and stands down, so a
# problem Claude cannot fix costs one extra turn rather than eight.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

# Already continuing from a Stop hook: report nothing and let the turn end.
[[ "$(hook_field '.stop_hook_active // false')" == true ]] && exit 0

cwd="$(hook_field '.cwd // empty')"
[[ -n $cwd ]] || cwd="$PWD"

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# No Python in the repository means no opinion.
[[ -f pyproject.toml ]] || exit 0

# Nothing changed, nothing to check.
git diff --quiet HEAD -- '*.py' '*.pyi' 2>/dev/null \
  && [[ -z "$(git ls-files --others --exclude-standard -- '*.py' '*.pyi' 2>/dev/null)" ]] \
  && exit 0

checker=()
if [[ -x ./run-typecheck.sh ]]; then
  # The repository's own script defines its tools, so it is run as it stands.
  checker=(./run-typecheck.sh)
elif [[ -x "${CLAUDE_PLUGIN_ROOT:-}/bin/run-typecheck.sh" ]]; then
  # The fallback runs mypy and basedpyright out of the target project's
  # environment. A repository that does not have them (whetstone itself declares
  # only ruff) would fail on the missing executables rather than on its code, so
  # the fallback is used only where both resolve. A repository that wants them
  # gated differently ships its own ./run-typecheck.sh.
  if uv run --no-sync python -c 'import mypy, basedpyright' >/dev/null 2>&1; then
    checker=("${CLAUDE_PLUGIN_ROOT}/bin/run-typecheck.sh")
  fi
fi
((${#checker[@]})) || exit 0

# Interleaved into one stream: a checker's complaint is on stdout or stderr
# depending on the tool, and the report needs both.
output=""
status=0
output="$("${checker[@]}" 2>&1)" || status=$?
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
