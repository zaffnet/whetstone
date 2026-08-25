# 0006: `~/.agents` is the single source of truth for agent configuration

## Context

Claude Code reads `~/.claude`, Codex reads `~/.codex`, Cursor reads `~/.cursor`. Each has
its own skills directory, MCP server list, and instruction file. Maintaining three copies
of the same skill drifted within a week.

## Decision

`~/.agents` holds skills, `mcp.json`, and the plugin inventory. Each agent gets symlinks:
`~/.claude/skills -> ~/.agents/skills`, `~/.cursor/mcp.json -> ~/.agents/mcp.json`,
`~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` -> the repo's `AGENTS.md`. `bin/sync-mcp`
writes the `[mcp_servers.*]` section of Codex `config.toml` and the `mcpServers` map of
`~/.claude.json` from the same `mcp.json`; chezmoi runs it after every apply, so there is
one writer. Hand-written skills are symlinks into this repo's `skills/`; third-party skills
are listed in `~/.agents/skills.txt` and installed by `npx skills`.

## Consequences

- A skill is edited once and visible to every agent.
- The same `skills/` directory is what `npx skills add zaffnet/whetstone` and the Claude
  plugin marketplace publish, so local use and distribution share one copy.
- `~/.claude.json` is not managed by chezmoi (it holds OAuth state and usage counters);
  `sync-mcp` edits only its `mcpServers` map.
- Tool updates that move a config path require one new symlink file in `home/`.

## Alternatives considered

- Per-tool copies with a sync script: drift between syncs.
- Vendoring third-party skills into the repo: license and update burden.
