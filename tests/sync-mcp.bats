#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Issue #21: bin/sync-mcp is the single writer of `mcpServers` in ~/.claude.json and of
# [mcp_servers.*] in ~/.codex/config.toml, and nothing exercised it. home.bats only asserts
# that the script is symlinked, and .chezmoiscripts/40-sync-mcp.sh is CI-ignored, so the
# macOS workflow never ran it either.
#
# Every case here builds a throwaway home and runs the real script against it. The script
# takes its paths from $HOME at import, so overriding HOME is all the isolation needed --
# nothing here can reach the machine's own configs.

setup_file() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  # sync-mcp needs 3.11+ for tomllib and the system python3 on macOS is 3.9. Resolve the
  # interpreter once and call it directly: `uv run` under a throwaway HOME would miss uv's
  # cache and re-download a toolchain for every case.
  PY="$(uv run --no-project --python 3.12 python -c 'import sys; print(sys.executable)')"
  export REPO PY
}

# A home with the three files sync-mcp writes, and nothing else.
seed_home() {
  FAKE="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE/.agents" "$FAKE/.codex" "$FAKE/.cursor"
  cat >"$FAKE/.agents/mcp.json"
  printf '{}\n' >"$FAKE/.claude.json"
  : >"$FAKE/.codex/config.toml"
  export FAKE
}

sync() {
  run env HOME="$FAKE" "$PY" "$REPO/bin/sync-mcp"
}

toml_get() {
  "$PY" -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb")))' "$1"
}

@test "a managed server reaches all three products" {
  seed_home <<'JSON'
{
  "mcpServers": {
    "local-tool": {"command": "/bin/echo", "args": ["hi"], "env": {"AWS_PROFILE": "example"}},
    "remote-tool": {"url": "https://example/mcp", "headers": {"Authorization": "Bearer ${TOKEN}"}}
  }
}
JSON
  sync
  [ "$status" -eq 0 ]

  # Cursor is a symlink to the shared file, not a copy, so it cannot drift.
  [ -L "$FAKE/.cursor/mcp.json" ]
  [ "$(readlink "$FAKE/.cursor/mcp.json")" = "$FAKE/.agents/mcp.json" ]

  jq -e '.mcpServers | keys == ["local-tool", "remote-tool"]' "$FAKE/.claude.json"

  # A url server carries the credential as an env var name, never the value.
  grep -qF '[mcp_servers.remote-tool]' "$FAKE/.codex/config.toml"
  grep -qF 'bearer_token_env_var = "TOKEN"' "$FAKE/.codex/config.toml"
  run ! grep -qF 'Bearer' "$FAKE/.codex/config.toml"
  grep -qF '[mcp_servers.local-tool.env]' "$FAKE/.codex/config.toml"
  grep -qF 'AWS_PROFILE = "example"' "$FAKE/.codex/config.toml"
}

@test "Claude local-scope servers are emptied, and the rest of the file is left alone" {
  seed_home <<'JSON'
{"mcpServers": {"keeper": {"command": "/bin/true"}}}
JSON
  cat >"$FAKE/.claude.json" <<'JSON'
{
  "numStartups": 42,
  "mcpServers": {"stale": {"command": "/bin/false"}},
  "projects": {
    "/one": {"mcpServers": {"local-a": {"command": "x"}}, "allowedTools": ["Read"]},
    "/two": {"mcpServers": {"local-b": {"command": "y"}, "local-c": {"command": "z"}}}
  }
}
JSON
  sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed 3 local-scope servers"* ]]

  jq -e '.mcpServers | keys == ["keeper"]' "$FAKE/.claude.json"
  jq -e '[.projects[].mcpServers // {} | length] | add == 0' "$FAKE/.claude.json"
  # Untouched keys survive: this rewrites two things, not the file.
  jq -e '.numStartups == 42' "$FAKE/.claude.json"
  jq -e '.projects["/one"].allowedTools == ["Read"]' "$FAKE/.claude.json"
}

