#!/usr/bin/env bash
# Shared body for the two Stop hooks that ask a headless Claude whether the prose in
# this turn's diff is honest: code_prose_honesty.sh for comments, docstrings, and
# checker suppressions, prose_honesty.sh for markdown and text files.
#
# A caller sets four variables and sources this file after _common.sh:
#
#   HONESTY_NAME    this hook's name, for the diagnostics it prints
#   HONESTY_BRIEF   basename of the markdown brief, resolved against the plugin root,
#                   the project's .claude, and this directory's siblings
#   HONESTY_LEAD    the instruction printed above the findings
#   HONESTY_GLOBS   array of pathspecs the diff is limited to
#
# Neither hook edits a file: they report, and Claude makes the edit.
# Nothing here blocks. A checker that cannot run must not hold a turn, but must not
# pass as a clean audit either, so every failure path says so and exits 0.

# How recently a file must have changed to count as this turn's work, matching the
# typecheck hook. Short because a checkout restamps the mtime of what it rewrites, so
# the window must have closed by the time the turn ends.
HONESTY_STALE_AFTER_SECONDS=30

# Diagnostics go to stderr, which reaches the debug log and not Claude. That is the
# right place for "the auditor could not run": it is not a finding about the code.
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

# Guarded with :+ because unset, the first entry would be an absolute path rooted at
# /. An empty candidate falls through to the next.
for candidate in \
  "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/$HONESTY_BRIEF}" \
  "$root/.claude/$HONESTY_BRIEF" \
  "${BASH_SOURCE[0]%/*}/../$HONESTY_BRIEF"; do
  [[ -f $candidate ]] && brief="$candidate" && break
done
[[ -n ${brief:-} ]] || exit 0

# Narrowed to this turn's writes before the diff is built, not after. The
# working-tree diff against HEAD cannot tell an edit from a `git checkout` or
# `git reset`: those move HEAD, and every file differing across the two commits
# reads as changed, which would send a whole repository's comments to the auditor
# or overrun the line limit below and skip the audit altogether.
# :(literal), because these are filenames going back to git as pathspecs: a name
# holding pathspec metacharacters is otherwise read as a pattern, and `a[1].py`
# then matches `a1.py` as well.
recent=()
while IFS= read -r -d '' file; do
  recent+=(":(literal)$file")
done < <(hook_changed_files "${HONESTY_GLOBS[@]}" | hook_recently_modified "$HONESTY_STALE_AFTER_SECONDS")
((${#recent[@]})) || exit 0

diff_text="$(hook_changed_diff "${recent[@]}")"
[[ -n $diff_text ]] || exit 0

# A rewrite this large is reviewed by a person rather than by this.
if (($(wc -l <<<"$diff_text") > 4000)); then
  honesty_note 'diff over 4000 lines; not audited'
  exit 0
fi

# --setting-sources "" and --strict-mcp-config keep this machine's settings, MCP
# servers, and CLAUDE.md out of the subprocess: none of them bear on the question, and
# loading them costs.
# --tools "" with --max-turns 1: the diff is on stdin, so the answer is one message.
# With any tool enabled the model can spend the single turn on it and return nothing.
# --allowed-tools "" is not a substitute -- it grants the full set.
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

# --output-format json returns the event stream as an array, the result last. Guarded
# because a zero-exit claude can still leave unparseable stdout behind, and set -e
# would otherwise end the hook on the failing jq, without the message below.
result="$(jq -c 'if type == "array" then .[-1] else . end' <<<"$envelope" 2>/dev/null)" || result=""

if [[ -z $result ]]; then
  honesty_note "the auditor's output did not parse; prose was not checked"
  exit 0
fi

# The envelope reports its own failures in is_error, with the text in result.
if [[ "$(jq -r '.is_error // false' <<<"$result" 2>/dev/null)" != false ]]; then
  honesty_note 'the auditor reported an error; prose was not checked'
  jq -r '.result // empty' <<<"$result" 2>/dev/null | head -c 2000 >&2
  exit 0
fi

# Anything but a findings array -- prose, or JSON of another shape -- is a failure to
# follow the format, not a clean audit. Fenced output is tolerated. The type is checked
# because `length` is defined on objects and strings too: {"findings": {}} would
# otherwise read as nothing to report.
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

printf '%s\n\n%s\n' "$HONESTY_LEAD" "$report" | hook_emit_system_message
exit 0
