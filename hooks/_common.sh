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

# Findings on stdout as JSON, for a hook the harness waits for. Text on stdin.
# A backgrounded hook reaches Claude through hook_emit_rewake below instead.
#
# systemMessage is top level, not under hookSpecificOutput, which holds a
# per-event decision instead. Nested, it is silently discarded and nothing reaches
# Claude. jq -Rs does the escaping, so a finding may contain quotes and newlines.
hook_emit_system_message() {
  jq -Rs '{systemMessage: .}'
}

# Findings from a hook configured with "asyncRewake": true, which the harness runs in
# the background and stops waiting for. Text on stdin; this function ends the script.
#
# Two details of that path decide the shape of this function, both read from the
# CLI at 2.1.261:
#
# Exit 2 is the only code that delivers anything. The harness builds the message
# from the completed process only under `if (code === 2)`; exit 0 drops the registry
# entry and Claude is told nothing. That is what keeps every failure path in these
# hooks on `exit 0` -- a checker that could not run stays in the debug log, and does
# not read as a clean audit either.
#
# The text comes from stderr, falling back to stdout, and reaches Claude as plain
# text: the harness does not parse systemMessage on this path. Stdout would also
# arrive, but it is where the harness scans for a leading `{` to detect an async
# marker, so a bare report there is matched against JSON first and delivered by a
# fallback. Stderr has no such branch.
#
# Exit 2 from a hook the harness *is* waiting for means "refuse to let the turn
# end". So a caller of this function must be configured with asyncRewake; dropping
# that field turns these reports into blocked turns.
hook_emit_rewake() {
  cat >&2
  exit 2
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

# NUL-separated subset of the NUL-separated paths on stdin that were modified within
# the last $1 seconds. A file the tool that just finished wrote is necessarily fresh,
# so this is what separates its writes from work the user already had in progress.
#
# perl's utime and bash's -nt, because `find -newermt` rejects a relative time on BSD
# and `stat` spells the mtime differently on BSD and GNU.
hook_recently_modified() {
  local within=$1 reference path
  reference="$(mktemp)" || return 0
  perl -e 'utime(time() - $ARGV[0], time() - $ARGV[0], $ARGV[1]) or exit 1' \
    "$within" "$reference" 2>/dev/null || {
    # Without a reference there is no way to tell fresh from stale. Emitting nothing
    # skips formatting, which is the safe direction: the alternative rewrites files
    # this tool never touched.
    rm -f "$reference"
    return 0
  }

  while IFS= read -r -d '' path; do
    [[ $path -nt $reference ]] && printf '%s\0' "$path"
  done
  rm -f "$reference"
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