@test "Codex private servers are kept and unmanaged ones are dropped" {
  seed_home <<'JSON'
{"mcpServers": {"keeper": {"command": "/bin/true"}}}
JSON
  cat >"$FAKE/.codex/config.toml" <<'TOML'
model = "gpt-5.6-sol"

[mcp_servers.node_repl]
command = "/codex/node_repl"

[mcp_servers.stale-unmanaged]
command = "/bin/false"

[tui]
status_line_use_colors = true
TOML
  sync
  [ "$status" -eq 0 ]

  # node_repl is Codex's own (CODEX_PRIVATE); it is not in mcp.json and must survive.
  grep -qF '[mcp_servers.node_repl]' "$FAKE/.codex/config.toml"
  grep -qF '[mcp_servers.keeper]' "$FAKE/.codex/config.toml"
  run ! grep -qF 'stale-unmanaged' "$FAKE/.codex/config.toml"
  # Everything that is not an MCP table is carried over.
  grep -qF 'model = "gpt-5.6-sol"' "$FAKE/.codex/config.toml"
  grep -qF '[tui]' "$FAKE/.codex/config.toml"
  toml_get "$FAKE/.codex/config.toml" >/dev/null
}

# Issue #21 flagged this as unverified: TABLE_HEADER was `^\[([^]]+)\]\s*$`, which cannot
# match `[[history]]`, so the block read as ordinary lines and was absorbed into the chunk
# above it. When that chunk was an unmanaged [mcp_servers.*] table being dropped, the block
# was deleted with it. Reproduced before fixing: [[history]] and `kept = true` both vanished.
@test "an array-of-tables block after a dropped server survives" {
  seed_home <<'JSON'
{"mcpServers": {"keeper": {"command": "/bin/true"}}}
JSON
  cat >"$FAKE/.codex/config.toml" <<'TOML'
[mcp_servers.stale-unmanaged]
command = "/bin/false"

[[history]]
kept = true

[projects."/some/path"]
trust_level = "trusted"
TOML
  sync
  [ "$status" -eq 0 ]

  grep -qF '[[history]]' "$FAKE/.codex/config.toml"
  grep -qF 'kept = true' "$FAKE/.codex/config.toml"
  grep -qF 'trust_level = "trusted"' "$FAKE/.codex/config.toml"
  run ! grep -qF 'stale-unmanaged' "$FAKE/.codex/config.toml"
}

# Copilot on #30: the fix above was not the whole shape. TABLE_HEADER had dropped the
# trailing-comment branch, so `[projects."/x"] # note` read as an ordinary line and the
# whole table went with the dropped server above it. Codex writes those comments itself, so
# this deleted a real trust decision. Reproduced before fixing.
@test "a header carrying a trailing comment is still a header" {
  seed_home <<'JSON'
{"mcpServers": {"keeper": {"command": "/bin/true"}}}
JSON
  cat >"$FAKE/.codex/config.toml" <<'TOML'
[mcp_servers.stale-unmanaged]
command = "/bin/false"

[mcp_servers.node_repl] # Codex's own
command = "/codex/node_repl"

[projects."/some/path"] # trusted at some point
trust_level = "trusted"

[[history]] # and the other shape, commented
kept = true
TOML
  sync
  [ "$status" -eq 0 ]

  grep -qF 'trust_level = "trusted"' "$FAKE/.codex/config.toml"
  grep -qF 'kept = true' "$FAKE/.codex/config.toml"
  # A commented header on a private server still identifies it, so it is not dropped.
  grep -qF '/codex/node_repl' "$FAKE/.codex/config.toml"
  run ! grep -qF 'stale-unmanaged' "$FAKE/.codex/config.toml"
}

# The chunker and the Codex modify script split the same file. A shape one recognises and
# the other does not is a silent deletion, which is how both misses above got in, so the
# patterns are pinned to each other rather than to a literal.
@test "the chunker and the Codex modify script use the same header pattern" {
  rendered="$BATS_TEST_TMPDIR/modify.sh"
  HOME="${WHETSTONE_HOME:-$HOME}" chezmoi --source "$REPO" execute-template \
    <"$REPO/home/dot_codex/modify_private_config.toml.tmpl" >"$rendered"

  chunker=$(sed -nE 's/^TABLE_HEADER = re\.compile\((r".*")\)$/\1/p' "$REPO/bin/sync-mcp")
  modify=$(sed -nE 's/^HEADER = re\.compile\((r".*")\)$/\1/p' "$rendered")
  [ -n "$chunker" ]
  [ -n "$modify" ]
  [ "$chunker" = "$modify" ]
}

