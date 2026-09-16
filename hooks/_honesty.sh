#!/usr/bin/env bash

# Sourced by prose_honesty.sh and code_prose_honesty.sh, which set HONESTY_NAME,
# HONESTY_BRIEF, HONESTY_GLOBS, and HONESTY_LEAD. Every path out but the last
# exits 0, which delivers nothing to Claude; only the closing exit 2 reports.

honesty_give_up() {
  printf '%s: %s\n' "$HONESTY_NAME" "$1" >&2
  exit 0
}

command -v claude >/dev/null 2>&1 || honesty_give_up 'claude was not found; prose was not checked'

cwd="$(hook_field '.cwd // empty')"
root="$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

brief=""
for candidate in \
  "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/$HONESTY_BRIEF}" \
  "$root/.claude/$HONESTY_BRIEF" \
  "${BASH_SOURCE[0]%/*}/../$HONESTY_BRIEF"; do
  [[ -f $candidate ]] && brief="$candidate" && break
done
[[ -n $brief ]] || exit 0

honesty_select() {
  hook_changed_files "${HONESTY_GLOBS[@]}" | hook_recently_modified 30
  # A script with no extension matches no glob, so admit it on its shebang.
  ((${#HONESTY_SHEBANG_GLOBS[@]})) || return 0
  while IFS= read -r -d '' file; do
    [[ $(head -c 2 -- "$file" 2>/dev/null) == '#!' ]] && printf '%s\0' "$file"
  done < <(hook_changed_files "${HONESTY_SHEBANG_GLOBS[@]}" | hook_recently_modified 30)
}

paths=()
while IFS= read -r -d '' file; do
  paths+=(":(literal)$file")
done < <(honesty_select)
((${#paths[@]})) || exit 0

diff_text="$(hook_changed_diff "${paths[@]}")"

# Scope is what the diff adds, so a diff that only deletes has nothing to audit.
grep -qE '^\+([^+]|$)' <<<"$diff_text" || exit 0

if (($(wc -l <<<"$diff_text") > 4000)); then
  honesty_give_up 'diff over 4000 lines; not audited'
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
  head -c 2000 "$errfile" >&2
  honesty_give_up "the auditor did not run (exit $status); prose was not checked"
fi

report="$(
  jq -r 'if type == "array" then .[-1] else . end
         | if .is_error then error else .result end' <<<"$envelope" 2>/dev/null \
    | sed -e '/^[[:space:]]*```/d' \
    | jq -r '.findings[] | "  \(.file):\(.line)  \(.why)"' 2>/dev/null
)" || honesty_give_up 'the auditor did not answer with findings; prose was not checked'

[[ -n $report ]] || exit 0

# head -c cuts bytes, so the budget is in bytes too; the 4 covers the newlines
# printf adds around the lead and the marker.
marker='  [report truncated; findings above are the first of more]'
budget=$((16384 - ${#HONESTY_LEAD} - ${#marker} - 4))
if (($(wc -c <<<"$report") > budget)); then
  report="$(head -c "$budget" <<<"$report")
$marker"
fi

printf '%s\n\n%s\n' "$HONESTY_LEAD" "$report" | hook_emit_rewake
