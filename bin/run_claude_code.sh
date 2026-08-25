#!/usr/bin/env bash
# Starts Claude Code in the current repo with every sibling repository under
# SRC_DIR mounted via --add-dir, so the agent can read reference code.
#
# Environment:
#   SRC_DIR        Directory holding the repos (default: parent of the current repo).
#   CLAUDE_MODEL   Model (default: opus).
#   CLAUDE_EFFORT  Effort level (default: high).
set -euo pipefail

REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SRC_DIR="${SRC_DIR:-$(dirname "$REPO_DIR")}"
REPO_NAME="$(basename "$REPO_DIR")"

ADD_DIRS=()
for dir in "$SRC_DIR"/*/; do
  dir_name="$(basename "$dir")"
  [[ "$dir_name" == "$REPO_NAME" ]] && continue
  [[ "$dir_name" == .* ]] && continue
  ADD_DIRS+=(--add-dir "$dir")
done

cd "$REPO_DIR"
exec claude \
  --permission-mode auto \
  --verbose \
  --effort "${CLAUDE_EFFORT:-high}" \
  --model "${CLAUDE_MODEL:-opus}" \
  --chrome \
  ${ADD_DIRS[@]+"${ADD_DIRS[@]}"} \
  "$@"