@test "a literal secret is refused and nothing is written" {
  seed_home <<'JSON'
{"mcpServers": {"bad": {"url": "https://example/mcp", "headers": {"Authorization": "Bearer sk-live-abc"}}}}
JSON
  printf 'model = "untouched"\n' >"$FAKE/.codex/config.toml"
  sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing a literal secret"* ]]

  # It dies in load_managed(), before any writer runs, so the products are as they were.
  [ "$(cat "$FAKE/.codex/config.toml")" = 'model = "untouched"' ]
  [ ! -e "$FAKE/.cursor/mcp.json" ]
  jq -e 'has("mcpServers") | not' "$FAKE/.claude.json"
}

@test "a literal env value is refused unless the key is configuration, not a credential" {
  seed_home <<'JSON'
{"mcpServers": {"bad": {"command": "/bin/true", "env": {"API_KEY": "sk-live-abc"}}}}
JSON
  sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"bad.env.API_KEY must be \${VAR}"* ]]

  # PLAIN_ENV_KEYS and PLAIN_ENV_SUFFIXES: a profile, a region, a log level are settings.
  seed_home <<'JSON'
{
  "mcpServers": {
    "ok": {
      "command": "/bin/true",
      "env": {
        "AWS_PROFILE": "example",
        "AWS_DEFAULT_REGION": "us-east-1",
        "SOMETHING_REGION": "eu-west-2",
        "LOG_LEVEL": "debug"
      }
    }
  }
}
JSON
  sync
  [ "$status" -eq 0 ]
  grep -qF 'AWS_PROFILE = "example"' "$FAKE/.codex/config.toml"
  grep -qF 'AWS_DEFAULT_REGION = "us-east-1"' "$FAKE/.codex/config.toml"
  grep -qF 'SOMETHING_REGION = "eu-west-2"' "$FAKE/.codex/config.toml"
  grep -qF 'LOG_LEVEL = "debug"' "$FAKE/.codex/config.toml"
}

# Pins current behaviour rather than endorsing it. refuse_literal_secrets() accepts a
# ${VAR} env value on a command server, which reads as a promise that the variable is
# resolved somewhere -- and for a url server it is, into bearer_token_env_var or
# env_http_headers, both of which carry the name for Codex to look up. A command server has
# no such indirection: the placeholder is written through verbatim, so the child process
# receives the six characters ${VAR} rather than the secret. No entry in ~/.agents/mcp.json
# uses this today, and whether Codex expands [mcp_servers.*.env] could not be checked from
# here, so the behaviour is recorded instead of changed. Filed separately.
@test "a \${VAR} env value on a command server is written through unresolved" {
  seed_home <<'JSON'
{"mcpServers": {"cmd": {"command": "/bin/true", "env": {"TOKEN": "${REAL_TOKEN}"}}}}
JSON
  sync
  [ "$status" -eq 0 ]
  grep -qF "TOKEN = \"\${REAL_TOKEN}\"" "$FAKE/.codex/config.toml"
}

@test "a header that is neither \${VAR} nor Bearer \${VAR} is refused" {
  seed_home <<'JSON'
{"mcpServers": {"bad": {"url": "https://example/mcp", "headers": {"X-Api-Key": "literal"}}}}
JSON
  sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing a literal secret"* ]]

  seed_home <<'JSON'
{"mcpServers": {"ok": {"url": "https://example/mcp", "headers": {"X-Api-Key": "${KEY}"}}}}
JSON
  sync
  [ "$status" -eq 0 ]
  grep -qF '[mcp_servers.ok.env_http_headers]' "$FAKE/.codex/config.toml"
  grep -qF 'X-Api-Key = "KEY"' "$FAKE/.codex/config.toml"
}

