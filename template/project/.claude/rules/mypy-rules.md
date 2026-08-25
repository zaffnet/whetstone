---
description: Fix mypy errors; do not silence them
paths:
  - "**/*.{py,pyi}"
  - "pyproject.toml"
---

Treat mypy errors as real defects. Fix the bug, add accurate annotations, or add real stubs (`types-<pkg>` or `stubs/`). Do not add `# type: ignore` or file-level mypy pragmas without asking. Use `Any` only for values that are genuinely dynamic. Do not copy existing silences into new code.

`uv run mypy --no-pretty --no-error-summary --hide-error-context`
