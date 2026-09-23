#!/usr/bin/env bash
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_claude-config.sh
source "${BASH_SOURCE[0]%/*}/_claude-config.sh"

CLAUDE_MODEL=$(claude_model)
EFFORT="medium"
readonly CLAUDE_MODEL EFFORT

require_command git
require_command jq
require_command claude

if [[ -z "$(git status --porcelain)" ]]; then
  printf '%s\n' 'No changes to name a branch from.' >&2
  exit 1
fi

resolve_prefix() {
  local prefix="${GIT_BRANCH_PREFIX:-}"
  if [[ -z $prefix ]] && command -v gh >/dev/null 2>&1; then
    prefix="$(gh api user --jq .login 2>/dev/null || true)"
    [[ -z $prefix ]] || prefix="$prefix/"
  fi
  if [[ -z $prefix ]]; then
    prefix="$(git config user.name 2>/dev/null | tr '[:upper:] ' '[:lower:]-')"
    if [[ -z $prefix ]]; then
      printf '%s\n' 'Set GIT_BRANCH_PREFIX, sign in to gh, or set git user.name.' >&2
      exit 1
    fi
    prefix="$prefix/"
  fi
  printf '%s' "$prefix"
}

PREFIX="$(resolve_prefix)"
readonly PREFIX

SCHEMA="$(
  jq -n --arg prefix "$PREFIX" --argjson min "$((${#PREFIX} + 2))" '
    ($prefix | gsub("(?<c>[\\\\^$.|?*+()\\[\\]{}/])"; "\\" + .c)) as $escaped
    | {
        type: "object",
        properties: {
          branch_name: {
            type: "string",
            minLength: $min,
            maxLength: 60,
            pattern: ("^" + $escaped + "[a-z0-9]([a-z0-9-]*[a-z0-9])?$"),
            description: ("A git branch name starting with " + $prefix)
          }
        },
        required: ["branch_name"],
        additionalProperties: false
      }'
)"
readonly SCHEMA

DIFF="$(prompt_bound_diff "$(git diff HEAD)")"
readonly DIFF

PROMPT=$(
  cat <<PROMPT
Suggest one git branch name for these working-tree changes. Do not run
commands. Return only the structured output.

Ignore suggest-branch-name.sh unless it is the only change.

Names look like ${PREFIX}client-retries, ${PREFIX}ci-cache, ${PREFIX}search-model.
Prefer a concrete component from the changed paths plus a short change word.
Do not use a conventional-commit type or filler words: tool, helper, util,
script, update, changes, wip.

git status -sb:
$(git status -sb)

git diff --stat HEAD:
$(git diff --stat HEAD)

git diff HEAD:
$DIFF
PROMPT
)
readonly PROMPT

TEMP_DIR=$(mktemp -d)
readonly TEMP_DIR
SCHEMA_FILE="$TEMP_DIR/schema.json"
PROMPT_FILE="$TEMP_DIR/prompt.txt"
RESULT_FILE="$TEMP_DIR/result.json"
printf '%s\n' "$SCHEMA" >"$SCHEMA_FILE"
printf '%s\n' "$PROMPT" >"$PROMPT_FILE"

trap cleanup EXIT

if ! claude_structured_output "$SCHEMA_FILE" "$PROMPT_FILE" "$RESULT_FILE" "$EFFORT"; then
  exit 1
fi

jq -er '.branch_name | select(type == "string" and length > 0)' "$RESULT_FILE"
