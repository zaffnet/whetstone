#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Assertions against an applied chezmoi tree. Run against the real home with `just test`,
# or against the throwaway CI home with `just test-home` (sets WHETSTONE_HOME).

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  H="${WHETSTONE_HOME:-$HOME}"
  export REPO H
}

resolves_to() {
  local link=$1 expected=$2
  [ -L "$link" ]
  [ "$(readlink "$link")" = "$expected" ]
}

@test "managed files exist" {
  for f in .zshrc .gitconfig .p10k.zsh .claude/settings.json .codex/config.toml \
    .agents/mcp.json .config/homebrew/Brewfile .cursor/cli-config.json; do
    [ -f "$H/$f" ]
  done
}

@test ".claude/skills points at ~/.agents/skills" {
  resolves_to "$H/.claude/skills" "$H/.agents/skills"
}

@test "each hand-written skill resolves into the repo and has a SKILL.md" {
  for s in address-pr-comments-sequential deep-claude-code-review deep-pr-review deslop \
    fastapi fix-design-implementation-discrepancies simplify-english sqlmodel teach-me \
    verification-before-completion writing-whip; do
    resolves_to "$H/.agents/skills/$s" "$REPO/skills/$s"
    [ -f "$H/.agents/skills/$s/SKILL.md" ]
  done
}

@test "agent instruction files resolve to the repo AGENTS.md" {
  resolves_to "$H/.codex/AGENTS.md" "$REPO/AGENTS.md"
  resolves_to "$H/.claude/CLAUDE.md" "$REPO/AGENTS.md"
}

@test "Claude settings carry no env block" {
  jq -e 'has("env") | not' "$H/.claude/settings.json"
}

@test ".zshrc has no corporate CA bundle export" {
  run ! grep -q 'system-certs' "$H/.zshrc"
}

@test "git identity comes from chezmoi data (CI home only)" {
  if [ "$H" = "$HOME" ]; then skip "real home uses the machine's own identity"; fi
  grep -q 'name = T' "$H/.gitconfig"
  grep -q 'email = t@example.com' "$H/.gitconfig"
}

@test "Codex config renders the shared MCP servers" {
  grep -q '^\[mcp_servers.context7\]' "$H/.codex/config.toml"
}

@test "the secrets file is not managed" {
  if [ "$H" = "$HOME" ]; then skip "the real home may hold a hand-made ~/.zsh_secrets"; fi
  [ ! -e "$H/.zsh_secrets" ]
}
