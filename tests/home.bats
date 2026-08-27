#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Assertions against an applied chezmoi tree. Run against the real home with `just test`,
# or against the throwaway CI home with `just test-home` (sets WHETSTONE_HOME). The macOS
# workflow applies into the runner's own HOME, so CI=1 also counts as a throwaway home.
#
# Four conditions skip a test. The rule, not a count, because a count goes stale the moment
# a case is added -- and a skip nobody knows about is what let the regression through on #10:
#
#   real home without CI  the cases named "(CI home only)", which write to or delete from
#                         the home, and `the secrets file is not managed`, which a
#                         hand-made ~/.zsh_secrets would fail
#   role is work          `git identity comes from chezmoi data`, the one role where
#                         .gitconfig is deliberately unmanaged
#   config predates       `a bare chezmoi command resolves this checkout`; a throwaway or
#   sourceDir             CI home is regenerated every time, so there it always runs
#   no ~/.zsh_secrets     `the secrets file, when present, is readable only by its owner`,
#                         which therefore never runs in CI -- only a real machine with
#                         secrets exercises it
#
# macos.yml asserts that exactly this set skips, so a new one cannot arrive unannounced.

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
# keys were being dropped. Seed a bare key and three tables the template does not declare,
# one of them nested under a table it does declare.
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
    # [tui] is declared, [tui.model_availability_nux] is not: it is Codex's own state, and
    # the KEEP allowlist this script replaced named it for exactly that reason. The
    # status_line_use_colors line below it must still lose to the template.
    printf '[tui]\nstatus_line_use_colors = false\n\n'
    printf '[tui.model_availability_nux]\nseen = true\n\n'
    printf '[mcp_servers.private]\ncommand = "x"\n'
  } >"$seeded"

  first="$BATS_TEST_TMPDIR/first.toml"
  bash "$script" <"$seeded" >"$first"
  grep -qF '"/opt/notifier",' "$first"
  grep -qF '"turn-ended",' "$first"
  grep -qF '[plugins."browser@openai-bundled"]' "$first"
  grep -qF '[tui.model_availability_nux]' "$first"
  grep -qF '[mcp_servers.private]' "$first"
  # A declared table is still rewritten whole, so the template's value wins.
  grep -qF 'status_line_use_colors = true' "$first"
  run grep -qF 'status_line_use_colors = false' "$first"
  [ "$status" -ne 0 ]
  # tomllib needs 3.11+; the system python3 on macOS is 3.9.
  uv run --no-project --python 3.12 python -c \
    'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$first"

  second="$BATS_TEST_TMPDIR/second.toml"
  bash "$script" <"$first" >"$second"
  diff "$first" "$second"
}

