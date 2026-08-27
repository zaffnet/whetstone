#!/usr/bin/env bash
# Suggests one git branch name for the current working-tree changes with Codex.
# Prints the name; create the branch yourself (`git switch -c "$(suggest-branch-name.sh)"`).
#
# Environment:
#   GIT_BRANCH_PREFIX  Prefix for the name, with trailing slash (default: the
#                      GitHub login from `gh api user`, else the git user name,
#                      lower-cased with spaces as hyphens).
#   CODEX_MODEL        Overrides ~/.codex/config.toml's `model` (fallback: gpt-5.5).
#   CODEX_BASE_URL     Overrides ~/.codex/config.toml's `openai_base_url`, then OPENAI_BASE_URL;
#                      OPENAI_API_KEY is the credential.
set -euo pipefail

# The library is symlinked into ~/.local/bin too, so it sits beside this script whichever
# path reached it. No symlink resolution, which is where the first attempt went wrong.
# shellcheck source-path=SCRIPTDIR source=_codex-config.sh
source "${BASH_SOURCE[0]%/*}/_codex-config.sh"

CODEX_MODEL=$(codex_model)
EFFORT="medium"
readonly CODEX_MODEL EFFORT

require_command() {
  local command_name=$1

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf "Required command '%s' was not found.\n" "$command_name" >&2
    exit 127
  fi
}

require_command git
require_command jq
require_command codex

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

# jq builds the schema so the prefix is escaped once for the regex (inside jq) and
# once for JSON (by jq's encoder). Escaping by hand mixed the two: a prefix such as
# "j.smith/" produced "\." and "\/", which JSON rejects.
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

PROVIDER_ARGS=()
CODEX_BASE_URL=$(codex_base_url)
if [[ -n "$CODEX_BASE_URL" ]]; then
  PROVIDER_ARGS=(
    --config 'model_provider="proxy"'
    --config "model_providers.proxy={name=\"Proxy\",base_url=\"$CODEX_BASE_URL\",env_key=\"OPENAI_API_KEY\",wire_api=\"responses\",supports_websockets=false}"
  )
fi

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

git diff HEAD:
$(git diff HEAD)
PROMPT
)
readonly PROMPT

TEMP_DIR=$(mktemp -d)
readonly TEMP_DIR
SCHEMA_FILE="$TEMP_DIR/schema.json"
PROMPT_FILE="$TEMP_DIR/prompt.txt"
RESULT_FILE="$TEMP_DIR/result.json"
printf '%s\n' "$SCHEMA" >"$SCHEMA_FILE"
# The prompt embeds the whole diff; on stdin it has no argv size limit.
printf '%s\n' "$PROMPT" >"$PROMPT_FILE"

cleanup() {
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

if ! codex exec \
  --ephemeral \
  --ignore-user-config \
  --skip-git-repo-check \
  --disable hooks \
  --disable plugins \
  --cd "$TEMP_DIR" \
  --sandbox read-only \
  --model "$CODEX_MODEL" \
  --config "model_reasoning_effort=\"$EFFORT\"" \
  ${PROVIDER_ARGS[@]+"${PROVIDER_ARGS[@]}"} \
  --output-schema "$SCHEMA_FILE" \
  --output-last-message "$RESULT_FILE" \
  - >/dev/null 2>"$TEMP_DIR/codex.stderr" <"$PROMPT_FILE"; then
  cat "$TEMP_DIR/codex.stderr" >&2
  exit 1
fi

jq -er '.branch_name | select(type == "string" and length > 0)' "$RESULT_FILE"
