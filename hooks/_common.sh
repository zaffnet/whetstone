#!/usr/bin/env bash
set -euo pipefail

HOOK_INPUT="$(cat)"

hook_field() {
  printf '%s' "$HOOK_INPUT" | jq -r "$1"
}

# systemMessage must be top level: nested under hookSpecificOutput it is silently
# discarded and nothing reaches Claude.
hook_emit_system_message() {
  jq -Rs '{systemMessage: .}'
}

hook_emit_rewake() {
  cat >&2
  exit 2
}

hook_changed_files() {
  local base=HEAD
  git rev-parse --verify -q HEAD >/dev/null \
    || base="$(git hash-object -t tree /dev/null)"

  {
    git diff -z --name-only --diff-filter=d "$base" -- "$@" 2>/dev/null || true
    git ls-files -z --others --exclude-standard -- "$@" 2>/dev/null || true
  } | sort -zu
}

hook_recently_modified() {
  local within=$1 reference path
  reference="$(mktemp)" || return 0
  perl -e 'utime(time() - $ARGV[0], time() - $ARGV[0], $ARGV[1]) or exit 1' \
    "$within" "$reference" 2>/dev/null || {
    rm -f "$reference"
    return 0
  }

  while IFS= read -r -d '' path; do
    [[ $path -nt $reference ]] && printf '%s\0' "$path"
  done
  rm -f "$reference"
}

hook_changed_diff() {
  local base=HEAD f
  git rev-parse --verify -q HEAD >/dev/null \
    || base="$(git hash-object -t tree /dev/null)"

  git --no-pager diff "$base" --no-color -U3 --diff-filter=d -- "$@" 2>/dev/null || true
  while IFS= read -r -d '' f; do
    git --no-pager diff --no-index --no-color -U3 -- /dev/null "$f" 2>/dev/null || true
  done < <(git ls-files -z --others --exclude-standard -- "$@" 2>/dev/null)
}

hook_strip_frontmatter() {
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { in_fm = 0; next }
    !in_fm { print }
  ' "$1"
}
