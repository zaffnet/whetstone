---
description: Modify files with Edit and Write, not with shell writes
paths:
  - "**/*"
---

# Edit files with Edit and Write

Modify files with Edit and Write. Never with a shell redirect, `sed -i`, `tee`, or a
`python3 - <<'PY'` heredoc that calls `write_text`.

Edit reads the file first and fails on an ambiguous match. A shell write shows no diff and
silently mangles what it rewrites instead. Auto mode tells an agent to prefer Bash wherever
Bash can do the job, file changes included, which is why this needs saying.

The `ruff_format` hook in `.claude/settings.json` matches `Edit|Write`, so a Python file
written through Bash is never formatted and its problems surface at pre-commit rather than at
edit time.

Reads and searches stay with Bash: `cat`, `head`, `sed -n`, `grep`, `find`.
