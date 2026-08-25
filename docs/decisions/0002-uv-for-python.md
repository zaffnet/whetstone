# 0002: uv for Python environments, packaging, and interpreters

## Context

A Python project needs an interpreter, a virtual environment, a lockfile, and a way to run
tools. pip + venv + pyenv + pip-tools did this with four tools and four config styles.

## Decision

uv for everything: `uv python install`, `uv sync`, `uv lock`, `uv run`, `uv tool install`,
`uvx`. `uv.lock` is committed. CI uses `astral-sh/setup-uv`.

## Consequences

- One lockfile and one command to reproduce an environment.
- Dependabot updates `uv.lock` natively.
- Global CLIs (ruff, basedpyright, pyrefly) are `uv tool install`ed and listed in the
  Brewfile under `uv`.
- A machine with a private index needs `index-strategy = "unsafe-first-match"`; the
  reason is written in `home/dot_config/uv/uv.toml.tmpl`.

## Alternatives considered

- Poetry: its own resolver and lock format, slower, and `pyproject.toml` sections that are
  not PEP 621.
- pip-tools + pyenv: works, but two tools and no interpreter management in the lockfile.
