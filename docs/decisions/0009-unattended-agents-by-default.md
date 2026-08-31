# 0009: agents run unattended by default

## Context

Claude Code, Codex, and Cursor each ask for confirmation before shell commands, file
writes, and network access unless told otherwise. The user-level settings in this repo leave
Codex and Cursor unattended, and leave Claude Code unattended except when it writes a file:
Claude Code `permissions.defaultMode = "auto"` with
`ask = ["Edit", "Write", "NotebookEdit"]`, Codex
`approval_policy = "never"` inside a `workspace-write` sandbox with network access, Cursor
`claudeCode.initialPermissionMode = "bypassPermissions"`. `bin/run-coding-agent.sh` passes no
permission override on either branch, so a launched session keeps whatever posture its own
settings file sets.

## Decision

Keep the unattended posture at user level, with one exception: Claude Code asks before it
writes a file. The machines this repo is applied to are the author's own, and the
repositories opened on them are the author's own work, so per-action prompts there cost more
attention than they save -- for commands. Writing a file is the action that is awkward to
inspect after the fact, and it is the one an agent takes most often, so the three tools that
write one -- `Edit`, `Write`, `NotebookEdit` -- earn a prompt that commands do not. The rules
cover a subagent's writes too: `Agent` does not prompt on launch, and the subagent's own tool
calls are checked as it runs.

Claude Code alone. Codex keeps `approval_policy = "never"` and Cursor keeps
`bypassPermissions`, so the posture is deliberately uneven rather than uniform: this is the
tool where the prompt was wanted, not a principle applied everywhere.

## Consequences

- Any repository opened on a machine with this config gets an agent that can run commands
  without asking. File writes ask in any Claude session, launched or plain; Codex and Cursor
  still write without asking. Code from someone else is reviewed in a VM or a sandbox, or with
  a project-level `.claude/settings.json` that sets `permissions.defaultMode` back to
  `default`.
- `bin/run-coding-agent.sh` passes no permission override on either branch, so a launched
  session inherits the posture above rather than widening it: Claude prompts on a write via
  `permissions.ask`, and Codex stays unattended through `approval_policy = "never"` in
  `~/.codex/config.toml`. The launcher reproduces the settings files, it does not override
  them.
- The only edit-time guard is `ruff_format.sh`, and it runs in two places: every project
  generated from the template wires it in `.claude/settings.json`, and any other repository
  gets it only when the `whetstone-hooks` plugin is enabled. The global
  `~/.claude/settings.json` configures no `PostToolUse` hook, so in a repository outside
  those two cases nothing checks what an edit leaves behind until pre-commit.

## Alternatives considered

- Attended by default, unattended only through the launcher: safer for borrowed code, but
  every Cursor and plain `claude` session would prompt.
- Per-project allowlists: precise, but each new repo starts with a round of prompts.
