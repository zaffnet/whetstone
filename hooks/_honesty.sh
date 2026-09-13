#!/usr/bin/env bash

HONESTY_STALE_AFTER_SECONDS=30

HONESTY_MAX_REPORT_BYTES=16384

HONESTY_MIN_ADDED_LINES=1

honesty_note() {
  printf '%s: %s\n' "$HONESTY_NAME" "$1" >&2
}

if ! command -v claude >/dev/null 2>&1; then
  honesty_note 'claude was not found; prose was not checked'
  exit 0
fi

cwd="$(hook_field '.cwd // empty')"
[[ -n $cwd ]] || cwd="$PWD"

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

for candidate in \
  "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/$HONESTY_BRIEF}" \
  "$root/.claude/$HONESTY_BRIEF" \
  "${BASH_SOURCE[0]%/*}/../$HONESTY_BRIEF"; do
  [[ -f $candidate ]] && brief="$candidate" && break
done
[[ -n ${brief:-} ]] || exit 0

recent=()
while IFS= read -r -d '' file; do
  recent+=(":(literal)$file")
done < <(hook_changed_files "${HONESTY_GLOBS[@]}" | hook_recently_modified "$HONESTY_STALE_AFTER_SECONDS")

if [[ -n ${HONESTY_SHEBANG_GLOBS+x} ]] && ((${#HONESTY_SHEBANG_GLOBS[@]})); then
  while IFS= read -r -d '' file; do
    [[ -f $file && $(head -c 2 -- "$file" 2>/dev/null) == '#!' ]] || continue
    recent+=(":(literal)$file")
  done < <(hook_changed_files "${HONESTY_SHEBANG_GLOBS[@]}" | hook_recently_modified "$HONESTY_STALE_AFTER_SECONDS")
fi
((${#recent[@]})) || exit 0

diff_text="$(hook_changed_diff "${recent[@]}")"
[[ -n $diff_text ]] || exit 0

if (($(wc -l <<<"$diff_text") > 4000)); then
  honesty_note 'diff over 4000 lines; not audited'
  exit 0
fi

added="$(
  awk '
    /^@@/ { in_hunk = 1; next }
    /^diff --git / { in_hunk = 0 }
    in_hunk && /^\+/ { n++ }
    END { print n + 0 }
  ' <<<"$diff_text"
)"
if ((added < HONESTY_MIN_ADDED_LINES)); then
  exit 0
fi

errfile="$(mktemp)"
trap 'rm -f "$errfile"' EXIT

status=0
envelope="$(
  printf 'Audit this diff and reply with the JSON described in your instructions.\n\n%s\n' "$diff_text" \
    | claude -p \
      --model sonnet \
      --output-format json \
      --max-turns 1 \
      --strict-mcp-config \
      --setting-sources "" \
      --tools "" \
      --append-system-prompt "$(hook_strip_frontmatter "$brief")" \
      2>"$errfile"
)" || status=$?

if ((status != 0)); then
  honesty_note "the auditor did not run (exit $status); prose was not checked"
  head -c 2000 "$errfile" >&2
  exit 0
fi

result="$(jq -c 'if type == "array" then .[-1] else . end' <<<"$envelope" 2>/dev/null)" || result=""

if [[ -z $result ]]; then
  honesty_note "the auditor's output did not parse; prose was not checked"
  exit 0
fi

if [[ "$(jq -r '.is_error // false' <<<"$result" 2>/dev/null)" != false ]]; then
  honesty_note 'the auditor reported an error; prose was not checked'
  jq -r '.result // empty' <<<"$result" 2>/dev/null | head -c 2000 >&2
  exit 0
fi

findings="$(
  jq -r '.result // empty' <<<"$result" \
    | sed -e '/^[[:space:]]*```/d' \
    | jq -c 'if (.findings | type) == "array" then .findings else empty end' 2>/dev/null
)" || findings=""

if [[ -z $findings ]]; then
  honesty_note 'the auditor did not answer with a findings array; prose was not checked'
  exit 0
fi

count="$(jq -r 'length' <<<"$findings")"
((count > 0)) || exit 0

report="$(jq -r '.[] | "  \(.file):\(.line)  \(.why)"' <<<"$findings")"

honesty_truncation_marker='  [report truncated; findings above are the first of more]'

honesty_overhead=$((${#HONESTY_LEAD} + ${#honesty_truncation_marker} + 3))
if (($(printf '%s' "$report" | wc -c) > HONESTY_MAX_REPORT_BYTES - honesty_overhead)); then
  report="${report:0:$(((HONESTY_MAX_REPORT_BYTES - honesty_overhead) / 4))}
$honesty_truncation_marker"
fi

printf '%s\n\n%s\n' "$HONESTY_LEAD" "$report" | hook_emit_rewake
