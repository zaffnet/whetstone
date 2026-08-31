#!/usr/bin/env bash
# Stop hook. Reports comments and docstrings in this session's diff that record
# the session instead of the code, and blocks the turn until they are rewritten.
#
# It never edits a file. Claude makes the edit, so it lands in the diff, in view,
# with the tests still to run -- a hook that rewrote the source after the work was
# reported done would change code nobody reviewed.
#
# Scope is the lines the working-tree diff adds, so a comment that was already
# committed is not reported when an unrelated line of the same file changes.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

# Already continuing from a Stop hook: report nothing and let the turn end.
[[ "$(hook_field '.stop_hook_active // false')" == true ]] && exit 0

cwd="$(hook_field '.cwd // empty')"
[[ -n $cwd ]] || cwd="$PWD"

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# The plugin copy when the plugin is installed, the project's own copy in a
# generated project, where CLAUDE_PLUGIN_ROOT is unset.
for candidate in \
  "${CLAUDE_PLUGIN_ROOT:-}/tools/audit-comments.py" \
  "$root/tools/audit-comments.py" \
  "${BASH_SOURCE[0]%/*}/../../tools/audit-comments.py"; do
  [[ -f $candidate ]] && auditor="$candidate" && break
done
[[ -n ${auditor:-} ]] || exit 0

# The added lines (^+) of the working-tree diff, as FILE:LINE,LINE for the
# auditor, so a comment that was already committed is not reported when an
# unrelated line of the same file changes. Untracked files have no diff, so they
# are read whole through --no-index against /dev/null, which exits non-zero
# whenever it prints anything; `|| true` keeps that from ending the hook.
#
# NUL-delimited file lists throughout, read with `while read -d` rather than
# `mapfile -d`: macOS ships bash 3.2, where mapfile has no -d.
targets="$(
  {
    git diff HEAD -U0 --diff-filter=d -- '*.py' '*.pyi' 2>/dev/null || true
    while IFS= read -r -d '' f; do
      git diff --no-index -U0 -- /dev/null "$f" 2>/dev/null || true
    done < <(git ls-files -z --others --exclude-standard -- '*.py' '*.pyi' 2>/dev/null)
  } | awk '
    /^\+\+\+ / {
      file = substr($0, 7)
      sub(/^b\//, "", file)
      # `git diff --no-index` pads the path with a tab, which would otherwise
      # become part of the filename.
      sub(/[ \t]+$/, "", file)
      next
    }
    /^@@/ {
      match($0, /\+[0-9]+/)
      line = substr($0, RSTART + 1, RLENGTH - 1) + 0
      next
    }
    /^\+/ {
      if (file != "") added[file] = (file in added ? added[file] "," line : line)
      line++
    }
    END { for (f in added) printf "%s:%s\n", f, added[f] }
  '
)"
[[ -n $targets ]] || exit 0

# A path is kept only if it is still a regular file, since a file can be deleted
# or replaced by a broken symlink between the diff and this read.
errfile="$(mktemp)"
trap 'rm -f "$errfile"' EXIT

present=()
while IFS= read -r target; do
  [[ -f ${target%%:*} ]] && present+=("$target")
done <<<"$targets"
((${#present[@]})) || exit 0

# Exit 0 is clean, 1 is findings, anything else is the auditor failing to run.
# A failure is reported on stderr and does not block: a broken checker must not
# hold a turn hostage. It must not pass silently either, which is what
# discarding stderr and treating an empty report as clean used to do.
# Declared first, then assigned: `set -e` would abort on the assignment's own
# nonzero status before it could be read, and exit 1 is the reporting case.
report=""
status=0
report="$(python3 "$auditor" "${present[@]}" 2>"$errfile")" || status=$?
case "$status" in
  0) exit 0 ;;
  1) ;;
  *)
    {
      printf 'audit_comments: the auditor failed (exit %s); comments were not checked\n' "$status"
      cat "$errfile"
    } >&2
    exit 0
    ;;
esac
[[ -n $report ]] || exit 0

reason="These comments record the session that wrote them rather than the code.
Rewrite each to state what the code cannot -- why a constraint exists, which
bug a workaround answers, what a caller must hold -- or delete it. A comment
that states a reason is never reported here, so adding one is a real fix and
deleting the comment is the other.

Docstrings stay: shrink them, do not remove them, or pre-commit will fail on a
public interface with none.
"
jq -n --arg reason "$reason$report" '{decision: "block", reason: $reason}'
exit 0
