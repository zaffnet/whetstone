# 0004: ruff for style, three type checkers for types

## Context

Static analysis catches the bugs tests miss. Ruff covers linting and formatting. No single
type checker covers the Python typing spec, Pydantic models, and editor latency at
once.

## Decision

- ruff with `select = ["ALL"]` and a commented ignore list. Ruff owns formatting, imports,
  and naming; nothing else formats Python.
- mypy with the Pydantic plugin, run in pre-commit and CI.
- basedpyright in strict mode, run in pre-commit and CI.
- pyrefly in strict mode as the editor language server, for speed while typing.

## Consequences

- Each disabled ruff rule in `pyproject.toml` carries the reason it is off.
- A type error must be fixed, not silenced: no `# type: ignore` without a reason that names
  the checker limitation.
- Three checkers means three configs to keep aligned on `pythonVersion` and excludes.
- Pre-commit runs take longer; mypy runs with multiple workers to compensate.

## Alternatives considered

- mypy only: about 58% typing-spec conformance and slow on large trees.
- pyright or basedpyright only: no Pydantic plugin, so model field inference is weaker.
- ty: fastest, but still in beta with deliberate feature gaps. Revisit when it ships 1.0.
