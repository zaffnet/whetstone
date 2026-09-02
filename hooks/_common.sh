#!/usr/bin/env bash
# Shared preamble for the hook scripts in this directory:
#
#   source "${BASH_SOURCE[0]%/*}/_common.sh"
#
# Enables strict mode and consumes stdin: the JSON hook payload is read once into
# HOOK_INPUT, and hook_field reads fields from there rather than from stdin again.
set -euo pipefail

HOOK_INPUT="$(cat)"

# Takes the full jq filter including any fallback, e.g.
# hook_field '.session_id // "nosession"' (string fallback) or
# hook_field '.tool_name // empty' (jq's empty keyword, prints nothing).
hook_field() {
  printf '%s' "$HOOK_INPUT" | jq -r "$1"
}

# Findings on stdout as JSON, which is the only channel Claude reads: stderr from a
# hook that exits 0 reaches the debug log and nothing else. Text on stdin, event name
# in $1. jq -Rs does the escaping, so a finding may contain quotes and newlines.
hook_emit_system_message() {
  jq -Rs --arg event "$1" \
    '{hookSpecificOutput: {hookEventName: $event, systemMessage: .}}'
}

# NUL-separated paths of the files this turn changed, tracked and untracked, matching
# the pathspecs in "$@". Run from inside the repository.
hook_changed_files() {
  # Before the first commit there is no HEAD to diff against, and staged files are not
  # untracked either, so that state would reach neither command below. The empty tree
  # stands in for the absent commit.
  local base=HEAD
  git rev-parse --verify -q HEAD >/dev/null \
    || base="$(git hash-object -t tree /dev/null)"

  {
    git diff -z --name-only --diff-filter=d "$base" -- "$@" 2>/dev/null || true
    git ls-files -z --others --exclude-standard -- "$@" 2>/dev/null || true
  } | sort -zu
}

# One patch covering this turn's changes to the pathspecs in "$@", tracked and
# untracked. --no-color and no pager so a model reads the diff and not terminal
# escapes. Untracked files have no diff, so they go through --no-index against
# /dev/null, which exits non-zero whenever it prints anything -- hence the `|| true`.
hook_changed_diff() {
  local base=HEAD f
  git rev-parse --verify -q HEAD >/dev/null \
    || base="$(git hash-object -t tree /dev/null)"

  git --no-pager diff "$base" --no-color -U3 --diff-filter=d -- "$@" 2>/dev/null || true
  while IFS= read -r -d '' f; do
    git --no-pager diff --no-index --no-color -U3 -- /dev/null "$f" 2>/dev/null || true
  done < <(git ls-files -z --others --exclude-standard -- "$@" 2>/dev/null)
}

# Strips YAML frontmatter so a brief written as an agent or skill markdown file can be
# passed as a system prompt. awk, not sed: the BSD sed on macOS rejects the address
# form this needs.
hook_strip_frontmatter() {
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { in_fm = 0; next }
    !in_fm { print }
  ' "$1"
}
