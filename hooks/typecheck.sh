#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

STALE_AFTER_SECONDS=30

MAX_REPORT_LINES=200

MAX_REPORT_BYTES=16384

cwd="$(hook_field '.cwd // empty')"
[[ -n $cwd ]] || cwd="$PWD"

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

unset VIRTUAL_ENV

[[ -f pyproject.toml ]] || exit 0

candidates=()
while IFS= read -r -d '' file; do
  candidates+=("$file")
done < <(hook_changed_files '*.py' '*.pyi' | hook_recently_modified "$STALE_AFTER_SECONDS")
((${#candidates[@]})) || exit 0

changed=()
for file in "${candidates[@]}"; do
  changed+=("./$file")
done

checker="./run-typecheck.sh"
if [[ ! -r $checker ]]; then
  checker="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/run-typecheck.sh}"
  if [[ ! -r $checker ]]; then
    here="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)" || exit 0
    checker="$here/../bin/run-typecheck.sh"
  fi
  [[ -r $checker ]] \
    && uv run --no-sync python -c 'import mypy, basedpyright' >/dev/null 2>&1 \
    || exit 0
fi

output=""
status=0
report="$(mktemp)" || exit 0
trap 'rm -f "$report"' EXIT
bash "$checker" "${changed[@]}" >"$report" 2>&1 || status=$?
((status != 0)) || exit 0
output="$(head -n "$MAX_REPORT_LINES" "$report")"

truncated=no
(($(awk 'END {print NR}' "$report") > MAX_REPORT_LINES)) && truncated=yes

truncation_marker='[report truncated; run the checkers directly for the rest]'

lead="The type checkers reported findings on the files the turn that just ended changed.
Fix the root cause of each; do not silence a checker.
Line numbers are from that turn and may have shifted; re-read before editing.
"

overhead=$((${#lead} + ${#truncation_marker} + 3))
if (($(printf '%s' "$output" | wc -c) > MAX_REPORT_BYTES - overhead)); then
  output="${output:0:$(((MAX_REPORT_BYTES - overhead) / 4))}"
  truncated=yes
fi
[[ $truncated == yes ]] && output="$output
$truncation_marker"

printf '%s\n%s\n' "$lead" "$output" | hook_emit_rewake
