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

CLAUDE_MODEL="${CLAUDE_MODEL:-opus}"
EFFORT="high"

if [[ ${1:-} == claude || ${1:-} == --claude ]]; then
  shift
fi

ADD_DIRS=()
for repo in ${REFERENCE_REPOS_LIST[@]+"${REFERENCE_REPOS_LIST[@]}"}; do
  git -C "$SRC_DIR/$repo" pull -q || echo "warning: could not pull $repo; mounting it as is" >&2
  ADD_DIRS+=(--add-dir "$SRC_DIR/$repo")
done

echo "AGENT: claude"
echo "MODEL: $CLAUDE_MODEL"
echo "EFFORT: $EFFORT"
echo "--------------------------------"
echo ""

exec claude \
  --effort "$EFFORT" \
  --model "$CLAUDE_MODEL" \
  ${ADD_DIRS[@]+"${ADD_DIRS[@]}"} \
  "$@"
