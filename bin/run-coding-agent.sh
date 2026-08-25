#!/usr/bin/env bash
# Launches Claude Code or Codex in the current repository, with sibling
# reference repositories mounted read-only via --add-dir and pulled first.
#
# Usage: run-coding-agent.sh [claude|codex] [--opus|--sonnet] [--medium|--high|--xhigh] [AGENT ARGS...]
#
# Environment:
#   REFERENCE_REPOS   Space-separated directory names under SRC_DIR (the parent of
#                     the current repo) to pull and mount. Falls back to a .reference-repos
#                     file in the repo root, one name per line. Default: none.
#   CLAUDE_MODEL      Claude model (default: opus).
#   CODEX_MODEL       Codex model (default: gpt-5.5).
#
# AGENTS.md is the source of truth for agent instructions; CLAUDE.md is @AGENTS.md.
# When CLAUDE.local.md exists, it is appended to a machine-local AGENTS.override.md
# so Codex sees the same extra context without it ever being committed.
set -euo pipefail

REPO_DIR="$(git rev-parse --show-toplevel)"
SRC_DIR="$(dirname "$REPO_DIR")"

cd "$REPO_DIR"

REFERENCE_REPOS_LIST=()
if [[ -n "${REFERENCE_REPOS:-}" ]]; then
  read -r -a REFERENCE_REPOS_LIST <<<"$REFERENCE_REPOS"
elif [[ -f .reference-repos ]]; then
  while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] || REFERENCE_REPOS_LIST+=("$line")
  done <.reference-repos
fi

if [[ -f CLAUDE.local.md ]]; then
  cat CLAUDE.md >AGENTS.override.md
  echo "" >>AGENTS.override.md
  cat CLAUDE.local.md >>AGENTS.override.md
fi

for repo in ${REFERENCE_REPOS_LIST[@]+"${REFERENCE_REPOS_LIST[@]}"}; do
  git -C "$SRC_DIR/$repo" pull -q
done

AGENT="claude" # "codex"
CLAUDE_MODEL="${CLAUDE_MODEL:-opus}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.5}"
EFFORT="high"

while [[ $# -gt 0 ]]; do
  case "$1" in
    claude | --claude)
      AGENT="claude"
      ;;
    codex | --codex)
      AGENT="codex"
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
      CLAUDE_MODEL="opus"
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
    --permission-mode bypassPermissions \
    --effort "$EFFORT" \
    --model "$CLAUDE_MODEL" \
    --chrome \
    ${ADD_DIRS[@]+"${ADD_DIRS[@]}"} \
    "$@"
else
  exec codex \
    --sandbox danger-full-access \
    --ask-for-approval never \
    --dangerously-bypass-hook-trust \
    --config model="$MODEL" \
    --config model_reasoning_effort="$EFFORT" \
    ${ADD_DIRS[@]+"${ADD_DIRS[@]}"} \
    "$@"
fi