# The Cursor settings were a plain template, so every apply wrote the file whole and
# deleted whatever Cursor and its extensions had written into it. Seed keys the template
# does not declare, including a multi-line value holding a blank and a comment line, a
# string holding `//`, and a string holding an escaped quote and a brace -- the input that
# makes a line-oriented or regex-stripping merge produce a plausible but wrong file.
@test "the Cursor modify script keeps undeclared settings and is idempotent" {
  script="$BATS_TEST_TMPDIR/modify.sh"
  HOME="$H" chezmoi --source "$REPO" execute-template \
    <"$REPO/home/Library/Application Support/Cursor/User/modify_settings.json.tmpl" >"$script"

  seeded="$BATS_TEST_TMPDIR/seeded.json"
  cat >"$seeded" <<'JSON'
{
	// a stray { and } in a comment must not move the depth
	"editor.formatOnSave": false,
	"[python]": {
		"editor.defaultFormatter": "someone.else"
	},
	"python.defaultInterpreterPath": "/opt/py/bin/python3.14",
	"sonarlint.rules": {
		// a comment and a blank line inside a value: capture must not stop here

		"python:S1234": { "level": "off" }
	},
	"myext.docsUrl": "https://example.com//docs",
	"myext.quote": "say \"hi\" }",
	"snyk.yesWelcomeNotification": false,
}
JSON

  first="$BATS_TEST_TMPDIR/first.json"
  bash "$script" <"$seeded" >"$first"

  # Undeclared keys survive, whole values and all, under the marker.
  grep -qF '"python.defaultInterpreterPath": "/opt/py/bin/python3.14"' "$first"
  grep -qF '"snyk.yesWelcomeNotification": false' "$first"
  grep -qF '"python:S1234"' "$first"
  grep -qF 'https://example.com//docs' "$first"
  grep -qF 'say \"hi\" }' "$first"
  grep -qF '// --- preserved' "$first"

  # A declared key still loses to the template, and is written once.
  grep -qF '"editor.formatOnSave": true' "$first"
  run grep -qF '"editor.formatOnSave": false' "$first"
  [ "$status" -ne 0 ]
  run grep -qF 'someone.else' "$first"
  [ "$status" -ne 0 ]
  # Anchored to one tab: the template also sets this key inside a per-language block, so
  # a plain count would be 2 for a correct file.
  [ "$(grep -cE '^\t"editor\.formatOnSave":' "$first")" -eq 1 ]

  # The template's own comments are documentation and survive verbatim.
  grep -qF 'SC2121' "$first"
  grep -qF 'FiraCode-VF.ttf' "$first"

  # Valid JSONC: the seeded trailing comma is gone and it parses once out-of-string //
  # comments do. This stripper tracks strings but not keys or depth, so it is independent
  # of the code under test.
  python3 "$REPO/tests/strip-jsonc-comments.py" "$first" | python3 -c 'import json,sys; json.load(sys.stdin)'

  second="$BATS_TEST_TMPDIR/second.json"
  bash "$script" <"$first" >"$second"
  diff "$first" "$second"

  # First apply on a new machine: no live file, so no marker and no block, and the output
  # is the rendered template byte for byte. A truncated file Cursor could not read either
  # falls back the same way rather than emitting half a value.
  plain="$BATS_TEST_TMPDIR/plain.json"
  HOME="$H" chezmoi --source "$REPO" execute-template \
    <"$REPO/home/.chezmoitemplates/cursor-settings.json.tmpl" >"$plain"
  bash "$script" </dev/null | diff "$plain" -
  printf '{\n\t"a": [1,\n' | bash "$script" | diff "$plain" -

  # Copilot on #19: depth alone let a malformed file through. `[1}` reaches depth zero, so
  # the slice was preserved and the emitted file would not parse at all -- worse than the
  # deletions this script exists to stop. A closer now has to match its opener.
  printf '{\n\t"extension.value": [1}\n}\n' | bash "$script" | diff "$plain" -
  # And nothing but whitespace or a comment may follow the root object, so a second one
  # cannot have a winner silently picked for it.
  printf '{\n\t"a.b": 1\n}\n{\n\t"c.d": 2\n}\n' | bash "$script" | diff "$plain" -
  printf '{\n\t"a.b": 1\n}\ngarbage\n' | bash "$script" | diff "$plain" -

  # Copilot on #19: a key name is compared decoded. Spelled with an escape it is still the
  # declared key, so it loses to the template rather than being appended after it and
  # winning as a duplicate once Cursor parses the result.
  escaped="$BATS_TEST_TMPDIR/escaped.json"
  printf '{\n\t"editor\\u002eformatOnSave": false\n}\n' | bash "$script" >"$escaped"
  diff "$plain" "$escaped"

  # A trailing comma is legal in settings.json, so a file carrying one still merges.
  printf '{\n\t"snyk.yesWelcomeNotification": false,\n}\n' | bash "$script" \
    | grep -qF '"snyk.yesWelcomeNotification": false'
}

# Copilot on #11: chezmoi replaces a real directory with the managed symlink by deleting it
# recursively and without a prompt, so an apply could take Cursor-only skills with it.
@test "an apply refuses while a skills directory is real (CI home only)" {
  if [ "$H" = "$HOME" ] && [ -z "${CI:-}" ]; then skip "would disturb the real home"; fi
  rm -rf "$H/.cursor/skills"
  mkdir -p "$H/.cursor/skills/only-here"

  run env HOME="$H" CI=1 chezmoi apply --source "$REPO"
  survived=no
  [ -d "$H/.cursor/skills/only-here" ] && survived=yes

  # Put the home back before asserting, so a failure here does not affect later tests.
  rm -rf "$H/.cursor/skills"
  env HOME="$H" CI=1 chezmoi apply --force --source "$REPO"

  [ "$status" -ne 0 ]
  [ "$survived" = yes ]
  resolves_to "$H/.cursor/skills" "$H/.agents/skills"
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
