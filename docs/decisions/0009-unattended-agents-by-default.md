# 0009: agents run unattended by default

## Context

Claude Code, Codex, and Cursor each ask for confirmation before shell commands, file
writes, and network access unless told otherwise. The user-level settings in this repo leave
Codex and Cursor unattended, and leave Claude Code unattended except for edits: Claude Code
`permissions.defaultMode = "auto"` with `ask = ["Edit"]`, Codex
`approval_policy = "never"` inside a `workspace-write` sandbox with network access, Cursor
`claudeCode.initialPermissionMode = "bypassPermissions"`. The two launchers in `bin/` start
Claude with `--permission-mode bypassPermissions` and Codex with
`--sandbox danger-full-access --ask-for-approval never`.

## Decision

Keep the unattended posture at user level, with one exception: Claude Code asks before an
edit. The machines this repo is applied to are the author's own, and the repositories opened
on them are the author's own work, so per-action prompts there cost more attention than they
save -- for commands. An edit is the action that is awkward to inspect after the fact, and it
is the one an agent takes most often, so it earns the single prompt that the rest do not.

Claude Code alone. Codex keeps `approval_policy = "never"` and Cursor keeps
`bypassPermissions`, so the posture is deliberately uneven rather than uniform: this is the
tool where the prompt was wanted, not a principle applied everywhere.

## Consequences

- Any repository opened on a machine with this config gets an agent that can run commands
  without asking. File edits ask only in a plain `claude` session; the unattended launchers,
  Codex, and Cursor still edit without asking. Code from someone else is reviewed in a VM or
  a sandbox, or with a project-level `.claude/settings.json` that sets
  `permissions.defaultMode` back to `default`.
- `bin/run_claude_code.sh:26` and `bin/run-coding-agent.sh:99` pass
  `--permission-mode bypassPermissions`, which overrides the setting. So the edit prompt
  reaches a plain `claude` session and neither launcher, and the guard is narrower than the
  settings file alone suggests. Removing it from the launchers is a separate decision: they
  exist to run unattended, which is the case the prompt would break.
- The only edit-time guard is `ruff_format.sh`, and it runs in two places: every project
  generated from the template wires it in `.claude/settings.json`, and any other repository
  gets it only when the `whetstone-hooks` plugin is enabled. The global
  `~/.claude/settings.json` configures no `PostToolUse` hook, so in a repository outside
  those two cases nothing checks what an edit leaves behind until pre-commit.

## Alternatives considered

- Attended by default, unattended only through the launcher: safer for borrowed code, but
  every Cursor and plain `claude` session would prompt.
- Per-project allowlists: precise, but each new repo starts with a round of prompts.
