#!/usr/bin/env bash
# Regenerates a pull request title and body with Codex from the PR diff, commits, and
# recent history, shows the result, and applies it with `gh pr edit` after confirmation.
# Existing checklist ticks and a `<!-- branch-stack-start -->...<!-- branch-stack-end -->`
# block in the current body are preserved.
#
# Usage: update-pr-title-and-body.sh PR_NUMBER [-y|--yes]
#
# Environment:
#   CODEX_MODEL      Model name passed to `codex exec` (default: gpt-5.5).
#   CODEX_BASE_URL   OpenAI-compatible proxy (falls back to OPENAI_BASE_URL); OPENAI_API_KEY is the credential.
set -euo pipefail

SCHEMA=$(
  cat <<'JSON'
{
  "type": "object",
  "properties": {
    "title": {
      "type": "string",
      "minLength": 1,
      "maxLength": 72,
      "description": "A Conventional Commits PR title of 72 characters or fewer."
    },
    "description": {
      "type": "string",
      "minLength": 1,
      "description": "A PR description of 200 words or fewer."
    }
  },
  "required": ["title", "description"],
  "additionalProperties": false
}
JSON
)
readonly SCHEMA

CODEX_MODEL="${CODEX_MODEL:-gpt-5.5}"
ASSUME_YES=false
PR_NUMBER=""
readonly CODEX_MODEL

usage() {
  printf 'Usage: %s PR_NUMBER [-y|--yes]\n' "${0##*/}"
}

usage_error() {
  printf '%s\n' "$1" >&2
  usage >&2
  exit 2
}

