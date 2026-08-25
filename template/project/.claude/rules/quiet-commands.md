---
description: Quiet flags for daily commands
---

Prefer these forms so runner output does not stay in context:

- One test file: `uv run pytest <file> -qq --tb=short --no-header`
- Live marker: `uv run pytest -qq --tb=short --no-header -m live`
- Sync: `uv sync -q --all-groups --all-extras --upgrade`

`pyproject.toml` addopts start with `-v`; use `-qq`, not `-q`. Other commands are fine; keep them quiet when they would print a lot (`ruff --quiet`, `git fetch -q`).
