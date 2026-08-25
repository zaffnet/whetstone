# Skills, plugins, and MCP

Edit this directory. Do not edit `~/.cursor/mcp.json`, `~/.claude.json`, or `~/.codex/config.toml` for shared MCP.

## Skills

Add: put a folder with `SKILL.md` at `~/.agents/skills/<name>/`.

Remove: delete that folder.

Claude follows `~/.claude/skills` → `~/.agents/skills`. Codex reads `~/.agents/skills`. Cursor sees them through the Claude symlink. Do not copy the same skill into `~/.cursor/skills` or `~/.codex/skills`.

## MCP

Shared raw servers live in `~/.agents/mcp.json`. Secrets are environment variable names, never values. `${VAR}` is the Claude and Codex syntax; Cursor expands `${env:VAR}`. No shared server needs a secret today, so this only matters when one is added.

Add:

1. Confirm it is not already a plugin (github, figma).
2. Add one key to `mcp.json`.
3. Run `~/.agents/bin/sync-mcp`.
4. Start a new Cursor / Claude / Codex session.

Remove:

1. Delete that key from `mcp.json`.
2. Run `~/.agents/bin/sync-mcp`.
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
