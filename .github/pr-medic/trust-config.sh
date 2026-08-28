#!/usr/bin/env bash
# Replace the config the Claude CLI reads from cwd at startup with the default branch's copy.
#
# claude-code-action does this itself, but only for entity pull-request events:
# src/entrypoints/run.ts guards restoreConfigFromBase with
# `isEntityContext(context) && context.isPR`. The medic also wakes on schedule,
# workflow_dispatch and workflow_run, and on those the PR's own copies would be live. The CLI
# reads them before any tool-permission gating -- SessionStart hooks, MCP servers, env vars
# such as NODE_OPTIONS and LD_PRELOAD, apiKeyHelper commands -- while a write token and the
# Anthropic credential are present.
#
# The list mirrors SENSITIVE_PATHS in that file. If upstream adds a path, this restores one
# fewer than it should, so re-check it when bumping the action.
set -euo pipefail

paths=(.claude .mcp.json .claude.json .gitmodules .ripgreprc CLAUDE.md CLAUDE.local.md .husky)
default_branch=$(gh api "repos/$REPO" --jq .default_branch)

# Delete before fetching: an attacker-controlled .gitmodules is read during fetch under the
# default fetch.recurseSubmodules=on-demand and can block on a credential prompt.
rm -rf "${paths[@]}"
git fetch --depth=1 --no-recurse-submodules origin "$default_branch"
for p in "${paths[@]}"; do
  # Absent on the default branch: it stays deleted, which is the safe direction.
  git checkout "origin/$default_branch" -- "$p" 2>/dev/null || true
done
# `git checkout <ref> -- <path>` stages what it restored. Unstage, or Claude's next commit
# carries the revert back onto the PR author's branch.
git reset -q -- "${paths[@]}" 2>/dev/null || true
