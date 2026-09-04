# Skills, plugins, and MCP

Edit this directory. Do not edit `~/.cursor/mcp.json`, `~/.claude.json`, or `~/.codex/config.toml` for shared MCP.

## Skills

Add: put a folder with `SKILL.md` at `~/.agents/skills/<name>/`.

Remove: delete that folder.

`~/.claude/skills`, `~/.cursor/skills`, and `~/.kiro/skills` are all symlinks to this directory, and Codex reads it in place, so a skill is installed once. `home/.chezmoiscripts/run_onchange_after_30-agent-skills.sh.tmpl` passes `-a claude-code`, so the installer writes here and never into an agent's own directory.

`skills.txt` plus the folders in the repo's `skills/` are the reproducible set. Anything else in `~/.agents/skills` is a hand install: an apply neither creates it nor removes it, and `chezmoi status` says nothing about it. Add it to `skills.txt` to keep it, or delete the folder.

## MCP

Every stdio server that runs a published package is pinned to a version (`pkg@X.Y.Z`). Bump the pin by hand, then sync. `code-scan` is the exception: its command is a local executable path from `[data.work]`, so there is no package and nothing to pin.

Sync means `uv run --no-project --python 3.12 python ~/.agents/bin/sync-mcp`. The script needs tomllib and the system python3 on macOS is 3.9, so the bare path fails on a fresh Mac. An apply runs it this way for you (`home/.chezmoiscripts/run_after_40-sync-mcp.sh.tmpl`).

Shared raw servers live in `~/.agents/mcp.json`. Secrets are environment variable names, never values. `${VAR}` is the Claude and Codex syntax; Cursor expands `${env:VAR}`. No shared server needs a secret today, so this only matters when one is added.

Add:

1. Confirm it is not already a plugin (github, figma).
2. Add one key to `mcp.json`.
3. Run `uv run --no-project --python 3.12 python ~/.agents/bin/sync-mcp`.
4. Start a new Cursor / Claude / Codex session.

Remove:

1. Delete that key from `mcp.json`.
2. Run `uv run --no-project --python 3.12 python ~/.agents/bin/sync-mcp`.
3. Start a new session in each agent.

Do not use `claude mcp add`, `codex mcp add`, or Cursor's MCP form for shared servers. The next sync overwrites those product files. Sync also empties every Claude local scope (`projects[*].mcpServers` in `~/.claude.json`), so anything added with `claude mcp add` is gone after the next sync.

Codex keeps `node_repl`, `computer-use`, and `event-stream` as private servers; sync never touches them.

## Browser

`chrome-devtools` in `mcp.json` runs `chrome-devtools-mcp` with `--autoConnect`. It attaches to the Chrome that is already running on the stable channel's default user data directory and never launches a Chrome of its own. If Chrome is not running, tools fail with `Could not connect to Chrome`.

Requirements:

- Chrome is running with the daily profile.
- `chrome://inspect/#remote-debugging` has "Allow remote debugging for this browser instance" ticked. Re-check after a Chrome update.

Chrome shows an Allow dialog once per agent session when the MCP server connects. That is Chrome's design; no flag, policy, or checkbox persists the choice (chrome-devtools-mcp issue #825, closed as not planned). Chrome also refuses `--remote-debugging-port` on the default user data directory, so there is no prompt-free route to the daily profile.

Playwright MCP is disabled in Claude (`~/.claude/settings.json` `enabledPlugins`) and Codex (`~/.codex/config.toml` `[plugins."playwright@claude-plugins-official"]`) because it launches its own signed-out profile. Cursor's built-in browser and Codex `chrome@openai-bundled` / `browser@openai-bundled` are outside this directory.

## Plugins

Add:

1. Enable it in Claude. Codex already sees `claude-plugins-official`.
2. Install the Cursor marketplace equivalent.
3. Tick the name in `~/.agents/plugins/desired.yaml`.

Remove:

1. Disable or uninstall it in that product.
2. Untick `desired.yaml`.

Do not also add a plugin-provided server to `mcp.json`.

Product-locked plugins stay in one product: Codex Computer Use / Chrome, Cursor Canvas, Claude output styles.

## Graphify

Not an MCP server (`sync-mcp` never touches it) and not a skill (`skills.txt` never lists
it). It is a standalone CLI, `graphify`, from the `graphifyy` package pinned in the Brewfile.
`home/.chezmoiscripts/run_onchange_after_35-graphify.sh.tmpl` runs `graphify install` on
every apply that changes the Brewfile; that subcommand is graphify's own, and this doc does
not reproduce what files it writes.

The per-product registrations graphify also offers are left out of that script, because each
one writes to a path this repo already owns or to the current directory. The script's own
comment lists them and why. The exception is Claude's `PreToolUse` hook, which nudges an
agent towards the graph on Bash, Grep, Read, and Glob: that hook is declared by hand in
`home/.chezmoitemplates/claude-settings.json`, so every repo on this machine gets it. What
`graphify claude install` is still refused for is its `~/.claude/CLAUDE.md` write. Codex gets
its graph guidance from `AGENTS.md`, and generated projects get the Cursor rule from the
template.

Building and updating a project's graph is manual, per repo: `/graphify .` inside the
assistant, `graphify update .` after a pull. The git hooks that automate the rebuild are a
different mechanism from the `PreToolUse` hook above: `graphify hook install` writes
`post-commit` and `post-checkout` into one clone, so it is opt-in per clone, and where
`core.hooksPath` points at a managed directory it cannot be installed at all.
