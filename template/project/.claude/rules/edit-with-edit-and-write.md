---
description: Modify files with Edit and Write, not with shell writes
paths:
  - "**/*"
---

# Edit files with Edit and Write

Modify files with Edit and Write. Never with a shell redirect, `sed -i`, `tee`, or a
`python3 - <<'PY'` heredoc that calls `write_text`.

Auto mode instructs an agent to prefer Bash wherever Bash can do the job, file changes
included. Two things here depend on that not happening: `permissions.ask` gates Edit, Write,
and NotebookEdit by name, so a shell write shows no diff and raises no prompt; and the
`ruff_format` hook in `.claude/settings.json` matches `Edit|Write`, so a Python file written
through Bash is never formatted and its problems surface at pre-commit instead of at edit
time.

Reads and searches stay with Bash: `cat`, `head`, `sed -n`, `grep`, `find`.
