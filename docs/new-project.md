# New Python project

```bash
uvx copier copy --trust gh:zaffnet/whetstone my-project
cd my-project
uv sync --all-groups
uv run pre-commit install
```

`--trust` lets the template run its post-generation tasks (`uv lock`, `git init`).

## Questions

| Question | Effect |
| --- | --- |
| `project_name` | Distribution name in `pyproject.toml`, repo name in README and CI |
| `package_name` | Import name; defaults to `project_name` with hyphens turned into underscores |
| `description` | `pyproject.toml` description and README first line |
| `github_owner` | `CODEOWNERS`, clone URL in `docs/DEVELOPMENT.md`, container registry path |
| `python_version` | `requires-python`, `.python-version`, `target-version` for ruff, mypy, basedpyright |
| `line_length` | ruff and editor rulers |
| `use_docker` | Adds `Dockerfile`, `docker-compose.yaml`, the override file, `.dockerignore`, the image-version pre-commit hook, and the image build job in CI |
| `use_fastapi` | Adds FastAPI, uvicorn, and pydantic-settings to dependencies and the async-safety reviewer agent |
| `license` | `LICENSE` file and the `license` field |

## What you get

- `pyproject.toml` with ruff `select = ["ALL"]` and a commented ignore list, mypy with the
  Pydantic plugin, basedpyright strict, bandit, pytest (`*_test.py`), coverage.
- `.pre-commit-config.yaml`: ruff fix and format, mypy, basedpyright, bandit, pip-audit,
  unit tests with coverage, `diff-cover --fail-under=80` against `origin/main`, and a
  pygrep hook that rejects section-separator comments.
- `.github/workflows/ci.yaml` with SHA-pinned actions, `permissions: {}` by default,
  pre-commit as the gate, and a diff-cover summary on the job page.
- `.github/dependabot.yml` for uv, GitHub Actions, pre-commit, and (with Docker) the
  Dockerfile and compose file.
- `.claude/` with hooks (ruff on every edit, worktree setup), rules, reviewer agents, and
  `.codex/` with the same agents in TOML.
- `.vscode/settings.json` pinned to the project's `.venv` ruff and basedpyright.
- `CLAUDE.md`, `AGENTS.md`, `docs/DEVELOPMENT.md`, a design-doc template, `.env.example`.

## Later: pulling template changes

```bash
uvx copier update --trust
```

Copier reads `.copier-answers.yml`, fetches the template version recorded there and the
latest, and three-way merges. Conflicts land as `.rej` files or inline markers depending on
`--conflict`. Review, fix, commit.
