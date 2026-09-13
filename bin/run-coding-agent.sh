#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(git rev-parse --show-toplevel)"
SRC_DIR="$(dirname "$REPO_DIR")"

cd "$REPO_DIR"

REFERENCE_REPOS_LIST=()
if [[ -n "${REFERENCE_REPOS:-}" ]]; then
  read -r -a REFERENCE_REPOS_LIST <<<"$REFERENCE_REPOS"
elif [[ -f .reference-repos ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] || REFERENCE_REPOS_LIST+=("$line")
  done <.reference-repos
fi

if [[ -f CLAUDE.local.md && -f AGENTS.md ]]; then
  cat AGENTS.md CLAUDE.local.md >AGENTS.override.md
else
  rm -f AGENTS.override.md
fi

AGENT="claude" # "codex"
CLAUDE_MODEL="${CLAUDE_MODEL:-opus[1m]}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-sol}"
EFFORT="high"

while [[ $# -gt 0 ]]; do
  case "$1" in
    claude | --claude)
      AGENT="claude"
      ;;
    codex | --codex)
      AGENT="codex"
      ;;
    --low)
      EFFORT="low"
      ;;
    --medium)
      EFFORT="medium"
      ;;
    --high)
      EFFORT="high"
      ;;
    --xhigh)
      EFFORT="xhigh"
      ;;
    --opus)
      AGENT="claude"
      CLAUDE_MODEL="opus[1m]"
      ;;
    --sonnet)
      AGENT="claude"
      CLAUDE_MODEL="sonnet"
      ;;
    *)
      break
      ;;
  esac
  shift
done

ADD_DIRS=()
for repo in ${REFERENCE_REPOS_LIST[@]+"${REFERENCE_REPOS_LIST[@]}"}; do
  git -C "$SRC_DIR/$repo" pull -q || echo "warning: could not pull $repo; mounting it as is" >&2
  ADD_DIRS+=(--add-dir "$SRC_DIR/$repo")
done

if [ "$AGENT" = "claude" ]; then
  MODEL="$CLAUDE_MODEL"
else
  MODEL="$CODEX_MODEL"
fi

echo "AGENT: $AGENT"
echo "MODEL: $MODEL"
echo "EFFORT: $EFFORT"
echo "--------------------------------"
echo ""

if [ "$AGENT" = "claude" ]; then
  exec claude \
    --effort "$EFFORT" \
    --model "$CLAUDE_MODEL" \
    ${ADD_DIRS[@]+"${ADD_DIRS[@]}"} \
    "$@"
else
  exec codex \
    --config model="$MODEL" \
    --config model_reasoning_effort="$EFFORT" \
    ${ADD_DIRS[@]+"${ADD_DIRS[@]}"} \
    "$@"
fi
