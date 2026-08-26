#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Assertions against an applied chezmoi tree. Run against the real home with `just test`,
# or against the throwaway CI home with `just test-home` (sets WHETSTONE_HOME). Two tests
# skip on a real home; the macOS workflow applies into the runner's own HOME, so CI=1 also
# counts as a throwaway home.

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

chezmoi_role() {
  sed -nE 's/^ *role = "([a-z]+)"$/\1/p' "$H/.config/chezmoi/chezmoi.toml"
}

chezmoi_managed() {
  HOME="$H" chezmoi --source "$REPO" managed
}

@test "managed files exist" {
  for f in .zshrc .p10k.zsh .claude/settings.json .codex/config.toml \
    .agents/mcp.json .config/homebrew/Brewfile .cursor/cli-config.json; do
    [ -f "$H/$f" ]
  done
}

@test ".gitconfig is managed on personal machines only" {
  if [ "$(chezmoi_role)" = personal ]; then
    chezmoi_managed | grep -qxF '.gitconfig'
    [ -f "$H/.gitconfig" ]
  else
    run ! bash -c "HOME='$H' chezmoi --source '$REPO' managed | grep -qxF .gitconfig"
  fi
}

@test "every agent's skills directory points at ~/.agents/skills" {
  resolves_to "$H/.claude/skills" "$H/.agents/skills"
  resolves_to "$H/.cursor/skills" "$H/.agents/skills"
  resolves_to "$H/.kiro/skills" "$H/.agents/skills"
}

