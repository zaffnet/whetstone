# 0009: agents run unattended by default

## Context

Claude Code, Codex, and Cursor each ask for confirmation before shell commands, file
writes, and network access unless told otherwise. The user-level settings in this repo turn
those prompts off: Claude Code `permissions.defaultMode = "dontAsk"`, Codex
`approval_policy = "never"` inside a `workspace-write` sandbox with network access, Cursor
`claudeCode.initialPermissionMode = "bypassPermissions"`. The two launchers in `bin/` start
Claude with `--permission-mode bypassPermissions` and Codex with
`--sandbox danger-full-access --ask-for-approval never`.

## Decision

Keep the unattended posture at user level. The machines this repo is applied to are the
author's own, and the repositories opened on them are the author's own work. Per-action
prompts there cost more attention than they save.

## Consequences

- Any repository opened on a machine with this config gets an agent that can run commands
  and edit files without asking. Code from someone else is reviewed in a VM or a sandbox,
  or with a project-level `.claude/settings.json` that sets `permissions.defaultMode`
  back to `default`.
- `bin/run_claude_code.sh` and `bin/run-coding-agent.sh` use the same mode,
  `bypassPermissions`, so launching either way behaves the same.
- Hooks still run (`ruff_format.sh`, `worktree_create.sh`); they are the remaining guard
  on what an edit leaves behind.

## Alternatives considered

- Attended by default, unattended only through the launcher: safer for borrowed code, but
  every Cursor and plain `claude` session would prompt.
- Per-project allowlists: precise, but each new repo starts with a round of prompts.
