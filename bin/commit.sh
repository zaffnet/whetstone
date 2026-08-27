#!/usr/bin/env bash
# Generates a Conventional Commits message for the staged changes with Codex,
# shows it, and commits after confirmation.
#
# Codex runs in an empty temp directory with every tool disabled; it sees only
# the prompt (git status, recent log, staged diff) and returns structured JSON.
#
# Usage: commit.sh [-y|--yes]
#
# The model and the proxy come from ~/.codex/config.toml (see bin/_codex-config.sh), so this
# agrees with interactive Codex by construction.
#
# Environment:
#   CODEX_MODEL      Overrides the config's `model` (fallback: gpt-5.5).
#   CODEX_BASE_URL   Overrides the config's `openai_base_url`, then OPENAI_BASE_URL. When set,
#                    requests go through it with OPENAI_API_KEY. Unset = OpenAI direct.
#   COMMIT_SIGN      Set to 1 to force `git commit -S`. Otherwise the commit is
#                    signed only when `git config commit.gpgsign` is true.
#
# The generated message is saved to $GIT_DIR/COMMIT_MESSAGE.md for reference.
set -euo pipefail

# The library is symlinked into ~/.local/bin too, so it sits beside this script whichever
# path reached it. No symlink resolution, which is where the first attempt went wrong.
# shellcheck source-path=SCRIPTDIR source=_codex-config.sh
source "${BASH_SOURCE[0]%/*}/_codex-config.sh"

CODEX_MODEL=$(codex_model)
ASSUME_YES=false
readonly CODEX_MODEL

usage() {
  printf 'Usage: %s [-y|--yes]\n' "${0##*/}"
}

usage_error() {
  printf '%s\n' "$1" >&2
  usage >&2
  exit 2
}

require_command() {
  local command_name=$1

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf "Required command '%s' was not found.\n" "$command_name" >&2
    exit 127
  fi
}

confirm_commit() {
  local answer

  if [[ $ASSUME_YES == true ]]; then
    return
  fi

  if ! read -r -p 'Proceed? (Y/n) ' answer; then
    printf '\n%s\n' 'Aborted.'
    exit 0
  fi

  case "$answer" in
    '' | [Yy] | [Yy][Ee][Ss]) ;;
    *)
      printf '%s\n' 'Aborted.'
      exit 0
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y | --yes)
      ASSUME_YES=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      [[ $# -eq 0 ]] || usage_error "Unexpected argument: $1"
      ;;
    *)
      usage_error "Unexpected argument: $1"
      ;;
  esac
done
readonly ASSUME_YES

require_command git
require_command jq
require_command codex

set +e
git diff --cached --quiet
staged_diff_status=$?
set -e
case "$staged_diff_status" in
  0)
    printf '%s\n' 'No staged changes to commit.' >&2
    exit 1
    ;;
  1) ;;
  *)
    printf 'Unable to inspect staged changes (git exited with status %s).\n' \
      "$staged_diff_status" >&2
    exit "$staged_diff_status"
    ;;
esac

# Optional OpenAI-compatible proxy. Empty array means Codex uses its default provider.
PROVIDER_ARGS=()
CODEX_BASE_URL=$(codex_base_url)
if [[ -n "$CODEX_BASE_URL" ]]; then
  PROVIDER_ARGS=(
    --config 'model_provider="proxy"'
    --config "model_providers.proxy={name=\"Proxy\",base_url=\"$CODEX_BASE_URL\",env_key=\"OPENAI_API_KEY\",wire_api=\"responses\",supports_websockets=false}"
  )
fi

TEMP_DIR=$(mktemp -d)
readonly TEMP_DIR
SCHEMA_FILE="$TEMP_DIR/schema.json"
RESULT_FILE="$TEMP_DIR/result.json"
PROMPT_FILE="$TEMP_DIR/prompt.txt"