@test "each hand-written skill resolves into the repo and has a SKILL.md" {
  for dir in "$REPO"/skills/*/; do
    s="$(basename "$dir")"
    resolves_to "$H/.agents/skills/$s" "$REPO/skills/$s"
    [ -f "$H/.agents/skills/$s/SKILL.md" ]
  done
}

@test "every symlink_* under home/dot_local/bin resolves to an executable in bin/" {
  for tmpl in "$REPO"/home/dot_local/bin/symlink_*.tmpl; do
    s="$(basename "$tmpl" .tmpl)"
    s="${s#symlink_}"
    resolves_to "$H/.local/bin/$s" "$REPO/bin/$s"
    [ -x "$H/.local/bin/$s" ]
  done
  resolves_to "$H/.agents/bin/sync-mcp" "$REPO/bin/sync-mcp"
}

@test "agent instruction files resolve to the repo AGENTS.md and handbook" {
  resolves_to "$H/.codex/AGENTS.md" "$REPO/AGENTS.md"
  resolves_to "$H/.claude/CLAUDE.md" "$REPO/AGENTS.md"
  resolves_to "$H/.agents/handbook" "$REPO/docs/handbook"
}

@test "reviewer subagents are linked for Claude Code and Codex" {
  resolves_to "$H/.claude/agents" "$REPO/agents"
  resolves_to "$H/.codex/agents" "$REPO/codex/agents"
}

@test "statusline scripts arrive executable" {
  [ -x "$H/.claude/statusline-command.sh" ]
  [ -x "$H/.claude/subagent-statusline.sh" ]
}

@test "Claude settings carry no env block" {
  jq -e 'has("env") | not' "$H/.claude/settings.json"
}

@test ".zshrc exports no CA bundle" {
  run ! grep -Eq '(SSL_CERT_FILE|REQUESTS_CA_BUNDLE|NODE_EXTRA_CA_CERTS|CURL_CA_BUNDLE)=' "$H/.zshrc"
}

@test "git identity comes from chezmoi data (CI home only)" {
  if [ "$H" = "$HOME" ] && [ -z "${CI:-}" ]; then skip "real home uses the machine's own identity"; fi
  if [ "$(chezmoi_role)" = work ]; then skip ".gitconfig is unmanaged when role is work"; fi
  [ "$(git config -f "$H/.gitconfig" user.name)" = T ]
  [ "$(git config -f "$H/.gitconfig" user.email)" = t@example.com ]
}

# Copilot on #10: nothing fed live state through the modify script, which is where two
# keys were being dropped. Seed a bare key and two tables the template does not declare.
@test "the Codex modify script keeps undeclared state and is idempotent" {
  script="$BATS_TEST_TMPDIR/modify.sh"
  HOME="$H" chezmoi --source "$REPO" execute-template \
    <"$REPO/home/dot_codex/modify_private_config.toml.tmpl" >"$script"

  # notify spans lines and holds a blank and a comment line, which are valid inside a
  # multiline value: capturing has to run to the next key, not stop at the first blank.
  seeded="$BATS_TEST_TMPDIR/seeded.toml"
  {
    printf 'notify = [\n  # the client\n  "/opt/notifier",\n\n  "turn-ended",\n]\n\n'
    printf '[plugins."browser@openai-bundled"] # trailing comment\nenabled = true\n\n'
    printf '[mcp_servers.private]\ncommand = "x"\n'
  } >"$seeded"

  first="$BATS_TEST_TMPDIR/first.toml"
  bash "$script" <"$seeded" >"$first"
  grep -qF '"/opt/notifier",' "$first"
  grep -qF '"turn-ended",' "$first"
  grep -qF '[plugins."browser@openai-bundled"]' "$first"
  grep -qF '[mcp_servers.private]' "$first"
  # tomllib needs 3.11+; the system python3 on macOS is 3.9.
  uv run --no-project --python 3.12 python -c \
    'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$first"

  second="$BATS_TEST_TMPDIR/second.toml"
  bash "$script" <"$first" >"$second"
  diff "$first" "$second"
}

# Copilot on #10: nothing exercised the .chezmoiremove entries, so a typo in one would
# leave the live file in place while the suite passed.
@test ".chezmoiremove deletes the paths it lists (CI home only)" {
  if [ "$H" = "$HOME" ] && [ -z "${CI:-}" ]; then skip "would delete files from the real home"; fi
  mkdir -p "$H/.codex" "$H/.agents/plugins"
  echo seeded >"$H/.codex/hooks.json"
  echo seeded >"$H/.agents/plugins/marketplace.json"

  HOME="$H" CI=1 chezmoi apply --source "$REPO"

  [ ! -e "$H/.codex/hooks.json" ]
  [ ! -e "$H/.agents/plugins/marketplace.json" ]
}

# Copilot on #10: every other invocation passes --source, so none of them exercises the
# sourceDir that .chezmoi.toml.tmpl now emits.
@test "a bare chezmoi command resolves this checkout" {
  # A real home's config may predate sourceDir and needs one chezmoi init. A throwaway or CI
  # home is generated from the template every time, so there the key has to be there.
  if [ "$H" = "$HOME" ] && [ -z "${CI:-}" ] \
    && ! grep -q '^sourceDir' "$H/.config/chezmoi/chezmoi.toml"; then
    skip "this home's config predates sourceDir; run chezmoi init to regenerate it"
  fi
  [ "$(HOME="$H" chezmoi source-path)" = "$REPO/home" ]
}

@test "the Codex config is readable only by its owner" {
  [ "$(stat -f '%Lp' "$H/.codex/config.toml")" = 600 ]
}

@test "Codex config parses as TOML" {
  # tomllib needs 3.11+; the system python3 on macOS is 3.9.
  uv run --no-project --python 3.12 python -c \
    'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$H/.codex/config.toml"
}

@test "shared MCP config parses as JSON with a non-empty server map" {
  jq -e '.mcpServers | type == "object" and length > 0' "$H/.agents/mcp.json"
}

@test "the secrets file is not managed" {
  if [ "$H" = "$HOME" ] && [ -z "${CI:-}" ]; then skip "the real home may hold a hand-made ~/.zsh_secrets"; fi
  [ ! -e "$H/.zsh_secrets" ]
}

# dot_zsh_secrets.example:1 and docs/new-machine.md:31 both say chmod 600, and nothing
# else checks that the instruction was followed.
@test "the secrets file, when present, is readable only by its owner" {
  [ -e "$H/.zsh_secrets" ] || skip "no ~/.zsh_secrets on this machine"
  [ "$(stat -f '%Lp' "$H/.zsh_secrets")" = 600 ]
}