set_pr_number() {
  local value=$1

  if [[ -n $PR_NUMBER ]]; then
    usage_error "Unexpected argument: $value"
  fi

  PR_NUMBER=$value
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
      while [[ $# -gt 0 ]]; do
        set_pr_number "$1"
        shift
      done
      ;;
    -*)
      usage_error "Unknown option: $1"
      ;;
    *)
      set_pr_number "$1"
      shift
      ;;
  esac
done

if [[ ! $PR_NUMBER =~ ^[1-9][0-9]*$ ]]; then
  usage_error 'PR_NUMBER must be a positive integer.'
fi

require_command() {
  local command_name=$1

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf "Required command '%s' was not found.\n" "$command_name" >&2
    exit 127
  fi
}

require_command gh
require_command git
require_command jq
require_command codex

REPO_ROOT=$(git rev-parse --show-toplevel)
readonly REPO_ROOT
cd "$REPO_ROOT"

TEMP_DIR=$(mktemp -d)
readonly TEMP_DIR
SCHEMA_FILE="$TEMP_DIR/schema.json"
RESULT_FILE="$TEMP_DIR/result.json"
PR_BODY_FILE="$TEMP_DIR/pr-body.md"
PR_VIEW_FILE="$TEMP_DIR/pr-view.json"
PR_DIFF_FILE="$TEMP_DIR/pr.diff"
GIT_STATUS_FILE="$TEMP_DIR/git-status.txt"
GIT_LOG_FILE="$TEMP_DIR/git-log.txt"
GIT_DIFF_STAT_FILE="$TEMP_DIR/git-diff-stat.txt"
PROMPT_FILE="$TEMP_DIR/prompt.md"
printf '%s\n' "$SCHEMA" >"$SCHEMA_FILE"

cleanup() {
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

readonly ASSUME_YES PR_NUMBER

# Optional OpenAI-compatible proxy. Empty array means Codex uses its default provider.
PROVIDER_ARGS=()
CODEX_BASE_URL="${CODEX_BASE_URL:-${OPENAI_BASE_URL:-}}"
if [[ -n "$CODEX_BASE_URL" ]]; then
  PROVIDER_ARGS=(
    --config 'model_provider="proxy"'
    --config "model_providers.proxy={name=\"Proxy\",base_url=\"$CODEX_BASE_URL\",env_key=\"OPENAI_API_KEY\",wire_api=\"responses\",supports_websockets=false}"
  )
fi

wait_gathered() {
  local pid=$1
  local label=$2
  local status=0

  wait "$pid" || status=$?
  if [[ $status -ne 0 ]]; then
    printf '%s failed with status %s.\n' "$label" "$status" >&2
    GATHER_STATUS=$status
  fi
}

GATHER_STATUS=0
gh pr view "$PR_NUMBER" --json title,body,baseRefName,headRefName,commits \
  >"$PR_VIEW_FILE" &
PR_VIEW_PID=$!
gh pr diff "$PR_NUMBER" >"$PR_DIFF_FILE" &
PR_DIFF_PID=$!
git status -sb >"$GIT_STATUS_FILE" &
GIT_STATUS_PID=$!
git log --oneline -n 10 >"$GIT_LOG_FILE" &
GIT_LOG_PID=$!

wait_gathered "$PR_VIEW_PID" "gh pr view"
wait_gathered "$PR_DIFF_PID" "gh pr diff"
wait_gathered "$GIT_STATUS_PID" "git status"
wait_gathered "$GIT_LOG_PID" "git log"
if [[ $GATHER_STATUS -ne 0 ]]; then
  exit "$GATHER_STATUS"
fi

resolve_pr_git_ref() {
  local ref_name=$1
  local fallback=$2

  if git rev-parse --verify --quiet "origin/${ref_name}^{commit}" >/dev/null; then
    printf '%s\n' "origin/${ref_name}"
    return
  fi
  if git rev-parse --verify --quiet "${ref_name}^{commit}" >/dev/null; then
    printf '%s\n' "$ref_name"
    return
  fi
  printf '%s\n' "$fallback"
}

BASE_REF_NAME=$(jq -er '.baseRefName' "$PR_VIEW_FILE")
HEAD_REF_NAME=$(jq -er '.headRefName' "$PR_VIEW_FILE")
DIFF_BASE=$(resolve_pr_git_ref "$BASE_REF_NAME" "$BASE_REF_NAME")
DIFF_HEAD=$(resolve_pr_git_ref "$HEAD_REF_NAME" HEAD)
DIFF_RANGE="${DIFF_BASE}...${DIFF_HEAD}"
readonly BASE_REF_NAME HEAD_REF_NAME DIFF_BASE DIFF_HEAD DIFF_RANGE

git diff --stat "$DIFF_RANGE" >"$GIT_DIFF_STAT_FILE"

CURRENT_BODY=$(jq -er '.body' "$PR_VIEW_FILE")

# Checklist items come from the repository's pull request template so the script
# works for any repo. Items already ticked in the current body stay ticked.
checklist_items() {
  local template
  for template in .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md \
    PULL_REQUEST_TEMPLATE.md; do
    if [[ -f $template ]]; then
      sed -nE 's/^- \[[ xX]\] (.+)$/\1/p' "$template"
      return
    fi
  done
  printf '%s\n' 'Design docs reflect the code changes.' \
    'If this PR was generated by AI, the **AI Generated** label is applied.'
}

render_checklist() {
  local item
  while IFS= read -r item; do
    [[ -n $item ]] || continue
    if grep -Fq -- "- [x] $item" <<<"$CURRENT_BODY" || grep -Fq -- "- [X] $item" <<<"$CURRENT_BODY"; then
      printf -- '- [x] %s\n' "$item"
    else
      printf -- '- [ ] %s\n' "$item"
    fi
  done < <(checklist_items)
}

CHECKLIST="$(cd "$REPO_ROOT" && render_checklist)"
readonly CHECKLIST

BRANCH_STACK_BLOCK=""
if grep -Fq '<!-- branch-stack-start -->' <<<"$CURRENT_BODY" \
  && grep -Fq '<!-- branch-stack-end -->' <<<"$CURRENT_BODY"; then
  BRANCH_STACK_BLOCK=$(
    awk '
			/<!-- branch-stack-start -->/ { capture=1 }
			capture { print }
			/<!-- branch-stack-end -->/ { exit }
		' <<<"$CURRENT_BODY"
  )
fi
readonly BRANCH_STACK_BLOCK

{
  cat <<PROMPT
Inspect pull request #${PR_NUMBER}. Generate an updated pull request title
and description. Do not edit the pull request. Do not run commands. Do not
read files. Do not run gh pr edit. Do not modify files. Return only the
structured output.

The command outputs below are complete. Use them. Match existing title
style in git log.

Title requirements:

- Follow Conventional Commits: <type>[optional scope]: <subject>
- Use one of these types: feat, fix, refactor, chore, docs, test, ci, style, perf,
  build, revert
- scope is optional, e.g. "feat(api_client): add retry test"
- Use imperative mood: "add", "fix", "remove", not "added", "fixes", "removed"
- Keep the subject line all lowercase and DO NOT end it with a full stop
- title should be 72 characters or less
- Name the component and the decision or bug. Someone scanning closed PRs
  while hunting a regression should be able to tell if this change is
  relevant. Prefer "docs(api_client): replace protocols with bases" over
  "docs(api_client): revise client design".

Description should be in markdown format and should look like this:

<body>

<footer>

Body requirements:
- Keep the body under 200 words
- Each line in the body should be less than 100 characters

Footer requirements:
- Footer should be just one line and there should be an empty line between the body and
  the footer

Description requirements (point-in-time writing for the reviewer):
- Lead with what changed and why. This is persuasive writing: justify why
  the change should be accepted.
- State the problem or design decision, how this implements it, alternatives
  rejected if the diff records them, and how to review it.
- If this pull request is a design-doc change, describe the design decision.
  Design is decided, written down, then implemented. Do not say the document
  is catching up to already-written code. If a companion implementation
  pull request exists, say that pull request implements this design.
- Do not put durable how-to notes here (how to call a function, schema
  links). Those belong in code comments.
- Do not put point-in-time claims in a way that reads like a code comment.
- Keep the description to 200 words or fewer
- Do not claim that tests ran unless you can see evidence that they did

If any line in the description is over 100 characters, split it into multiple lines.

You can use markdown in the body and footer, but not in the title

gh pr view ${PR_NUMBER} --json title,body,baseRefName,headRefName,commits:
PROMPT
  cat "$PR_VIEW_FILE"
  printf '\n\ngh pr diff %s:\n' "$PR_NUMBER"
  cat "$PR_DIFF_FILE"
  printf '\n\ngit status -sb:\n'
  cat "$GIT_STATUS_FILE"
  printf '\n\ngit log --oneline -n 10:\n'
  cat "$GIT_LOG_FILE"
  printf '\n\ngit diff --stat %s:\n' "$DIFF_RANGE"
  cat "$GIT_DIFF_STAT_FILE"
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
  --config 'model_reasoning_effort="medium"' \
  --config 'model_reasoning_summary="none"' \
  --config 'model_verbosity="low"' \
  --config 'service_tier="fast"' \
  ${PROVIDER_ARGS[@]+"${PROVIDER_ARGS[@]}"} \
  --output-schema "$SCHEMA_FILE" \
  --output-last-message "$RESULT_FILE" \
  - <"$PROMPT_FILE" >/dev/null 2>"$TEMP_DIR/codex.stderr"; then
  cat "$TEMP_DIR/codex.stderr" >&2
  exit 1
fi

PR_TITLE=$(jq -er '.title | select(type == "string" and length > 0)' "$RESULT_FILE")
DESCRIPTION=$(jq -er '.description | select(type == "string" and length > 0)' "$RESULT_FILE")
readonly PR_TITLE DESCRIPTION

PR_BODY=$(
  cat <<EOF
## Description

$DESCRIPTION

## Checklist

$CHECKLIST
EOF
)

if [[ -n "$BRANCH_STACK_BLOCK" ]]; then
  PR_BODY+=$'\n\n'"$BRANCH_STACK_BLOCK"
fi
readonly PR_BODY

printf '\nPR title:\n%s\n\nPR body:\n%s\n\n' "$PR_TITLE" "$PR_BODY"

confirm_pr_edit() {
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

confirm_pr_edit
printf '%s\n' "$PR_BODY" >"$PR_BODY_FILE"

gh pr edit "$PR_NUMBER" \
  --title "$PR_TITLE" \
  --body-file "$PR_BODY_FILE"
