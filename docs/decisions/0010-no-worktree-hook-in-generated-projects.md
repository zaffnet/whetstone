# 0010: Generated projects carry no WorktreeCreate hook

## Context

A WorktreeCreate hook replaces Claude Code's worktree logic. It has no fallback: if the
hook cannot print the path of a worktree it created, the creation fails. The Claude desktop
app runs each session in a sandbox that cannot reach the repository on disk, so a hook
configured in a project's `.claude/settings.json` failed every worktree there.

## Decision

The Copier template does not configure a WorktreeCreate hook. The hook and its setup script
stay in `hooks/` and ship as the opt-in `whetstone-hooks` plugin for terminal sessions that
want worktrees placed beside the repository. `template.yml` asserts the generated settings
file has no `WorktreeCreate` entry.

## Consequences

- Worktrees in generated projects use Claude's default location (`.claude/worktrees/`).
- `.worktreeinclude` is still copied by Claude's own logic when no hook is present.
- Anyone who wants sibling worktrees installs the plugin once at user level.

## Alternatives considered

- Guarding the hook command (`[ -r ]`, `bash -n`) and exiting 0 when it cannot run. Rejected:
  an exit 0 with no path is still a failed creation.
- Keeping the hook and documenting the app limitation. Rejected: a default that breaks one
  supported client is the wrong default.