cleanup() {
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

cat <<'JSON' >"$SCHEMA_FILE"
{
  "type": "object",
  "properties": {
    "message": {
      "type": "string",
      "minLength": 1,
      "description": "A complete Conventional Commits message under 100 words."
    }
  },
  "required": ["message"],
  "additionalProperties": false
}
JSON

{
  cat <<'PROMPT'
Write one commit message for the staged changes only. Do not run
commands. Return only the structured output.

Match the commit-message style in git log.

Use this format:

<type>[optional scope][optional !]: <subject>

[body]

[optional footer]

Requirements:
- Use exactly one of these lowercase types: build, chore, ci, docs, feat, fix,
  perf, refactor, revert, style, test.
- A scope is optional. When present, it must be nonempty and enclosed in
  parentheses, as in "feat(api_client): add client test".
- Use "!" immediately before the colon only for a breaking change.
- Put one space after the colon. Do not add leading or trailing whitespace to
  the first line.
- Write a nonempty subject in imperative mood: "add", "fix", or "remove", not
  "added", "fixes", or "removed".
- Start the subject with a lowercase word. Do not use Sentence case, Title Case,
  PascalCase, or ALL CAPS. Preserve necessary acronyms and code identifiers.
- Do not end the subject with a full stop.
- Keep the entire first line, including type and scope, at 72 characters or
  fewer.
- Keep the complete message under 100 words.
- Keep every body and footer line at 100 characters or fewer.
- Include a body when the staged diff is more than a small, self-explanatory
  edit. Explain the main changes without repeating the subject. When present, separate
  it from the first line with one empty line.
- The footer is optional. When present, make it one line and separate it from
  the body with one empty line. If there is no body, separate it from the first
  line with one empty line.
- Do not invent a body, footer, issue number, or breaking change when the staged
  changes do not support one.
- Markdown is allowed in the body and footer, but not in the first line.

Framing (commit message is a durable record of what changed and why):
- Lead with what changed and why. Do not say the work "aligns with", "catches
  up to", or "reflects" already-written code.
- Name the component in the subject so someone scanning git log for a later
  regression can tell whether this commit is relevant. Prefer
  "docs(api_client): replace protocols with bases" over "docs: revise client".
- If the staged files are a design doc, describe the design decision. Design
  is decided, written down, then implemented. Do not frame a design-doc commit
  as documentation matching code that already landed.
- Do not put point-in-time review claims in the message ("I checked every
  caller", "tests passed" unless the staged diff is the test change itself).
  Those belong in a pull request description, not in git history.

git status -sb:
PROMPT
  git status -sb
  printf '\n\ngit log --oneline -n 10:\n'
  git log --oneline -n 10
  printf '\n\ngit diff --cached --stat:\n'
  git diff --cached --stat
  printf '\n\ngit diff --cached -W:\n'
  git diff --cached -W
} >"$PROMPT_FILE"

if ! codex exec \
  --ephemeral \
  --ignore-user-config \
  --ignore-rules \
  --skip-git-repo-check \
  --disable hooks \
  --disable plugins \
  --disable memories \
  --disable skill_search \
  --disable multi_agent \
  --disable browser_use \
  --disable computer_use \
  --config 'web_search="disabled"' \
  --disable image_generation \
  --disable tool_suggest \
  --disable workspace_dependencies \
  --disable shell_tool \
  --disable unified_exec \
  --cd "$TEMP_DIR" \
  --sandbox read-only \
  --model "$CODEX_MODEL" \
  --config 'model_reasoning_effort="high"' \
  --config 'model_reasoning_summary="none"' \
  --config 'model_verbosity="low"' \
  --config 'service_tier="fast"' \
  ${PROVIDER_ARGS[@]+"${PROVIDER_ARGS[@]}"} \
  --output-schema "$SCHEMA_FILE" \
  --output-last-message "$RESULT_FILE" \
  - >/dev/null 2>"$TEMP_DIR/codex.stderr" <"$PROMPT_FILE"; then
  cat "$TEMP_DIR/codex.stderr" >&2
  exit 1
fi

COMMIT_MESSAGE=$(jq -er '.message | select(type == "string" and length > 0)' "$RESULT_FILE")
# Strip a fence around the whole message; fences inside the body are content.
COMMIT_MESSAGE=$(printf '%s\n' "$COMMIT_MESSAGE" | sed -E '1{/^[[:space:]]*```/d;}' | sed -E '${/^[[:space:]]*```[[:space:]]*$/d;}')

printf '%s\n' "$COMMIT_MESSAGE" >"$(git rev-parse --git-dir)/COMMIT_MESSAGE.md"

printf '%s\n%s\n' 'Commit Message:' "$COMMIT_MESSAGE"

confirm_commit

SIGN_ARGS=()
if [[ "${COMMIT_SIGN:-}" == 1 || "$(git config --get --type=bool commit.gpgsign || true)" == true ]]; then
  SIGN_ARGS=(-S)
fi

git commit ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} -m "$COMMIT_MESSAGE"