@test "an unreadable or empty shared config stops the run" {
  seed_home <<'JSON'
{"mcpServers": {}}
JSON
  sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-empty mcpServers object"* ]]

  seed_home <<'JSON'
{not json
JSON
  sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read"* ]]
}

@test "an absent Codex private server is a note, not a failure" {
  seed_home <<'JSON'
{"mcpServers": {"keeper": {"command": "/bin/true"}}}
JSON
  sync
  [ "$status" -eq 0 ]
  # Codex writes node_repl and friends itself on first launch, so a fresh machine has none.
  [[ "$output" == *"Codex private servers not present yet"* ]]
  toml_get "$FAKE/.codex/config.toml" | grep -q "'keeper'"
}

# Copilot on #30: the case above passes with validate_codex() deleted, because it re-parses
# output that generation already got right. This one cannot -- it needs the validator to
# fire. A dotted server name renders as `[mcp_servers.has.a.dot]`, which is valid TOML and
# so clears the pre-write tomllib guard, but parses as nested tables rather than a server
# called `has.a.dot`. Only the post-write re-read notices the server asked for is not the
# server that landed.
@test "a name that renders as valid TOML but the wrong table is caught after the write" {
  seed_home <<'JSON'
{"mcpServers": {"has.a.dot": {"command": "/bin/true"}}}
JSON
  sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"Codex missing managed servers: ['has.a.dot']"* ]]

  # The pre-write guard passed, so the file on disk is well-formed and the mismatch is only
  # visible by reading it back.
  toml_get "$FAKE/.codex/config.toml" >/dev/null
  grep -qF '[mcp_servers.has.a.dot]' "$FAKE/.codex/config.toml"
}

# Issue #22: one fixed backup name was overwritten every run, so a run that corrupted the
# file backed up the corrupt copy over the last good one.
@test "a backup is stamped, and an existing one is not overwritten" {
  seed_home <<'JSON'
{"mcpServers": {"keeper": {"command": "/bin/true"}}}
JSON
  printf 'model = "generation-one"\n' >"$FAKE/.codex/config.toml"
  printf '{"mcpServers": {"generation-one": {"command": "x"}}}\n' >"$FAKE/.claude.json"
  sync
  [ "$status" -eq 0 ]

  backups=("$FAKE"/.codex/config.toml.bak-before-agents-sync-*)
  [ "${#backups[@]}" -eq 1 ]
  grep -qF 'generation-one' "${backups[0]}"
  first="${backups[0]}"

  # A second run must not destroy the first backup, which is the only copy of the state
  # before the first run.
  printf 'model = "generation-two"\n' >"$FAKE/.codex/config.toml"
  sync
  [ "$status" -eq 0 ]
  [ -e "$first" ]
  grep -qF 'generation-one' "$first"

  # And the Claude file is backed up the same way.
  claude_backups=("$FAKE"/.claude.json.bak-before-agents-sync-*)
  grep -qF 'generation-one' "${claude_backups[0]}"
}

@test "backups are pruned to the newest few, so they cannot grow without bound" {
  seed_home <<'JSON'
{"mcpServers": {"keeper": {"command": "/bin/true"}}}
JSON
  printf 'model = "live"\n' >"$FAKE/.codex/config.toml"
  # Seven stamps older than any this run can produce, plus the fixed name older versions
  # left behind, which the glob has to collect too.
  for year in 2019 2020 2021 2022 2023 2024 2025; do
    printf 'model = "%s"\n' "$year" >"$FAKE/.codex/config.toml.bak-before-agents-sync-${year}0101T000000Z"
  done
  printf 'model = "legacy"\n' >"$FAKE/.codex/config.toml.bak-before-agents-sync"
  sync
  [ "$status" -eq 0 ]

  backups=("$FAKE"/.codex/config.toml.bak-before-agents-sync*)
  [ "${#backups[@]}" -eq 5 ]
  # The oldest go first, and the unstamped legacy name sorts below every stamp.
  [ ! -e "$FAKE/.codex/config.toml.bak-before-agents-sync" ]
  [ ! -e "$FAKE/.codex/config.toml.bak-before-agents-sync-20190101T000000Z" ]
  [ -e "$FAKE/.codex/config.toml.bak-before-agents-sync-20250101T000000Z" ]
}
